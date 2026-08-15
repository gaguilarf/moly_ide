-- INF-50 — La documentacion viva se muda al Jetson (ADR-004).
--
--   docker exec -i postgres psql -U lab_admin -d moly_orchestrator < este.sql
--
-- No hay datos que migrar: las tablas doc_* del panel estan vacias a proposito
-- (la semilla de greenter se borro para no contaminar con contenido inventado),
-- asi que esto rehace el ESQUEMA, no copia contenido.
--
-- Se conserva entero lo que decidio ADR-003 con la correccion de PAN-33:
--
--   La unidad NO es el documento sino la SECCION, y es ahi donde vive la
--   etiqueta de audiencia. No es un control de acceso -aqui solo entran
--   desarrolladores-: es lo que permitira servir estos datos fuera del equipo
--   sin que un asistente para administracion suelte por donde corre cada cosa.
--   Un mismo tema mezcla las dos cosas, asi que clasificar el documento entero
--   deja al asistente o filtrando de mas o inutil.
--
--   El filtro se aplica en CADA consulta, no al exportar: una etiqueta que solo
--   se respeta al construir el corpus deja de proteger en cuanto alguien
--   reindexa con el volcado completo.

CREATE TYPE doc_tipo AS ENUM ('servicio', 'regla', 'mejora', 'runbook');
CREATE TYPE doc_estado AS ENUM ('borrador', 'publicado', 'archivado');
CREATE TYPE doc_audiencia AS ENUM ('publico_general', 'administrativo', 'ti');
CREATE TYPE doc_origen AS ENUM ('manual', 'importado', 'generado');
CREATE TYPE doc_seccion_estado AS ENUM ('activa', 'archivada');
CREATE TYPE doc_accion AS ENUM ('creada', 'editada', 'reclasificada', 'verificada', 'archivada', 'restaurada');
CREATE TYPE doc_enlace_tipo AS ENUM ('tema', 'doc_git', 'url');

CREATE TABLE IF NOT EXISTS doc_temas (
    id SERIAL PRIMARY KEY,
    slug VARCHAR(80) NOT NULL UNIQUE,
    titulo VARCHAR(200) NOT NULL,
    tipo doc_tipo NOT NULL DEFAULT 'servicio',
    resumen TEXT NULL,
    -- Un tema sin responsable no se publica: la documentacion huerfana es justo
    -- la que se pudre.
    responsable VARCHAR(120) NULL,
    proyecto VARCHAR(30) NULL REFERENCES registro_proyectos(slug),
    servicio_ref VARCHAR(80) NULL,
    estado doc_estado NOT NULL DEFAULT 'borrador',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_doctema_estado ON doc_temas (estado, tipo);

CREATE TABLE IF NOT EXISTS doc_secciones (
    id SERIAL PRIMARY KEY,
    tema_id INT NOT NULL REFERENCES doc_temas(id) ON DELETE CASCADE,
    padre_id INT NULL REFERENCES doc_secciones(id) ON DELETE CASCADE,
    orden INT NOT NULL DEFAULT 0,
    titulo VARCHAR(200) NOT NULL,
    cuerpo TEXT NOT NULL,
    audiencia doc_audiencia NOT NULL DEFAULT 'ti',
    -- Todo nace indexable y es la audiencia la que decide a que asistente
    -- llega. El interruptor queda para la excepcion a mano.
    indexable_ia BOOLEAN NOT NULL DEFAULT TRUE,
    origen doc_origen NOT NULL DEFAULT 'manual',
    -- Las secciones se archivan, no se borran: si se borraran, su historial se
    -- iria con ellas.
    estado doc_seccion_estado NOT NULL DEFAULT 'activa',
    verificado_en DATE NULL,
    verificado_por VARCHAR(120) NULL,
    -- La fecha de caducidad que un .md no tiene.
    vigencia_dias INT NOT NULL DEFAULT 180,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_docsec_tema ON doc_secciones (tema_id, orden);
CREATE INDEX IF NOT EXISTS idx_docsec_audiencia ON doc_secciones (audiencia, estado);

CREATE TABLE IF NOT EXISTS doc_revisiones (
    id SERIAL PRIMARY KEY,
    seccion_id INT NOT NULL REFERENCES doc_secciones(id) ON DELETE CASCADE,
    at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actor VARCHAR(120) NOT NULL,
    accion doc_accion NOT NULL,
    cuerpo_anterior TEXT NULL,
    -- La audiencia que tenia la seccion cuando se escribio ESE cuerpo, y se
    -- guarda en toda edicion, no solo al reclasificar: si solo se anotara al
    -- reclasificar, bastaria editar una seccion tecnica y bajarla despues a
    -- publica para que su version con puertos y claves saliera por el historial.
    audiencia_anterior doc_audiencia NULL,
    motivo TEXT NULL,
    ticket_ref VARCHAR(16) NULL
);
CREATE INDEX IF NOT EXISTS idx_docrev_seccion ON doc_revisiones (seccion_id, at);

CREATE TABLE IF NOT EXISTS doc_enlaces (
    id SERIAL PRIMARY KEY,
    tema_id INT NOT NULL REFERENCES doc_temas(id) ON DELETE CASCADE,
    tipo doc_enlace_tipo NOT NULL,
    destino_tema_id INT NULL REFERENCES doc_temas(id) ON DELETE CASCADE,
    destino_ref VARCHAR(250) NULL,
    nota VARCHAR(250) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_docenl_tema ON doc_enlaces (tema_id);

CREATE TABLE IF NOT EXISTS doc_etiquetas (
    tema_id INT NOT NULL REFERENCES doc_temas(id) ON DELETE CASCADE,
    etiqueta VARCHAR(40) NOT NULL,
    PRIMARY KEY (tema_id, etiqueta)
);
CREATE INDEX IF NOT EXISTS idx_docetq_etiqueta ON doc_etiquetas (etiqueta);
