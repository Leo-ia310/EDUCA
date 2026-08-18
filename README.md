# Educa360

Plataforma educativa SaaS multi-institución (Flutter + Supabase). App móvil para Android e iOS, orientación vertical.

## Roles soportados
- Estudiante
- Maestro
- Padre / Madre / Tutor
- Administrador
- Coordinador / Director

## Stack
- Flutter 3.22+ / Dart 3.4+
- Clean Architecture (feature-first)
- Riverpod 2.x para estado
- go_router para navegación
- Supabase (Auth + Postgres + Storage + Realtime)
- Hive para persistencia offline (asistencia)
- Web Push (VAPID) para notificaciones push — sin Firebase

## Estructura del repo

El repo separa físicamente **frontend** (app Flutter) y **backend** (Supabase:
SQL, RLS, Edge Functions). Ver [`docs/OWNERSHIP.md`](docs/OWNERSHIP.md) para
el detalle de propiedad por carpeta y [`docs/PLAN_DESARROLLO.md`](docs/PLAN_DESARROLLO.md)
para el plan de fases.

```
frontend/               App Flutter completa
├── lib/
│   ├── core/            Tema, routing, constantes, utilidades, widgets globales
│   ├── features/        Feature-first: auth, dashboard, attendance, schedule, etc.
│   └── shared/           Modelos, widgets y servicios reutilizables
├── android/ web/ windows/
├── assets/
├── pubspec.yaml
├── run_dev.ps1           Arrancar conectado a Supabase real
└── run_demo.ps1          Arrancar en modo demo (sin backend)

backend/                 Supabase: SQL, RLS, seeds, Edge Functions
├── migrations/           DDL + RLS multi-tenant, en orden estricto
├── functions/             Edge Functions (Deno)
├── seed/                  Datos operativos de demo
└── test_users.sql         Usuarios demo (Auth + roles)
```

## Configuración

1. **Instalar Flutter 3.22+** y ejecutar `flutter doctor`.
2. Entrar a la carpeta de la app: `cd frontend`.
3. **Variables de entorno** — copiar `.env.example` a `.env` y completar:
   ```
   SUPABASE_URL=https://xxx.supabase.co
   SUPABASE_ANON_KEY=eyJ...
   ```
   Arrancar conectado con `.\run_dev.ps1` o en modo demo (sin backend) con
   `.\run_demo.ps1`.
4. **Supabase** — crear proyecto, ejecutar migraciones en orden desde
   `backend/migrations/`.
5. **Codegen** (modelos Freezed / Riverpod), desde `frontend/`:
   ```
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

## Login flow
1. Usuario ingresa **código de colegio** (`institutions.code`).
2. App valida que la institución exista y esté activa.
3. Usuario ingresa correo/usuario + contraseña.
4. Supabase Auth autentica; el JWT lleva `institution_id` y `roles[]`.
5. Router redirige al dashboard correspondiente al rol activo.

## Multi-tenancy
- Toda tabla operativa lleva `institution_id`.
- RLS de Postgres aísla los datos por colegio: `institution_id = (auth.jwt() ->> 'institution_id')::bigint`.

## Offline
- Asistencia se guarda en Hive con `pending_sync = true`.
- Al recuperar conectividad, una cola sube los registros y resuelve conflictos por `uuid + updated_at`.
