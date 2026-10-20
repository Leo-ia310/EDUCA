# Correcciones de escalabilidad y consistencia

**Estado actualizado:** las migraciones 0029–0053 y los 9 cambios de horarios autorizados ya se aplicaron a Supabase. Backend local `/ready`: 200, contrato 53. Publicación de backend en Render/Edge/clientes pendiente. Ver [registro de aplicación](MIGRACION_SUPABASE_APLICADA_2026_10_19.md). Las referencias siguientes a pendientes describen el estado previo o el procedimiento para otros destinos.

Seguimiento de los hallazgos del análisis del 18 de octubre de 2026. Cada bloque incluye implementación, pruebas y compatibilidad de contratos. Las migraciones se verifican en una base aislada antes de desplegar; no se consideran aplicadas al servicio de Render por el solo hecho de existir en el repositorio.

## Secuencia

- [x] 1. Pagos atómicos, idempotencia y cancelación concurrente (implementado; migración pendiente de despliegue).
- [x] 2. Lecturas completas y agregaciones correctas de pagos, notas, asistencia y dashboard (implementado; migraciones pendientes de despliegue).
- [x] 3. Tareas: eliminar consultas por elemento, paginar y resolver identidad del alumno (implementado; migración pendiente de despliegue).
- [x] 4. Notas: agrupar evaluaciones de materias y periodos (implementado; migración pendiente de despliegue).
- [x] 5. Chat: consultas agrupadas, mensajes paginados, lecturas incrementales y ciclo de vida (implementado; migración pendiente de despliegue).
- [x] 6. Notificaciones: Realtime, respaldo adaptativo y suspensión en segundo plano.
- [x] 7. Autenticación, presupuesto de consultas y cupo por usuario compartido entre instancias (implementado; migración pendiente de despliegue).
- [x] 8. Directorio administrativo paginado y búsquedas en servidor (implementado; migraciones pendientes de despliegue).
- [x] 9. Horarios: filtros SQL y protección transaccional de conflictos (implementado; migración pendiente de despliegue).
- [x] 10. RLS e índices: optimizaciones verificadas sin relajar autorización (implementado; migraciones pendientes de despliegue).
- [x] 11. Anuncios: contadores incrementales, reparto de trabajo, audiencia SQL y feed paginado (implementado; migraciones pendientes de despliegue).
- [x] 12. Asistencia offline: lotes, versiones, caché por cuenta y confirmación de escritura (implementado; migración pendiente de despliegue).
- [x] 13. Escrituras compuestas: roles, personas y boletines sin estados parciales (implementado; migraciones pendientes de despliegue).
- [x] 14. Errores HTTP, timeouts, cancelación, métricas y cierre ordenado (implementado; marcador SQL pendiente de despliegue).
- [x] 15. Pruebas de regresión, CI, documentación y carga reproducible (verificadas localmente; CI remoto y nueva carga tras despliegue pendientes).

## Verificación

No se utilizan las cuentas ni datos reales de BigSchool como fixtures de escritura.

### 1. Pagos

- Migración `0029_atomic_payments.sql`: RPC con actor derivado del JWT, bloqueo por clave y cargo, recibo original en reintentos y conflicto 409 si cambia el contenido. Triggers protegen también escrituras directas. Se impide anular un cargo que ya tiene pagos.
- El checkout conserva la clave y la referencia de pasarela entre reintentos y navegación, queda separado por cargo y se invalida al cambiar de cuenta. La pasarela sigue siendo demo: integrar un proveedor real requiere además idempotencia y conciliación persistentes del proveedor, incluidas interrupciones de la aplicación.
- `npm test`: typecheck, generación de documentación y 8 pruebas de integración aprobadas en PostgreSQL 17 temporal. Casos concurrentes, aislamiento, permisos y MFA. El harness no lee `.env`; omite exclusivamente los seeds históricos de datos demo 0011/0013 que requieren IDs aprovisionados manualmente.
- Flutter: 2 pruebas de checkout aprobadas, incluida respuesta perdida después del commit, doble clic, navegación, conflicto y saldo. Analyzer detectó únicamente comas finales en los archivos editados; corrección y verificación final en curso.
- Despliegue: aplicar 0029 antes de publicar el backend que invoca las nuevas RPC. Los índices y cambios SQL no se han aplicado a producción.

