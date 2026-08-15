# ⚡ Moly Backend Orchestrator

Servicio backend en **FastAPI** diseñado para ejecutarse en el **Jetson Orin Nano**, coordinando agentes de desarrollo autónomos (Claude Code CLI), sincronización de tickets, supervisión de puertos y documentación viva.

---

## 📁 Estructura del Backend

```
backend/
├── app/
│   ├── config.py                 # Variables de entorno y rutas base
│   ├── database.py               # Motor Async SQLAlchemy + asyncpg
│   ├── main.py                   # Entrypoint FastAPI y ciclo de vida (lifespan)
│   ├── models/                   # Modelos SQLAlchemy (tickets, usuarios, claude, etc.)
│   ├── routers/                  # Routers API REST y WebSockets
│   │   ├── auth.py               # /api/v1/auth (login, register, me)
│   │   ├── tickets.py            # /api/v1/tickets
│   │   ├── claude.py             # /api/v1/claude (tareas, cuentas, websocket)
│   │   ├── infra.py              # /api/v1/infra (puertos multi-nodo)
│   │   ├── backups.py            # /api/v1/backups
│   │   ├── docs.py               # /api/v1/docs
│   │   └── explorer.py           # /api/v1/explorer
│   ├── schemas/                  # Esquemas de validación Pydantic
│   └── services/                 # Lógica de orquestación
│       ├── auth_service.py       # Hashing con bcrypt y tokens JWT
│       ├── claude_orchestrator.py # Motor dual-account y freno duro interactivo
│       ├── ssh_inspector.py      # Inspección remota con asyncssh
│       └── doc_service.py        # Indexación de documentación Markdown
├── migrations/
│   ├── schema_postgresql.sql     # DDL completo para PostgreSQL
│   ├── migrate_from_mysql.py     # Script de migración MySQL -> PostgreSQL
│   └── seed_user.py              # Sembrador de usuario administrador
├── moly-orchestrator.service     # Unit de systemd para Linux
└── requirements.txt              # Dependencias Python
```

---

## 🗄️ Base de Datos PostgreSQL

- **Contenedor Docker**: `postgres` (`pgvector/pgvector:pg17`) en `192.168.0.109:5432`.
- **Base de Datos**: `moly_orchestrator`.
- **Tablas principales**:
  - `panel_users`: Usuarios del sistema con contraseñas encriptadas en `bcrypt`.
  - `claude_accounts`: Cuentas de Claude con estados `activa`, `cuota_agotada`, `inactiva`.
  - `claude_tasks`: Registro de tareas ejecutadas por Claude con logs y detección de bloqueos.
  - `ticket_projects`, `sprints`, `tickets`, `ticket_events`: Sistema ágil de tickets e historial de auditoría.

---

## 🚀 Despliegue y Ejecución en el Jetson

```bash
# 1. Crear venv e instalar dependencias
python3 -m venv /home/jetson/moly_backend/venv
/home/jetson/moly_backend/venv/bin/pip install -r /home/jetson/moly_backend/backend/requirements.txt

# 2. Iniciar servidor FastAPI en segundo plano
cd /home/jetson/moly_backend
nohup /home/jetson/moly_backend/venv/bin/python3 -m uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 > /home/jetson/moly_backend/backend.log 2>&1 </dev/null &

# 3. Monitorear logs
tail -f /home/jetson/moly_backend/backend.log
```
