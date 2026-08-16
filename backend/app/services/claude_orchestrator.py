import asyncio
import os
import re
import json
import logging
from typing import Dict, Optional, List, Set
from datetime import datetime, timezone
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from backend.app.models.claude import (
    ClaudeAccount,
    ClaudeTask,
    ClaudeAccountStatus,
    ClaudeTaskStatus,
)
from backend.app.models.ticket import Ticket, TicketEvent, EventKind, TicketStatus
from backend.app.config import settings

logger = logging.getLogger("claude_orchestrator")


class ActiveClaudeProcess:
    def __init__(self, task_id: UUID, process: asyncio.subprocess.Process):
        self.task_id = task_id
        self.process = process
        self.logs: List[str] = []
        self.wait_event = asyncio.Event()
        self.human_input: Optional[str] = None
        self.is_waiting_human: bool = False
        self.question: Optional[str] = None


class ClaudeOrchestratorService:
    def __init__(self):
        self.active_processes: Dict[UUID, ActiveClaudeProcess] = {}
        self.ws_subscribers: Set[any] = set()

    async def register_ws(self, websocket):
        self.ws_subscribers.add(websocket)

    async def unregister_ws(self, websocket):
        self.ws_subscribers.discard(websocket)

    async def broadcast_event(self, event_type: str, data: dict):
        payload = json.dumps({"event": event_type, "data": data, "timestamp": datetime.now(timezone.utc).isoformat()})
        dead = []
        for ws in self.ws_subscribers:
            try:
                await ws.send_text(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.ws_subscribers.discard(ws)

    async def get_next_available_account(self, session: AsyncSession) -> Optional[ClaudeAccount]:
        """Obtiene la cuenta principal disponible o rota automáticamente a la cuenta secundaria si la cuota expiró."""
        # 1. Buscar primaria activa
        stmt_primary = select(ClaudeAccount).where(
            ClaudeAccount.is_primary == True,
            ClaudeAccount.status == ClaudeAccountStatus.activa,
        )
        res = await session.execute(stmt_primary)
        primary = res.scalar_one_or_none()
        if primary:
            return primary

        # 2. Si no hay primaria o está agotada, buscar secundaria activa
        stmt_sec = select(ClaudeAccount).where(
            ClaudeAccount.is_primary == False,
            ClaudeAccount.status == ClaudeAccountStatus.activa,
        )
        res_sec = await session.execute(stmt_sec)
        secondary = res_sec.scalar_one_or_none()
        if secondary:
            logger.info(f"Usando cuenta secundaria {secondary.alias} por cuota agotada en la primaria.")
            return secondary

        # 3. Fallback: cualquier cuenta activa
        stmt_any = select(ClaudeAccount).where(ClaudeAccount.status == ClaudeAccountStatus.activa)
        res_any = await session.execute(stmt_any)
        return res_any.scalars().first()

    async def mark_account_quota_exhausted(self, account_id: int, session: AsyncSession):
        """Marca una cuenta como cuota agotada para disparar la rotación."""
        await session.execute(
            update(ClaudeAccount)
            .where(ClaudeAccount.id == account_id)
            .values(status=ClaudeAccountStatus.cuota_agotada, last_used_at=datetime.now(timezone.utc))
        )
        await session.commit()
        await self.broadcast_event("account_quota_exhausted", {"account_id": account_id})

    async def start_task(self, task_id: UUID, db_session_factory) -> None:
        """Inicia la ejecución asíncrona de Claude para una tarea o resolución de ticket."""
        async with db_session_factory() as session:
            task = await session.get(ClaudeTask, task_id)
            if not task:
                return

            account = await self.get_next_available_account(session)
            if not account:
                task.status = ClaudeTaskStatus.fallido
                task.execution_logs = "Error: No hay cuentas de Claude activas o disponibles."
                await session.commit()
                await self.broadcast_event("task_failed", {"task_id": str(task_id), "reason": "no_accounts"})
                return

            task.account_id = account.id
            task.status = ClaudeTaskStatus.ejecutando
            await session.commit()

            # Lanzar subproceso en segundo plano
            asyncio.create_task(self._run_claude_process(task_id, task.prompt, task.target_repo, account, db_session_factory))

    async def _marcar_fallida(self, task_id: UUID, db_session_factory, motivo: str):
        """Deja la tarea en fallido con el motivo, y lo manda por el WebSocket.

        Sin el aviso, una tarea que muere antes de arrancar no genera ni un solo
        `task_log`: la app se queda con su «Iniciando tarea...» para siempre.
        """
        async with db_session_factory() as session:
            task = await session.get(ClaudeTask, task_id)
            if task:
                task.status = ClaudeTaskStatus.fallido
                task.execution_logs = motivo
                await session.commit()

        await self.broadcast_event(
            "task_log", {"task_id": str(task_id), "chunk": f"\n[ERROR] {motivo}\n"}
        )
        await self.broadcast_event(
            "task_finished", {"task_id": str(task_id), "status": "fallido"}
        )

    async def _run_claude_process(self, task_id: UUID, prompt: str, target_repo: Optional[str], account: ClaudeAccount, db_session_factory):
        cmd = [settings.CLAUDE_CLI_PATH, "--print", prompt]
        cwd = target_repo or settings.REPOS_BASE_DIR

        # create_subprocess_exec da el MISMO ENOENT tanto si falta el binario
        # como si falta el directorio de trabajo, y el mensaje decia siempre
        # «Fallo al invocar Claude CLI». Con REPOS_BASE_DIR apuntando a un
        # directorio inexistente, toda tarea sin repo moria en 150 ms
        # aparentando que Claude no estaba instalado.
        if not os.path.isdir(cwd):
            await self._marcar_fallida(
                task_id,
                db_session_factory,
                f"El directorio de trabajo no existe: {cwd}. "
                "Creelo o ajuste REPOS_BASE_DIR.",
            )
            return

        if not os.path.exists(settings.CLAUDE_CLI_PATH):
            await self._marcar_fallida(
                task_id,
                db_session_factory,
                f"No se encuentra el CLI de Claude en {settings.CLAUDE_CLI_PATH}. "
                "Ajuste CLAUDE_CLI_PATH.",
            )
            return

        try:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                cwd=cwd,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
            )
        except Exception as e:
            await self._marcar_fallida(
                task_id,
                db_session_factory,
                f"Fallo al invocar Claude CLI ({' '.join(cmd[:2])}) en {cwd}: {e}",
            )
            return

        active = ActiveClaudeProcess(task_id, process)
        self.active_processes[task_id] = active

        await self.broadcast_event("task_started", {"task_id": str(task_id), "account": account.alias})

        rate_limit_pattern = re.compile(r"(rate limit reached|usage limit exceeded|credit balance is too low)", re.IGNORECASE)
        hard_stop_question_pattern = re.compile(r"(\[PROMPT_USER\]|¿Quieres que proceda\?|Do you want to proceed\?|Please confirm|Por favor confirma)", re.IGNORECASE)

        full_output = []

        try:
            while True:
                line = await process.stdout.readline()
                if not line:
                    break
                text = line.decode("utf-8", errors="replace")
                full_output.append(text)
                active.logs.append(text)

                # Emitir log a la app móvil por WebSocket
                await self.broadcast_event("task_log", {"task_id": str(task_id), "chunk": text})

                # 1. Detección de Rate Limit / Cuota Agotada -> Rotación automática
                if rate_limit_pattern.search(text):
                    logger.warning(f"Límite de cuota detectado en la tarea {task_id}.")
                    async with db_session_factory() as session:
                        await self.mark_account_quota_exhausted(account.id, session)
                    # Reintentar la tarea con la siguiente cuenta disponible
                    break

                # 2. Detección de Freno Duro (Human-in-the-Loop)
                if hard_stop_question_pattern.search(text) or "¿" in text:
                    active.is_waiting_human = True
                    active.question = text.strip()
                    async with db_session_factory() as session:
                        task = await session.get(ClaudeTask, task_id)
                        if task:
                            task.status = ClaudeTaskStatus.bloqueado_esperando_humano
                            task.pending_question = active.question
                            await session.commit()

                    await self.broadcast_event("hard_stop_triggered", {
                        "task_id": str(task_id),
                        "question": active.question,
                    })

                    # Esperar la respuesta que el usuario envíe desde la app móvil
                    active.wait_event.clear()
                    await active.wait_event.wait()

                    # Inyectar la respuesta al stdin de Claude y reanudar
                    if active.human_response:
                        resp_bytes = (active.human_response + "\n").encode("utf-8")
                        process.stdin.write(resp_bytes)
                        await process.stdin.drain()
                        active.human_response = None
                        active.is_waiting_human = False

            await process.wait()

            # Finalización de la tarea
            async with db_session_factory() as session:
                task = await session.get(ClaudeTask, task_id)
                if task:
                    task.status = ClaudeTaskStatus.completado if process.returncode == 0 else ClaudeTaskStatus.fallido
                    task.execution_logs = "".join(full_output)
                    task.finished_at = datetime.now(timezone.utc)

                    # Si estaba ligada a un ticket, registrar el evento de cierre
                    if task.ticket_id:
                        ticket = await session.get(Ticket, task.ticket_id)
                        if ticket:
                            event = TicketEvent(
                                ticket_id=ticket.id,
                                actor=f"claude-agent ({account.alias})",
                                kind=EventKind.resolucion_agente,
                                to_status=TicketStatus.revision.value,
                                note="Resolución autónoma completada. Pasado a revisión.",
                            )
                            ticket.status = TicketStatus.revision
                            session.add(event)

                    await session.commit()

            await self.broadcast_event("task_finished", {
                "task_id": str(task_id),
                "exit_code": process.returncode,
            })

        finally:
            self.active_processes.pop(task_id, None)

    async def provide_human_feedback(self, task_id: UUID, response_text: str, db_session_factory) -> bool:
        """Recibe la respuesta del usuario desde la app móvil y desbloquea a Claude."""
        active = self.active_processes.get(task_id)
        if not active or not active.is_waiting_human:
            return False

        active.human_response = response_text
        active.wait_event.set()

        async with db_session_factory() as session:
            task = await session.get(ClaudeTask, task_id)
            if task:
                task.human_response = response_text
                task.status = ClaudeTaskStatus.ejecutando
                task.pending_question = None
                await session.commit()

        await self.broadcast_event("hard_stop_resumed", {
            "task_id": str(task_id),
            "response": response_text,
        })
        return True


orchestrator_service = ClaudeOrchestratorService()