### 2. Lecturas y agregados

- Resumen de pagos en SQL con saldos después de abonos, fechas en zona institucional y separación de monedas. Totales por cargo en lotes de 200; no se descarga el libro de pagos de toda la institución para consultar un alumno/cargo.
- Flutter agrupa balances en una lectura de cargos y consultas de totales por lote, eliminando una lectura por alumno. `dunningMetrics` consume el resumen del backend.
- Notas y asistencia leen las páginas completas de grids/reportes con orden estable. Matrícula del gradebook acotada al año de la clase, estado ACT y alumnos activos; se deduplica el roster.
- Dashboard: conteos HEAD, agregados SQL, año actual, PRE por código y totales del grupo correcto por tarea. Contratos en `RPCS_LECTURA_ESCALABILIDAD.md`.
- Verificado: typecheck backend, 5 pruebas unitarias y 12 de integración aprobadas; la comprobación específica de dashboard incluye promedio anual y restricciones de notas. Flutter: 12 pruebas de cargos, paginación y checkout aprobadas. La prueba con 1105 abonos detectó timeout de políticas repetidas por fila; tras autorización explícita y agregación en SQL, pasó. Corrección adicional: un cargo que vence hoy no se marca en mora al empezar el día; los anulados no cuentan como mora. API calcula vencimiento con la zona institucional.
- `flutter analyze`: No issues found! antes de iniciar el bloque 3. Los índices y migraciones siguen sin aplicar a producción.
- La suite general Flutter arrojó 112 aprobadas y 5 fallidas en `two_factor_methods_test.dart`: desbordamientos y controles fuera de vista en la pantalla de seguridad. Se corregirá y repetirá la suite en el bloque 15; no se considera una suite aprobada.

### 3. Tareas

- Feed por cursor de fecha/ID, 50 elementos por defecto (máximo 100), búsqueda/tipo/materia/abiertas filtrados antes de paginar. SQL agrupa matrícula, entregas y adjuntos. Un request al backend por página; Flutter añade páginas sin volver a consultar las anteriores.
- Proveedores separados por alumno, materia y tareas/pruebas; el detalle del alumno resuelve su identidad. Las tarjetas usan el avance incluido en la página y no consultan una entrega por cada elemento. Entregas del panel docente también leen el endpoint por lotes, no una consulta por alumno.
- Catálogo de estados comparte la solicitud en curso. Contadores y matrículas se agregan en SQL. Fechas nulas se conservan y se muestran como “Sin fecha de entrega”. El tipo de tarea ahora se persiste y se sincroniza con su evaluación.
- Se verificaron páginas con fechas iguales/nulas, filtros, permisos, notas ocultas, tipos de evaluación y contadores. `npm test`: typecheck, 7 pruebas unitarias y 13 pruebas SQL aprobadas. Flutter: 15 pruebas de feed/estados aprobadas, incluidos filtros vacíos y cargas sin consultas por tarjeta. `flutter analyze`: No issues found!
- Una ejecución de `dart fix` se cruzó con ediciones y produjo comas fuera de posición. Se repararon los archivos y se repitieron las 15 pruebas con éxito. Las siguientes correcciones automáticas se ejecutan sin otras ediciones Dart hasta que terminan.
- Revisión pendiente en bloque 10: los roles mixtos padre/administrador deben conservar el alcance de hijos cuando usan permisos de padre, sin aprovechar el alcance amplio del rol administrativo para eludir permisos explícitos.

### 4. Notas y boletines

- Evaluaciones agrupadas por clases/periodos en memoria después de lecturas completas por lotes, sin HTTP dentro del bucle materia×periodo. Matrícula ACT y clases del año actual. El filtro de periodo de notas se envía a SQL.
- Gradebook Flutter conectado al endpoint del backend: una llamada conserva grids de más de 1000 celdas. Una nota cero cuenta en el promedio; NULL y materias sin calificar no se convierten en notas cero.
- Contexto del boletín por RPC 0033 con RLS, permisos y fechas del periodo. Asistencia sin registros queda desconocida; se retiran los valores inventados de primer puesto y asistencia perfecta. Pantalla y PDF muestran los valores no calculados como no disponibles.
- Verificado: 11 pruebas Flutter aprobadas (1440 evaluaciones, 12 materias×4 periodos, 1200 celdas, consultas paginadas, cero/NULL y datos desconocidos). `flutter analyze`: No issues found! Backend: typecheck, 7 pruebas unitarias y 14 SQL aprobadas antes del bloque de chat; incluye fechas, permisos y alcance del boletín.

