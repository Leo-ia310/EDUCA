# Estado de la base de datos y reconexión — Educa360

_Última revisión: 2026-07-30_

## Resumen del diagnóstico

El proyecto de Supabase (`qwfkmijewogksfizdski.supabase.co`) estuvo un tiempo
inaccesible (su DNS no resolvía → parecía que "colapsó" o que faltaban tablas).
Ahora **está en línea otra vez** y se verificó lo siguiente:

- ✅ **Las 70 tablas del esquema existen.** No falta ninguna.
- ✅ Catálogos sembrados (monedas, roles=7, etc.) e institución demo
  **EDU360 – "Colegio Demo Educa360"** (id 1).
- ❌ **Bug real encontrado:** `conversation_participants` y `messages` devolvían
  error 500 → `42P17 infinite recursion detected in policy`. La política RLS de
  `conversation_participants` en `0003_rls_policies.sql` se auto-referenciaba.
  **Corregido en `migrations/0005_fix_chat_rls.sql`.**
- ⚠️ **No hay datos operativos sembrados** (estudiantes, clases, tareas, notas)
  ni usuarios de Supabase Auth provisionados.

## Qué falta para el modo CONECTADO completo (opcional)

1. **Aplicar `0005_fix_chat_rls.sql`** (arregla el chat). Ver abajo.
2. **Crear usuarios de Auth** con su `raw_app_meta_data`:
   `{ "institution_id": 1, "roles": ["teacher"] }` y su fila en `public.users`
   (ver `backend/README.md` y `supabase/seed_auth_users.sql`).
3. **Sembrar datos operativos** (estudiantes, clases, matrículas, tareas…).
4. **Terminar los repos de Supabase** que aún tienen `UnimplementedError`
   (`supabase_assignment_repository.dart`, `supabase_chat_repository.dart`).

Mientras tanto, la app funciona **al 100% en modo demo** (datos mock), que no
necesita backend. Ver `run_demo.ps1`.

## Cómo aplicar la corrección del chat (`0005`)

### Opción A — SQL Editor de Supabase (recomendada, 1 minuto)
1. Entra al panel del proyecto → **SQL Editor** → **New query**.
2. Pega **todo** el contenido de `supabase/migrations/0005_fix_chat_rls.sql`.
3. **Run**. Debe terminar sin errores (es idempotente, se puede repetir).
4. Verifica: en **Table Editor** abre `messages`; ya no debe dar error 500.

### Opción B — CLI de Supabase
```bash
supabase db push        # si el proyecto está "linked"
```

## Cómo correr la app

| Modo | Comando | Requiere backend | Estado |
|------|---------|------------------|--------|
| **Demo (mock)** | `.\run_demo.ps1` | No | ✅ 100% funcional |
| Conectado | `.\run_dev.ps1` | Sí (pasos 1-4 arriba) | ⚠️ parcial |

`flutter run` sin argumentos también arranca en modo demo (no hay `--dart-define`).

### Login demo
- Código de colegio: **EDU360**
- Contraseña: **demo1234**
- Usuario (prefijo): **student@** · **teacher@** · **parent@** · **admin@**
  (p. ej. `teacher@demo.com`)
