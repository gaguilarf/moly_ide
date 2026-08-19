-- Migración 0001 — Brittany Group / documentación viva
-- Primera migración versionada de este esquema: doc_temas/doc_secciones/
-- doc_revisiones/registro_auditorias se crearon directo en la base viva,
-- sin DDL en disco. A partir de aquí, cambios de esquema van en un archivo
-- nuevo numerado, nunca directo en psql sin registrar.
--
-- Qué hace:
--   1) Agrega 'auditoria' al enum doc_tipo (para migrar los reportes de
--      auditoría de docs_brittanygroup, deprecado, a documentación viva).
--   2) Permite que doc_revisiones registre ediciones a nivel de TEMA
--      (metadata: titulo/tipo/estado/resumen/responsable/proyecto/servicio_ref),
--      no solo a nivel de sección — hoy PATCH /temas/{slug} no existe y esos
--      cambios no dejan rastro.
--   3) Enlaza registro_auditorias con su contenido en documentación viva,
--      sin duplicar dos sistemas de auditoría.

BEGIN;

ALTER TYPE doc_tipo ADD VALUE IF NOT EXISTS 'auditoria';

COMMIT;

-- ALTER TYPE ... ADD VALUE no puede usarse en la misma transacción en la que
-- se agregó (restricción de Postgres) — de ahí el COMMIT antes de seguir.

BEGIN;

ALTER TABLE doc_revisiones
  ALTER COLUMN seccion_id DROP NOT NULL;

ALTER TABLE doc_revisiones
  ADD COLUMN tema_id INTEGER NULL REFERENCES doc_temas(id) ON DELETE CASCADE;

ALTER TABLE doc_revisiones
  ADD CONSTRAINT doc_revisiones_seccion_o_tema_chk
  CHECK ((seccion_id IS NOT NULL) != (tema_id IS NOT NULL));

CREATE INDEX IF NOT EXISTS idx_docrev_tema ON doc_revisiones (tema_id, at);

ALTER TABLE registro_auditorias
  ADD COLUMN doc_tema_id INTEGER NULL REFERENCES doc_temas(id) ON DELETE SET NULL;

COMMIT;
