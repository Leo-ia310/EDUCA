# Supabase — Educa360

Migraciones para PostgreSQL en orden estricto:

1. `0001_init_core.sql` — núcleo SaaS, RBAC, personas y estructura académica.
2. `0002_init_academic_extras.sql` — tareas, evaluaciones, calificaciones, comunicaciones, chat, pagos y sync offline.
3. `0003_rls_policies.sql` — Row Level Security multi-tenant. Activa políticas en todas las tablas operativas.
4. `0004_seed_catalogs.sql` — catálogos globales + institución demo (`EDU360`).

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

## Storage

Crear un bucket `files` privado y aplicar la policy comentada al final de `0003_rls_policies.sql` para aislar por institución.
