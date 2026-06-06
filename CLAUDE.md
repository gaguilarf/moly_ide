# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

**Moly IDE** is a Flutter Android app that turns a phone into a remote IDE. It connects to a VPS over SSH, then exposes three panels: a file explorer (SFTP), a code editor, and a live interactive terminal shell. The primary use case is running Claude Code on a remote server from a mobile device.

## Commands

```bash
# Run on connected Android device
flutter run

# Analyze (lint)
flutter analyze

# Run all tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Get dependencies
flutter pub get
```

## Reglas de trabajo

- **No construyas APKs** (`flutter build apk`) al terminar una tarea. El usuario los construye manualmente cuando decide publicar.

## Architecture

### Dependency injection

`lib/core/di/injection.dart` sets up a global `GetIt` locator. Two singletons are registered at startup: `FlutterSecureStorage` and `SSHService`. Widgets that need these call `locator<T>()` directly — no constructor injection.

### SSHService (`lib/core/ssh/ssh_service.dart`)

The single source of truth for all remote connectivity. It owns both the `SSHClient` (for shell sessions) and the `SftpClient` (for file operations). It exposes a state stream (`stateStream`) and a reference to `activeTerminalSession` that widgets share. All SFTP operations (read, write, mkdir, delete, rename, listdir) go through this class.

### State management

All state is managed with `flutter_bloc` Cubits:

- **`ConnectionCubit`** — manages the SSH login flow and persists a list of saved `VPSConnection` objects in `flutter_secure_storage` under the key `saved_vps_connections` (JSON array). On startup it auto-migrates the old single-connection keys (`vps_host`, `vps_port`, etc.) to the new list format.

- **`IDECubit`** — owns the whole post-login state: current directory, open file tabs (`List<IDEFileTab>`), active tab index, and visibility flags for the three panels. Any component that needs to open/close a file, change directory, save, or toggle panels calls methods on this cubit.

### IDE layout (`lib/features/ide_dashboard/presentation/pages/ide_dashboard_page.dart`)

Uses a `Stack` with `AnimatedPositioned` for the panel layout:
- **Terminal** (`TerminalWidget`) is permanently `Positioned.fill` — it is always rendered underneath.
- **File Explorer** slides in from the left (width 260 px) over the terminal.
- **Code Editor** slides in from the right (width clamped 280–600 px).
- **FloatingDpadWidget** is anchored to the bottom-left corner of the terminal stack for arrow key input.

Thin "restore handle" strips appear on the left/right edge when a panel is hidden.

### IDEState nullable field pattern

`IDEState.copyWith` uses `String? Function()?` for nullable message fields (`loadingFileMessage`, `savingFileMessage`, `errorMessage`). Passing `() => null` explicitly clears the field; omitting the parameter preserves it. This avoids the standard `copyWith` limitation with nullable types.

### Code editor (`lib/features/editor/presentation/widgets/code_editor_widget.dart`)

Uses `code_text_field` + `highlight` for syntax highlighting. The `CodeController` is recreated whenever the active tab's file path changes. A listener on the controller calls `IDECubit.updateFileDraft()` on every keystroke. The Monokai Sublime theme is applied via `flutter_highlight`.

Supported languages (by file extension): `.dart`, `.js`/`.ts`, `.py`, `.html`/`.xml`, `.css`, `.json`, `.md`, `.yaml`/`.yml`.

### Terminal (`lib/features/terminal/presentation/widgets/terminal_widget.dart`)

Wraps the `xterm` package. On mount it calls `SSHService.createShellSession()` and pipes `session.stdout → Terminal.write` and `Terminal.onOutput → session.write`. It also scans stdout in a 2000-char rolling buffer for URLs (`http://` / `https://`) and surfaces a glassmorphic card to copy or open them in the mobile browser via `url_launcher`.

### Theme (`lib/core/theme/app_theme.dart`)

Dark-only. Brand colors: `primaryPurple` (`#9E00FF`) and `accentBlue` (`#00E5FF`). A `purpleBlueGradient` is used consistently for primary CTAs. `AppTheme.codeStyle` returns a Fira Code style used in both the editor and terminal. All border radii use `AppTheme.borderRadius` (8 px).
