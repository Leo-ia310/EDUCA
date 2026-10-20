# Directorio vacío por compilación web anterior — 19 de octubre de 2026

La web local se estaba sirviendo desde `frontend/build/web`, con `main.dart.js` compilado el 17 de octubre a las 08:45:57. El servidor estático no compila automáticamente los cambios de Dart. La compilación anterior consumía el directorio completo, mientras que la API nueva separa catálogos paginados, páginas de personas y contadores. Interpretaba la respuesta parcial como ausencia de alumnos/padres.

La API actual devuelve para Big School 16 alumnos y 15 padres visibles. Los totales físicos incluyen datos archivados y son distintos de los totales visibles; no se deben mostrar esos totales físicos en las tarjetas.

## Verificación de conservación de datos

Se restauró otra copia aislada del backup y se comparó SHA256 del contenido JSON de cada fila, ordenando los hashes y fijando la zona UTC en ambos servidores. No se imprimieron datos personales. Resultado:

| Tabla | Filas backup | Filas actuales | Contenido de todas las filas idéntico |
| --- | --- | --- | --- |
| students | 180 | 180 | Sí |
| parents | 63 | 63 | Sí |
| persons | 316 | 316 | Sí |
| parent_students | 69 | 69 | Sí |
| enrollments | 149 | 149 | Sí |

Las lecturas no modificaron el origen. La comprobación local se detuvo al terminar y la evidencia permanece en la carpeta protegida del backup, bajo `.data-integrity-check/data-comparison.json`.

## Corrección local

Recompilar Flutter web con los defines del backend local (`DEMO=false`, URL de Supabase y `http://localhost:3001/api`) y comprobar que el servidor 8080 entregue el JavaScript nuevo. No vaciar Hive, SharedPreferences ni datos del navegador como solución: podrían contener trabajo offline. Recargar la página con Ctrl+F5 para sustituir el cliente anterior.

## Resultado

La compilación release terminó correctamente (194 segundos de compilación). `main.dart.js` se actualizó el 19 de octubre a las 21:44:39, hora de Nicaragua. El servidor 8080 responde 200, sirve exactamente el SHA256 del archivo recién compilado y entrega `Cache-Control: no-cache`. Se comprobó que incluye las consultas nuevas de contadores y páginas de personas. No se modificaron datos de alumnos/padres para corregir la pantalla.
