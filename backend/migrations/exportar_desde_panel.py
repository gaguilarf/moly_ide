"""PAN-35 — exporta de la MySQL del panel a un JSON, para cargarlo en la Jetson.

Se ejecuta EN EL VPS. No toca nada: solo lee.

Genera el JSON_OBJECT dinamicamente a partir de information_schema en vez de
escribir las columnas a mano: si el esquema del panel tiene una columna que yo
no sabia, entra igual y se ve en el destino, en vez de perderse en silencio.
"""

import json
import subprocess
import sys
import urllib.parse

TABLAS = [
    "ticket_projects",
    "sprints",
    "tickets",
    "ticket_events",
    "registro_proyectos",
    "registro_funcionalidades",
    "registro_cambios",
    "registro_auditorias",
    "registro_hallazgos",
]

dsn = subprocess.run(
    ["grep", "-oE", "^PANEL_DATABASE_URL=.*", "/panel_brittanygroup/.env.local"],
    capture_output=True, text=True,
).stdout.strip().split("=", 1)[1].strip()

u = urllib.parse.urlparse(dsn)
DB = u.path.lstrip("/").split("?")[0]
USER = u.username
PW = urllib.parse.unquote(u.password or "")


def mysql(query):
    # --default-character-set=utf8mb4 no es opcional: sin el, el cliente negocia
    # otro juego y los acentos vuelven rotos. Se detecto porque «Gestion
    # Academica» salia con el caracter de reemplazo.
    r = subprocess.run(
        ["mysql", "--default-character-set=utf8mb4", "-u", USER, f"-p{PW}", DB, "-N", "--raw", "-e", query],
        capture_output=True, text=True, encoding="utf-8",
    )
    if r.returncode != 0:
        print(r.stderr, file=sys.stderr)
        raise SystemExit(1)
    return r.stdout


salida = {}
for tabla in TABLAS:
    cols = [
        c for c in mysql(
            "select column_name from information_schema.columns "
            f"where table_schema='{DB}' and table_name='{tabla}' order by ordinal_position"
        ).split()
    ]
    pares = ", ".join(f"'{c}', `{c}`" for c in cols)
    # JSON_ARRAYAGG sin ORDER BY no garantiza orden; se ordena por la clave
    # primaria para que el volcado sea comparable entre corridas.
    orden = "slug" if tabla == "registro_proyectos" else "id"
    crudo = mysql(
        f"select coalesce(json_arrayagg(fila), json_array()) from "
        f"(select json_object({pares}) as fila from `{tabla}` order by `{orden}`) t"
    ).strip()
    filas = json.loads(crudo) if crudo else []
    salida[tabla] = filas
    print(f"{tabla}: {len(filas)}", file=sys.stderr)

with open("/tmp/migracion_panel.json", "w", encoding="utf-8") as f:
    json.dump(salida, f, ensure_ascii=False)

print("escrito /tmp/migracion_panel.json", file=sys.stderr)
