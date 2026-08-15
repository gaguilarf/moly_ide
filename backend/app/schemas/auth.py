from pydantic import BaseModel, ConfigDict, model_validator
from typing import Optional
from datetime import datetime
from backend.app.models.user import UserRole


class UserLogin(BaseModel):
    """Credenciales de acceso.

    `email` sigue aceptandose como puente: una app sin actualizar manda ese
    campo, y romperle el acceso a quien todavia no ha instalado la version nueva
    es la peor forma de estrenar un cambio de login. Se puede retirar cuando
    todos los dispositivos esten al dia.
    """

    username: Optional[str] = None
    email: Optional[str] = None
    password: str

    @model_validator(mode="after")
    def exigir_identificador(self):
        if not (self.username or self.email):
            raise ValueError("Falta el nombre de usuario.")
        return self

    @property
    def identificador(self) -> str:
        return (self.username or self.email or "").strip().lower()


class UserRegister(BaseModel):
    username: str
    password: str
    name: str = ""
    role: UserRole = UserRole.developer


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    name: str
    role: UserRole
    is_active: bool
    created_at: datetime


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut
