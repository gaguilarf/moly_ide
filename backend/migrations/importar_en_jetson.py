"""PAN-35 — carga en el PostgreSQL de la Jetson el JSON exportado del panel.

Se ejecuta EN LA JETSON con el python del venv (trae asyncpg).

Sustituye a backend/migrations/migrate_from_mysql.py, que no servia:
  - Leia las cinco tablas registro_* y no insertaba ninguna. Se habrian perdido
    17 funcionalidades, 51 cambios, 3 auditorias y 40 hallazgos sin un solo aviso.
  - No tocaba zonas horarias. El panel guarda DATETIME en hora de Lima y aqui las
    columnas son timestamptz: sin decir el huso, las 212 fichas se habrian
    desplazado cinco horas.
  - Exigia llegar a la MySQL del VPS desde donde corriera, y la Jetson no puede.
    Por eso esto se parte en dos: exportar alli, importar aqui.

Todo va en UNA transaccion: o entra completo o no entra nada. Un volcado a medias
en el que nadie sepa que falta es peor que no haberlo intentado.
"""

import asyncio
import json
import sys
from datetime import date, datetime, timedelta, timezone

LIMA = timezone(timedelta(hours=-5))

DSN = sys.argv[1]
ORIGEN = sys.argv[2] if len(sys.argv) > 2 else "/tmp/migracion_panel.json"

# columna -> tipo de destino. 'ts' = timestamptz, 'd' = date, lo demas se pasa tal cual.
# El tercer elemento es el tipo enum, cuando hay que forzar la conversion.
TABLAS = [
    ("sprints", ["id", "name", "goal", "status", "start_date", "end_date", "closed_at", "created_at", "updated_at"],
     {"start_date": "d", "end_date": "d", "closed_at": "ts", "created_at": "ts", "updated_at": "ts"},
     {"status": "sprint_status"}),
    ("tickets", ["id", "project_id", "sprint_id", "number", "code", "title", "description", "plan",
                 "type", "area", "priority", "status", "assignee", "reporter", "source",
                 "external_ref", "created_at", "updated_at", "resolved_at"],
     {"created_at": "ts", "updated_at": "ts", "resolved_at": "ts"},
     {"type": "ticket_type", "area": "ticket_area", "priority": "ticket_priority",
      "status": "ticket_status", "source": "ticket_source"}),
    ("ticket_events", ["id", "ticket_id", "at", "actor", "kind", "from_status", "to_status", "note"],
     {"at": "ts"}, {"kind": "event_kind"}),
    ("registro_proyectos", ["slug", "nombre", "ticket_key", "repo_path"], {}, {}),
    ("registro_funcionalidades", ["id", "proyecto", "nombre", "descripcion", "doc_path", "estado", "creado_en"],
     {"creado_en": "d"}, {}),
    ("registro_cambios", ["id", "funcionalidad_id", "fecha", "tipo", "descripcion", "commit_ref", "ticket_ref"],
     {"fecha": "d"}, {}),
    ("registro_auditorias", ["id", "proyecto", "fecha", "tipo", "resumen", "doc_path"], {"fecha": "d"}, {}),
    ("registro_hallazgos", ["id", "auditoria_id", "funcionalidad_id", "codigo", "severidad", "titulo",
                            "detalle", "estado", "resolucion", "resuelto_en", "ticket_ref"],
     {"resuelto_en": "d"}, {}),
]

SECUENCIAS = ["ticket_projects", "sprints", "tickets", "ticket_events",
              "registro_funcionalidades", "registro_cambios", "registro_auditorias", "registro_hallazgos"]


def convertir(valor, tipo):
    if valor is None:
        return None
    if tipo == "ts":
        texto = str(valor).replace("T", " ").split(".")[0]
        # El panel guarda la hora de Lima sin decirlo. Se lo decimos aqui: sin
        # esto, PostgreSQL asume UTC y todo se corre cinco horas.
        return datetime.strptime(texto, "%Y-%m-%d %H:%M:%S").replace(tzinfo=LIMA)
    if tipo == "d":
        return date.fromisoformat(str(valor)[:10])
    return valor


async def main():
    import asyncpg

    with open(ORIGEN, encoding="utf-8") as f:
        datos = json.load(f)

    conn = await asyncpg.connect(DSN)
    try:
        async with conn.transaction():
            # ticket_projects va aparte: el destino YA tiene sus proyectos
            # sembrados (incluido MOLY, que no existe en el panel), asi que no se
            # insertan, se concilian POR CLAVE. De paso arregla los nombres, que
            # en la Jetson estaban sembrados con la codificacion rota.
            mapa_proyectos = {}
            for p in datos.get("ticket_projects", []):
                destino_id = await conn.fetchval(
                    """
                    INSERT INTO ticket_projects (key, name, repo_url, next_number)
                    VALUES ($1, $2, $3, $4)
                    ON CONFLICT (key) DO UPDATE
                        SET name = EXCLUDED.name,
                            repo_url = COALESCE(EXCLUDED.repo_url, ticket_projects.repo_url),
                            next_number = EXCLUDED.next_number
                    RETURNING id
                    """,
                    p["key"], p["name"], p.get("repo_url"), p.get("next_number"),
                )
                mapa_proyectos[p["id"]] = destino_id
                if destino_id != p["id"]:
                    print(f"  aviso: {p['key']} es {p['id']} en el panel y {destino_id} aqui; se remapea")
            print(f"ticket_projects: {len(mapa_proyectos)} conciliados por clave")

            # Los tickets apuntan al id del panel; hay que traducirlo al de aqui.
            # Sin esto, un desajuste de ids colgaria cada ticket del proyecto
            # equivocado sin que ninguna restriccion se queje.
            for t in datos.get("tickets", []):
                t["project_id"] = mapa_proyectos.get(t["project_id"], t["project_id"])

            for tabla, columnas, tipos, enums in TABLAS:
                filas = datos.get(tabla, [])
                if not filas:
                    print(f"{tabla}: nada que insertar")
                    continue

                # Solo las columnas que existen de verdad en el origen.
                presentes = [c for c in columnas if c in filas[0]]
                marcadores = ", ".join(
                    f"${i + 1}::{enums[c]}" if c in enums else f"${i + 1}"
                    for i, c in enumerate(presentes)
                )
                sql = (f'INSERT INTO {tabla} ({", ".join(chr(34) + c + chr(34) for c in presentes)}) '
                       f"VALUES ({marcadores})")

                lote = [
                    tuple(convertir(fila.get(c), tipos.get(c)) for c in presentes)
                    for fila in filas
                ]
                await conn.executemany(sql, lote)
                print(f"{tabla}: {len(lote)} filas insertadas")

            # Sin esto, el siguiente ticket que alguien cree arranca en id 1 y
            # choca contra los que acabamos de meter.
            for tabla in SECUENCIAS:
                await conn.execute(
                    f"SELECT setval(pg_get_serial_sequence('{tabla}', 'id'), "
                    f"COALESCE((SELECT MAX(id) FROM {tabla}), 1))"
                )
            print("secuencias recolocadas")
    finally:
        await conn.close()


asyncio.run(main())
