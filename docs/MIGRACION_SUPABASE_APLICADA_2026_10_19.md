# Migraciones de Supabase aplicadas — 19 de octubre de 2026

Tras autorización expresa del usuario se aplicaron los 9 cambios de [PROPUESTA_HORARIOS_BIGSCHOOL.md](PROPUESTA_HORARIOS_BIGSCHOOL.md) y las 25 migraciones 0029–0053 en una sola transacción. La base devolvió `schemaVersion: 53`; ambas comprobaciones de horarios devolvieron cero filas.

Antes de ejecutar se restauró una copia del backup en PostgreSQL local y se ensayó la propuesta junto con todas las migraciones sobre los datos reales copiados. El ensayo llegó a versión 53 sin modificar el origen. La ejecución remota bloqueó temporalmente las escrituras en las tablas públicas durante la transacción. El único trabajo de anuncios existente estaba finalizado con errores; no había trabajos activos en la revisión previa.

## Evidencia

- Transacción remota finalizada UTC: `2026-10-20T03:21:04.019Z` (19 de octubre, hora de Nicaragua).
- SHA256 del SQL ejecutado, incluida aprobación y bloqueos: `1a54def7c425891e5fecc29b9f83f568a17d759994d2f9d5f33620c54336da58`.
- Backup previo: `C:/Users/Maykel/Backups/EDUCA/2026-10-19_21-06-26`.
- Registro local protegido: `C:/Users/Maykel/Backups/EDUCA/migration-2026-10-19.json`.
- Backend local: `/health` 200 y `/ready` 200 con contrato 53.
- Prueba HTTP real: login 200 sin segundo factor, `/api/auth/2fa/status` 200 con `enabled=false, required=false`, notificaciones 200 y directorio administrativo 200. La sesión de pruebas se cerró con alcance local, conservando las demás sesiones del usuario.

La primera comprobación HTTP detectó una relación ambigua de PostgREST entre `users` e `institutions` debido a las nuevas tablas de recibos. Se corrigieron las lecturas de Auth y developer para indicar `users_institution_id_fkey`, y la de cargos para indicar `charges_institution_id_fkey`. Se añadió una prueba del SDK para evitar la regresión. Esto es un cambio de backend, no una migración SQL adicional.

## Alcance

El 2FA continúa siendo opcional y no se activó para ninguna cuenta. Las cuentas que lo tenían activo siguen requiriendo su segundo factor.

Supabase ya está actualizado y el backend local usa la corrección de consultas. No se desplegó un binario nuevo en Render, no se publicaron funciones Edge ni se distribuyeron clientes. Esas publicaciones siguen pendientes en sus respectivos entornos. Las notas anteriores que decían «migraciones pendientes» son cortes históricos previos a esta autorización.

La aplicación debe recargarse. Si conserva un refresh token inválido de antes, cerrar sesión y volver a entrar. No volver a ejecutar el paquete 0029–0053: su marcador rechaza una segunda aplicación. Para futuras migraciones, tener en cuenta que la base se administraba mediante SQL manual y no tenía tabla de historial del CLI; no marcar retrospectivamente migraciones como aplicadas sin comprobarlas.