### 5. Chat

- Las páginas de conversaciones se obtienen con una consulta agrupada, con participantes, último mensaje, no leídos y total global. Búsqueda en servidor y cursor que conserva microsegundos. La siguiente página no vuelve a descargar las anteriores; las actualizaciones periódicas reconcilian las páginas visibles.
- Historial inicial limitado a 100 mensajes, carga explícita de anteriores y sondeo de deltas. Los eventos Realtime pueden hidratar un mensaje puntual, incluidas modificaciones/borrados. Se mantiene el orden numérico de IDs en fechas iguales.
- Lecturas confirmadas por RPC en una transacción: solo inserta recibos faltantes y confirma notificaciones, sin transportar IDs ni truncarlos. Creación individual serializada por par de usuarios con inserción atómica de ambos participantes.
- El proveedor libera repositorios reales y demo al cambiar de cuenta. Al cerrar un historial se cancelan canal/temporizador y se libera su caché; las solicitudes compartidas evitan consultas superpuestas y las respuestas tras `dispose` no emiten datos.
- Verificado: 16 pruebas PostgreSQL aprobadas, incluidos 1105 mensajes, paginación, alcance, actor inactivo, búsqueda y creación concurrente. Las 14 pruebas Flutter de notas/chat pasan juntas. Las 3 de chat cubren consulta compartida de feed/badge, cursor, total global, historial/deltas, orden, cancelación y respuesta tardía. Typecheck backend aprobado. `flutter analyze`: No issues found!

### 6. Realtime y segundo plano

- Control compartido de refresco para notificaciones/chat: una lectura en curso, eventos agrupados y una lectura posterior si llega un evento durante la consulta. Realtime sano concilia cada 5 minutos; sin canal, respaldo de 30 segundos (15 para el chat abierto), con variación aleatoria y backoff hasta 5 minutos ante fallos.
- Se cancelan temporizadores en segundo plano y al destruir el repositorio. Al volver se reconcilia el estado; el chat recarga una ventana reciente acotada y mantiene los mensajes locales pendientes. Eventos de inserción ordinarios se agrupan para no hacer un HTTP por mensaje.
- El aviso local de 2FA conserva su consulta durante 5 minutos y se comprueba de nuevo al reanudar. La pantalla de seguridad ya invalida el feed al habilitar/deshabilitar 2FA. Se conserva el feed ante fallos, sin repetir avisos de llegada para entradas recientes que reaparecen; memoria de IDs limitada a 1000.
- Verificado: 10 pruebas de refresco/notificaciones/chat y 21 pruebas de regresión juntas aprobadas. Cubren concurrencia, evento durante lectura, backoff, reanudación, suspensión, caché de estado, avisos, fallos y destrucción. `flutter analyze`: No issues found!

### 7. Autenticación y cupos

- Se conserva la verificación del bearer exacto en Supabase Auth. Una RPC privada para backend obtiene contexto, permisos de módulos, identidades asociadas y cupo, comprobando cuenta/institución activas, sesión real y 2FA. El contexto solo vive durante esa petición; no se relaja la revocación mediante caché temporal.
- Cupo atómico por cuenta en PostgreSQL, común a procesos/instancias; cabeceras de límite y `Retry-After`. Los límites de fallos por IP siguen siendo la primera protección local por proceso. Configuración y despliegue en `AUTENTICACION_Y_CUPOS.md`.
- El middleware hace una verificación Auth y una RPC de contexto/cupo; ya no repite HTTP para permisos de módulo ni para resolver padre/alumno/maestro. Las comprobaciones de recurso y RLS siguen activas. Las caídas de Auth devuelven 503, sin contarlas como contraseña/token incorrectos.
- Verificado: `npm test` aprobó documentación, typecheck, 10 unitarias y 18 pruebas PostgreSQL. Incluye conexiones concurrentes, vencimiento/revocación, roles globales, permisos modificados, 2FA, aislamiento de la RPC y ausencia de caché entre peticiones.
- La validación detectó bloqueos transitorios de archivos generados en Windows: la documentación se escribe de forma atómica y se conserva sin sobrescribir cuando el contenido es idéntico.

