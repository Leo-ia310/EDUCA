# Validación local de las correcciones de escalabilidad

Fecha: 19 de octubre de 2026. Entorno: Windows, Node 22.15.1, PostgreSQL temporal 17.10 (paquete embedded-postgres 17.10.0-beta.17), Flutter 3.47.4 y Dart 3.13.3.

Los 15 bloques de [ESCALABILIDAD_IMPLEMENTACION.md](ESCALABILIDAD_IMPLEMENTACION.md) están implementados y verificados localmente. Esto no significa que estén desplegados ni que se haya medido la nueva capacidad de Render.

## Resultados

| Comprobación | Resultado |
| --- | --- |
| `npm --prefix backend run typecheck` | Aprobado: aplicación y pruebas TypeScript |
| `npm --prefix backend run test:unit` | 50 aprobadas; 0 fallidas |
| `npm --prefix backend run test:integration` (incluido en `npm test`) | 77 aprobadas; 0 fallidas, omitidas o canceladas |
| `npm --prefix backend run build` | Aprobado; incluye generación de documentación API |
| `cd frontend` y `flutter test` | 175 aprobadas |
| `cd frontend` y `flutter analyze` | No issues found! |
| `k6 inspect backend/scripts/k6/session-flow.js` | Aprobado; inspección sin solicitudes de carga |
| `k6 inspect backend/scripts/k6/backend.js` | Aprobado; inspección sin solicitudes de carga |
| `git diff --check` | Sin errores de whitespace |

Total: **302 pruebas aprobadas**. La última validación de unidades se repitió después de endurecer validadores: una expectativa que rechazaba la página válida `"1"` fue corregida; la suite final pasa completa. La suite SQL completa tarda aproximadamente 380 segundos en este equipo. Los tiempos locales no son un benchmark de producción.

Las 77 pruebas SQL se reparten en 40 regresiones generales, 13 de administración atómica, 10 de anuncios, 9 de chat/push y 5 de asistencia. La base temporal aplica migraciones reales, excepto los seeds demo históricos 0011/0013 que dependen de identidades aprovisionadas manualmente. Cada prueba general crea sus propios datos y no depende de los resultados de otra.

## Cobertura relevante

- Pagos, cargos, roles, personas, boletines y horarios: autorización, transacciones, concurrencia, idempotencia, rollback y protección de historial.
- Lecturas: paginación/cursor, más de 1000 filas, agregados, años/periodos, aislamiento institucional, RLS y planes con índices reales.
- Auth: recuperación de altas interrumpidas y rechazo de compensaciones destructivas ante respuestas ambiguas. El proveedor está simulado; se valida la lógica de recuperación y el contrato SQL.
- Anuncios y push: límites compartidos, reparto entre instituciones, leases, checkpoints, consentimiento/permisos vigentes, reintentos, revisión de correo ambiguo y caducidad. Transporte externo simulado.
- Flutter: estado offline persistido en Hive, conflicto entre escritores, respuesta perdida, cambio de cuenta, cancelación, paginación, composición de mensajes y controles de seguridad.
- Operación: errores controlados, admisión, plazos, readiness, métricas y cierre acotado; handlers puros de las funciones legacy.

## Alcance pendiente de publicación

No se aplicaron migraciones a Supabase, no se desplegó en Render/Edge, no se publicaron clientes ni se enviaron correos/push reales durante esta fase. La pasarela de pagos sigue siendo demo. CI quedó configurado, pero no se ejecutó en GitHub; los scripts E2E que requieren servicios reales tampoco forman parte de estos resultados.

La API de Auth, el servicio PostgREST administrado, los proveedores y las condiciones reales de CPU/RAM/red pueden comportarse distinto del harness. Hay que seguir [DESPLIEGUE_ESCALABILIDAD.md](DESPLIEGUE_ESCALABILIDAD.md), verificar compatibilidad de clientes y ejecutar pruebas representativas después de publicar.

**Todavía no hay una cifra nueva defendible de personas simultáneas.** k6 distingue recorridos de negocio de `/health` y exige identidades distintas para estimar personas. La inspección de los scripts no ejecuta escenarios ni demuestra capacidad. La prueba histórica anterior a las correcciones permanece en `backend/stress-results/2026-10-17/REPORTE.md` y no debe atribuirse a esta versión.
