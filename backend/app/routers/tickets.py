from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from sqlalchemy.orm import selectinload
from typing import List, Optional
from datetime import datetime, timezone
from backend.app.database import get_db
from backend.app.security import Actor, require_actor
from backend.app.models.ticket import (
    Ticket,
    TicketProject,
    Sprint,
    TicketEvent,
    TicketStatus,
    SprintStatus,
    EventKind,
)
from backend.app.schemas.ticket import (
    TicketOut,
    TicketEventOut,
    TicketCreate,
    TicketNote,
    TicketTransition,
    TicketUpdate,
    TicketProjectOut,
    SprintOut,
    SprintCreate,
)

router = APIRouter(prefix="/tickets", tags=["Tickets & Sprints"])

# Reglas del flujo de desarrollo, portadas del panel al mudarse aqui la fuente de
# verdad (PAN-36). Se mueve libremente entre estados de trabajo; la regla dura es
# que a `hecho` SOLO se llega desde `revision` y con nota de cierre. Sin esto, la
# mudanza al Jetson habria sido tambien una perdida de frenos.
TRANSICIONES = {
    TicketStatus.backlog: [TicketStatus.desarrollo, TicketStatus.pruebas, TicketStatus.revision, TicketStatus.descartado],
    TicketStatus.desarrollo: [TicketStatus.backlog, TicketStatus.pruebas, TicketStatus.revision, TicketStatus.descartado],
    TicketStatus.pruebas: [TicketStatus.backlog, TicketStatus.desarrollo, TicketStatus.revision, TicketStatus.descartado],
    TicketStatus.revision: [TicketStatus.backlog, TicketStatus.desarrollo, TicketStatus.pruebas, TicketStatus.hecho, TicketStatus.descartado],
    TicketStatus.hecho: [TicketStatus.backlog, TicketStatus.revision],
    TicketStatus.descartado: [TicketStatus.backlog],
}


async def sprint_editable(db: AsyncSession, ticket: Ticket) -> None:
    """Un sprint cerrado es solo lectura tambien por API, no solo en la pantalla."""
    if not ticket.sprint_id:
        return
    sprint = await db.get(Sprint, ticket.sprint_id)
    if sprint and sprint.status == SprintStatus.cerrado:
        raise HTTPException(
            status_code=409,
            detail=f"{ticket.code} pertenece a '{sprint.name}', que esta cerrado: solo lectura.",
        )


@router.get("/projects", response_model=List[TicketProjectOut])
async def list_projects(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(TicketProject).order_by(TicketProject.id))
    return result.scalars().all()


@router.get("/sprints", response_model=List[SprintOut])
async def list_sprints(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Sprint).order_by(Sprint.created_at.desc()))
    return result.scalars().all()


@router.post("/sprints", response_model=SprintOut)
async def create_sprint(payload: SprintCreate, db: AsyncSession = Depends(get_db)):
    sprint = Sprint(**payload.model_dump())
    db.add(sprint)
    await db.commit()
    await db.refresh(sprint)
    return sprint


@router.get("", response_model=List[TicketOut])
async def list_tickets(
    status: Optional[TicketStatus] = None,
    project: Optional[str] = None,
    sprint_id: Optional[int] = None,
    db: AsyncSession = Depends(get_db),
):
    query = select(Ticket).options(selectinload(Ticket.events)).order_by(Ticket.created_at.desc())

    if status:
        query = query.where(Ticket.status == status)
    if sprint_id:
        query = query.where(Ticket.sprint_id == sprint_id)
    if project:
        proj_res = await db.execute(select(TicketProject).where(TicketProject.key == project))
        proj = proj_res.scalar_one_or_none()
        if proj:
            query = query.where(Ticket.project_id == proj.id)

    result = await db.execute(query)
    return result.scalars().all()


@router.get("/{code}", response_model=TicketOut)
async def get_ticket_detail(code: str, db: AsyncSession = Depends(get_db)):
    query = select(Ticket).where(Ticket.code == code).options(selectinload(Ticket.events))
    result = await db.execute(query)
    ticket = result.scalar_one_or_none()
    if not ticket:
        raise HTTPException(status_code=404, detail=f"Ticket {code} no encontrado")
    return ticket