### 8. Directorio y búsquedas

- Personas, perfiles administrativos, grupos y clases se filtran en SQL antes de paginar (50, máximo 100); se hidratan solo relaciones de la página. Contadores separados del catálogo, sin descargar toda la institución. Los selectores conservan elecciones entre búsquedas/páginas y recuperan sus etiquetas por ID.
- Formularios recuperan el detalle completo antes de editar relaciones. Contactos buscan en servidor; dashboard docente pide solo clases actuales y calificaciones recientes con JOIN; tareas pendientes usa su agregado, no las cinco tarjetas de vista previa. Boletines emitidos seleccionan la última versión en SQL antes de paginar.
- Verificado: documentación, typecheck, 10 pruebas unitarias y 24 PostgreSQL aprobadas; cubren más de 1000 personas/usuarios/boletines, selecciones fuera de página, aislamiento, permisos y visibilidad. Las 8 pruebas Flutter de directorio, creación de perfiles y presupuesto de consultas pasan. `flutter analyze`: No issues found! Contrato y despliegue en `DIRECTORIO_PAGINADO.md`.

### 9. Horarios

- Filtros administrativos y paginación en SQL; la semana personal se agrega sin truncamiento de PostgREST y con matrícula ACT/año actual o clases titulares/colaboradas. La búsqueda de grupos conserva estado y no depende del primer catálogo.
- Restricciones EXCLUDE por institución/año/día impiden cruces concurrentes de grupo, maestro y nombre normalizado del aula. Recesos generales ocupan todos los grupos. Crear varios días y resolver aula es una transacción; una actualización combina solo campos enviados con el registro bloqueado. Cambiar clases o aulas vuelve a validar sus horarios.
- Verificado: 30 pruebas PostgreSQL, 12 unitarias de backend y 14 Flutter aprobadas; más de 1000 bloques, escrituras simultáneas, rollback completo, intervalos adyacentes, año histórico, permisos y búsqueda/paginación. `flutter analyze`: No issues found! La prueba visual detectó y corrigió el Material local necesario para las interacciones del selector.
- Despliegue condicionado a backup y consultas de solo lectura `backend/scripts/schedules-preflight.sql`: la prueba detecta cruces históricos sin borrar datos. Instrucciones en `HORARIOS_TRANSACCIONALES.md`. No se ha aplicado a producción.

### 10. RLS e índices

- Funciones invariantes envueltas en SELECT para ejecutarse una vez por sentencia; los permisos de recursos siguen dependiendo de cada fila. Índices ligados a filtros/relaciones reales, incluido nombre completo del directorio privado. Se verifica el plan real, no se fuerza un índice ni se desactiva RLS.
- Roles activos y asignaciones vinculadas a la institución; se ignoran JWTs con roles antiguos y asignaciones ajenas. Revocar el último rol o desactivar institución se aplica en SQL y HTTP. Las cuentas mixtas conservan el pago a hijos reales y el permiso docente sobre sus clases, sin saltarse límites administrativos sobre otras personas. API de datos protegida contra autoasignación de superadministrador y cambios directos de identidad.
- Horarios directos limitados a grupos/clases autorizados. Las candidatas del docente se materializan antes de comprobar sus permisos: la regresión detectó timeouts al comprobar también clases ajenas y se corrigió el orden. Una repetición concurrente de horarios detectó un deadlock entre índices GiST; las mutaciones administrativas ahora se serializan por institución antes de bloquear filas, conservando las exclusiones para escritores directos.
- Visibilidad de promedios/boletines/PDF por año conocido, sin que un periodo histórico oculto bloquee el actual. Documentos anuales sin año verificable conservan el bloqueo conservador. Solo se rellenan años derivados de matrícula o periodo existentes.
- Verificado: documentación, typecheck, 12 unitarias y 39 pruebas PostgreSQL aprobadas; 11 Flutter de accesos/notas aprobadas. EXPLAIN confirma un InitPlan de MFA ejecutado una vez y los índices de nombre/persona en el directorio privado con 10 000 personas adicionales (última consulta local: 2,801 ms; no es una medida de capacidad de Render). Analyzer previo de frontend: No issues found! Detalles y orden de despliegue en `RLS_E_INDICES.md`.
- Antes del despliegue debe completarse el bloque 13 de aprovisionamiento compuesto: los nuevos límites de roles no se deben sortear con escrituras parciales de los flujos anteriores.

