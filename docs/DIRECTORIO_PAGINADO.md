# Lecturas administrativas por páginas

Aplicar `0036_admin_people_page.sql` y `0037_scoped_directory_reads.sql` antes del backend/frontend que las consume. Estas migraciones están verificadas localmente; no se han aplicado a producción.

- `/admin/students`, `/admin/teachers` y `/admin/parents`: página de 50 registros (máximo 100), búsqueda en servidor, `id` opcional para cargar un perfil concreto. Las relaciones del curso actual se hidratan solo para la página: `group_id/group_name`, `class_ids/classes`, `child_ids/children`.
- `/admin/directory/people`: resumen de personas para roles, salones y boletines; acepta `role=all|student|teacher|parent`, `groupId`, `id`, `search`, `page`, `pageSize`. Excluye documentos y datos médicos. El filtro de salón usa matrícula ACT del año actual.
- `/admin/directory/options`: selectores con búsqueda y páginas. `kind=students|teachers|parents|groups|classes`. `includeIds` (máximo 100) hidrata etiquetas seleccionadas aparte de los resultados; cambiar de búsqueda/página no reemplaza ni elimina la selección del formulario.
- `/admin/directory`: ahora es un catálogo paginado, `kind=classes|groups` (classes por defecto). Incluye las clases/salones de esa página y sus maestros relacionados; no descarga todas las personas. Los salones incluyen contadores completos de alumnos y clases. `groupId` permite abrir un salón aunque no tenga clases. Los consumidores del antiguo directorio completo deben usar los endpoints de personas/catálogos apropiados.
- `/admin/directory/counts`: conteos SQL para el home y la vista de roles, con `dashboard.view` o `roles.view`. No se calculan contando la primera página ni se muestran cifras demo mientras carga una cuenta real.
- `/admin/profiles`: filtra perfiles administrativos antes de paginar y devuelve `{ profiles, pageInfo }`. Acepta `search`, `page`, `pageSize`; evita perder administradores situados después de los primeros 1000 usuarios.

`pageInfo` incluye `page`, `pageSize`, `total`, `totalPages`, `hasNextPage`, `hasPreviousPage`. El orden es estable por nombre e ID (y rol cuando se mezclan tipos). Cada página tiene su propia lectura; no se presenta como un snapshot transaccional que abarque toda la navegación.

Los formularios consultan sus opciones al usarlas y cargan los vínculos actuales del perfil antes de editar. No recargan el directorio completo después de guardar. Clases, salones, alumnos del salón, roles, perfiles administrativos y acceso a boletines navegan por páginas. El listado/filtrado de horarios se trata en su propio bloque.

Contactos del chat: `/chats/contacts?q=&limit=` busca nombre, correo y rol antes de limitar (40 por defecto, máximo 100), incluida la etiqueta española del rol. El cliente aplica debounce. El dashboard docente usa `teacher_dashboard_classes`, limitado a asignaciones/colaboraciones del año actual, sin descargar opciones de maestros ni invitaciones del workspace de administración. Las notas recientes se consultan por clase con JOIN, sin descargar IDs de todas las evaluaciones; el contador de tareas del alumno usa el agregado completo, independiente de las cinco tarjetas visibles.

Boletines emitidos: `/reports/report-cards` devuelve el más reciente por alumno/periodo mediante SQL antes de paginar. Devuelve `{ reportCards, pageInfo }` y conserva filtros de alumno, periodo y salón. Padres/alumnos solo consultan su alcance y no reciben promedios de periodos ocultos. Un `academicPeriodId` nulo representa un boletín anual.
