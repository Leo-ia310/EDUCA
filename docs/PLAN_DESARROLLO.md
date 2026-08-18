# Plan de desarrollo — Educa360 (equipo de 2)

Objetivo: dejar la app **completa y sólida**. Estrategia acordada: **pulir y
completar todo en modo demo primero**, y conectar el backend real después.

- **Frontend — Finn:** UI, navegación, tema, estado de presentación, mocks.
- **Backend — compañero/a (perfil experto):** Supabase (BD, RLS, seed, Auth,
  Storage), repos reales, push. Ver división en [`OWNERSHIP.md`](OWNERSHIP.md).

### Contexto del proyecto
- **Plataformas objetivo:** Android, iOS y Web (las tres).
  - ⚠️ **iOS requiere una Mac** (Xcode) para compilar/firmar/publicar.
- **Push sin Firebase:** decisión 2026-08 — **no se usa Firebase/FCM**. El
  push real se implementa con **Web Push estándar (VAPID)** vía una Supabase
  Edge Function (`backend/functions/send-push/`). Cubre Flutter Web de forma
  nativa; **no cubre push nativo en Android/iOS** (requeriría FCM/APNs u otro
  proveedor tipo OneSignal) — limitación conocida, no deuda oculta.
- Perfil del equipo: backend experto → guías de backend a alto nivel.
- **Estructura física:** desde la rama `Backend-MK` el repo separa
  `frontend/` (app Flutter completa) y `backend/` (SQL, RLS, seeds, Edge
  Functions) como carpetas de primer nivel. Ver detalle de rutas en
  [`OWNERSHIP.md`](OWNERSHIP.md).

---

## 1. Flujo de trabajo (Git)

Somos 2 personas sobre `main`. Para no romper el trabajo del otro:

1. **Nadie commitea directo a `main`.** Se trabaja en ramas:
   - `feat/<feature>-<detalle>` · `fix/<detalle>` · `chore/<detalle>` · `db/<detalle>`
2. **Pull Request** hacia `main`, con el otro como reviewer (CODEOWNERS lo pide
   solo en zonas compartidas; para el resto es buena práctica igual).
3. **Antes de empezar el día:** `git pull` en `main` y rebase de tu rama.
4. **CI mínima recomendada:** `flutter analyze` + `flutter test` deben pasar
   antes de mergear (ver Fase 3).
5. **Nunca** subir `.env` (ya está en `.gitignore`).

## 2. La regla del contrato (`domain/`)

`frontend/lib/features/<x>/domain/` (entidades + interfaces) es la frontera entre ambos.
**Cambios ahí se acuerdan en pareja.** Flujo cuando el frontend necesita un dato
nuevo:

1. Se define/ajusta la **interfaz + entidad** en `domain/` (PR con ambos).
2. Frontend implementa/ajusta el **mock** y consume la UI.
3. Backend implementa la **misma interfaz** contra Supabase (Fase 2).

---

## 3. Fases

### Fase 0 — Setup (ambos, ~1 día)
- [ ] Backend: obtener acceso al panel Supabase (credenciales las gestiona quien
      administre; ver notas de seguridad abajo).
- [ ] Ambos: correr la app en demo (`.\run_dev.ps1` sin `--dart-define`, o
      `.\run_demo.ps1 -Device chrome`).
- [ ] Activar ramas + PR + CODEOWNERS (reemplazar usuarios en `.github/CODEOWNERS`).

### Fase 1 — Pulido y completitud en DEMO  ⭐ (prioridad actual)
**Lidera Frontend.** Meta: cada pantalla funcional, consistente y sin errores de
layout, con datos mock realistas. Backend avanza terreno en paralelo (Fase 2 prep).

Backlog por feature — ver §4. Definición de "hecho" — ver §5.

### Fase 2 — Conexión a backend real
**Lidera Backend.** Reemplazar mocks por Supabase, feature por feature, sin tocar
la UI (misma interfaz `domain/`).
- [ ] Aplicar migraciones `0001`→`0005` en orden (SQL Editor o `supabase db push`).
- [ ] Aplicar `0005_fix_chat_rls.sql` (arregla recursión RLS del chat, error 42P17).
- [ ] Provisionar usuarios de **Auth** con `raw_app_meta_data`
      `{ "institution_id": 1, "roles": [...] }` + fila en `public.users` +
      `user_roles` (ver `backend/README.md` y `test_users.sql`).