### 11. Anuncios

- Contadores incrementales y checkpoints idempotentes; preparación de destinatarios una vez, admisión global de 4 trabajos y uno por institución, porciones acotadas que ceden el turno. Consentimiento y roles se vuelven a comprobar antes del envío. Todas las operaciones de correo comparten presupuesto en PostgreSQL, respetando límites y enfriamiento del proveedor.
- Se conservan clave y payload de Resend durante su ventana de idempotencia; después de 23 horas o al cambiar de correo tras un intento se requiere revisión. Reintentar no reenvía casos ambiguos automáticamente. Conciliación privada con evidencia del proveedor y clave nueva únicamente tras confirmar que no se envió.
- Audiencia/grupos filtrados en SQL antes de paginar, calendario con igual privacidad y publicación transaccional obligatoria. Flutter conserva páginas, evita que nuevas publicaciones desplacen el cursor y consulta solo metadatos de trabajos activos. Realtime con respaldo adaptativo, suspensión en segundo plano, respuestas tardías descartadas y progreso ordenado por versión temporal del servidor.
- Verificado: 24 pruebas unitarias backend, 9 PostgreSQL de anuncios y 20 Flutter aprobadas. Incluyen más de 1000 destinatarios/publicaciones, migración de trabajos antiguos, límites compartidos, leases, consentimiento, concurrencia, conciliación, privacidad, cursor bigint, lotes de progreso y cierre de pantalla. La regresión backend previa pasó 39 pruebas SQL adicionales. Correos simulados, sin envíos ni migraciones en producción. `flutter analyze`: No issues found! Contratos y despliegue en `ANUNCIOS_Y_ENTREGAS.md`; el cierre HTTP que espera al worker se integra en el bloque 14.

### 12. Asistencia offline

- Lotes de hasta 100 marcas/sesiones con versión optimista y claves de operación persistidas. Sesión, asistencia, recibos y cambios en una transacción. Un elemento inválido revierte todo; los conflictos conservan la elección local y requieren revisión explícita, sin sobrescribir el servidor.
- Hive y caché de clases/roster separados por cuenta/institución; no se atribuyen registros históricos sin autor al usuario siguiente. La cola solo se limpia después de validar la confirmación. Ediciones durante envío, reinicio y cierre de cuenta conservan el trabajo. No se fabrican marcas presentes ni clases demo en una sesión real.
- Cursor `(updated_at,id)` con microsegundos y bloqueo de commit por institución para no saltar cambios tardíos, acotado a clases autorizadas. La conectividad obtiene estado inicial y mantiene el seguimiento, sin esperar un cambio de Wi-Fi para empezar. Base de errores HTTP estructurados para permitir caché ante fallos transitorios, conservando denegaciones; se amplía en el bloque 14.
- Verificado: `npm test` aprobó documentación, typecheck, 27 unitarias y 53 PostgreSQL; incluye reintentos, dos docentes concurrentes, revocación de colaborador, más de 1000 cambios con timestamps iguales, rollback e aislamiento. 20 Flutter de asistencia/cliente HTTP/refresco/notificaciones aprobadas, con cajas Hive reabiertas desde disco. `flutter analyze`: No issues found! Contratos y actualización coordinada de clientes en `ASISTENCIA_OFFLINE.md`. No se ha desplegado.
### 13. Escrituras compuestas y entrega de push

