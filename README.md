# 🚀 Moly IDE & Orchestrator (Control Center Móvil)

**Moly Control Center** es una plataforma móvil y distribuida de orquestación, agentes de inteligencia artificial autónomos y supervisión de infraestructura multi-servidor diseñada para operar y resolver tareas desde un dispositivo Android conectándose al **Jetson Orin Nano** como nodo maestro.

---

## 🏗️ Arquitectura del Sistema

```
┌─────────────────────────────────────────────────────────────┐
│              VPS BRITTANY GROUP (144.91.113.27)             │
│  • SGA Backend (NestJS 11 - Puertos 3000 / 3001)            │
│  • Greenter Microservicio (PHP - Puertos 8000 / 8001)       │
│  • Portal Académico API (NestJS - Puertos 3003 / 3004)      │
│  • tIAcher Backend (Django 4.2 - Puertos 8080 / 8081)       │
│  • MySQL 8.0 & 4 Instancias Redis Dedicadas (6379-6382)     │
│  • Observabilidad & Métricas (Grafana, Loki, Tempo, Prom)   │
└─────────────────────────────────────────────────────────────┘
                               ▲
                               │ SSH Asíncrono / Git Deploy
                               ▼
┌─────────────────────────────────────────────────────────────┐
│          JETSON ORIN NANO (192.168.0.109 / Tailscale)       │
│  • Backend FastAPI Orquestador (Puerto 8000)                │
│  • PostgreSQL 17 (pgvector en Docker - moly_orchestrator)   │
│  • Motor Claude Code Dual-Account & Failover de Cuota       │
│  • Sistema de "Freno Duro" Interactivo (Human-in-the-Loop)  │
│  • Monitor Multi-Servidor (ss -tlnp) & Backups GFS (<26h)   │
│  • Servicio de Documentación Técnica Viva (Markdown)        │
│  • Explorador Remoto & Visor Seguro de .env (Solo Lectura)  │
└─────────────────────────────────────────────────────────────┘
                               ▲
                               │ REST (JWT) / WebSocket Streaming
                               ▼
┌─────────────────────────────────────────────────────────────┐
│             MOLY CONTROL CENTER (Flutter Android)           │
│  [Auth con Baúl] [Tablero Tickets] [Consola Claude Streaming]│
│  [Monitor Puertos] [Backups GFS] [Docs] [Explorador .env]   │
└─────────────────────────────────────────────────────────────┘
```

---

## 📱 Módulos de la Aplicación Móvil (`lib/`)

1. **🔐 Autenticación & Baúl Seguro (`lib/features/auth/`)**:
   - Login por correo y contraseña con emisión de tokens JWT.
   - Baúl seguro encriptado en el dispositivo (`FlutterSecureStorage` con `EncryptedSharedPreferences` en Android KeyStore).
   - `AuthGate` reactivo para inicio automático de sesión sin necesidad de reingresar credenciales.
   - Selector dinámico de servidor Jetson (Red Local LAN `192.168.0.109:8000` vs Tailscale `jetson-desktop.tail452840.ts.net:8000`).

2. **🎫 Tablero Kanban & Tickets (`lib/features/tickets/`)**:
   - Gestión ágil por proyectos (`SGA`, `TIA`, `PAN`, `INF`, `PAC`, `MOLY`).
   - Sprints, backlog, estados (`backlog`, `analisis`, `en_progreso`, `bloqueado`, `completado`).
   - Timeline de auditoría y botón directo: **"Resolver con Claude en Jetson"**.

3. **🤖 Consola Claude Dual-Account & Freno Duro (`lib/features/claude_agent/`)**:
   - Visualización en tiempo real del estado de las dos cuentas de Claude (Primaria y Secundaria).
   - Terminal en streaming continuo vía WebSockets (`/api/v1/claude/ws`).
   - **Tarjeta de Freno Duro**: Cuando Claude se detiene a pedir una confirmación o instrucción humana, la app muestra una alerta interactiva con la pregunta exacta. El usuario responde desde su móvil y Claude reanuda automáticamente su ejecución en el Jetson.

4. **🌐 Monitor de Puertos e Infraestructura (`lib/features/infrastructure/`)**:
   - Inspección en vivo de puertos abiertos (`ss -tlnp`) en el VPS Brittany, Jetson y Servidor Personal.
   - Alertas visuales para puertos expuestos públicamente (`0.0.0.0` / `[::]`).

5. **💾 Auditoría de Backups Multi-Proyecto (`lib/features/backups/`)**:
   - Estado de esquemas de respaldo GFS (Daily, Weekly, Monthly).
   - Indicador de frescura y salud (<26 horas desde el último dump exitoso).

