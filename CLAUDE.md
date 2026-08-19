# CLAUDE.md - Moly App (Flutter) — Guía de Proyecto

Este archivo contiene las directrices, arquitectura y reglas operativas para cualquier agente que trabaje en este repositorio.

---

## 🎯 Visión y Alcance del Proyecto

Este repo es **solo la app móvil Android en Flutter** ("Moly App") que controla el ecosistema Brittany Group desde el bolsillo: desarrollo, resolución autónoma de tickets, supervisión de infraestructura y ejecución de agentes Claude en el **Jetson Orin Nano**.

**El backend FastAPI ya NO vive aquí** (RAG-7, 2026-08-19): este repo era un monorepo con `backend/` y `lib/` juntos, pero se despliegan y ejecutan por separado, sin código compartido. `backend/` se extrajo a su propio repo con historia nueva — ver el tema `moly` (ahora "Ragnar Group — orquestador del ciclo de desarrollo") en documentación viva para su ubicación exacta una vez que el repo remoto exista.

### Separación de Responsabilidades:
1. **VPS Brittany Group (`144.91.113.27`)**: Entorno de producción institucional (SGA NestJS, tIAcher Django, Greenter facturación SUNAT, bases de datos de negocio MySQL 8.0, 4 instancias Redis 6379-6382).
2. **Jetson Orin Nano (`192.168.0.109` / `jetson-desktop.tail452840.ts.net`)**: Nodo maestro de desarrollo, orquestación y automatización — backend FastAPI (repo aparte, ver arriba), PostgreSQL 17 (`moly_orchestrator` en contenedor Docker), motor Claude Code con rotación automática de 2 cuentas por cuota/rate limit, detección de Freno Duro (Human-in-the-Loop), documentación técnica viva, inspección asíncrona de puertos e infraestructura remota vía SSH.
3. **Esta app (`lib/`)**: Cliente Flutter Android con autenticación JWT, persistencia segura en baúl Android KeyStore (`FlutterSecureStorage`) y 6 módulos integrados.

---

## 📋 Reglas Obligatorias de Desarrollo

1. **Compilación de APKs**:
   - **NO construyas APKs** (`flutter build apk`) automáticamente al terminar una tarea a menos que el usuario lo solicite expresamente.
2. **Calidad de Código**:
   - Todo cambio en Flutter debe validarse con `dart analyze lib` y mantenerse con **0 errores y 0 warnings**.
3. **Manejo de Contraseñas y Seguridad**:
   - Tokens y credenciales en `FlutterSecureStorage` con `EncryptedSharedPreferences`.
4. **Modo Solo Lectura para Archivos Remotos**:
   - El explorador de archivos y visor de `.env` opera en modo **solo lectura**. Las modificaciones se solicitan al agente Claude mediante tickets o prompts para mantener la trazabilidad y evitar fallos manuales.
5. **La app NO tiene IDE**:
   - El terminal, el editor de código, el visor de diferencias, el explorador por SSH y su formulario de conexión **se retiraron a propósito** (MOLY-3) y **no se reintroducen**. El nombre del repositorio es histórico.
   - Que un módulo compile sin tener pantalla que lo abra **no es motivo para devolverle una entrada en el menú**: es motivo para borrarlo. Así volvió el IDE una vez.
   - Lo único que hacía falta de ahí —mirar archivos del servidor— vive en el explorador de solo lectura, que tiene su propia entrada en el menú y va por la API, no por SSH.

---

## 🏗️ Estructura del Código (`lib/`)

- `lib/core/di/injection.dart`: Inyección de dependencias con GetIt.
- `lib/core/api/orchestrator_api_client.dart`: Cliente HTTP Dio con soporte dinámico de servidor LAN/Tailscale.
- `lib/core/api/websocket_service.dart`: Cliente WebSocket para streaming en tiempo real.
- `lib/core/theme/app_theme.dart`: Tema oscuro con paleta HSL/neón (`primaryPurple` `#9E00FF`, `accentBlue` `#00E5FF`).
- `lib/features/auth/`: `AuthCubit`, `AuthState`, `LoginPage` y `AuthGate` en `main.dart`.
- `lib/features/tickets/`: `TicketsCubit`, `TicketsPage`, `TicketDetailPage`.
- `lib/features/claude_agent/`: `ClaudeCubit`, `ClaudeAgentPage` con tarjeta interactiva de freno duro y visualizador de cuentas duales.
- `lib/features/infrastructure/`: `InfraCubit`, `InfrastructurePage` (monitoreo de puertos).
- `lib/features/backups/`: `BackupsCubit`, `BackupsPage` (estado GFS).
- `lib/features/documentation/`: `DocsCubit`, `DocsPage` (temas/secciones de documentación viva, con historial de revisiones por sección desde RAG-5).
- `lib/features/explorer_readonly/`: `ReadonlyExplorerCubit`, `ReadonlyExplorerPage` (visor seguro de `.env`).
- `lib/features/main_navigation/presentation/pages/main_navigation_page.dart`: Barra de navegación inferior que integra los 6 módulos.

---

## 🔧 Comandos Rápidos

```bash
# Validar código Flutter
dart analyze lib

# Ejecutar app móvil
flutter run
```

Para todo lo del backend (estado, reinicio, esquema de la base) ver el repo del backend (nombre pendiente al 2026-08-19, ver tema `moly`/"Ragnar Group" en documentación viva) — no está aquí.