- Migraciones 0048–0051: personas, relaciones, roles, escalas, boletines y cargos se guardan mediante operaciones atómicas con autorización vigente. Los boletines se generan desde una instantánea autorizada de SQL. Los lotes de cargos validan todos sus elementos antes de escribir; no truncan resultados al primer millar.
- El alta de cuentas reserva una identidad y una clave persistente antes de llamar a Auth. Si se pierde la respuesta se recupera esa identidad verificada y se retoma la transacción; no se borra Auth ante un resultado ambiguo. Las reservas pendientes o en revisión necesitan conciliación. Flutter conserva únicamente las claves necesarias para reintentar, separadas por cuenta/institución.
- Migración 0052: mensaje, notificaciones y trabajos por dispositivo se registran en una transacción. UUID de mensaje obligatorio, reutilizado tras respuesta perdida y reconciliado por identidad. El compositor conserva el contenido fallido. Registro de dispositivo mediante RPC; las escrituras directas que eludían estos contratos quedan revocadas.
- Push de chat y anuncios comparte una cola durable: leases, límite global y por institución, selección justa, reintentos acotados, caducidad y nueva comprobación de permisos. No se añaden dispositivos nuevos a una notificación antigua. El worker cede el turno entre lotes; los correos pendientes tienen prioridad sobre destinatarios que solo esperan push. Los proveedores externos no ofrecen una transacción conjunta con PostgreSQL: se conservan límites y conciliación explícitos.
- Verificado: 13 pruebas SQL administrativas, 9 de chat/push y regresiones de anuncios; unidades de aprovisionamiento y workers, además de la suite Flutter completa. Contratos y recuperación en [ESCRITURAS_TRANSACCIONALES.md](ESCRITURAS_TRANSACCIONALES.md).

### 14. Operación y errores

- Errores de base/Auth transformados a códigos HTTP controlados y sin detalles SQL privados. Validación estricta de IDs, números, fechas y booleanos; conflictos, denegaciones, cuotas y dependencias caídas conservan significados distintos. Las caídas de Auth no se cuentan como credenciales incorrectas.
- Admisión y plazo por petición, cancelación propagada a dependencias y cierre por SIGTERM/SIGINT que espera peticiones y ambos workers dentro de un límite. Flutter cancela al cerrar o cambiar de cuenta y descarta respuestas tardías. No reintenta escrituras automáticamente con claves nuevas.
- `/health` comprueba vida; `/ready` comprueba disponibilidad SQL y marcador de contrato 53. Métricas internas protegidas, por proceso, con códigos exactos y rutas normalizadas sin parámetros privados. La admisión HTTP y los límites por IP siguen siendo locales a cada proceso; el cupo de usuario y las colas sí se coordinan en SQL.
- Verificado: unidades de errores, sobrecarga, readiness, cancelación, Auth y cierre, typecheck y compilación. Detalles y límites en [OPERACION_BACKEND.md](OPERACION_BACKEND.md).

### 15. Regresión, CI y carga reproducible

- Base PostgreSQL temporal de loopback que aplica las migraciones reales sin leer `.env`; fixtures independientes por prueba. Incluye rollback, concurrencia, permisos, más de 1000 filas, recuperación y planes de consultas. Se corrigieron los controles fuera de vista/desbordamientos de la pantalla de seguridad y sus pruebas.
- CI preparado para backend en Windows/Linux y Flutter en Linux, con typecheck, pruebas, compilación y comprobación de documentación generada. Su ejecución en GitHub queda pendiente de publicar los cambios; no se presenta como una ejecución remota aprobada.
- Las funciones legacy ya no mantienen escritores privilegiados paralelos: `business-api` reenvía al backend y `send-push` solo encola. Se probaron sus handlers puros sin desplegarlos. Scripts E2E adaptados a claves de petición; los que requieren servicios externos no se ejecutaron en esta fase.
- k6 incluye recorridos con una cuenta distinta por usuario virtual, tiempos de interacción, etapas, umbrales y exclusión de salud/métricas de la carga de negocio. Ambos scripts pasan `k6 inspect`; no se ejecutó una nueva carga de Render.
- Validación final: **50 unitarias backend + 77 PostgreSQL + 175 Flutter = 302 pruebas aprobadas**, analyzer limpio, typecheck y build aprobados. Los conteos anteriores de este documento son cortes históricos por bloque. Evidencia y alcance en [VALIDACION_ESCALABILIDAD.md](VALIDACION_ESCALABILIDAD.md); publicación coordinada en [DESPLIEGUE_ESCALABILIDAD.md](DESPLIEGUE_ESCALABILIDAD.md).
