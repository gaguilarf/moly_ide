from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from sqlalchemy.orm import selectinload
from typing import List, Optional
from datetime import datetime, timezone
from backend.app.database import get_db
from backend.app.models.ticket import (
    Ticket,
    TicketProject,
    Sprint,
    TicketEvent,
    TicketStatus,
    EventKind,
)
from backend.app.schemas.ticket import (
    TicketOut,
    TicketCreate,
    TicketTransition,
    TicketUpdate,
    TicketProjectOut,
    SprintOut,
    SprintCreate,
)

router = APIRouter(prefix="/tickets", tags=["Tickets & Sprints"])


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


@router.patch("/{code}/transition", response_model=TicketOut)
async def transition_ticket(code: str, payload: TicketTransition, db: AsyncSession = Depends(get_db)):
    query = select(Ticket).where(Ticket.code == code).options(selectinload(Ticket.events))
    result = await db.execute(query)
    ticket = result.scalar_one_or_none()
    if not ticket:
        raise HTTPException(status_code=404, detail="Ticket no encontrado")

    old_status = ticket.status.value
    new_status = payload.to_status.value

    ticket.status = payload.to_status
    if payload.to_status == TicketStatus.hecho:
        ticket.resolved_at = datetime.now(timezone.utc)

    event = TicketEvent(
        ticket_id=ticket.id,
        actor=payload.actor,
        kind=EventKind.transicion,
        from_status=old_status,
        to_status=new_status,
        note=payload.note,
    )
    db.add(event)
    await db.commit()
    await db.refresh(ticket)
    return ticket
