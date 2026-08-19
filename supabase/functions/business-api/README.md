# Edge Function `business-api` (legacy temporal)

Esta Edge Function conserva la API de negocio anterior como respaldo temporal.
La lógica principal migró a `backend/src` (Node.js + TypeScript), separada en
routes, controllers, services y repositories.

## Invocación

```
POST /functions/v1/business-api
Authorization: Bearer <access_token>

{
  "action": "assignments.upsert",
  "payload": { ... }
}
```

## Acciones cubiertas

- `assignments.teacherClasses`
- `assignments.upsert`
- `assignments.delete`
- `assignments.publish`
- `assignments.submit`
- `assignments.gradeSubmission`
- `payments.register`
- `payments.cancelCharge`
- `events.create`
- `attendance.upsertClassSession`
- `attendance.upsertAttendance`
- `grades.upsertScale`
- `grades.setDefaultScale`
- `grades.setGrade`
- `chat.sendMessage`
- `chat.markAsRead`
- `chat.ensureIndividual`
- `notifications.saveWebPushDevice`

El nuevo backend compatible recibe el mismo contrato en:

```http
POST /api/business-api
```

No elimines esta función hasta confirmar que no hay frontend, webhook ni
servicio externo llamándola.

## Estructura interna

```
business-api/
├─ index.ts          # entrada HTTP: CORS, auth, dispatch
├─ modules/          # lógica por dominio/categoría
│  ├─ assignments.ts
│  ├─ attendance.ts
│  ├─ chat.ts
│  ├─ events.ts
│  ├─ grades.ts
│  ├─ notifications.ts
│  └─ payments.ts
└─ shared/           # piezas transversales
   ├─ auth.ts        # contexto, roles y permisos
   ├─ db.ts          # helpers de consultas
   ├─ files.ts       # mapeo de adjuntos
   ├─ http.ts        # CORS/respuestas/errores
   ├─ supabase.ts    # cliente service-role del backend
   └─ validators.ts  # validadores de payload
```

`index.ts` no contiene reglas de negocio. Solo enruta la acción al módulo
correspondiente.

## Deploy

```bash
supabase functions deploy business-api --use-api
```

Supabase inyecta `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` en runtime.