- [ ] Sembrar datos operativos (estudiantes, clases, matrículas, tareas, notas).
- [ ] Crear bucket `files` (privado) + policy de Storage por institución.
- [ ] Completar repos Supabase (ver §4, columna Backend).
- [ ] Push real (Web Push/VAPID, sin Firebase): `web_push_service.dart` +
      Edge Function `backend/functions/send-push/` (ver detalle abajo).
      Cubre Flutter Web; Android/iOS nativo queda pendiente de un proveedor
      compatible (fuera de alcance por ahora).

### Fase 3 — Endurecimiento y release
- [ ] Tests: ampliar más allá del smoke test (widget + unit de controllers/repos).
- [ ] Estados de error/carga/vacío en todas las pantallas.
- [ ] Offline de asistencia end-to-end (cola de sync Hive).
- [ ] Revisar `flutter analyze` a 0 warnings (hoy: 0 errores, ~19 warnings, ~267 info).
- [ ] **Builds de release por plataforma:**
  - Web → `flutter build web` + hosting.
  - Android → `flutter build appbundle` + firma + Play Console.
  - iOS → `flutter build ipa` **en una Mac** + firma + App Store Connect.
- [ ] Push por plataforma probado (web push funcional; Android/iOS nativo
      pendiente de proveedor — ver nota en Fase 2).
- [ ] Íconos/splash y permisos revisados en las 3 plataformas.

---

## 4. Backlog por feature

Leyenda: 🟦 Frontend (demo)  ·  🟥 Backend (Fase 2)

| Feature | Frontend (Fase 1) | Backend (Fase 2) |
|---------|-------------------|------------------|
| **auth** | Pulir splash, código de colegio, login, errores | Provisionar usuarios Auth + roles en JWT |
| **dashboard** (4 roles) | Consistencia visual, datos mock realistas por rol | Agregaciones reales (repo Supabase) |
| **assignments** | Estados de UI, adjuntos en demo | Completar `grade()`, `submit()`, attachments, filtros por enrollment |
| **attendance** | Flujo tomar asistencia + historial | Cola de sync offline (Hive→Supabase) end-to-end |
| **chat** | Pulir conversaciones, input, burbujas | `ensureIndividual`, unread/typing/reads, RLS 0005, realtime |
| **grades** | Boletín alumno + libreta docente | Repo Supabase (evaluations/grades) |
| **payments** | Cobros, checkout, historial (demo gateway) | Repo Supabase + gateway de pago real |
| **events** | Anuncios + crear evento | Persistencia (hoy in-memory) |
| **schedule** | Horario semanal | Repo Supabase |
| **notifications** | Feed + ajustes | Web Push (VAPID) real; nativo Android/iOS pendiente |
| **profile / support / admin** | Pulir UI | Datos reales donde aplique |

## 5. Definición de "hecho" (DoD) por feature

- [ ] Corre en demo sin excepciones (`flutter analyze` sin errores en el archivo).
- [ ] Estados carga / vacío / error contemplados.
- [ ] Navegación e íconos consistentes con el design system (`core/theme`, `core/widgets`).
- [ ] Responsive (sin overflow) — cuidar botones full-width dentro de `Row`
      (ver el fix de `manage_teachers_screen`).
- [ ] (Fase 2) Repo Supabase implementa la interfaz `domain/` y pasa en conectado.
- [ ] PR revisado por el otro; `main` verde.

## 6. Notas de seguridad (Supabase)

- Credenciales **públicas** (URL, anon/publishable key): ya están en `.env`, OK.
- **service_role key** y **password de la BD**: SECRETAS. No van en la app, ni en
  el repo, ni en chats. Solo las usa quien administre el backend.
- Pendiente registrado: aplicar `0005_fix_chat_rls.sql` cuando haya acceso al panel.
