import os

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List
from uuid import UUID
from backend.app.config import settings
from backend.app.database import get_db, AsyncSessionLocal
from backend.app.models.claude import ClaudeTask
from backend.app.schemas.claude import (
    ClaudeTaskCreate,
    ClaudeHumanFeedback,
    ClaudeTaskOut,
)
from backend.app.services.claude_orchestrator import orchestrator_service
from backend.app.security import actor_de_websocket

router = APIRouter(prefix="/claude", tags=["Claude Autonomous Engine"])

# El WebSocket va en su propio router porque se autentica distinto: la
# dependencia que protege el resto exige la cabecera Authorization, y el cliente
# de Flutter no puede ponerla al abrir un WebSocket. Aquí el token se comprueba
# dentro del endpoint y se cierra la conexión con código si no vale.
ws_router = APIRouter(prefix="/claude", tags=["Claude Autonomous Engine"])


# Las rutas de /accounts se retiraron: el CLI de Claude guarda UNA sesion en
# ~/.claude y el orquestador nunca paso credenciales al subproceso, asi que la
# rotacion entre dos cuentas alternaba etiquetas sobre la misma sesion. Con una
# sola cuenta, registrar cuentas y resetear cuotas solo prometia algo que no
# ocurria.


@router.get("/tasks", response_model=List[ClaudeTaskOut])
async def list_tasks(db: AsyncSession = Depends(get_db)):
    res = await db.execute(select(ClaudeTask).order_by(ClaudeTask.created_at.desc()))
    return res.scalars().all()


@router.post("/tasks", response_model=ClaudeTaskOut)
async def create_and_run_task(payload: ClaudeTaskCreate, db: AsyncSession = Depends(get_db)):
    # Sin esto, target_repo era una ruta libre y el agente arrancaba donde le
    # dijeran: bastaba pedir "/home/jetson" y un prompt que leyera
    # ~/.ssh/id_ed25519_claude_deploy para sacar por el WebSocket la clave con
    # la que este backend entra como root al VPS de produccion.
    if payload.target_repo:
        base = os.path.realpath(settings.REPOS_BASE_DIR)
        destino = os.path.realpath(payload.target_repo)
        if destino != base and not destino.startswith(base + os.sep):
            raise HTTPException(
                status_code=400,
                detail=f"target_repo debe estar dentro de {settings.REPOS_BASE_DIR}",
            )

    task = ClaudeTask(
        ticket_id=payload.ticket_id,
        title=payload.title,
        prompt=payload.prompt,
        target_repo=payload.target_repo,
        target_branch=payload.target_branch,
    )
    db.add(task)
    await db.commit()
    await db.refresh(task)

    # Iniciar la tarea en segundo plano con el orquestador
    await orchestrator_service.start_task(task.id, AsyncSessionLocal)
    return task


@router.post("/tasks/{task_id}/respond-hard-stop")
async def respond_to_hard_stop(task_id: UUID, payload: ClaudeHumanFeedback):
    """Permite al usuario responder a Claude cuando la tarea se pausó por una pregunta/bloqueo duro."""
    success = await orchestrator_service.provide_human_feedback(task_id, payload.response, AsyncSessionLocal)
    if not success:
        raise HTTPException(status_code=400, detail="La tarea no está activa o no está esperando respuesta humana.")
    return {"status": "success", "message": "Respuesta enviada a Claude. Tarea reanudada."}


@ws_router.websocket("/ws")
async def claude_websocket_logs(websocket: WebSocket):
    # Se comprueba ANTES de aceptar: aceptar y cerrar después deja pasar el
    # primer mensaje, y por aquí sale la salida en bruto de Claude.
    actor = await actor_de_websocket(websocket)
    if actor is None:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    await websocket.accept()
    await orchestrator_service.register_ws(websocket)
    try:
        while True:
            # Mantener conexión viva y recibir posibles mensajes de ping
            await websocket.receive_text()
    except WebSocketDisconnect:
        await orchestrator_service.unregister_ws(websocket)
