-- ============================================================================
-- Moly Orchestrator - PostgreSQL Schema for Jetson Orin Nano
-- Database: moly_orchestrator
-- ============================================================================

-- 1. Extensiones requeridas
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Enumerados para tipado estricto
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('admin', 'developer', 'viewer');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE sprint_status AS ENUM ('planificado', 'activo', 'cerrado');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE ticket_type AS ENUM ('bug', 'feature', 'mejora', 'seguridad', 'deuda_tecnica');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE ticket_area AS ENUM ('back', 'front', 'mobile', 'infra', 'qa', 'pm', 'datos', 'diseno');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE ticket_priority AS ENUM ('critica', 'alta', 'media', 'baja');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE ticket_status AS ENUM ('backlog', 'desarrollo', 'pruebas', 'revision', 'hecho', 'descartado');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE ticket_source AS ENUM ('manual', 'auditoria', 'agente');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE event_kind AS ENUM ('transicion', 'comentario', 'plan', 'bloqueo_agente', 'resolucion_agente');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE claude_account_status AS ENUM ('activa', 'cuota_agotada', 'error_auth', 'inactiva');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE claude_task_status AS ENUM ('pendiente', 'ejecutando', 'bloqueado_esperando_humano', 'completado', 'fallido');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. Usuarios y Credenciales del Orquestador
CREATE TABLE IF NOT EXISTS panel_users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL DEFAULT '',
    password_hash VARCHAR(255) NOT NULL,
    role user_role NOT NULL DEFAULT 'developer',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- El primer usuario NO se siembra aqui: el hash bcrypt de una contrasena real
-- en un fichero versionado es una contrasena publicada, y un hash se ataca
-- fuera de linea sin limite de intentos. Se crea con:
--     SEED_EMAIL=... SEED_PASSWORD=... PG_DSN=... python3 migrations/seed_user.py

-- 4. Proyectos y Sprints
CREATE TABLE IF NOT EXISTS ticket_projects (
    id SERIAL PRIMARY KEY,
    key VARCHAR(6) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    repo_url VARCHAR(255),
    target_server VARCHAR(50) DEFAULT 'vps-brittany',
    next_number INT NOT NULL DEFAULT 1
);

INSERT INTO ticket_projects (key, name, target_server) VALUES
    ('SGA', 'SGA (Sistema de Gestión Académica)', 'vps-brittany'),
    ('TIA', 'tIAcher (App + API)', 'vps-brittany'),
    ('PAN', 'Panel Admin Brittany', 'vps-brittany'),
    ('EBK', 'Ebooks', 'vps-brittany'),
    ('INF', 'Infraestructura VPS & Jetson', 'vps-brittany'),
    ('PAC', 'Portal Académico', 'vps-brittany'),
    ('MOLY', 'Moly IDE & Orquestador', 'jetson')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS sprints (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    goal TEXT,
    status sprint_status NOT NULL DEFAULT 'planificado',
    start_date DATE,
    end_date DATE,
    closed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 5. Tickets e Historial de Eventos
CREATE TABLE IF NOT EXISTS tickets (
    id SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES ticket_projects(id) ON DELETE RESTRICT,
    sprint_id INT REFERENCES sprints(id) ON DELETE SET NULL,
    number INT NOT NULL,
    code VARCHAR(16) NOT NULL UNIQUE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    plan TEXT,
    type ticket_type NOT NULL DEFAULT 'feature',
    area ticket_area,
    priority ticket_priority NOT NULL DEFAULT 'media',
    status ticket_status NOT NULL DEFAULT 'backlog',
    assignee VARCHAR(120),
    reporter VARCHAR(120) NOT NULL,
    source ticket_source NOT NULL DEFAULT 'manual',
    external_ref VARCHAR(50),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMPTZ,
    CONSTRAINT uq_project_number UNIQUE (project_id, number)
);

CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status, priority);
CREATE INDEX IF NOT EXISTS idx_tickets_project ON tickets(project_id);
CREATE INDEX IF NOT EXISTS idx_tickets_sprint ON tickets(sprint_id);

CREATE TABLE IF NOT EXISTS ticket_events (
    id SERIAL PRIMARY KEY,
    ticket_id INT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actor VARCHAR(120) NOT NULL,
    kind event_kind NOT NULL,
    from_status VARCHAR(30),
    to_status VARCHAR(30),
    note TEXT
);

CREATE INDEX IF NOT EXISTS idx_ticket_events_ticket ON ticket_events(ticket_id, at);

-- 6. Motor Claude Dual-Account y Tareas Autónomas
CREATE TABLE IF NOT EXISTS claude_accounts (
    id SERIAL PRIMARY KEY,
    alias VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255),
    session_token_encrypted TEXT,
    status claude_account_status NOT NULL DEFAULT 'activa',
    rate_limit_resets_at TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ,
    is_primary BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS claude_tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_id INT REFERENCES tickets(id) ON DELETE SET NULL,
    account_id INT REFERENCES claude_accounts(id),
    title VARCHAR(255) NOT NULL,
    prompt TEXT NOT NULL,
    target_repo VARCHAR(100),
    target_branch VARCHAR(100),
    status claude_task_status NOT NULL DEFAULT 'pendiente',
    pending_question TEXT,
    human_response TEXT,
    execution_logs TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_claude_tasks_status ON claude_tasks(status);

-- 7. Registro Histórico de Arquitectura (Transversal)
CREATE TABLE IF NOT EXISTS registro_proyectos (
    slug VARCHAR(30) PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    ticket_key VARCHAR(6) UNIQUE,
    repo_path VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS registro_funcionalidades (
    id SERIAL PRIMARY KEY,
    proyecto VARCHAR(30) NOT NULL REFERENCES registro_proyectos(slug) ON DELETE CASCADE,
    nombre VARCHAR(150) NOT NULL,
    descripcion TEXT,
    doc_path VARCHAR(255),
    estado VARCHAR(30) NOT NULL DEFAULT 'activa',
    creado_en DATE NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT uq_proyecto_nombre UNIQUE (proyecto, nombre)
);

CREATE TABLE IF NOT EXISTS registro_cambios (
    id SERIAL PRIMARY KEY,
    funcionalidad_id INT NOT NULL REFERENCES registro_funcionalidades(id) ON DELETE CASCADE,
    fecha DATE NOT NULL DEFAULT CURRENT_DATE,
    tipo VARCHAR(30) NOT NULL,
    descripcion TEXT NOT NULL,
    commit_ref VARCHAR(64),
    ticket_ref VARCHAR(16)
);

CREATE TABLE IF NOT EXISTS registro_auditorias (
    id SERIAL PRIMARY KEY,
    proyecto VARCHAR(30) NOT NULL REFERENCES registro_proyectos(slug) ON DELETE CASCADE,
    fecha DATE NOT NULL DEFAULT CURRENT_DATE,
    tipo VARCHAR(80) NOT NULL,
    resumen TEXT,
    doc_path VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS registro_hallazgos (
    id SERIAL PRIMARY KEY,
    auditoria_id INT NOT NULL REFERENCES registro_auditorias(id) ON DELETE CASCADE,
    funcionalidad_id INT REFERENCES registro_funcionalidades(id) ON DELETE SET NULL,
    codigo VARCHAR(20),
    severidad VARCHAR(20) NOT NULL,
    titulo VARCHAR(250) NOT NULL,
    detalle TEXT,
    estado VARCHAR(30) NOT NULL DEFAULT 'abierto',
    resolucion TEXT,
    resuelto_en DATE,
    ticket_ref VARCHAR(16)
);
