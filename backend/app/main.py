import logging
import os

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager
from sqlalchemy import func, update
from backend.app.config import settings
from backend.app.database import engine, Base, AsyncSessionLocal
from backend.app.models.claude import ClaudeTask, ClaudeTaskStatus
from backend.app.routers import auth, tickets, claude, infra, backups, docs, explorer, registro, documentacion, system
from backend.app.security import require_actor


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
    except Exception as e:
        # Los esquemas y tipos enumerados ya existen en PostgreSQL
        pass

    # Ninguna tarea sobrevive a un reinicio: sus subprocesos mueren con este
    # servicio. Las que quedaron en `ejecutando` son zombis —la app las enseña
    # corriendo para siempre y se niega a borrarlas, porque borrar una viva es
    # tirar la mesa mientras se come—. Se cierran al arrancar, diciendo por que.
    try:
        async with AsyncSessionLocal() as session:
            res = await session.execute(
                update(ClaudeTask)
                .where(ClaudeTask.status == ClaudeTaskStatus.ejecutando)
                .values(
                    status=ClaudeTaskStatus.fallido,
                    execution_logs=func.concat(
                        func.coalesce(ClaudeTask.execution_logs, ""),
                        "\n\n[Interrumpida: el servicio se reinicio mientras "
                        "Claude respondia.]\n",
                    ),
                )
            )
            await session.commit()
            if res.rowcount:
                logging.getLogger("moly").warning(
                    "Cerradas %s tareas que quedaron ejecutando de un arranque "
                    "anterior.",
                    res.rowcount,
                )
    except Exception:
        logging.getLogger("moly").exception("No se pudieron cerrar las tareas zombis.")

    yield
    await engine.dispose()


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Backend Orquestador en Jetson Orin Nano para Control Móvil y Agentes Autónomos Claude.",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# La autenticación se monta en el router entero, no en cada endpoint: así una
# ruta nueva nace protegida en vez de nacer abierta y esperar a que alguien se
# acuerde. Solo `auth` queda fuera, porque ahí vive el login.
protegido = [Depends(require_actor)]

app.include_router(auth.router, prefix=settings.API_V1_STR)
app.include_router(tickets.router, prefix=settings.API_V1_STR, dependencies=protegido)
app.include_router(registro.router, prefix=settings.API_V1_STR, dependencies=protegido)
app.include_router(documentacion.router, prefix=settings.API_V1_STR, dependencies=protegido)
app.include_router(claude.router, prefix=settings.API_V1_STR, dependencies=protegido)
app.include_router(claude.ws_router, prefix=settings.API_V1_STR)  # se autentica solo
app.include_router(infra.router, prefix=settings.API_V1_STR, dependencies=protegido)
app.include_router(backups.router, prefix=settings.API_V1_STR, dependencies=protegido)
app.include_router(docs.router, prefix=settings.API_V1_STR, dependencies=protegido)
app.include_router(explorer.router, prefix=settings.API_V1_STR, dependencies=protegido)
app.include_router(system.router, prefix=settings.API_V1_STR, dependencies=protegido)


@app.get("/status")
async def status():
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "online",
        "target": "Jetson Orin Nano Orchestrator",
    }


# La app web se sirve desde el propio backend, en la raiz. Compartir origen con
# la API evita el CORS entero: el navegador ve la pagina y las llamadas en el
# mismo host y puerto, asi que CORS_ORIGINS puede seguir vacio.
#
# Va en la raiz (no en /app) porque el `<base href="/">` que genera
# `flutter build web` por defecto asume que la app vive ahi; montarla en un
# subpath sin pasarle `--base-href` deja pidiendo sus propios archivos en la
# raiz del dominio, 404 y pagina en blanco (paso el 2026-08-19). El montaje va
# al final, despues de los routers de la API: Starlette prueba las rutas en el
# orden en que se registran, asi que /api/v1/* las atrapan los routers de
# arriba antes de llegar aqui, y todo lo demas cae en el `html=True` de
# StaticFiles, que sirve index.html para las rutas propias de Flutter.
#
# Se monta solo si el directorio existe, para que un backend sin web desplegada
# arranque igual en vez de reventar al inicio.
DIRECTORIO_WEB = os.getenv("WEB_DIR", "/home/jetson/moly_web")
if os.path.isdir(DIRECTORIO_WEB):
    app.mount(
        "/",
        StaticFiles(directory=DIRECTORIO_WEB, html=True),
        name="web",
    )
