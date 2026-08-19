"""Ciclo de vida de un ticket: catalogo estatico de solo lectura, servido para
que un agente (o una persona) sepa que hacer paso a paso al tomar un ticket.

Mismo espiritu que TRANSICIONES en tickets.py: una estructura fija en codigo,
no una tabla nueva -- no hace falta persistencia para un catalogo que no
cambia por ticket, solo por decision de proceso (y esas se versionan en git,
no en la base).

/tickets/lifecycle (JSON, protegido) es para agentes/tooling.
/flujo (HTML, publica) es la misma data para que una persona la vea en el
navegador sin necesitar un token -- no expone nada sensible, es la
descripcion del proceso, no datos de negocio.
"""

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

# `router` va protegido en main.py (igual que el resto de la API) porque ahi
# nace toda ruta nueva; `public_router` queda deliberadamente afuera de esa
# lista, igual que `auth`, porque /flujo es una pagina de referencia sin datos
# de negocio -- una persona la abre en el navegador sin token, igual que abre
# la app Flutter servida en la raiz.
router = APIRouter(tags=["Ciclo de vida del ticket"])
public_router = APIRouter(tags=["Ciclo de vida del ticket (pagina publica)"])

PASOS = [
    {
        "id": "analisis",
        "titulo": "Análisis",
        "que_hace_el_agente": (
            "Lee el ticket completo (título, descripción, eventos previos). "
            "Si el pedido cruza más de un área (ej. API + pantalla), lo separa "
            "en tickets distintos en vez de mezclar."
        ),
        "artefactos": ["Ticket movido a 'desarrollo' con una nota inicial"],
        "condiciones": [],
    },
    {
        "id": "plan",
        "titulo": "Plan",
        "que_hace_el_agente": (
            "Para cambios no triviales (arquitectura, múltiples archivos, "
            "enfoque ambiguo), escribe un plan antes de tocar código y lo deja "
            "como nota del ticket."
        ),
        "artefactos": ["Nota de plan en el ticket (kind='plan')"],
        "condiciones": [
            "Cambios en emisión SUNAT/facturación, migraciones destructivas o "
            "rotación de secretos requieren aprobación humana explícita antes "
            "de este paso — freno duro, no una sugerencia.",
        ],
    },
    {
        "id": "rama",
        "titulo": "Rama",
        "que_hace_el_agente": (
            "Ramifica desde la rama de integración del repo, al día "
            "(`git fetch --prune` primero, verificar contra `git branch -r` no "
            "contra el clon local). Una rama por ticket, nombrada por el ticket."
        ),
        "artefactos": ["Rama nueva: feat/<CODIGO>-descripcion-corta"],
        "condiciones": [],
    },
    {
        "id": "desarrollo",
        "titulo": "Desarrollo",
        "que_hace_el_agente": (
            "Implementa el cambio siguiendo los patrones ya establecidos del "
            "repo (layout de capas, convenciones de commits, reglas de "
            "seguridad del CLAUDE.md del repo). No debilita guards, "
            "validaciones ni tests para que algo pase."
        ),
        "artefactos": ["Commits con Conventional Commits, referenciando el ticket"],
        "condiciones": [],
    },
    {
        "id": "pruebas",
        "titulo": "Pruebas",
        "que_hace_el_agente": (
            "Corre los tests del área afectada (no solo el archivo tocado). "
            "En repos sin CI de tests (los fronts), corre lint/typecheck/tests "
            "localmente porque nadie más lo va a comprobar."
        ),
        "artefactos": ["Tests del área en verde"],
        "condiciones": [
            "Si el cambio toca auth, pagos, SUNAT o PII: correr también la "
            "suite de seguridad del repo si existe (ej. test:security).",
        ],
    },
    {
        "id": "revision",
        "titulo": "Revisión",
        "que_hace_el_agente": (
            "Corre /code-review sobre el diff. Si el cambio toca auth, pagos, "
            "SUNAT o PII, corre también /security-review. Aplica los hallazgos "
            "antes de seguir."
        ),
        "artefactos": ["Hallazgos de /code-review resueltos o descartados con razón"],
        "condiciones": [
            "Nunca se mueve a 'hecho' con hallazgos críticos abiertos sin "
            "resolución explícita.",
        ],
    },
    {
        "id": "documentacion",
        "titulo": "Documentación",
        "que_hace_el_agente": (
            "Si el cambio afecta una funcionalidad ya documentada (CLAUDE.md "
            "de un repo, o un tema de documentación viva), la actualiza en el "
            "mismo ticket — no la deja para después. Si es una decisión "
            "arquitectónica, considera si amerita un ADR."
        ),
        "artefactos": ["CLAUDE.md y/o documentación viva al día"],
        "condiciones": [],
    },
    {
        "id": "hecho",
        "titulo": "Hecho + Registro",
        "que_hace_el_agente": (
            "Mergea a la rama de integración, borra la rama (local y remota). "
            "Mueve el ticket a 'hecho' con una nota de cierre — a 'hecho' solo "
            "se llega desde 'revisión' y con nota de cierre, nunca directo. "
            "Registra el cambio en registro_cambios si corresponde a una "
            "funcionalidad trackeada."
        ),
        "artefactos": [
            "Rama borrada (local y remota)",
            "Ticket en 'hecho' con nota de cierre",
            "Entrada en registro_cambios (si aplica)",
        ],
        "condiciones": [],
    },
]


@router.get("/tickets/lifecycle")
async def ciclo_de_vida_ticket():
    return {"pasos": PASOS}


def _render_html() -> str:
    filas = ""
    for i, p in enumerate(PASOS, start=1):
        artefactos = "".join(f"<li>{a}</li>" for a in p["artefactos"])
        condiciones = "".join(f"<li class='cond'>⚠ {c}</li>" for c in p["condiciones"])
        filas += f"""
        <section class="paso">
          <h2><span class="num">{i}</span> {p['titulo']}</h2>
          <p>{p['que_hace_el_agente']}</p>
          {f'<ul class="artefactos">{artefactos}</ul>' if artefactos else ''}
          {f'<ul class="condiciones">{condiciones}</ul>' if condiciones else ''}
        </section>"""

    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<title>Ciclo de vida de un ticket — Brittany Group</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root {{ color-scheme: light dark; }}
  body {{ font-family: -apple-system, system-ui, sans-serif; max-width: 760px; margin: 0 auto; padding: 2rem 1.25rem 4rem; line-height: 1.5; }}
  h1 {{ font-size: 1.4rem; }}
  .paso {{ border-left: 3px solid #2563eb; padding: 0.25rem 0 0.25rem 1rem; margin: 1.5rem 0; }}
  .num {{ display: inline-flex; align-items: center; justify-content: center; width: 1.6rem; height: 1.6rem; border-radius: 50%; background: #2563eb; color: white; font-size: 0.85rem; margin-right: 0.5rem; }}
  h2 {{ font-size: 1.05rem; margin: 0 0 0.4rem; }}
  ul {{ margin: 0.4rem 0 0; padding-left: 1.2rem; }}
  .condiciones {{ list-style: none; padding-left: 0; }}
  .cond {{ color: #b45309; font-size: 0.9rem; }}
</style></head>
<body>
  <h1>Ciclo de vida de un ticket</h1>
  <p>Qué hace un agente (o una persona) desde que toma un ticket hasta que lo cierra. Fuente: <code>GET /api/v1/tickets/lifecycle</code>.</p>
  {filas}
</body></html>"""


@public_router.get("/flujo", response_class=HTMLResponse, include_in_schema=False)
async def pagina_flujo():
    return HTMLResponse(_render_html())
