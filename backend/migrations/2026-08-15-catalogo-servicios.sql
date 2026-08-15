-- INF-51 — Catalogo de servicios del ecosistema.
--
--   docker exec -i postgres psql -U lab_admin -d moly_orchestrator < este.sql
--
-- POR QUE EXISTE, con el caso que lo motivo: greenter, el microservicio PHP de
-- facturacion SUNAT, se describe a mano en al menos nueve documentos. No es un
-- problema de formato: es que greenter NO EXISTE COMO ENTIDAD en ningun sitio,
-- solo como parrafos repetidos dentro del documento de quien lo usa. Vive ademas
-- dentro del repo del SGA, asi que el dia que otro proyecto lo use se duplica
-- otra vez.
--
-- Aqui cada servicio es UNA fila, y los temas de documentacion la enlazan por
-- `doc_temas.servicio_ref` en vez de volver a contarla.
--
-- LO QUE SE PUEDE GENERAR NO SE ESCRIBE: puerto y unit salen de `ss -tlnp` y
-- `systemctl`, que este backend ya consulta por SSH. Lo escrito a mano caduca en
-- silencio; lo generado se contrasta contra la maquina.

CREATE TYPE servicio_categoria AS ENUM (
    'aplicacion', 'datos', 'observabilidad', 'seguridad', 'sistema', 'herramienta'
);
CREATE TYPE servicio_entorno AS ENUM ('produccion', 'desarrollo', 'compartido');
CREATE TYPE servicio_estado AS ENUM ('activo', 'detenido', 'retirado', 'planificado');

CREATE TABLE IF NOT EXISTS servicios (
    id SERIAL PRIMARY KEY,
    slug VARCHAR(60) NOT NULL UNIQUE,
    nombre VARCHAR(120) NOT NULL,
    categoria servicio_categoria NOT NULL,
    entorno servicio_entorno NOT NULL DEFAULT 'produccion',
    proposito TEXT NULL,
    stack VARCHAR(120) NULL,
    repo VARCHAR(120) NULL,
    -- Donde corre. `host` es la maquina (vps-brittany, jetson) y no una IP: las
    -- IP cambian y el nombre no.
    host VARCHAR(60) NOT NULL DEFAULT 'vps-brittany',
    unit VARCHAR(80) NULL,
    puerto INT NULL,
    responsable VARCHAR(120) NULL,
    estado servicio_estado NOT NULL DEFAULT 'activo',
    -- La frescura, igual que en las secciones de documentacion: una fila del
    -- catalogo se pudre exactamente igual que un .md si nadie la comprueba.
    verificado_en DATE NULL,
    verificado_por VARCHAR(120) NULL,
    -- Marca lo que se rellena solo desde la maquina, para no editarlo a mano y
    -- que la siguiente sincronizacion lo pise sin avisar.
    origen VARCHAR(20) NOT NULL DEFAULT 'manual',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_servicios_host ON servicios (host, entorno);

-- Las dependencias entre servicios: es lo que hoy no existe en ningun sitio y
-- lo unico que responde "si tumbo esto, que se cae".
CREATE TABLE IF NOT EXISTS servicio_dependencias (
    id SERIAL PRIMARY KEY,
    servicio_id INT NOT NULL REFERENCES servicios(id) ON DELETE CASCADE,
    depende_de_id INT NOT NULL REFERENCES servicios(id) ON DELETE CASCADE,
    -- 'dura' = sin esto no arranca o no funciona; 'blanda' = se degrada.
    tipo VARCHAR(10) NOT NULL DEFAULT 'dura',
    nota VARCHAR(250) NULL,
    UNIQUE (servicio_id, depende_de_id),
    -- Un servicio que depende de si mismo no dice nada y ensucia el grafo.
    CHECK (servicio_id <> depende_de_id)
);
CREATE INDEX IF NOT EXISTS idx_servdep_depende ON servicio_dependencias (depende_de_id);
