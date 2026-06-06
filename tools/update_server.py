#!/usr/bin/env python3
"""
Moly IDE Auto-Update Server
Puerto 9090 — sirve info de versión y APK para actualización automática.

SETUP EN EL VPS (una sola vez):
  1. Instalar PM2:  npm install -g pm2
  2. Editar VERSION y BUILD_NUMBER abajo
  3. Iniciar con PM2:
       pm2 start ~/tools/update_server.py --name moly-update --interpreter python3
       pm2 save
       pm2 startup   # (para que arranque al reiniciar el servidor)

COMANDOS PM2 ÚTILES:
  pm2 status              — ver estado
  pm2 logs moly-update    — ver logs en tiempo real
  pm2 restart moly-update — reiniciar después de actualizar este archivo

ACTUALIZAR VERSIÓN (después de cada build):
  1. Incrementar BUILD_NUMBER y VERSION aquí
  2. Copiar el APK:
       cp ~/moly_ide/build/app/outputs/apk/release/app-release.apk ~/moly-builds/app.apk
  3. Reiniciar el servidor:
       pm2 restart moly-update

SCRIPT DE BUILD RÁPIDO (guardar como build_release.sh):
  #!/bin/bash
  set -e
  cd ~/moly_ide
  flutter build apk --release --build-number=$1
  mkdir -p ~/moly-builds
  cp build/app/outputs/apk/release/app-release.apk ~/moly-builds/app.apk
  sed -i "s/^BUILD_NUMBER = .*/BUILD_NUMBER = $1/" ~/tools/update_server.py
  pm2 restart moly-update
  echo "APK build $1 listo y servidor reiniciado"
"""

import http.server
import json
import os

PORT = 9090
VERSION = "1.0.0"
BUILD_NUMBER = 5
APK_PATH = os.path.expanduser("~/moly-builds/app.apk")


class UpdateHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[{self.date_time_string()}] {args[0]} {args[1]} {args[2]}")

    def do_GET(self):
        if self.path == "/version":
            self._serve_json({"version": VERSION, "build": BUILD_NUMBER})
        elif self.path == "/app.apk":
            self._serve_apk()
        elif self.path == "/health":
            self._serve_json({"status": "ok"})
        else:
            self.send_error(404)

    def _serve_json(self, data: dict):
        body = json.dumps(data).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _serve_apk(self):
        if not os.path.exists(APK_PATH):
            self.send_error(404, "APK no encontrado en " + APK_PATH)
            return
        size = os.path.getsize(APK_PATH)
        self.send_response(200)
        self.send_header("Content-Type", "application/vnd.android.package-archive")
        self.send_header("Content-Length", size)
        self.send_header("Content-Disposition", "attachment; filename=moly_ide.apk")
        self.end_headers()
        with open(APK_PATH, "rb") as f:
            while chunk := f.read(65536):
                self.wfile.write(chunk)


if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", PORT), UpdateHandler)
    print(f"Moly IDE Update Server en http://0.0.0.0:{PORT}")
    print(f"Versión: {VERSION} (build {BUILD_NUMBER})")
    print(f"APK: {APK_PATH}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()
