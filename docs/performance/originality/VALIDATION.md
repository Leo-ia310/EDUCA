# Validación local — 2026-10-23

Los tests PostgreSQL usan `embedded-postgres` en loopback y fixtures propias. No leen credenciales de producción. Los benchmarks deshabilitan `fetch` y solo procesan texto sintético. No se aplicaron migraciones remotas ni se desplegó.

| Comprobación | Resultado |
| --- | --- |
| Baseline backend | 72 unitarias y 88 integraciones aprobadas |
| Baseline Flutter analyzer | No issues found! |
| Build y typecheck backend final | Aprobados |
| Unitarias backend finales | 84/84 aprobadas (`originality-unit-confirmed.log`) |
| PostgreSQL del módulo y rollback | 11/11 aprobadas (`originality-database-confirmed.log`) |
| Compatibilidad de entrega, enlaces ajenos y borrador | 3/3 aprobadas (`originality-submit-compatibility.log`) |
| Flutter completo | 194/194 aprobadas con `flutter test --no-pub --concurrency=1` (`originality-frontend-recovered.log`) |
| Flutter analyzer final | No issues found! (`originality-analyzer-final.log`) |
| Extracción compilada en aislamiento | Editor, TXT, DOCX y PDF completados; PDF vacío insuficiente (`isolated-extractors.json`) |
| Dependencias de producción | Cero vulnerabilidades reportadas (`originality-audit-final.log`) |
| Presupuesto offline | 0,5 CPU / 512 MiB mediante Windows Job Object, salida 0 (`resource-limits.json`) |

Una regresión completa anterior registró **98/99**: todas las 88 integraciones preexistentes aprobaron. El único fallo estaba en una fixture nueva que asumía que una llamada de reconciliación recorría más de 50 entregas. Se corrigió el test para paginar hasta el final y se volvió a ejecutar todo el módulo y rollback: **11/11**. Antes del push solicitado a `main`, el 2026-10-23, se ejecutaron nuevamente `npm run build` y `npm test`: compilación y typecheck correctos, **84/84 unitarias y 99/99 integraciones en una sola ejecución completa** (integraciones: 440.231 ms), sin cancelaciones ni casos omitidos. `npm audit --omit=dev` reportó cero vulnerabilidades. Los logs históricos conservan el intento anterior y la repetición del módulo. No se omitieron casos ni se ampliaron sus timeouts.

Durante ejecuciones simultáneas con Flutter hubo timeouts en fixtures grandes. El perfil de limpieza de 10.000 alumnos encontró un escaneo de FK `students.person_id`; el índice de retención añadido permitió pasar sus dos casos con los límites originales. Se preservan comparación con 0057, perfil y repeticiones. Un intento de Flutter encontró un crash nativo del compilador Dart (`0xC0000005`); se conservó la caché de tests previa en `frontend/build/originality-test-cache-backup-20261023`, se reconstruyó y la suite serial pasó completa. No se cambió el SDK ni el APK existente.

El heap V8 observado en el extractor es 192.937.984 bytes (184 MiB): 160 MiB de old-space y presupuesto young-space. Se verificó expresamente porque el flag del proceso padre prevalece sobre un `resourceLimits` menor. El límite de heap no es un límite RSS; el hosting debe imponer el límite total de memoria del proceso, como hace el Job Object del benchmark.

El benchmark de cinco clases y 40 alumnos por clase usa 400 palabras por documento, incluye el alumno 39 coincidente con el 1, mide preselección y comparación y extrae además una muestra de 20.000 palabras. Son mediciones offline: **no son latencia HTTP, rendimiento físico de PostgreSQL/GIN ni validación de Render**. Los bytes JSON/gzip tampoco equivalen a espacio físico de PostgreSQL. Las salidas y límites exactos están en los JSON adyacentes.

Pendientes antes de producción: prueba end-to-end con Storage y HTTP en staging Render o entorno equivalente, PDFs/DOCX representativos, p95 antes/durante y tamaño físico TOAST/GIN; aprobación institucional de retención adicional, plantillas, acceso administrativo y cambios de algoritmo. `npm run check:schemas` requiere una cuenta administrativa y crea fixtures contra un backend; no se ejecutó contra una base real sin ese entorno de pruebas. Se añadieron sus casos nuevos y se validaron contratos HTTP locales y permisos SQL por separado.

Actualización operativa, 2026-10-23: con autorización del usuario se aplicó 0058 en EDUCA tras crear un respaldo lógico local, verificar su listado y leer todo el archivo; no se ensayó una restauración. Se comprobaron las cinco tablas con RLS, cinco triggers, permisos y métricas por HTTP. La prueba directa de Storage aprobó carga mediante token firmado, descarga íntegra con la función real `OriginalityRepository.sourceUrl` (60 segundos) y extracción aislada local de TXT, PDF y DOCX sintéticos (80 palabras cada uno). Acceso público, firma alterada y generación anónima de URL rechazados. Se eliminaron los tres objetos temporales y se verificó que no quedaban objetos en su prefijo. Evidencia: `storage-http-2026-10-23.json`. No se registraron archivos ni entregas académicas. Esto no valida el flujo Express autenticado por alumno/docente, la caducidad observada de la URL, documentos reales ni la ejecución del worker en Render; esos puntos siguen pendientes.

Verificación Flutter previa al mismo push: `flutter analyze --no-pub` terminó con **No issues found!**; `flutter test --no-pub --concurrency=1 test/originality_report_test.dart test/originality_card_test.dart` aprobó **4/4**. Esta repetición enfocada complementa la suite completa de 194 pruebas registrada arriba.

Comandos reproducibles principales:

```powershell
cd backend
npm run build
npm run typecheck
npm run test:unit
node --test --test-concurrency=1 test/originality.integration.test.mjs test/originality-rollback.integration.test.mjs
node --max-old-space-size=160 scripts/check-originality-extraction.cjs
node --max-old-space-size=160 scripts/benchmark-originality.cjs
./scripts/benchmark-originality-limited.ps1
npm audit --omit=dev
cd ../frontend
C:\src\flutter\bin\flutter.bat test --no-pub --concurrency=1
C:\src\flutter\bin\flutter.bat analyze --no-pub
```
