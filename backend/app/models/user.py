from sqlalchemy import Column, Integer, String, Boolean, DateTime, Enum as SQLEnum
from sqlalchemy.sql import func
from backend.app.database import Base
import enum


class UserRole(str, enum.Enum):
    admin = "admin"
    developer = "developer"
    viewer = "viewer"


class User(Base):
    __tablename__ = "panel_users"

    id = Column(Integer, primary_key=True, index=True)
    # Nombre de usuario, no correo: aqui no hay envio de correo, ni
    # verificacion, ni recuperacion por esa via, asi que la direccion solo era
    # una cadena larga que escribir en el movil cada vez que caduca la sesion.
    username = Column(String(64), unique=True, nullable=False, index=True)
    name = Column(String(150), default="", nullable=False)
    password_hash = Column(String(255), nullable=False)
    role = Column(SQLEnum(UserRole, name="user_role"), default=UserRole.developer, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
