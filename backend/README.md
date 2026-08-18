# Backend — Educa360 (Supabase)

SQL de Postgres/Supabase: DDL, RLS multi-tenant, seeds y Edge Functions.
El resto del backend "real" (implementación de los repos `data/supabase_*`)
vive en `frontend/lib/features/*/data/` — ver [`../docs/OWNERSHIP.md`](../docs/OWNERSHIP.md).

Migraciones para PostgreSQL en orden estricto:

1. `0001_init_core.sql` — núcleo SaaS, RBAC, personas y estructura académica.
2. `0002_init_academic_extras.sql` — tareas, evaluaciones, calificaciones, comunicaciones, chat, pagos y sync offline.
3. `0003_rls_policies.sql` — Row Level Security multi-tenant. Activa políticas en todas las tablas operativas.
4. `0004_seed_catalogs.sql` — catálogos globales + institución demo (`EDU360`).
5. `0005_fix_chat_rls.sql` — corrige recursión infinita (42P17) en RLS de `conversation_participants`/`messages` vía función `security definer`.
6. `0006_hardening.sql` — RLS real en las 5 tablas que habían quedado con `using(true)`, bucket de Storage `files` + políticas (antes solo documentado, nunca ejecutado), triggers `updated_at`, índices en `institution_id`/FKs de mayor volumen, y fix de la FK faltante en `sessions.device_id`.
7. `0007_assignments_published.sql` — columna `assignments.published` (el catálogo `catalog_task_statuses` describe el ciclo de una entrega, no sirve para el estado publicado/borrador de la tarea).

`schema_all.sql` es la concatenación regenerada de 0001→0007 — no editar directo, editar la migración correspondiente y regenerar.

## Aplicar las migraciones

### Vía CLI de Supabase
```bash
supabase db reset            # entorno local
# o
supabase db push             # entorno linked
```

### Vía consola SQL
Pegar el contenido de cada archivo, en orden, en el SQL Editor.

## Provisión de usuarios

El JWT del usuario debe llevar en `auth.users.raw_app_meta_data`:
```json
{
  "institution_id": 1,
  "roles": ["teacher"]
}
```

Para asignarlo desde la consola:
```sql
update auth.users
   set raw_app_meta_data = raw_app_meta_data
        || '{"institution_id": 1, "roles": ["teacher"]}'::jsonb
 where email = 'maria@colegio.com';
```

Y crear el registro en `public.users`:
```sql
insert into public.users (auth_user_id, institution_id, email, full_name)
values ((select id from auth.users where email = 'maria@colegio.com'), 1, 'maria@colegio.com', 'María Pérez');
```

Asignar rol:
```sql
insert into public.user_roles (user_id, role_id, institution_id)
values (
  (select id from public.users where email = 'maria@colegio.com'),
  (select id from public.roles where code = 'teacher'),
  1
);
```

## Usuarios y datos de demo

- `test_users.sql` — crea 4 usuarios demo (`student@/teacher@/parent@/admin@educa360.com`, password `demo1234`) sobre la institución `EDU360`. Idempotente, ejecutar después de las migraciones.
- `seed/0007_seed_operational_demo.sql` — datos operativos de ejemplo (estudiantes, clases, matrículas, tareas, notas) para poder probar el modo conectado end-to-end. Idempotente.

## Storage

El bucket `files` (privado) y sus políticas de aislamiento por institución ya se crean por SQL en `0006_hardening.sql` — ya no es un paso manual del panel de Supabase.

## Push notifications

`functions/send-push/` — Edge Function (Deno) que envía Web Push (VAPID) a las suscripciones guardadas en `devices.push_token`. Ver su propio README para el paso de despliegue (pendiente, requiere `supabase login` + secrets).
