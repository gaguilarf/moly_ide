import asyncio
import os
import re
import json
import logging
from typing import Dict, Optional, List, Set
from datetime import datetime, timezone
from uuid import UUID
from backend.app.models.claude import (
    ClaudeTask,
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

    async def start_task(self, task_id: UUID, db_session_factory) -> None:
        """Inicia la ejecución asíncrona de Claude para una tarea o resolución de ticket."""
        async with db_session_factory() as session:
            task = await session.get(ClaudeTask, task_id)
            if not task:
                return

            task.status = ClaudeTaskStatus.ejecutando
            await session.commit()
            prompt, target_repo = task.prompt, task.target_repo

        asyncio.create_task(
            self._run_claude_process(task_id, prompt, target_repo, db_session_factory)
        )

    async def continue_task(self, task_id: UUID, mensaje: str, db_session_factory) -> None:
        """Sigue la conversacion: otro turno sobre la MISMA sesion de Claude.

        Antes no habia forma de continuar. Cada tarea era un `claude --print`
        suelto, asi que responder a lo que Claude preguntaba abria un chat nuevo
        que no sabia nada de lo anterior. Con `--session-id` al arrancar y
        `--resume` aqui, es la misma conversacion.
        """
        async with db_session_factory() as session:
            task = await session.get(ClaudeTask, task_id)
            if not task:
                return
            task.status = ClaudeTaskStatus.ejecutando
            await session.commit()
            target_repo = task.target_repo

        # El turno del usuario se mete en la transcripcion antes de responder,
        # para que la conversacion se lea en orden al reabrirla. Va en markdown
        # porque la app pinta la salida como tal.
        turno = f"\n\n**Tú:** {mensaje}\n\n"
        await self._anadir_a_log(task_id, turno, db_session_factory)

        asyncio.create_task(
            self._run_claude_process(
                task_id, mensaje, target_repo, db_session_factory, reanudar=True
            )
        )

    async def _anadir_a_log(self, task_id: UUID, texto: str, db_session_factory):
        async with db_session_factory() as session:
            task = await session.get(ClaudeTask, task_id)
            if task:
                task.execution_logs = (task.execution_logs or "") + texto
                await session.commit()
        await self.broadcast_event(
            "task_log", {"task_id": str(task_id), "chunk": texto}
        )

    async def _run_claude_process(
        self,
        task_id: UUID,
        prompt: str,
        target_repo: Optional[str],
        db_session_factory,
        reanudar: bool = False,
    ):
        # `--output-format=stream-json` con `--include-partial-messages` es lo
        # que hace que el texto llegue segun Claude lo escribe. Con la salida
        # `text` por defecto, el CLI no imprimia nada hasta terminar: la app se
        # quedaba en «Claude esta trabajando...» y luego soltaba todo de golpe.
        # `--verbose` es obligatorio para este formato en modo --print.
        #
        # La sesion se identifica con el id de la tarea, que ya es un UUID: al
        # arrancar se fija con `--session-id` y en los turnos siguientes se
        # retoma con `--resume`. Asi la conversacion tiene memoria.
        #
        # Las herramientas van declaradas porque en `--print` no hay a quien
        # pedirle permiso, y la lista es corta a proposito: lectura del
        # workspace y el cliente de la API. NO incluye Edit, Write ni Bash
        # libre. El `=` importa: la opcion es variadica y en la forma separada
        # se tragaba el prompt como si fuera otra herramienta.
        cmd = [
            settings.CLAUDE_CLI_PATH,
            "--print",
            "--output-format=stream-json",
            "--include-partial-messages",
            "--verbose",
            "--allowed-tools=Read,Glob,Grep,Bash(bin/moly *),Bash(git log *),Bash(git status)",
            "--resume" if reanudar else "--session-id",
            str(task_id),
            prompt,
        ]
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
                stdin=asyncio.subprocess.DEVNULL,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
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

        await self.broadcast_event("task_started", {"task_id": str(task_id)})

        rate_limit_pattern = re.compile(
            r"(rate limit reached|usage limit exceeded|credit balance is too low)",
            re.IGNORECASE,
        )

        trozos: list[str] = []
        fallo_declarado: Optional[str] = None

        try:
            while True:
                linea = await process.stdout.readline()
                if not linea:
                    break

                cruda = linea.decode("utf-8", errors="replace").strip()
                if not cruda:
                    continue

                try:
                    evento = json.loads(cruda)
                except json.JSONDecodeError:
                    # El CLI puede escupir alguna linea suelta que no es del
                    # protocolo. No es respuesta de Claude: no se enseña.
                    continue

                tipo = evento.get("type")

                if tipo == "stream_event":
                    interno = evento.get("event") or {}
                    if interno.get("type") == "content_block_delta":
                        delta = interno.get("delta") or {}
                        if delta.get("type") == "text_delta":
                            texto = delta.get("text") or ""
                            if texto:
                                trozos.append(texto)
                                active.logs.append(texto)
                                await self.broadcast_event(
                                    "task_log",
                                    {"task_id": str(task_id), "chunk": texto},
                                )

                elif tipo == "result":
                    if evento.get("is_error"):
                        fallo_declarado = (
                            str(evento.get("result") or "").strip()
                            or "Claude termino con error."
                        )

                elif tipo == "system" and evento.get("subtype") == "status":
                    # Solo telemetria del CLI; no es contenido.
                    continue

                if rate_limit_pattern.search(cruda):
                    logger.warning(f"Limite de cuota detectado en la tarea {task_id}.")
                    await self._marcar_fallida(
                        task_id,
                        db_session_factory,
                        "Cuota de Claude agotada. Espere a que se renueve y vuelva a lanzarla.",
                    )
                    return

            error_salida = (await process.stderr.read()).decode(
                "utf-8", errors="replace"
            ).strip()
            await process.wait()

            respuesta = "".join(trozos)

            # Un fallo sin una sola linea de texto dejaria la conversacion muda:
            # se enseña lo que dijera stderr, que es donde acaban los errores de
            # arranque del CLI.
            if process.returncode != 0 and not respuesta:
                await self._marcar_fallida(
                    task_id,
                    db_session_factory,
                    fallo_declarado
                    or error_salida
                    or f"Claude termino con codigo {process.returncode}.",
                )
                return

            async with db_session_factory() as session:
                task = await session.get(ClaudeTask, task_id)
                if task:
                    hubo_fallo = process.returncode != 0 or fallo_declarado
                    task.status = (
                        ClaudeTaskStatus.fallido
                        if hubo_fallo
                        else ClaudeTaskStatus.completado
                    )
                    # Se ACUMULA, no se reemplaza: al continuar la conversacion
                    # los turnos anteriores tienen que seguir ahi.
                    task.execution_logs = (task.execution_logs or "") + respuesta
                    task.finished_at = datetime.now(timezone.utc)

                    # Si estaba ligada a un ticket, registrar el evento de cierre
                    if task.ticket_id and not hubo_fallo:
                        ticket = await session.get(Ticket, task.ticket_id)
                        if ticket:
                            event = TicketEvent(
                                ticket_id=ticket.id,
                                actor="claude-agent",
                                kind=EventKind.resolucion_agente,
                                to_status=TicketStatus.revision.value,
                                note="Resolución autónoma completada. Pasado a revisión.",
                            )
                            ticket.status = TicketStatus.revision
                            session.add(event)

                    await session.commit()

            await self.broadcast_event(
                "task_finished",
                {"task_id": str(task_id), "exit_code": process.returncode},
            )

        finally:
            self.active_processes.pop(task_id, None)


orchestrator_service = ClaudeOrchestratorService()
