# Permisos múltiples y boletín

## Usuarios con buscador y edición individual

El botón **Editar permisos** está en **Roles y perfiles** y en la hoja de edición
de un perfil existente. Desde un alumno o padre, abre el listado con su nombre
prellenado en la búsqueda. Desde un maestro abre la gestión general de accesos
familiares; una nota aclara que su acceso académico se gestiona mediante clases
asignadas. No cambia el rol ni guarda el formulario de perfil al navegar.

La pantalla muestra una lista desplazable de todas las cuentas de alumnos y
padres disponibles en el colegio, tengan o no reglas personalizadas. El buscador
filtra por nombre, rol o número de usuario y no requiere escribir tildes.
Cada fila tiene un lápiz que abre **Editar permisos**.

El diálogo consulta los once permisos efectivos del usuario en Supabase, con
la precedencia real de sus reglas. Cada permiso tiene un interruptor independiente,
incluidos **Ver boletín** y **Descargar boletín**. Se pueden guardar juntos estados
distintos, por ejemplo habilitar notas y deshabilitar la descarga. Solo se escriben
los interruptores modificados: los demás siguen heredando las reglas de rol o
institución. Cancelar no guarda nada y un error de conexión conserva la edición
en el diálogo para reintentar.

Los controles globales y de visibilidad por periodo se mantienen. Docentes y
administración conservan el acceso académico existente; no aparecen como
destinatarios de restricciones familiares.

La migración `0062_portal_user_permission_editor.sql`, aplicada en Supabase, añade las RPC
`portal_user_permissions` y `manage_portal_user_permissions`. La API expone
`GET /api/portal-access/users/:id/permissions` y el guardado existente acepta
`save_user_permissions`, con `userId` y `permissions: [{ permission, allowed }]`.
Solo pueden gestionar estos permisos administradores autorizados con `roles.edit`,
para usuarios activos de su institución.

`backend/scripts/portal_user_permissions_check.mjs` verifica estados mixtos,
herencia global después de guardar, aislamiento y autorización. Las reglas de
prueba se revierten; `--apply` instala solo las funciones y registra la migración.
La interfaz se prueba con 1000 usuarios, búsqueda sin tildes, edición desde el
lápiz, estados reales al abrir, guardado de diferencias y reintento tras un error.

## Controles globales

En **Roles y permisos → Permisos por rol o usuario**, selecciona uno o varios
permisos, elige si se habilitan o deshabilitan y guarda. Se mantiene el alcance
existente: institución, rol de padres/alumnos o usuario específico.

El guardado es atómico: se aplican todos los permisos seleccionados o ninguno.
Las reglas de otros permisos se conservan. Cada regla guardada sigue teniendo
su propio interruptor y la opción de quitarla para heredar la configuración.
No seleccionar ningún permiso mantiene deshabilitado el botón Guardar.

- **Ver boletín** (`reports.view`) controla el acceso a la pantalla y consulta.
- **Descargar boletín** (`reports.download`) controla el PDF y compartirlo.

Se puede permitir ver el boletín y bloquear descargarlo. Para descargar o
compartir hacen falta ambos permisos y las notas del periodo deben ser visibles.
Ocultar la consulta también impide exportarla. Los permisos de notas y sus reglas
por periodo siguen aplicándose. No se alteran los permisos académicos de personal.

## Persistencia

La migración `0061_batch_portal_permissions.sql` añade
`manage_portal_permissions(jsonb)`, que reutiliza el escritor autorizado de reglas
existente. Conserva precedencia, aislamiento por institución, auditoría y
notificaciones de revisión en Realtime. Solo acepta entre 1 y 11 códigos válidos,
sin duplicados, y un valor booleano explícito. Las reglas individuales anteriores
siguen siendo compatibles.

El endpoint existente `POST /api/portal-access/config` acepta ahora:

```json
{
  "action": "save_permissions",
  "scope": "role",
  "role": "student",
  "permissions": ["payments.view", "reports.download"],
  "allowed": false
}
```

La migración 0061 ya se aplicó en Supabase después de validar sus comprobaciones.
Se requiere publicar el backend y Flutter actualizados para mostrar el nuevo
editor. No se cambiaron los permisos actuales de ninguna familia durante el
despliegue.

## Verificación

`backend/scripts/portal_permissions_batch_check.mjs` valida en una transacción:
los once permisos simultáneos de padre y estudiante, activación posterior,
consulta del boletín con descarga deshabilitada, bloqueo de consulta, conservación
de restricciones ajenas al lote, rechazo de lotes inválidos, autorización y
aislamiento entre instituciones. Todas las reglas de prueba se revierten; con
`--apply` se conserva únicamente la función nueva y su registro de migración.

Las pruebas de servicio cubren el envío de una única RPC, validación previa,
errores de autorización y compatibilidad con clientes anteriores. La prueba de
interfaz selecciona tres permisos para un padre y comprueba que salen juntos en
una sola petición.

## Web local

La sesión de `127.0.0.1:8080` usa `frontend/serve_web.js`, que sirve la compilación
estática de `frontend/build/web`. Editar Dart no actualiza esa compilación.
Ejecuta `frontend/build_web_local.ps1` desde la raíz y después recarga la pestaña
con Ctrl+F5. El script usa el backend local y las claves públicas configuradas,
sin incluir credenciales de administración en la web.
