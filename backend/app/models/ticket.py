from sqlalchemy import Column, Integer, String, Text, DateTime, Date, ForeignKey, Enum as SQLEnum
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from backend.app.database import Base
import enum


class SprintStatus(str, enum.Enum):
    planificado = "planificado"
    activo = "activo"
    cerrado = "cerrado"


class TicketType(str, enum.Enum):
    bug = "bug"
    feature = "feature"
    mejora = "mejora"
    seguridad = "seguridad"
    deuda_tecnica = "deuda_tecnica"


class TicketArea(str, enum.Enum):
    back = "back"
    front = "front"
    mobile = "mobile"
    infra = "infra"
    qa = "qa"
    pm = "pm"
    datos = "datos"
    diseno = "diseno"


class TicketPriority(str, enum.Enum):
    critica = "critica"
    alta = "alta"
    media = "media"
    baja = "baja"


class TicketStatus(str, enum.Enum):
    backlog = "backlog"
    desarrollo = "desarrollo"
    pruebas = "pruebas"
    revision = "revision"
    hecho = "hecho"
    descartado = "descartado"


class TicketSource(str, enum.Enum):
    manual = "manual"
    auditoria = "auditoria"
    agente = "agente"


class EventKind(str, enum.Enum):
    transicion = "transicion"
    comentario = "comentario"
    plan = "plan"
    bloqueo_agente = "bloqueo_agente"
    resolucion_agente = "resolucion_agente"


class TicketProject(Base):
    __tablename__ = "ticket_projects"

    id = Column(Integer, primary_key=True, index=True)
    key = Column(String(6), unique=True, nullable=False, index=True)
    name = Column(String(100), nullable=False)
    repo_url = Column(String(255), nullable=True)
    target_server = Column(String(50), default="vps-brittany")
    next_number = Column(Integer, default=1, nullable=False)

    tickets = relationship("Ticket", back_populates="project")


class Sprint(Base):
    __tablename__ = "sprints"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    goal = Column(Text, nullable=True)
    status = Column(SQLEnum(SprintStatus), default=SprintStatus.planificado, nullable=False)
    start_date = Column(Date, nullable=True)
    end_date = Column(Date, nullable=True)
    closed_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    tickets = relationship("Ticket", back_populates="sprint")


class Ticket(Base):
    __tablename__ = "tickets"

    id = Column(Integer, primary_key=True, index=True)
    project_id = Column(Integer, ForeignKey("ticket_projects.id"), nullable=False)
    sprint_id = Column(Integer, ForeignKey("sprints.id"), nullable=True)
    number = Column(Integer, nullable=False)
    code = Column(String(16), unique=True, nullable=False, index=True)
    title = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    plan = Column(Text, nullable=True)
    type = Column(SQLEnum(TicketType), default=TicketType.feature, nullable=False)
    area = Column(SQLEnum(TicketArea), nullable=True)
    priority = Column(SQLEnum(TicketPriority), default=TicketPriority.media, nullable=False)
    status = Column(SQLEnum(TicketStatus), default=TicketStatus.backlog, nullable=False)
    assignee = Column(String(120), nullable=True)
    reporter = Column(String(120), nullable=False, default="admin")
    source = Column(SQLEnum(TicketSource), default=TicketSource.manual, nullable=False)
    external_ref = Column(String(50), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    resolved_at = Column(DateTime(timezone=True), nullable=True)

    project = relationship("TicketProject", back_populates="tickets")
    sprint = relationship("Sprint", back_populates="tickets")
    events = relationship("TicketEvent", back_populates="ticket", cascade="all, delete-orphan")


class TicketEvent(Base):
    __tablename__ = "ticket_events"

    id = Column(Integer, primary_key=True, index=True)
    ticket_id = Column(Integer, ForeignKey("tickets.id", ondelete="CASCADE"), nullable=False)
    at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    actor = Column(String(120), nullable=False)
    kind = Column(SQLEnum(EventKind), nullable=False)
    from_status = Column(String(30), nullable=True)
    to_status = Column(String(30), nullable=True)
    note = Column(Text, nullable=True)

    ticket = relationship("Ticket", back_populates="events")
