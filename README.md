# Educa360

Plataforma educativa SaaS multi-institucion con app Flutter, backend Node.js y
Supabase como infraestructura de datos.

## Roles Soportados

- Estudiante
- Maestro
- Padre / Madre / Tutor
- Administrador
- Coordinador / Director

## Stack

- Flutter 3.22+ / Dart 3.4+
- Backend Node.js + TypeScript
- Supabase Auth, Postgres, Storage, Realtime, RPC y RLS
- Riverpod 2.x y go_router
- Hive para persistencia offline de asistencia
- Web Push (VAPID) via Supabase Edge Function `send-push`

## Estructura Del Repo

```text
EDUCA/
├── frontend/              App Flutter
├── backend/               API Node TypeScript + scripts
│   ├── src/
│   │   ├── routes/
│   │   ├── controllers/
│   │   ├── services/
│   │   ├── repositories/
│   │   ├── middleware/
│   │   ├── validators/
│   │   ├── lib/
│   │   └── types/
│   └── scripts/
├── supabase/              Infraestructura Supabase
│   ├── migrations/
│   ├── functions/
│   ├── seed.sql
│   └── config.toml
└── docs/
```

Regla arquitectonica:

```text
Frontend solicita.
Controller recibe.
Service decide.
Repository accede a datos.
PostgreSQL garantiza integridad y seguridad.
```

## Configuracion Rapida

Backend:

```bash
cd backend
npm install
npm run dev
```

Supabase:

```bash
supabase link --project-ref qwfkmijewogksfizdski
supabase db push
supabase db execute --file supabase/seed.sql
supabase db execute --file supabase/seed_auth_users.sql
```

Frontend:

```powershell
cd frontend
.\run_dev.ps1 -Device chrome
```

`frontend/run_dev.ps1` lee `backend/.env` y pasa las variables publicas al
cliente via `--dart-define`, incluyendo `BACKEND_API_BASE_URL`.

## Documentacion

- Backend: [`backend/README.md`](backend/README.md)
- Propiedad por carpeta: [`docs/OWNERSHIP.md`](docs/OWNERSHIP.md)
- Plan de desarrollo: [`docs/PLAN_DESARROLLO.md`](docs/PLAN_DESARROLLO.md)

## Seguridad

`SUPABASE_SERVICE_ROLE_KEY` vive solo en `backend/.env` o en Supabase secrets.
No debe tener prefijos publicos ni viajar al frontend. El cliente Flutter usa
Supabase Auth, envia el JWT al backend, y el backend valida permisos antes de
escribir en Postgres.
