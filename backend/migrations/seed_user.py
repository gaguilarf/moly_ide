"""Siembra el primer usuario del panel de Moly en PostgreSQL.

Existe porque POST /auth/register exige credencial: el primer usuario no puede
crearse por la API, que es justo lo que se queria -un registro abierto en una
API que controla el VPS significa que cualquiera en la red se hace una cuenta-.

La contrasena se pasa por entorno y NO se escribe aqui. Antes estaba en claro en
este mismo fichero, junto al correo, y entro asi al repositorio.

    SEED_EMAIL=... SEED_PASSWORD=... python3 migrations/seed_user.py
"""

import asyncio
import os
import asyncpg
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

EMAIL = os.environ.get("SEED_EMAIL", "")
RAW_PASS = os.environ.get("SEED_PASSWORD", "")
NAME = os.environ.get("SEED_NAME", "Administrador")
ROLE = os.environ.get("SEED_ROLE", "admin")

if not EMAIL or not RAW_PASS:
    raise SystemExit("Faltan SEED_EMAIL y SEED_PASSWORD en el entorno.")

# Sin valor por defecto: el que habia apuntaba a un usuario que no existe
# (postgres) y ademas llevaba una credencial escrita en el repositorio.
PG_DSN = os.environ.get("PG_DSN", "")
if not PG_DSN:
    raise SystemExit("Falta PG_DSN en el entorno.")


async def seed_user():
    hashed = pwd_context.hash(RAW_PASS)
    # No se imprime el hash: acaba en los logs del terminal.

    try:
        conn = await asyncpg.connect(PG_DSN)
        await conn.execute(
            """
            INSERT INTO panel_users (email, name, password_hash, role, is_active)
            VALUES ($1, $2, $3, $4, true)
            ON CONFLICT (email) DO UPDATE SET
                password_hash = EXCLUDED.password_hash,
                name = EXCLUDED.name,
                role = EXCLUDED.role,
                is_active = true;
        """,
            EMAIL,
            NAME,
            hashed,
            ROLE,
        )
        await conn.close()
        print(f"Usuario {EMAIL} sembrado con éxito en PostgreSQL!")
    except Exception as e:
        print(f"Aviso: No se pudo conectar a PostgreSQL directamente ({e}).")
        print("Puedes ejecutar la siguiente sentencia SQL en tu base de datos:")
        print(f"""
INSERT INTO panel_users (email, name, password_hash, role, is_active)
VALUES ('{EMAIL}', '{NAME}', '{hashed}', '{ROLE}', true)
ON CONFLICT (email) DO UPDATE SET
    password_hash = EXCLUDED.password_hash,
    name = EXCLUDED.name,
    role = EXCLUDED.role,
    is_active = true;
        """)


if __name__ == "__main__":
    asyncio.run(seed_user())
