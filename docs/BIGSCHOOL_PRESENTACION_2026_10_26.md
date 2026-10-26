# Big School: datos de presentación

La información se guardó en Supabase, institución `BIGSCHOOL`, año actual 2026.
Es contenido académico ficticio para la presentación, solicitado por el usuario.
No se añadieron datos mock ni constantes de presentación en Flutter.

## Carga aplicada

Se reutilizaron las cuentas, docentes, materias, grupos, matrículas y vínculos
familiares existentes. Se completaron los campos profesionales vacíos de docentes
y padres vinculados al alcance. No se cambiaron contraseñas, contactos personales,
matrículas, horarios ni notas anteriores.

| Registro | Agregados | Total de Big School después |
| --- | ---: | ---: |
| Escalas de calificación | 1 | 1 |
| Rangos de escala | 4 | 4 |
| Tareas y actividades | 182 | 195 |
| Evaluaciones publicadas | 156 | 169 |
| Entregas | 644 | 694 |
| Notas individuales | 624 | 673 |
| Resúmenes por materia y trimestre | 108 | 157 |
| Sesiones de clase | 178 | 187 |
| Registros de asistencia | 774 | 807 |
| Eventos de calendario | 3 | 6 |

La carga cubre 13 estudiantes matriculados, con notas en todas sus materias y en
los tres trimestres. Usa las 13 clases existentes del alcance; Física conserva su
grupo sin alumnos matriculados y tiene actividades publicadas. Hay 26 actividades
próximas y 20 entregas pendientes de calificar. Los registros de asistencia nuevos
respetan los días y horas de los horarios existentes.

## Recorrido de presentación

- **Osmar, profesor:** clases, tareas, entregas, libro de notas por trimestre y
  asistencia. Matemáticas de segundo grado tiene cinco estudiantes.
- **Pablo, estudiante:** cuatro materias de segundo grado, notas en los tres
  trimestres, boletín, tareas pendientes y entregas.
- **Maikel, padre:** conserva sus cuatro vínculos con Mateo, Camila, Diego y Emma;
  puede consultar sus notas, tareas y asistencia. No se vinculó artificialmente
  a Pablo.
- **Ernesto, director:** escala, trimestres y consulta del libro de notas.

Las claves se suministran por variables de entorno para las comprobaciones;
no se guardan en los scripts ni en este documento.

## Ejecución y comprobaciones

Desde la raíz del proyecto:

```powershell
# Valida dentro de una transacción y revierte al terminar.
node backend/scripts/bigschool-presentation.mjs

# Guarda la carga. Ejecutar únicamente cuando se quiera poblar este colegio.
node backend/scripts/bigschool-presentation.mjs --apply

# Sesiones reales: requiere BIGSCHOOL_PASSWORD y BIGSCHOOL_DIRECTOR_PASSWORD.
node backend/scripts/bigschool-verify.mjs
```

El SQL está en `supabase/demo/bigschool-presentation.sql`, separado de las
migraciones de esquema para evitar poblar automáticamente otros entornos.
Los UUID estables y las restricciones únicas impiden duplicados. Una segunda
validación después de aplicar la carga agregó cero registros en todas las tablas.
La comprobación transaccional confirmó cero materias/trimestres sin notas dentro
del alcance. Las inserciones quedaron registradas como `DEMO_SEED` en `audit_log`.

## Ajuste de lectura de asistencia

Al verificar el boletín de Pablo se reprodujo un timeout en Supabase. La consulta
de asistencia tardaba aproximadamente 7,6 segundos: repetía el alcance familiar
para cada sesión de clase. Actualizar las estadísticas no corrigió el problema.

La migración `0060_batched_attendance_portal_scope.sql` extiende a asistencia y
sesiones el cálculo por consulta que ya usa la migración 0054. Conserva las demás
políticas, RLS, permisos de módulo, institución y docente. No modifica datos.

La validación comparó el JSON completo del boletín y el hash de los registros de
asistencia de las cuatro cuentas antes y después. Los resultados fueron idénticos
y se mantuvo el aislamiento de familias e instituciones. La comprobación combinada
del boletín y la lectura de asistencia de Pablo pasó de 16,9 s a 0,85 s; son tiempos
de esa prueba, no una garantía de latencia. Se conservó el SQL de reversión en
`supabase/demo/rollback-0060.sql`.

```powershell
# Prueba transaccional con reversión; --apply confirma el ajuste.
node backend/scripts/bigschool-attendance-scope.mjs
```

El manifiesto API se actualizó y `npm.cmd run docs:apis` regeneró la documentación.
No se agregaron endpoints.

La comprobación final contra la API desplegada y Supabase pasó para Osmar, Pablo,
Maikel y Ernesto. Pablo leyó 49 notas y Maikel 52 notas de su primer hijo; ambas
sesiones vieron los tres trimestres, tareas y el contexto del boletín con
asistencia. La consulta del boletín de Pablo ya respondió sin timeout. Osmar y
Ernesto abrieron el libro de segundo grado con cinco estudiantes y cuatro
evaluaciones nuevas del tercer trimestre.

## Ramas

`main` se avanzó por fast-forward a `cc08ae8`. Todas las ramas locales y remotas
estaban contenidas en ese commit; no hubo conflictos. El APK modificado que ya
existía en el equipo se conservó y se incluye junto con los scripts en la entrega
a `main` solicitada por el usuario.