@router.post("", response_model=TicketOut)
async def create_ticket(payload: TicketCreate, db: AsyncSession = Depends(get_db)):
    # 1. Obtener proyecto y siguiente número
    proj_res = await db.execute(
        select(TicketProject).where(TicketProject.key == payload.project_key).with_for_update()
    )
    project = proj_res.scalar_one_or_none()
    if not project:
        raise HTTPException(status_code=404, detail=f"Proyecto {payload.project_key} no existe")

    next_num = project.next_number
    code = f"{project.key}-{next_num}"
    project.next_number += 1

    ticket_data = payload.model_dump(exclude={"project_key"})

    # Todo ticket nuevo entra al sprint activo salvo que se pida otro. Un ticket
    # sin sprint no aparece en el tablero y se trabaja sin que nadie lo vea.
    if ticket_data.get("sprint_id") is None:
        activo = await db.execute(select(Sprint).where(Sprint.status == SprintStatus.activo))
        sprint = activo.scalars().first()
        if sprint:
            ticket_data["sprint_id"] = sprint.id
    ticket = Ticket(
        project_id=project.id,
        number=next_num,
        code=code,
        **ticket_data,
    )
    db.add(ticket)
    await db.flush()

    # Evento de creación
    event = TicketEvent(
        ticket_id=ticket.id,
        actor=payload.reporter,
        kind=EventKind.comentario,
        to_status=TicketStatus.backlog.value,
        note=f"Ticket creado en backlog: {ticket.title}",
    )
    db.add(event)
    await db.commit()

    query = select(Ticket).where(Ticket.id == ticket.id).options(selectinload(Ticket.events))
    res = await db.execute(query)
    return res.scalar_one()


@router.post("/{code}/notes", response_model=TicketEventOut)
async def add_ticket_note(
    code: str,
    payload: TicketNote,
    db: AsyncSession = Depends(get_db),
    actor: Actor = Depends(require_actor),
):
    """Deja un comentario o un plan en el historial, sin mover el estado."""
    if not payload.note.strip():
        raise HTTPException(status_code=422, detail="La nota no puede estar vacia")
    if payload.kind not in (EventKind.comentario, EventKind.plan):
        raise HTTPException(status_code=422, detail="kind debe ser 'comentario' o 'plan'")

    res = await db.execute(select(Ticket).where(Ticket.code == code))
    ticket = res.scalar_one_or_none()
    if not ticket:
        raise HTTPException(status_code=404, detail=f"Ticket {code} no existe")

    await sprint_editable(db, ticket)

    event = TicketEvent(
        ticket_id=ticket.id,
        actor=payload.actor or actor.nombre,
        kind=payload.kind,
        note=payload.note.strip(),
    )
    db.add(event)
    await db.commit()
    await db.refresh(event)
    return event


@router.patch("/{code}/transition", response_model=TicketOut)
async def transition_ticket(
    code: str,
    payload: TicketTransition,
    db: AsyncSession = Depends(get_db),
    actor: Actor = Depends(require_actor),
):
    query = select(Ticket).where(Ticket.code == code).options(selectinload(Ticket.events))
    result = await db.execute(query)
    ticket = result.scalar_one_or_none()
    if not ticket:
        raise HTTPException(status_code=404, detail="Ticket no encontrado")

    await sprint_editable(db, ticket)

    permitidas = TRANSICIONES.get(ticket.status, [])
    if payload.to_status not in permitidas:
        raise HTTPException(
            status_code=409,
            detail=(f"Transicion invalida: {ticket.status.value} -> {payload.to_status.value}. "
                    f"Permitidas: {', '.join(e.value for e in permitidas) or 'ninguna'}"),
        )
    if payload.to_status == TicketStatus.hecho and not (payload.note or "").strip():
        raise HTTPException(
            status_code=422,
            detail="Para marcar 'hecho' la nota de cierre es obligatoria (tests que pasaron, commit/rama).",
        )

    old_status = ticket.status.value
    new_status = payload.to_status.value

    ticket.status = payload.to_status
    # Se limpia al salir de hecho: si no, un ticket reabierto conserva la fecha
    # de resolucion y parece cerrado en cualquier informe que la mire.
    ticket.resolved_at = datetime.now(timezone.utc) if payload.to_status == TicketStatus.hecho else None

    event = TicketEvent(
        ticket_id=ticket.id,
        actor=payload.actor or actor.nombre,
        kind=EventKind.transicion,
        from_status=old_status,
        to_status=new_status,
        note=(payload.note or "").strip() or None,
    )
    db.add(event)
    await db.commit()
    await db.refresh(ticket)
    return ticket
