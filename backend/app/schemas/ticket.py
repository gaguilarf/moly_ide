from pydantic import BaseModel, ConfigDict
from typing import Optional, List
from datetime import datetime, date
from backend.app.models.ticket import (
    TicketType,
    TicketArea,
    TicketPriority,
    TicketStatus,
    TicketSource,
    EventKind,
    SprintStatus,
)


class TicketProjectOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    key: str
    name: str
    target_server: Optional[str] = None
    next_number: int


class SprintOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    goal: Optional[str] = None
    status: SprintStatus
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    closed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime


class SprintCreate(BaseModel):
    name: str
    goal: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None


class TicketEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    ticket_id: int
    at: datetime
    actor: str
    kind: EventKind
    from_status: Optional[str] = None
    to_status: Optional[str] = None
    note: Optional[str] = None


class TicketOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    project_id: int
    sprint_id: Optional[int] = None
    number: int
    code: str
    title: str
    description: Optional[str] = None
    plan: Optional[str] = None
    type: TicketType
    area: Optional[TicketArea] = None
    priority: TicketPriority
    status: TicketStatus
    assignee: Optional[str] = None
    reporter: str
    source: TicketSource
    external_ref: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    resolved_at: Optional[datetime] = None
    events: Optional[List[TicketEventOut]] = None


class TicketCreate(BaseModel):
    project_key: str
    title: str
    description: Optional[str] = None
    plan: Optional[str] = None
    type: TicketType = TicketType.feature
    area: Optional[TicketArea] = None
    priority: TicketPriority = TicketPriority.media
    assignee: Optional[str] = None
    reporter: str = "admin"
    sprint_id: Optional[int] = None
    source: TicketSource = TicketSource.manual
    external_ref: Optional[str] = None


class TicketTransition(BaseModel):
    to_status: TicketStatus
    actor: str = "mobile_user"
    note: Optional[str] = None


class TicketUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    plan: Optional[str] = None
    area: Optional[TicketArea] = None
    priority: Optional[TicketPriority] = None
    assignee: Optional[str] = None
    sprint_id: Optional[int] = None
