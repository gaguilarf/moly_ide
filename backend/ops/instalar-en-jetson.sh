#!/bin/bash
# INF-49 — pasos que necesitan root en la Jetson. Ejecutar con:
#   sudo bash /home/jetson/moly_backend/backend/ops/instalar-en-jetson.sh
#
# Deja el backend como unit de systemd (hoy corre por nohup y no vuelve tras un
# reinicio) y programa el volcado diario de moly_orchestrator, que hasta ahora
# NO se copiaba: el backup-postgres.sh que ya existia volcaba la base `lab`.
set -eu

ORIGEN=/home/jetson/moly_backend/backend/ops

if [ "$(id -u)" -ne 0 ]; then
  echo "Esto necesita root: sudo bash $0" >&2
  exit 1
fi

echo "==> 1/5 parando el uvicorn suelto (el que se lanzo con nohup)"
pkill -f "uvicorn backend.app.main:app" || true
sleep 2

echo "==> 2/5 instalando la unit del backend"
install -m 644 "$ORIGEN/moly-orchestrator.service" /etc/systemd/system/moly-orchestrator.service

echo "==> 3/5 instalando el volcado de moly_orchestrator"
install -m 700 -o root -g root "$ORIGEN/backup-moly-postgres.sh" /usr/local/bin/backup-moly-postgres.sh
install -m 644 "$ORIGEN/backup-moly-postgres.service" /etc/systemd/system/backup-moly-postgres.service
install -m 644 "$ORIGEN/backup-moly-postgres.timer" /etc/systemd/system/backup-moly-postgres.timer

echo "==> 4/5 arrancando"
systemctl daemon-reload
systemctl enable --now moly-orchestrator.service
systemctl enable --now backup-moly-postgres.timer

echo "==> 5/5 estado"
sleep 3
systemctl --no-pager status moly-orchestrator.service | head -12
echo
systemctl list-timers --no-pager | grep -E "backup-(moly-)?postgres" || true
echo
echo "Comprobacion: el volcado a mano, una vez, para no esperar a las 04:00"
systemctl start backup-moly-postgres.service
sleep 5
journalctl -u backup-moly-postgres.service -n 8 --no-pager

cat <<'FIN'

LISTO. Queda por decidir una cosa: la copia FUERA de la Jetson.
Ahora mismo el volcado vive solo en /mnt/storage, que esta en el mismo disco
(/dev/sda1) que todo lo demas: si se pierde ese disco, se pierde la copia con el.
El VPS ya sube sus volcados cifrados a Google Drive con rclone (remoto "gcrypt").
Para hacer lo mismo aqui: instalar rclone, traer la configuracion de ese remoto,
y anadir al fichero de la unit:
    Environment=MOLY_RCLONE_REMOTE=gcrypt
FIN
