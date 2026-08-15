#!/bin/bash
# Copia de seguridad de moly_orchestrator (PostgreSQL en Docker, Jetson).
#
# Existe porque el backup-postgres.sh que ya corría en la Jetson volcaba la base
# `lab` y NO esta: 2,7 KB frente a los 43 KB que ocupa moly_orchestrator. La base
# que guarda tickets, registro y documentacion no se estaba copiando.
#
# Mismo esquema GFS que /opt/backups/mysql_backup.sh del VPS, y por el mismo
# motivo: retencion por CANTIDAD, no por antiguedad, y el nombre lleva el
# periodo (no la hora), asi que dos corridas del mismo dia SOBRESCRIBEN el mismo
# archivo en vez de acumularse.
#   - Diario:  moly_orchestrator_YYYYMMDD.dump   -> se conservan los 7 mas recientes
#   - Semanal: moly_orchestrator_W<isoAnioSem>.dump -> los 4 mas recientes
#   - Mensual: moly_orchestrator_M<anioMes>.dump -> los 12 mas recientes
#
# El sobrante se borra SOLO despues de que el volcado nuevo exista y se haya
# verificado que es legible.
set -u

BASE=${MOLY_BACKUP_DIR:-/mnt/storage/backups/moly}
LOG=$BASE/backup.log
ENV_FILE=${MOLY_ENV_FILE:-/home/jetson/moly_backend/.env}
CONTENEDOR=${MOLY_PG_CONTAINER:-postgres}
DB=${MOLY_DB:-moly_orchestrator}
# Remoto rclone para la copia fuera de la Jetson. Vacio = sin off-site, y el
# script lo dice en el log en vez de callarselo.
REMOTE=${MOLY_RCLONE_REMOTE:-}
REMOTE_BASE=${MOLY_RCLONE_PATH:-moly/postgres}

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=12

DATE=$(date +%Y%m%d)
WEEK=W$(date +%G%V)
MONTH=M$(date +%Y%m)

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

mkdir -p "$BASE"/{daily,weekly,monthly}

# Credenciales desde el .env de la app: una sola copia de la contrasena, la que
# ya usa el backend. Duplicarla aqui es garantizar que un dia dejen de coincidir.
DSN=$(grep -oE '^DATABASE_URL=.*' "$ENV_FILE" | cut -d= -f2-)
USUARIO=$(echo "$DSN" | sed -E 's#.*://([^:]+):.*#\1#')
CLAVE=$(echo "$DSN" | sed -E 's#.*://[^:]+:([^@]+)@.*#\1#')

if [ -z "$USUARIO" ] || [ -z "$CLAVE" ]; then
  log "ERROR: no pude sacar usuario/clave de DATABASE_URL en $ENV_FILE"
  exit 1
fi

DESTINO=$BASE/daily/${DB}_${DATE}.dump
TMP=$DESTINO.parcial

log "volcando $DB a $DESTINO"
if ! docker exec -e PGPASSWORD="$CLAVE" "$CONTENEDOR" pg_dump -U "$USUARIO" -Fc "$DB" > "$TMP" 2>>"$LOG"; then
  log "ERROR: pg_dump fallo; se conserva la copia anterior y no se borra nada"
  rm -f "$TMP"
  exit 1
fi

# Verificar ANTES de mover: un fichero de 0 bytes tambien "existe", y asi es como
# se descubre a los seis meses que no habia copia.
#
# La verificacion va DENTRO del contenedor porque en la Jetson no hay cliente de
# PostgreSQL instalado: el `pg_restore -l` del host no existe. Y tiene que ser
# sobre un fichero, no por tuberia: pg_restore necesita poder recolocarse dentro
# del volcado y con /dev/stdin falla.
verificar_volcado() {
  docker exec -i "$CONTENEDOR" sh -c \
    'cat > /tmp/verificacion.dump && pg_restore -l /tmp/verificacion.dump > /dev/null; r=$?; rm -f /tmp/verificacion.dump; exit $r' \
    < "$1"
}

if ! verificar_volcado "$TMP" 2>>"$LOG"; then
  log "ERROR: el volcado no es legible por pg_restore; se descarta"
  rm -f "$TMP"
  exit 1
fi

mv "$TMP" "$DESTINO"
chmod 600 "$DESTINO"
log "listo y verificado: $(du -h "$DESTINO" | cut -f1)"

# Semanal y mensual son copias del diario: mismo contenido, otra caducidad.
cp -f "$DESTINO" "$BASE/weekly/${DB}_${WEEK}.dump"
cp -f "$DESTINO" "$BASE/monthly/${DB}_${MONTH}.dump"
chmod 600 "$BASE/weekly/${DB}_${WEEK}.dump" "$BASE/monthly/${DB}_${MONTH}.dump"

conservar_mas_nuevos() {
  local dir=$1 keep=$2
  ls -1 "$dir"/*.dump 2>/dev/null | sort -r | tail -n +$((keep + 1)) | while read -r f; do
    log "retirando sobrante $f"
    rm -f "$f"
  done
}

if [ -n "$REMOTE" ]; then
  ok=1
  for nivel in daily weekly monthly; do
    if ! rclone copy "$BASE/$nivel" "$REMOTE:$REMOTE_BASE/$nivel/" --no-traverse >>"$LOG" 2>&1; then
      ok=0
    fi
  done
  if [ "$ok" = "1" ]; then
    log "off-site: subido a $REMOTE:$REMOTE_BASE"
  else
    log "AVISO: la subida off-site fallo; NO se borra el sobrante local"
    exit 1
  fi
else
  log "AVISO: sin MOLY_RCLONE_REMOTE configurado, la copia vive solo en la Jetson"
fi

conservar_mas_nuevos "$BASE/daily" "$KEEP_DAILY"
conservar_mas_nuevos "$BASE/weekly" "$KEEP_WEEKLY"
conservar_mas_nuevos "$BASE/monthly" "$KEEP_MONTHLY"

log "copias actuales:"
ls -l "$BASE"/daily/*.dump 2>/dev/null | tail -3 | tee -a "$LOG"
