# CLAUDE.md - Moly IDE & Orchestrator Guía de Proyecto

Este archivo contiene las directrices, arquitectura y reglas operativas para cualquier agente que trabaje en este repositorio.

---

## 🎯 Visión y Alcance del Proyecto

**Moly Control Center** es un ecosistema desacoplado que centraliza el desarrollo, resolución autónoma de tickets, supervisión de infraestructura y ejecución de agentes Claude en el **Jetson Orin Nano**, controlado desde una app móvil Android en Flutter.

### Separación de Responsabilidades:
1. **VPS Brittany Group (`144.91.113.27`)**: Entorno de producción institucional (SGA NestJS, tIAcher Django, Greenter facturación SUNAT, bases de datos de negocio MySQL 8.0, 4 instancias Redis 6379-6382).
2. **Jetson Orin Nano (`192.168.0.109` / `jetson-desktop.tail452840.ts.net`)**: Nodo maestro de desarrollo, orquestación y automatización:
   - Backend FastAPI en puerto 8000 (`backend/app/`).
   - PostgreSQL 17 (`moly_orchestrator` en contenedor Docker).
   - Motor Claude Code con **rotación automática de 2 cuentas** por cuota/rate limit.
   - Detección de **Freno Duro (Human-in-the-Loop)** para consultas interactivas con el usuario móvil.
   - Servicio de documentación técnica viva (Markdown).
   - Inspección asíncrona de puertos e infraestructura remota vía SSH.
3. **Moly App Móvil (`lib/`)**: Cliente Flutter Android con autenticación JWT, persistencia segura en baúl Android KeyStore (`FlutterSecureStorage`) y 6 módulos integrados.

---

## 📋 Reglas Obligatorias de Desarrollo

1. **Compilación de APKs**:
   - **NO construyas APKs** (`flutter build apk`) automáticamente al terminar una tarea a menos que el usuario lo solicite expresamente.
2. **Calidad de Código**:
   - Todo cambio en Flutter debe validarse con `dart analyze lib` y mantenerse con **0 errores y 0 warnings**.
3. **Manejo de Contraseñas y Seguridad**:
   - En el backend Python, utilizar `bcrypt` nativo (evitar el wrapper de `passlib` que tiene conflictos con versiones modernas de bcrypt).
   - En Flutter, almacenar tokens y credenciales en `FlutterSecureStorage` con `EncryptedSharedPreferences`.
4. **Modo Solo Lectura para Archivos Remotos**:
   - En la app móvil, el explorador de archivos y visor de `.env` opera en modo **solo lectura**. Las modificaciones se solicitan al agente Claude mediante tickets o prompts para mantener la trazabilidad y evitar fallos manuales.
5. **La app NO tiene IDE**:
   - El terminal, el editor de código, el visor de diferencias, el explorador por SSH y su formulario de conexión **se retiraron a propósito** (MOLY-3) y **no se reintroducen**. El nombre del repositorio es histórico.
   - Que un módulo compile sin tener pantalla que lo abra **no es motivo para devolverle una entrada en el menú**: es motivo para borrarlo. Así volvió el IDE una vez.
   - Lo único que hacía falta de ahí —mirar archivos del servidor— vive en el explorador de solo lectura, que tiene su propia entrada en el menú y va por la API, no por SSH.

---

## 🏗️ Estructura del Código

### Backend FastAPI (`backend/`)
- `backend/app/main.py`: Entrypoint FastAPI con routers incluidos (`auth`, `tickets`, `claude`, `infra`, `backups`, `docs`, `explorer`).
- `backend/app/services/claude_orchestrator.py`: Motor de Claude CLI con streaming WebSocket, captura de freno duro y conmutación de cuentas (`~/.claude_acc1` / `~/.claude_acc2`).
- `backend/app/services/auth_service.py`: Hashing `bcrypt` y tokens JWT `HS256`.
- `backend/app/services/ssh_inspector.py`: Inspección remota de puertos (`ss -tlnp`), salud de backups GFS y lectura segura de `.env`.
- `backend/app/models/` y `backend/app/schemas/`: Modelos SQLAlchemy y esquemas Pydantic.
- `backend/migrations/schema_postgresql.sql`: DDL completo para PostgreSQL.

### Frontend Flutter (`lib/`)
- `lib/core/di/injection.dart`: Inyección de dependencias con GetIt.
- `lib/core/api/orchestrator_api_client.dart`: Cliente HTTP Dio con soporte dinámico de servidor LAN/Tailscale.
- `lib/core/api/websocket_service.dart`: Cliente WebSocket para streaming en tiempo real.
- `lib/core/theme/app_theme.dart`: Tema oscuro con paleta HSL/neón (`primaryPurple` `#9E00FF`, `accentBlue` `#00E5FF`).
- `lib/features/auth/`: `AuthCubit`, `AuthState`, `LoginPage` y `AuthGate` en `main.dart`.
- `lib/features/tickets/`: `TicketsCubit`, `TicketsPage`, `TicketDetailPage`.
- `lib/features/claude_agent/`: `ClaudeCubit`, `ClaudeAgentPage` con tarjeta interactiva de freno duro y visualizador de cuentas duales.
- `lib/features/infrastructure/`: `InfraCubit`, `InfrastructurePage` (monitoreo de puertos).
- `lib/features/backups/`: `BackupsCubit`, `BackupsPage` (estado GFS).
- `lib/features/documentation/`: `DocsCubit`, `DocsPage` (buscador y visor Markdown).
- `lib/features/explorer_readonly/`: `ReadonlyExplorerCubit`, `ReadonlyExplorerPage` (visor seguro de `.env`).
- `lib/features/main_navigation/presentation/pages/main_navigation_page.dart`: Barra de navegación inferior que integra los 6 módulos.

---

## 🔧 Comandos Rápidos

```bash
# Validar código Flutter
dart analyze lib

# Ejecutar app móvil
flutter run

# Comprobar estado del backend en Jetson
ssh -i ~/.ssh/id_ed25519_jetson jetson@192.168.0.109 "ps aux | grep uvicorn; ss -tlnp | grep 8000"

# Reiniciar backend en Jetson si se actualiza código
ssh -i ~/.ssh/id_ed25519_jetson jetson@192.168.0.109 "pkill -f uvicorn || true; cd /home/jetson/moly_backend && nohup /home/jetson/moly_backend/venv/bin/python3 -m uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 > /home/jetson/moly_backend/backend.log 2>&1 </dev/null &"
```
