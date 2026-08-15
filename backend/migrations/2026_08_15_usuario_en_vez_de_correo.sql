-- La cuenta de la app se identifica por nombre de usuario, no por correo.
--
-- Se renombra la columna en vez de crear una nueva y arrastrar las dos: el
-- correo no se usaba para nada mas -no hay envio, ni verificacion, ni
-- recuperacion- asi que conservarlo solo dejaria dos identificadores donde hace
-- falta uno.
--
-- Idempotente: se puede volver a ejecutar sin romper nada.

BEGIN;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'panel_users' AND column_name = 'email'
    ) THEN
        ALTER TABLE panel_users RENAME COLUMN email TO username;
    END IF;
END $$;

-- El correo entero no cabe como nombre de usuario y ademas es justo lo que se
-- quiere dejar de escribir: la cuenta existente se queda con la parte local
-- acortada. Solo afecta a filas que todavia tengan forma de correo.
UPDATE panel_users
   SET username = LEFT(SPLIT_PART(username, '@', 1), 64)
 WHERE username LIKE '%@%';

ALTER TABLE panel_users ALTER COLUMN username TYPE VARCHAR(64);

COMMIT;

-- Los eventos ya registrados (`ticket_events.actor`) conservan el correo con el
-- que se firmaron. Es historial: dice quien hizo cada cosa cuando la hizo, y
-- reescribirlo seria falsearlo.