6. **📚 Servicio de Documentación Viva (`lib/features/documentation/`)**:
   - Búsqueda en tiempo real y visor Markdown integrado de la documentación técnica y ADRs.

7. **🔍 Explorador Seguro de Archivos & `.env` (`lib/features/explorer_readonly/`)**:
   - Navegación remota en modo solo lectura para inspeccionar `.env` y código sin riesgo de edición manual accidental.
   - Botón directo para solicitar modificaciones al agente Claude.

8. **🔄 Módulo de Actualizaciones con Autolimpieza (`lib/features/updates/`)**:
   - Descarga in-app del APK más reciente desde el servidor local (`192.168.0.101:8088/app-release.apk` o Tailscale `100.120.20.100:8088/app-release.apk`).
   - **Autolimpieza de Versiones Anteriores**: Antes de descargar un nuevo APK, verifica si existe un archivo `.apk` descargado previamente y lo elimina automáticamente para evitar la acumulación de archivos pesados en el almacenamiento del dispositivo.
   - Barra de progreso en vivo y ejecución directa del instalador de paquetes de Android (`OpenFilex`).

---

## ⚡ Backend Orquestador en Jetson (`backend/`)

- **FastAPI + Async SQLAlchemy + AsyncPG**.
- **PostgreSQL 17**: Base de datos `moly_orchestrator` corriendo en Docker (`pgvector/pgvector:pg17`).
- **Autenticación**: Hashing seguro con `bcrypt` nativo y tokens JWT `HS256`.
- **Ruta de Despliegue en Jetson**: `/home/jetson/moly_backend/` con entorno virtual en `/home/jetson/moly_backend/venv/`.

### Comandos de Gestión del Backend en el Jetson

```bash
# Conexión SSH al Jetson
ssh -i ~/.ssh/id_ed25519_jetson jetson@192.168.0.109

# Iniciar el backend con uvicorn en segundo plano
cd /home/jetson/moly_backend
nohup /home/jetson/moly_backend/venv/bin/python3 -m uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 > /home/jetson/moly_backend/backend.log 2>&1 </dev/null &

# Ver logs en vivo
tail -f /home/jetson/moly_backend/backend.log

# Verificar puertos escuchando
ss -tlnp | grep 8000
```

---

## 🤖 Configuración de Cuentas Claude en el Jetson

Para aislar las 2 cuentas de Claude y permitir la rotación automática por cuota:

```bash
# 1. Login Cuenta 1 (Primaria)
CLAUDE_CONFIG_DIR=/home/jetson/.claude_acc1 /home/jetson/.local/node/bin/claude login

# 2. Login Cuenta 2 (Secundaria / Backup)
CLAUDE_CONFIG_DIR=/home/jetson/.claude_acc2 /home/jetson/.local/node/bin/claude login

# 3. Registrar ambas cuentas en la base de datos PostgreSQL
docker exec -e PGPASSWORD=D7fz3yr0LEB5fNBDEhkMvjzefjyw -i postgres psql -U lab_admin -d moly_orchestrator -c "
INSERT INTO claude_accounts (alias, is_primary, status) VALUES
  ('cuenta_primaria', true, 'activa'),
  ('cuenta_secundaria', false, 'activa')
ON CONFLICT (alias) DO UPDATE SET status = 'activa';
"
```

---

## 🛠️ Comandos de Desarrollo Flutter

```bash
# Obtener dependencias
flutter pub get

# Análisis y linteo (Debe mantenerse en 0 warnings / 0 errors)
dart analyze lib

# Ejecutar en emulador / dispositivo Android
flutter run

# Compilar release APK (Solo cuando el usuario lo solicite)
flutter build apk --release
```

---

## 🔒 Credenciales y Puertos de Referencia

| Servicio | Host / IP | Credenciales / Detalles |
|---|---|---|
| **Jetson Backend** | `192.168.0.109:8000` / `jetson-desktop.tail452840.ts.net:8000` | Token API: `moly_orchestrator_secret_token_2026` |
| **Jetson PostgreSQL** | `192.168.0.109:5432` | User: `lab_admin`, Pass: `D7fz3yr0LEB5fNBDEhkMvjzefjyw`, DB: `moly_orchestrator` |
| **Usuario Inicial App** | App Login | `gustavo.f.aguilar1998@gmail.com` / `Gus19982***/` |
| **VPS Brittany** | `144.91.113.27` | Alias SSH: `brittany`, Key: `~/.ssh/id_ed25519_claude_deploy` |
