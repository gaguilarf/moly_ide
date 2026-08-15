from sqlalchemy import Column, Integer, String, Text, DateTime, Boolean, ForeignKey, Enum as SQLEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from backend.app.database import Base
import enum
import uuid


class ClaudeAccountStatus(str, enum.Enum):
    activa = "activa"
    cuota_agotada = "cuota_agotada"
    error_auth = "error_auth"
    inactiva = "inactiva"


class ClaudeTaskStatus(str, enum.Enum):
    pendiente = "pendiente"
    ejecutando = "ejecutando"
    bloqueado_esperando_humano = "bloqueado_esperando_humano"
    completado = "completado"
    fallido = "fallido"


class ClaudeAccount(Base):
    __tablename__ = "claude_accounts"

    id = Column(Integer, primary_key=True, index=True)
    alias = Column(String(50), unique=True, nullable=False)
    email = Column(String(255), nullable=True)
    session_token_encrypted = Column(Text, nullable=True)
    status = Column(SQLEnum(ClaudeAccountStatus, name="claude_account_status"), default=ClaudeAccountStatus.activa, nullable=False)
    rate_limit_resets_at = Column(DateTime(timezone=True), nullable=True)
    last_used_at = Column(DateTime(timezone=True), nullable=True)
    is_primary = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    tasks = relationship("ClaudeTask", back_populates="account")


class ClaudeTask(Base):
    __tablename__ = "claude_tasks"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    ticket_id = Column(Integer, ForeignKey("tickets.id", ondelete="SET NULL"), nullable=True)
    account_id = Column(Integer, ForeignKey("claude_accounts.id"), nullable=True)
    title = Column(String(255), nullable=False)
    prompt = Column(Text, nullable=False)
    target_repo = Column(String(100), nullable=True)
    target_branch = Column(String(100), nullable=True)
    status = Column(SQLEnum(ClaudeTaskStatus, name="claude_task_status"), default=ClaudeTaskStatus.pendiente, nullable=False, index=True)
    pending_question = Column(Text, nullable=True)  # Pregunta del freno duro
    human_response = Column(Text, nullable=True)    # Respuesta provista desde la app móvil
    execution_logs = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    finished_at = Column(DateTime(timezone=True), nullable=True)

    account = relationship("ClaudeAccount", back_populates="tasks")
    ticket = relationship("Ticket")
