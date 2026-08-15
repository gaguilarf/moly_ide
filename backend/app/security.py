"""Puerta de entrada de la API.

Hay dos clases de actor y una sola comprobación: la app móvil entra con el JWT
que emite `/auth/login`, y los agentes con el token de servicio más su nombre
(`X-Agent-Name`), que es el mismo patrón que ya usaban contra el panel.

Se aplica como dependencia del **router entero** en `main.py`, nunca endpoint
por endpoint: lo segundo se olvida en cuanto alguien añade una ruta, y así es
como este backend acabó sirviendo tickets, el explorador de `.env` y el motor de
Claude sin pedir credencial a nadie.
"""

import hmac
from dataclasses import dataclass
from typing import Optional

from fastapi import Depends, Header, HTTPException, WebSocket, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.app.config import settings
from backend.app.database import AsyncSessionLocal, get_db
from backend.app.models.user import User
from backend.app.services.auth_service import decode_access_token

NO_AUTORIZADO = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Credencial ausente o inválida",
    headers={"WWW-Authenticate": "Bearer"},
)


@dataclass(frozen=True)
class Actor:
    """Quién está llamando. `nombre` es lo que se escribe en el historial."""

    tipo: str  # "usuario" | "agente"
    nombre: str
    usuario: Optional[User] = None


def extraer_token(authorization: Optional[str]) -> Optional[str]:
    if not authorization:
        return None
    partes = authorization.split(" ", 1)
    if len(partes) != 2 or partes[0].lower() != "bearer":
        return None
    return partes[1].strip() or None


def es_token_de_agente(token: str) -> bool:
    # compare_digest y no ==: comparar tokens carácter a carácter deja medir
    # cuántos aciertas por el tiempo de respuesta.
    #
    # Se comparan los bytes: con cadenas, compare_digest lanza TypeError en
    # cuanto el token trae un carácter no ASCII, y eso convertía un 401 en un
    # 500 —basta con mandar una eñe para tirar la comprobación—.
    try:
        return hmac.compare_digest(
            token.encode("utf-8"), settings.AGENT_API_TOKEN.encode("utf-8")
        )
    except (AttributeError, UnicodeError):
        return False


async def resolver_actor(
    token: Optional[str],
    nombre_agente: Optional[str],
    db: AsyncSession,
) -> Optional[Actor]:
    """Devuelve el actor, o None si la credencial no vale. No lanza."""
    if not token:
        return None

    if es_token_de_agente(token):
        # El nombre es obligatorio: un evento firmado por «alguien con el token»
        # no sirve para saber quién movió un ticket.
        if not nombre_agente or not nombre_agente.strip():
            return None
        return Actor(tipo="agente", nombre=f"agente:{nombre_agente.strip()[:100]}")

    payload = decode_access_token(token)
    if not payload or "sub" not in payload:
        return None

    resultado = await db.execute(select(User).where(User.email == payload["sub"]))
    usuario = resultado.scalar_one_or_none()
    if not usuario or not usuario.is_active:
        return None

    return Actor(tipo="usuario", nombre=usuario.email, usuario=usuario)


async def require_actor(
    authorization: Optional[str] = Header(None),
    x_agent_name: Optional[str] = Header(None),
    db: AsyncSession = Depends(get_db),
) -> Actor:
    """Dependencia estándar de la API. Sin credencial válida, 401."""
    actor = await resolver_actor(extraer_token(authorization), x_agent_name, db)
    if actor is None:
        raise NO_AUTORIZADO
    return actor


async def require_admin(actor: Actor = Depends(require_actor)) -> Actor:
    """Para lo que reparte privilegio. Tener credencial no es tener permiso.

    Deja fuera a los agentes a propósito: el token de servicio lo comparten
    varios automatismos, así que no identifica a una persona y no puede ser la
    llave de las operaciones que crean cuentas.
    """
    if actor.tipo != "usuario" or actor.usuario is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Esta operación exige una sesión de usuario, no un token de agente.",
        )
    if actor.usuario.role.value != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Esta operación exige rol de administrador.",
        )
    return actor


async def actor_de_websocket(websocket: WebSocket) -> Optional[Actor]:
    """Igual que `require_actor`, pero para un WebSocket.

    Acepta el token por cabecera y también por parámetro de consulta: el cliente
    de Flutter no puede poner cabeceras en el WebSocket en todas las
    plataformas. Devuelve None en vez de lanzar porque en un WebSocket hay que
    cerrar con código, no responder un 401.
    """
    token = extraer_token(websocket.headers.get("authorization"))
    if not token:
        token = websocket.query_params.get("token")

    nombre_agente = websocket.headers.get("x-agent-name") or websocket.query_params.get(
        "agent_name"
    )

    async with AsyncSessionLocal() as db:
        return await resolver_actor(token, nombre_agente, db)
