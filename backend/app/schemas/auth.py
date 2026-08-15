from pydantic import BaseModel, EmailStr, ConfigDict
from typing import Optional
from datetime import datetime
from backend.app.models.user import UserRole


class UserLogin(BaseModel):
    email: str
    password: str


class UserRegister(BaseModel):
    email: str
    password: str
    name: str = ""
    role: UserRole = UserRole.developer


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: str
    name: str
    role: UserRole
    is_active: bool
    created_at: datetime


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut
