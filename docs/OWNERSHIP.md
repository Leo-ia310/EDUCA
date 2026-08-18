# Mapa de propiedad — Frontend / Backend (equipo de 2)

> En una app **Flutter + Supabase**, "frontend" y "backend" son ante todo
> **capas** dentro del mismo código Flutter, más el SQL de Supabase. Desde
> `Backend-MK` (2026-08) el repo además separa esas capas **físicamente** en
> dos carpetas de primer nivel — `frontend/` (toda la app Flutter) y
> `backend/` (SQL, RLS, seeds, Edge Functions) — para que cada quien tenga su
> propio árbol de trabajo. La frontera **lógica** sigue siendo la misma:
> `frontend/lib/features/<x>/domain/` (Clean Architecture), que ahora vive
> dentro de `frontend/` pero no cambió de rol.

## Roles

| Persona | Rol | Responsable de |
|---------|-----|----------------|
| **Finn** | **Frontend** | Toda la UI, navegación, tema, estado de presentación |
| *(compañero/a)* | **Backend** | Base de datos Supabase, repos de datos reales, Auth, Storage, push |

## Frontera del contrato: `domain/`

La carpeta `frontend/lib/features/<x>/domain/` (entidades + **interfaces** de
repositorio) es el **contrato compartido**. Regla de oro:

> **Ningún cambio en `domain/` se hace en solitario.** Modificar una interfaz o
> entidad rompe a ambos lados. Se acuerda en pareja (issue/PR con ambos como
> reviewers) antes de tocarla.

## Propiedad por capa

| Capa / Carpeta | Dueño | Notas |
|----------------|-------|-------|
| `frontend/lib/features/*/presentation/**` | 🟦 Frontend | Screens, widgets, controllers |
| `frontend/lib/core/theme/**`, `frontend/lib/core/widgets/**` | 🟦 Frontend | Design system |
| `frontend/lib/core/routing/**` | 🟦 Frontend | go_router, rutas |
| `frontend/lib/features/*/data/mock_*` | 🟦 Frontend | Fixtures de UI: viven con el demo |
| `frontend/web/`, `frontend/android/`, `frontend/assets/` | 🟦 Frontend | Shells de plataforma |
| `frontend/lib/features/*/domain/**` | 🟨 **Compartido** | Contrato — cambios en pareja |
| `frontend/lib/features/*/providers.dart` | 🟨 **Compartido** | El "switch" mock↔supabase |
| `frontend/lib/features/*/data/supabase_*` | 🟥 Backend | Implementaciones reales |
| `frontend/lib/features/*/data/datasources/**`, `models/**` | 🟥 Backend | Acceso a datos |
| `frontend/lib/core/network/**` | 🟥 Backend | Cliente Supabase, conectividad |
| `frontend/lib/features/notifications/data/web_push_service.dart` | 🟥 Backend | Push real (Web Push/VAPID) |
| `backend/**` (SQL, RLS, seed, Edge Functions) | 🟥 Backend | El backend real |

## Cómo colaboran sin pisarse

1. **Frontend** trabaja contra las **interfaces `domain/`** y los **mocks**. No
   necesita Supabase para avanzar (modo demo).
2. **Backend** implementa esas **mismas interfaces** contra Supabase, sin tocar
   la UI. El `providers.dart` intercambia una por otra según haya credenciales.
3. Cuando una feature necesita un dato nuevo → se acuerda la **interfaz en
   `domain/`** primero; luego cada quien implementa su lado.

Ver el plan de fases y el backlog en [`PLAN_DESARROLLO.md`](PLAN_DESARROLLO.md).
