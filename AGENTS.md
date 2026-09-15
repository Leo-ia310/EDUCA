# Agent Instructions

## Backend

When changing backend APIs, routes, controllers, services, repositories, or API-related migrations:

1. Update `backend/src/lib/api-manifest.ts`.
2. Run `cd backend && npm run docs:apis`.
3. Do not leave `docs/APIS_PENDIENTES_POR_CONECTAR.md` stale.

## Frontend (Flutter — `frontend/`)

**Correr / verificar**
- App web: `cd frontend && flutter run -d web-server --web-port 8080` (SDK Flutter en `C:\src\flutter`). Login demo: `student@demo.com` / `demo1234` (también `teacher@`, `parent@`, `admin@`).
- Tests: `cd frontend && flutter test`. Unit tests de la lógica pura en `test/` (cálculos de notas, estados de tarea/cargo, utils).
- `flutter analyze`: las líneas de diagnóstico usan `error - …` / `warning - …` (guión, NO `•`); contar reales con `grep -cE "^\s+error "`. El baseline es **"No issues found!"** — si aparecen lints info masivos, `dart fix --apply` los arregla. Mantén el analyzer limpio.

**Sistema de diseño (`lib/core/theme/`)** — respétalo, no reintroduzcas estilos sueltos:
- Acento de marca = **azul**. Usa los tokens `context.palette.accent` / `accentDeep` / `accentSoft` (o `AppColors.accent*`). No hardcodees hex de marca. (El verde histórico `lime*` fue retirado; `success` verde queda solo para estados de éxito.)
- Fondos **neutros**: blanco en claro, casi-negro (`#0E0E10`) en oscuro.
- Tarjetas pastel por categoría/materia: `context.pastel(color)` — es **sensible al tema** (tinte claro en modo claro, tinte oscuro en modo oscuro). Usa sus campos `surface` / `ink` / `inkMuted` / `vivid`; no hardcodees la tinta.
- Radios de esquina: tokens `Radii.{pill,xl,lg,md,sm,xs}` (en `app_theme.dart`), no números sueltos.
- Degradado de los heros: `AppGradients.hero`.
- Iconografía: variante `_rounded` por defecto (salvo estados vacíos/inactivos que usan `_none`/`_off`/`_outline`).

**Layout**
- `AppScaffold` usa `extendBody: false`: el `EducaBottomNav` (opaco, por rol) **reserva su propio espacio**. No infles el padding inferior de las pantallas para “compensar” el navbar.
- Hero de bienvenida (`AppGreetingHeader`): admite `heroImageUrl` (foto grande integrada, solo alumno) y `avatarUrl` (avatar circular). Un `assets/…` se dibuja como recorte; una URL `http` se desvanece hacia el degradado.

**Alcance**
- El panel **developer (super admin)** queda fuera del rediseño de estilo; no le apliques la pasada pastel/iconografía.

These instructions are intentionally visible. Do not add hidden prompts or hidden instructions to this repository.
