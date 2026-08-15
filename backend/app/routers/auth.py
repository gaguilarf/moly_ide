from fastapi import APIRouter, Depends, HTTPException, status, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
from backend.app.database import get_db
from backend.app.models.user import User
from backend.app.schemas.auth import UserLogin, UserRegister, UserOut, TokenResponse
from backend.app.services.auth_service import (
    verify_password,
    get_password_hash,
    create_access_token,
    decode_access_token,
)
from backend.app.security import Actor, require_actor

router = APIRouter(prefix="/auth", tags=["Authentication"])


async def get_current_user(
    authorization: Optional[str] = Header(None),
    db: AsyncSession = Depends(get_db),
) -> User:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token de autorización faltante o inválido",
            headers={"WWW-Authenticate": "Bearer"},
        )
    token = authorization.split(" ")[1]
    payload = decode_access_token(token)
    if not payload or "sub" not in payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token inválido o expirado",
            headers={"WWW-Authenticate": "Bearer"},
        )

    email = payload["sub"]
    res = await db.execute(select(User).where(User.email == email))
    user = res.scalar_one_or_none()
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario inactivo o no encontrado",
        )
    return user


@router.post("/register", response_model=UserOut)
async def register(
    payload: UserRegister,
    db: AsyncSession = Depends(get_db),
    actor: Actor = Depends(require_actor),
):
    """Alta de usuario. Exige credencial: un registro abierto en una API que
    controla el VPS significa que cualquiera en la red se hace una cuenta y
    entra. El primer usuario se siembra con `migrations/seed_user.py`."""
    res = await db.execute(select(User).where(User.email == payload.email.lower().strip()))
    if res.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El correo electrónico ya está registrado.",
        )

    user = User(
        email=payload.email.lower().strip(),
        name=payload.name,
        password_hash=get_password_hash(payload.password),
        role=payload.role,
        is_active=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@router.post("/login", response_model=TokenResponse)
async def login(payload: UserLogin, db: AsyncSession = Depends(get_db)):
    email_clean = payload.email.lower().strip()
    res = await db.execute(select(User).where(User.email == email_clean))
    user = res.scalar_one_or_none()

    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Correo o contraseña incorrectos.",
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Esta cuenta está desactivada.",
        )

    token = create_access_token({"sub": user.email, "role": user.role.value, "id": user.id})
    return TokenResponse(access_token=token, token_type="bearer", user=UserOut.model_validate(user))


@router.get("/me", response_model=UserOut)
async def get_my_profile(current_user: User = Depends(get_current_user)):
    return current_user
