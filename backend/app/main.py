from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from backend.app.config import settings
from backend.app.database import engine, Base
from backend.app.routers import auth, tickets, claude, infra, backups, docs, explorer, registro, documentacion
from backend.app.security import require_actor


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
    except Exception as e:
        # Los esquemas y tipos enumerados ya existen en PostgreSQL
        pass
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


@app.get("/")
async def root():
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "online",
        "target": "Jetson Orin Nano Orchestrator",
    }
