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
- Firebase Messaging para push

## Estructura
```
lib/
├── core/         Tema, routing, constantes, utilidades, widgets globales
├── features/     Feature-first: auth, dashboard, attendance, schedule, etc.
└── shared/       Modelos, widgets y servicios reutilizables
supabase/
└── migrations/   DDL + RLS multi-tenant
```

## Configuración

1. **Instalar Flutter 3.22+** y ejecutar `flutter doctor`.
2. **Variables de entorno** — crear `.env` o configurar `--dart-define`:
   ```
   SUPABASE_URL=https://xxx.supabase.co
   SUPABASE_ANON_KEY=eyJ...
   ```
   Y arrancar con:
   ```
   flutter run --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
   ```
3. **Supabase** — crear proyecto, ejecutar migraciones en orden desde `supabase/migrations/`.
4. **Codegen** (modelos Freezed / Riverpod):
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
