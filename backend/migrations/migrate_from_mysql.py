"""
Script de Migración: MySQL (Panel Brittany) -> PostgreSQL (Jetson Orin Nano)
Exporta los tickets, eventos, sprints y registros históricos desde MySQL
e inserta con resolución de conflictos en PostgreSQL.
"""

import os
import sys
import json
import asyncio
import pymysql
import asyncpg
from typing import Dict, Any, List

MYSQL_CONFIG = {
    "host": os.getenv("MYSQL_HOST", "127.0.0.1"),
    "port": int(os.getenv("MYSQL_PORT", "3307")),  # Puerto del túnel SSH
    "user": os.getenv("MYSQL_USER", "root"),
    "password": os.getenv("MYSQL_PASSWORD", ""),
    "database": os.getenv("MYSQL_DB", "panel_brittanygroup"),
    "charset": "utf8mb4",
    "cursorclass": pymysql.cursors.DictCursor,
}

PG_DSN = os.getenv(
    "PG_DSN", "postgresql://postgres:postgres@192.168.0.109:5432/moly_orchestrator"
)


def fetch_from_mysql():
    print("Conectando a MySQL...")
    conn = pymysql.connect(**MYSQL_CONFIG)
    data = {}
    try:
        with conn.cursor() as cursor:
            # 1. Projects
            cursor.execute("SELECT id, `key`, name, next_number FROM ticket_projects")
            data["ticket_projects"] = cursor.fetchall()

            # 2. Sprints
            cursor.execute("SELECT * FROM sprints")
            data["sprints"] = cursor.fetchall()

            # 3. Tickets
            cursor.execute("SELECT * FROM tickets ORDER BY id ASC")
            data["tickets"] = cursor.fetchall()

            # 4. Ticket Events
            cursor.execute("SELECT * FROM ticket_events ORDER BY id ASC")
            data["ticket_events"] = cursor.fetchall()

            # 5. Registro Histórico
            try:
                cursor.execute("SELECT * FROM registro_proyectos")
                data["registro_proyectos"] = cursor.fetchall()
            except Exception:
                data["registro_proyectos"] = []

            try:
                cursor.execute("SELECT * FROM registro_funcionalidades")
                data["registro_funcionalidades"] = cursor.fetchall()
            except Exception:
                data["registro_funcionalidades"] = []

            try:
                cursor.execute("SELECT * FROM registro_cambios")
                data["registro_cambios"] = cursor.fetchall()
            except Exception:
                data["registro_cambios"] = []

            try:
                cursor.execute("SELECT * FROM registro_auditorias")
                data["registro_auditorias"] = cursor.fetchall()
            except Exception:
                data["registro_auditorias"] = []

            try:
                cursor.execute("SELECT * FROM registro_hallazgos")
                data["registro_hallazgos"] = cursor.fetchall()
            except Exception:
                data["registro_hallazgos"] = []

            print(
                f"Extraídos {len(data['tickets'])} tickets, {len(data['ticket_events'])} eventos, {len(data['sprints'])} sprints."
            )
            return data
    finally:
        conn.close()


async def import_to_postgres(data: Dict[str, List[Dict[str, Any]]]):
    print(f"Conectando a PostgreSQL ({PG_DSN})...")
    conn = await asyncpg.connect(PG_DSN)
    try:
        async with conn.transaction():
            # 1. Projects
            for p in data["ticket_projects"]:
                await conn.execute(
                    """
                    INSERT INTO ticket_projects (id, key, name, next_number)
                    VALUES ($1, $2, $3, $4)
                    ON CONFLICT (key) DO UPDATE SET
                        name = EXCLUDED.name,
                        next_number = EXCLUDED.next_number;
                """,
                    p["id"],
                    p["key"],
                    p["name"],
                    p["next_number"],
                )

            # 2. Sprints
            for s in data["sprints"]:
                await conn.execute(
                    """
                    INSERT INTO sprints (id, name, goal, status, start_date, end_date, closed_at, created_at, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                    ON CONFLICT (id) DO NOTHING;
                """,
                    s["id"],
                    s["name"],
                    s.get("goal"),
                    s.get("status", "planificado"),
                    s.get("start_date"),
                    s.get("end_date"),
                    s.get("closed_at"),
                    s.get("created_at"),
                    s.get("updated_at"),
                )

            # 3. Tickets
            for t in data["tickets"]:
                await conn.execute(
                    """
                    INSERT INTO tickets (
                        id, project_id, sprint_id, number, code, title, description,
                        plan, type, area, priority, status, assignee, reporter,
                        source, external_ref, created_at, updated_at, resolved_at
                    ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19
                    ) ON CONFLICT (code) DO NOTHING;
                """,
                    t["id"],
                    t["project_id"],
                    t.get("sprint_id"),
                    t["number"],
                    t["code"],
                    t["title"],
                    t.get("description"),
                    t.get("plan"),
                    t.get("type", "feature"),
                    t.get("area"),
                    t.get("priority", "media"),
                    t.get("status", "backlog"),
                    t.get("assignee"),
                    t.get("reporter", "admin"),
                    t.get("source", "manual"),
                    t.get("external_ref"),
                    t.get("created_at"),
                    t.get("updated_at"),
                    t.get("resolved_at"),
                )

            # 4. Ticket Events
            for ev in data["ticket_events"]:
                await conn.execute(
                    """
                    INSERT INTO ticket_events (id, ticket_id, at, actor, kind, from_status, to_status, note)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    ON CONFLICT (id) DO NOTHING;
                """,
                    ev["id"],
                    ev["ticket_id"],
                    ev["at"],
                    ev["actor"],
                    ev.get("kind", "comentario"),
                    ev.get("from_status"),
                    ev.get("to_status"),
                    ev.get("note"),
                )

            # Resetear secuencias en PostgreSQL
            for table in [
                "ticket_projects",
                "sprints",
                "tickets",
                "ticket_events",
            ]:
                await conn.execute(
                    f"SELECT setval(pg_get_serial_sequence('{table}', 'id'), COALESCE(MAX(id), 1)) FROM {table};"
                )

            print("¡Migración a PostgreSQL completada con éxito!")
    finally:
        await conn.close()


if __name__ == "__main__":
    mysql_data = fetch_from_mysql()
    asyncio.run(import_to_postgres(mysql_data))
