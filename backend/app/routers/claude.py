from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List
from uuid import UUID
from backend.app.database import get_db, AsyncSessionLocal
from backend.app.models.claude import ClaudeAccount, ClaudeTask, ClaudeAccountStatus
from backend.app.schemas.claude import (
    ClaudeAccountOut,
    ClaudeAccountRegister,
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


@router.get("/accounts", response_model=List[ClaudeAccountOut])
async def list_claude_accounts(db: AsyncSession = Depends(get_db)):
    res = await db.execute(select(ClaudeAccount).order_by(ClaudeAccount.is_primary.desc()))
    return res.scalars().all()


@router.post("/accounts", response_model=ClaudeAccountOut)
async def register_account(payload: ClaudeAccountRegister, db: AsyncSession = Depends(get_db)):
    account = ClaudeAccount(
        alias=payload.alias,
        email=payload.email,
        session_token_encrypted=payload.session_token,
        is_primary=payload.is_primary,
    )
    db.add(account)
    await db.commit()
    await db.refresh(account)
    return account


@router.post("/accounts/{account_id}/reset-quota", response_model=ClaudeAccountOut)
async def reset_account_quota(account_id: int, db: AsyncSession = Depends(get_db)):
    account = await db.get(ClaudeAccount, account_id)
    if not account:
        raise HTTPException(status_code=404, detail="Cuenta no encontrada")
    account.status = ClaudeAccountStatus.activa
    await db.commit()
    await db.refresh(account)
    return account


@router.get("/tasks", response_model=List[ClaudeTaskOut])
async def list_tasks(db: AsyncSession = Depends(get_db)):
    res = await db.execute(select(ClaudeTask).order_by(ClaudeTask.created_at.desc()))
    return res.scalars().all()


@router.post("/tasks", response_model=ClaudeTaskOut)
async def create_and_run_task(payload: ClaudeTaskCreate, db: AsyncSession = Depends(get_db)):
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
