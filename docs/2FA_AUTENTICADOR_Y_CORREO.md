# 2FA con autenticador y correo (Task 39)

En **Cuenta → Seguridad**, el usuario elige **App autenticadora** o
**Correo electrónico**. Hay un método activo por cuenta; cambiarlo requiere
desactivar primero el actual confirmando un código o una recuperación.

El autenticador muestra QR generado localmente desde `otpauth://`, clave
manual y opción de copiarla. Usa TOTP SHA-1, seis dígitos, periodos de 30
segundos y tolerancia de un periodo a cada lado. El secreto aleatorio tiene
160 bits. No se envía el secreto a servicios de imágenes externos.

El correo usa el servicio Resend existente (`EMAIL_PROVIDER=resend`,
`RESEND_API_KEY`, `RESEND_FROM_EMAIL`). El código sirve para una acción concreta:
activación, login o desactivación. Caduca en cinco minutos. Se exige esperar
60 segundos entre solicitudes y se permiten cinco envíos por usuario/hora.
El reenvío invalida el reto anterior y conserva el contador global de fallos.
Cinco intentos incorrectos bloquean la cuenta durante 15 minutos. Los contadores
y el consumo de retos se actualizan bajo bloqueo de fila en Postgres.

Ambos métodos generan diez códigos de recuperación de un uso. Solo se muestran
al confirmar la activación; se almacenan sus hashes. Los códigos de correo se
guardan con HMAC ligado al reto y a una clave privada del servidor, nunca en
texto claro. Rotar la service-role key invalida los códigos de correo pendientes.
El backend no devuelve códigos de desarrollo cuando falla Resend.

El remitente acepta `correo@dominio.com` o `Nivra <correo@dominio.com>`.
Los delimitadores deben estar completos. Un remitente mal formado o un servicio
sin configurar produce un error controlado 503 y no activa 2FA. El frontend
conserva el mensaje de configuración para distinguirlo de un fallo temporal de envío.

## Persistencia y sesiones

La migración 0028 traslada secretos y recuperaciones existentes a
`auth_two_factor_settings`, privada al backend, y limpia los campos sensibles
del perfil público. Los retos, tokens retenidos y sesiones verificadas también
son privados. El método y el estado verificado se guardan al confirmar el código;
un envío fallido no activa 2FA. Los tokens retenidos se borran del reto consumido.

El login no entrega la sesión antes de confirmar el segundo factor. La sesión
Supabase verificada queda asociada a `auth.sessions.id`. Un token obtenido solo
con contraseña no puede obtener datos protegidos por API/RLS ni usar el alcance
institucional de los RPC de negocio. Activar 2FA valida la sesión que hizo la
activación; las renovaciones conservan esa sesión. Desactivar elimina las
marcas de verificación de la cuenta.

Las cuentas que ya tenían 2FA activo antes de esta migración deben volver a
iniciar sesión para registrar una sesión verificada. Sus secretos y método se
conservan. No se activó ni desactivó 2FA de cuentas reales durante las pruebas.

## API

- `GET /auth/2fa/status`: estado, método, verificación y recuperaciones restantes.
- `POST /auth/2fa/setup { method: 'totp' | 'email' }`: inicia activación.
- `POST /auth/2fa/enable { challengeId, code }`: confirma y devuelve recuperaciones.
- `POST /auth/2fa/email-code { purpose: 'disable' }`: envía código de desactivación.
- `POST /auth/2fa/disable { challengeId?, code? | recoveryCode? }`.
- `POST /auth/2fa/verify-login { challengeId, code? | recoveryCode? }`.
- `POST /auth/2fa/resend-login { challengeId }`: devuelve un reto nuevo.

Todos los paths usan el prefijo `/api`. Los retos de login son accesibles
solo después de verificar la contraseña. Los demás requieren la sesión del
propietario. Los errores diferencian código incorrecto, expirado, usado,
bloqueado, límite de envíos y fallo de proveedor.

## Verificación

Desde `backend`: `npm run typecheck`, `npm run docs:apis` y
`npx tsx scripts/two_factor_methods_check.ts`. El último ejercita el servicio
real y los RPC de Postgres con un transporte de correo inyectado; revierte
usuarios, sesiones y retos en una transacción y no envía correos reales.
`npx tsx scripts/email_delivery_check.ts` valida el remitente y la petición a
Resend con HTTP interceptado; tampoco envía correos.
También comprobar `portal_access_db_check.mjs`, `collaborations_db_check.mjs`
y `announcement_queue_check.mjs` desde `backend/scripts` después de cambios RLS.

Desde `frontend`: `flutter test --no-pub --concurrency=2` y
`flutter analyze --no-pub`. Los tests de 2FA cubren QR y clave manual, selección,
errores, expiración, recuperación, método activo, desactivación y ambos logins.
La recepción real del correo y su clasificación en spam dependen de la
configuración y dominio verificado de Resend; las pruebas automáticas no hacen
envíos a las cuentas del colegio.
