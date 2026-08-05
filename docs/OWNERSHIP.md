# Mapa de propiedad — Frontend / Backend (equipo de 2)

> En una app **Flutter + Supabase**, "frontend" y "backend" no son dos carpetas
> separables: son **capas** dentro de un mismo código, más la carpeta `supabase/`
> (SQL). Este documento define quién es responsable de cada capa/carpeta. La
> estructura de código **no se mueve** — la Clean Architecture ya codifica la
> frontera vía `domain/`.

## Roles

| Persona | Rol | Responsable de |
|---------|-----|----------------|
| **Finn** | **Frontend** | Toda la UI, navegación, tema, estado de presentación |
| *(compañero/a)* | **Backend** | Base de datos Supabase, repos de datos reales, Auth, Storage, push |

## Frontera del contrato: `domain/`

La carpeta `lib/features/<x>/domain/` (entidades + **interfaces** de repositorio)
es el **contrato compartido**. Regla de oro:

> **Ningún cambio en `domain/` se hace en solitario.** Modificar una interfaz o
> entidad rompe a ambos lados. Se acuerda en pareja (issue/PR con ambos como
> reviewers) antes de tocarla.

## Propiedad por capa

| Capa / Carpeta | Dueño | Notas |
|----------------|-------|-------|
| `lib/features/*/presentation/**` | 🟦 Frontend | Screens, widgets, controllers |
| `lib/core/theme/**`, `lib/core/widgets/**` | 🟦 Frontend | Design system |
| `lib/core/routing/**` | 🟦 Frontend | go_router, rutas |
| `lib/features/*/data/mock_*` | 🟦 Frontend | Fixtures de UI: viven con el demo |
| `web/`, `android/`, `assets/` | 🟦 Frontend | Shells de plataforma |
| `lib/features/*/domain/**` | 🟨 **Compartido** | Contrato — cambios en pareja |
| `lib/features/*/providers.dart` | 🟨 **Compartido** | El "switch" mock↔supabase |
| `lib/features/*/data/supabase_*` | 🟥 Backend | Implementaciones reales |
| `lib/features/*/data/datasources/**`, `models/**` | 🟥 Backend | Acceso a datos |
| `lib/core/network/**` | 🟥 Backend | Cliente Supabase, conectividad |
| `lib/features/notifications/data/firebase_*` | 🟥 Backend | Push real (FCM) |
| `supabase/**` (SQL, RLS, seed) | 🟥 Backend | El backend real |

## Cómo colaboran sin pisarse

1. **Frontend** trabaja contra las **interfaces `domain/`** y los **mocks**. No
   necesita Supabase para avanzar (modo demo).
2. **Backend** implementa esas **mismas interfaces** contra Supabase, sin tocar
   la UI. El `providers.dart` intercambia una por otra según haya credenciales.
3. Cuando una feature necesita un dato nuevo → se acuerda la **interfaz en
   `domain/`** primero; luego cada quien implementa su lado.

Ver el plan de fases y el backlog en [`PLAN_DESARROLLO.md`](PLAN_DESARROLLO.md).
