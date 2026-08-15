from pydantic import BaseModel, ConfigDict
from typing import Optional, List
from datetime import datetime
from uuid import UUID
from backend.app.models.claude import ClaudeAccountStatus, ClaudeTaskStatus


class ClaudeAccountOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    alias: str
    email: Optional[str] = None
    status: ClaudeAccountStatus
    rate_limit_resets_at: Optional[datetime] = None
    last_used_at: Optional[datetime] = None
    is_primary: bool
    created_at: datetime


class ClaudeAccountRegister(BaseModel):
    alias: str
    email: Optional[str] = None
    session_token: str
    is_primary: bool = False


class ClaudeTaskCreate(BaseModel):
    ticket_id: Optional[int] = None
    title: str
    prompt: str
    target_repo: Optional[str] = None
    target_branch: Optional[str] = None


class ClaudeHumanFeedback(BaseModel):
    response: str


class ClaudeTaskOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    ticket_id: Optional[int] = None
    account_id: Optional[int] = None
    title: str
    prompt: str
    target_repo: Optional[str] = None
    target_branch: Optional[str] = None
    status: ClaudeTaskStatus
    pending_question: Optional[str] = None
    human_response: Optional[str] = None
    execution_logs: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    finished_at: Optional[datetime] = None
