# Recuperación y cambio de contraseña

`Olvidé mi contraseña` llama a `POST /api/auth/recover-password`. Supabase
Admin genera un token de recuperación; Resend envía un enlace directo a la
pantalla de la app. No se usa `action_link`, el Site URL por defecto de Supabase
ni un verificador PKCE del navegador que solicitó el correo. Puede abrirse
en otro navegador o dispositivo.

## Android

El destino elegido es `https://nivramop.com/reset-password`. En `backend/.env`
y en las variables del backend desplegado:

```dotenv
PASSWORD_RESET_REDIRECT_URL="https://nivramop.com/reset-password"
```

`frontend/android/app/src/main/AndroidManifest.xml` registra esa ruta HTTPS
con `autoVerify` y activa el manejo de enlaces de Flutter. El identificador
actual es `com.nivra.demo`. GoRouter abre el formulario público de recuperación
tanto al iniciar la app desde cero como cuando ya está abierta. El token viaja
en `?token_hash=...`, no en `#/...` (el fragmento es solo para Flutter web).
La inicialización de Supabase desactiva `detectSessionInUri`: los enlaces
los recibe GoRouter y la recuperación la valida el backend, sin iniciar
sesiones de Supabase automáticamente desde una URL.

Para completar la asociación del dominio, publicar el contenido de
`deployment/android-links/public/` en el hosting de **nivramop.com**:

- `/.well-known/assetlinks.json`: HTTP 200, `Content-Type: application/json`,
  sin autenticación ni redirecciones. No confundir con el dominio del backend.
- `/reset-password`: página de respaldo para navegadores que no abran la app.
  Servir `reset-password/index.html` y `/reset-password/open-app.js` conservando
  el query string. El botón de apertura usa un Intent HTTPS dirigido
  exclusivamente a `com.nivra.demo`. No consume el token al cargar la página.
- En la ruta de recuperación, desactivar caché, analíticas y registros del
  query string; usar `Referrer-Policy: no-referrer` y `Cache-Control: no-store`.
  La página incluida no envía tokens a terceros.

**Firma:** el archivo incluido corresponde al certificado local actual
(`androiddebugkey`). Gradle actualmente también firma `release` con esa clave.
Permite verificar los APK actuales; antes de publicar en Google Play, generar
el archivo con el SHA-256 del **certificado de firma de la app** de Play Console
(no el certificado de subida). Al cambiar de firma hay que actualizarlo.
El generador acepta varias huellas si se distribuyen APK con diferentes firmas:

```powershell
node deployment/android-links/generate-assetlinks.cjs "HUELLA_SHA256_CON_DOS_PUNTOS"
```

El generador lee `applicationId` de Gradle. Si ese identificador cambia,
actualizar también el paquete del Intent en `open-app.js` antes de publicar.
No requiere ni publica claves privadas. Fuente de la asociación:
[App Links de Flutter](https://docs.flutter.dev/cookbook/navigation/set-up-app-links).
Fuente del botón: [Android Intents en Chrome](https://developer.chrome.com/docs/android/intents).

**Estado externo al configurar:** el dominio responde, pero
`https://nivramop.com/.well-known/assetlinks.json` devuelve 404. Los archivos
están preparados en el repositorio; todavía hay que publicarlos en el hosting.
No se confirmó apertura física en un teléfono.

Después de instalar un APK nuevo, verificar en un teléfono conectado:

```powershell
adb shell pm verify-app-links --re-verify com.nivra.demo
adb shell pm get-app-links com.nivra.demo
adb shell am start -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "https://nivramop.com/reset-password?token_hash=invalid-test-token"
```

El dominio debe figurar `verified`; el último comando debe abrir el formulario
y el token de ejemplo debe ser rechazado al guardar. Omitir el paquete en ese
comando comprueba la resolución del sistema, no una apertura forzada.
Después solicitar un correo real nuevo y probar el enlace con la app cerrada
y abierta. No reutilizar enlaces antiguos. El APK debe compilarse con
`BACKEND_API_BASE_URL` apuntando a la API HTTPS pública: un teléfono no puede
usar el `localhost` del equipo de desarrollo.

## Desarrollo web

Para continuar usando el formulario en el navegador local, reemplazar el
destino de forma explícita. Las comillas son necesarias porque dotenv
interpreta un `#` sin comillas como un comentario:

```dotenv
PASSWORD_RESET_REDIRECT_URL="http://127.0.0.1:8080/#/reset-password"
```

En producción configurar explícitamente el destino Android de arriba.
El servidor rechaza una URL inválida
o ausente en producción; nunca recibe una URL de redirección del cliente.
Los enlaces antiguos conservan el destino antiguo: solicitar un correo nuevo.

La ruta `/reset-password` es pública, incluso si hay una sesión o un 2FA
pendiente. El formulario envía `{ tokenHash, newPassword }` a
`POST /api/auth/reset-password`. El backend valida la contraseña antes de
consumir el token; Supabase verifica que el token sea de tipo `recovery` y
no esté usado ni expirado. Después cambia la contraseña y cierra las sesiones.
No devuelve tokens de sesión y conserva la configuración de 2FA. El usuario
vuelve al login y verifica su segundo factor normalmente.

El cambio desde el perfil llama a `POST /api/auth/change-password` con sesión
y `{ currentPassword, newPassword }`. Ya no simula el guardado. Verifica la
contraseña actual y exige una nueva diferente de al menos ocho caracteres.
La pantalla muestra los errores reales y confirma solo después de guardar.

## Comprobaciones

- `cd backend && npm run typecheck` y `npm run docs:apis`.
- `npx tsx scripts/password_security_e2e.ts`: cambia y recupera la contraseña
  de una cuenta temporal mediante Supabase y HTTP reales. Comprueba consumo
  único, enlaces inválidos, contraseña anterior rechazada, login nuevo y 2FA
  conservado. Intercepta el correo y elimina la cuenta al terminar.
- `flutter test --no-pub test/features/auth/password_security_test.dart`:
  formulario, errores, validación, envío autenticado/público y ruta de correo
  accesible antes de completar el login, arranque desde un App Link HTTPS
  y entrega de otro enlace con la app ya abierta.

No se envían correos de prueba a personas ni se cambian contraseñas reales.
