"""
Script para sembrar el usuario administrador en PostgreSQL
Email: gustavo.f.aguilar1998@gmail.com
Password: Gus19982***/
"""

import asyncio
import os
import asyncpg
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

EMAIL = "gustavo.f.aguilar1998@gmail.com"
RAW_PASS = "Gus19982***/"
NAME = "Gustavo Aguilar"
ROLE = "admin"

PG_DSN = os.getenv(
    "PG_DSN", "postgresql://postgres:postgres@192.168.0.109:5432/moly_orchestrator"
)


async def seed_user():
    hashed = pwd_context.hash(RAW_PASS)
    print(f"Generado Hash Bcrypt: {hashed}")

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
