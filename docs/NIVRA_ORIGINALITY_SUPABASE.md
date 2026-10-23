# Nivra Originality en Supabase

Destino elegido por el usuario el 2026-10-23. **Procesamiento activo en EDUCA mediante Supabase Edge, Vault y Cron cada diez segundos.** Las migraciones 0058 y 0059 están aplicadas y `ORIGINALITY_EDGE_ENABLED=true`. La cola procesa también las entregas anteriores elegibles. El backend de Render y el panel docente conservan su función; no hace falta contratar un Background Worker en Render.

## Diseño y límites

`supabase/functions/nivra-originality/` ejecuta una fase por petición: extracción (PDF de una página), preparación, comparación de hasta tres candidatas o publicación final. Entre peticiones guarda un checkpoint privado en PostgreSQL. Al ceder el trabajo libera el lease, pero conserva el avance y no consume otro intento. Una muerte del proceso sí consume intentos; tres agotados terminan en fallo recuperable. Se conservan los límites de 5 MiB, 50 páginas y 20.000 palabras, sin truncar para fabricar un porcentaje.

La migración `0059_nivra_originality_edge.sql` añade dos tablas con RLS y RPCs exclusivas de `service_role`; no instala extensiones ni programa tareas. Los avances con texto se eliminan al retirar una versión, borrar su origen o terminar/fallar definitivamente su trabajo. No se guarda ninguna URL firmada en checkpoints. El reporte público existente solo ve resultados finales; una pausa no publica una coincidencia máxima parcial.

La lógica de normalización, DOCX/TXT y comparación se genera desde el código Node con `npm --prefix backend run build:originality-edge`. `--check` y CI detectan diferencias; no se mantienen dos algoritmos editados por separado. PDF utiliza `unpdf@1.9.1`, cuya distribución serverless de PDF.js 6.4.299 incorpora el parser sin threads ni canvas. Los PDF sintéticos sin fuentes incrustadas generan advertencias sobre `standardFontDataUrl`; las pruebas verifican texto seleccionable, pero no representan todas las fuentes/CMaps, idiomas o archivos escolares reales. No hay OCR.

Supabase documenta **2 segundos de CPU por petición y 256 MB de memoria**; el tiempo de espera de red no equivale a CPU. El código por fases reduce el trabajo, pero no garantiza que cualquier PDF/DOCX permitido quepa en ese presupuesto. Un documento que supere el límite hosted puede morir sin ejecutar `catch`; el lease caduca y finalmente queda fallido, sin porcentaje parcial. `EdgeRuntime.waitUntil` no amplía esos límites. Fuentes: [límites](https://supabase.com/docs/guides/functions/limits), [tareas en background](https://supabase.com/docs/guides/functions/background-tasks), [unpdf](https://github.com/unjs/unpdf).

## Resultado local

- Compilación y typecheck Node correctos; 84 unitarias aprobadas tras compartir el extractor.
- 18 integraciones PostgreSQL aprobadas: siete del nuevo protocolo, diez del módulo y rollback 0058. Incluyen leases, más de tres pausas sin agotar intentos, recuperación tras caídas, RLS, borrado de avances y publicación/rollback atómicos.
- Pruebas Deno con red denegada: autenticación, TXT/DOCX, PDF vacío y multipágina, alteración de bytes entre páginas, tamaño declarado/real y recorrido completo de candidatas.
- Endpoint HTTP loopback: anónimo rechazado, tick autenticado aceptado y selección arbitraria de documento rechazada.
- `docs/performance/originality/supabase-edge-local.json`: en Deno 2.6.8/Windows las fases medidas usaron 31–438 ms de CPU; máximo RSS **muestreado**, no pico, 176.840.704 bytes. DOCX/preparación/comparación usaron 20.000 palabras; PDF, una página de 80 palabras. No son mediciones del hosting ni latencias HTTP/SQL reales.

Desde la raíz del repositorio:

```powershell
npm --prefix backend run build
npm --prefix backend run typecheck
node backend/scripts/build-originality-edge.cjs --check
deno check --frozen --config supabase/functions/nivra-originality/deno.json supabase/functions/nivra-originality/index.ts
deno test --frozen --config supabase/functions/nivra-originality/deno.json --allow-read --allow-env=NODE_ENV --deny-net supabase/functions/nivra-originality/test/edge_test.ts
deno test --frozen --config supabase/functions/nivra-originality/deno.json --allow-read --allow-env=NODE_ENV --allow-net=127.0.0.1 supabase/functions/nivra-originality/test/http_test.ts
```

## Validación alojada, 2026-10-23

Tras autenticar Supabase CLI con una cuenta con acceso a EDUCA, el usuario autorizó publicar solo la validación. Se configuraron únicamente `ORIGINALITY_CRON_SECRET` y `ORIGINALITY_EDGE_ENABLED=false`, y se desplegó `nivra-originality` sin Docker mediante `--use-api`. El secreto aleatorio quedó fuera del repositorio, en una carpeta con acceso restringido al usuario y SYSTEM.

Las diez peticiones de prueba (dos rondas de TXT, DOCX, PDF, preparación y comparación) devolvieron HTTP 200, `status=validated` y `mode=validate`. TXT/DOCX/preparación/comparación comprobaron 20.000 palabras; PDF, una página de 80 palabras. Los tiempos internos transcurridos fueron 8–92 ms: **no son mediciones de CPU ni de memoria máxima**. Sin secreto y con secreto incorrecto devolvió 401; seleccionar un documento por cuerpo devolvió 400. Se comprobó función ACTIVE v1, ausencia de 0059 y de `cron.job`, y cola sin trabajos ni errores.

Evidencia: [supabase-edge-hosted-validation-2026-10-23.json](performance/originality/supabase-edge-hosted-validation-2026-10-23.json). Esta validación no prueba archivos arbitrarios de 5 MiB/50 páginas, fuentes e idiomas representativos ni carga real. La publicación no equivale a activar el análisis de entregas.

## Publicación y activación por etapas

Los pasos 1–6 ya se completaron para EDUCA con autorización del usuario; se conservan como procedimiento reproducible. No repetir las migraciones ni regenerar el secreto en esta instalación activa.

1. Respaldar el estado actual de EDUCA y aplicar **solo 0059**, dentro de una transacción con timeout de bloqueo y verificación de permisos. No volver a ejecutar 0058. **Completado el 2026-10-23 a las 14:18, America/Managua:** respaldo lógico nuevo con checksum/listado/lectura completa verificados (sin ensayo de restauración), aplicación atómica con timeout de bloqueo de 5 segundos y de sentencia de 60 segundos, dos tablas privadas con RLS, seis funciones restringidas a `service_role` y dos triggers activos. La comprobación HTTP posterior confirmó acceso de servicio y rechazo anónimo a tabla/RPC con código `42501`; solo se invocó la RPC de lectura `originality_edge_live(-1)`, no claim ni reconciliación. Se verificó remotamente el flag de procesamiento deshabilitado, cero checkpoints y ausencia de `cron.job`. Evidencia: [production-migration-0059-2026-10-23.json](performance/originality/production-migration-0059-2026-10-23.json).
2. Generar un secreto aleatorio nuevo y guardar sus valores fuera del repositorio. La función recibe automáticamente `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`; no necesita copiar contraseñas de PostgreSQL, claves de correo ni secretos de otros proveedores. Un secreto ausente/corto devuelve 503.
3. Desplegar la función en **modo validación**, que es el valor predeterminado cuando `ORIGINALITY_EDGE_ENABLED` no es exactamente `true`. Este modo solo procesa fixtures sintéticas fijas: no reconcilia, no reclama trabajos y no lee archivos de alumnos. La prueba automática falla si toca cualquiera de esas dependencias.

Ejemplo PowerShell para preparar secretos locales (no imprime su contenido):

```powershell
$edgeSecretsFile = Join-Path $env:USERPROFILE '.codex\.tmp\nivra-originality-edge.env'
$edgeCronSecret = node -e "process.stdout.write(require('node:crypto').randomBytes(32).toString('hex'))"
@("ORIGINALITY_CRON_SECRET=$edgeCronSecret", 'ORIGINALITY_EDGE_ENABLED=false') | Set-Content -LiteralPath $edgeSecretsFile -Encoding ascii
# Sustituir PROJECT_REF por la referencia del proyecto EDUCA comprobada.
supabase secrets set --project-ref PROJECT_REF --env-file $edgeSecretsFile
supabase functions deploy nivra-originality --project-ref PROJECT_REF --use-api --no-verify-jwt
```

El gateway JWT está desactivado únicamente para este endpoint; su handler exige `x-originality-secret` antes de ejecutar trabajo y no acepta IDs, URLs ni institución en el cuerpo. `--use-api` permite empaquetar sin iniciar Docker. No ejecutar despliegues contra un proyecto deducido solo del nombre.

4. Con la función todavía en validación, invocar cada fixture en una petición independiente y comprobar 200, `status=validated`, número de palabras y ausencia de errores de recursos. No pegar el secreto en el chat:

```powershell
$edgeFunctionUrl = 'https://PROJECT_REF.supabase.co/functions/v1/nivra-originality'
foreach ($edgeProbe in @('txt','docx','pdf','prepare','compare')) {
  Invoke-RestMethod -Method Post -Uri "${edgeFunctionUrl}?probe=$edgeProbe" -Headers @{ 'x-originality-secret' = $edgeCronSecret } -ContentType 'application/json' -Body '{}'
}
```

También comprobar que una petición sin secreto devuelve 401. Consultar métricas/logs de Supabase para errores 546, CPU/memoria y fallos de importación. Estas fixtures no sustituyen una validación de documentos representativos y carga real; no activar el consumo de entregas si la prueba alojada falla.

5. Solo tras aprobar la ejecución alojada y la activación sobre entregas reales, configurar Vault mediante el script con parámetros SQL (no incorpora el secreto en archivos SQL ni argumentos de procesos):

```powershell
node backend/scripts/provision-originality-edge-vault.mjs --secrets-file $edgeSecretsFile
# La llamada anterior solo muestra el plan local.
node backend/scripts/provision-originality-edge-vault.mjs --secrets-file $edgeSecretsFile --apply
```

El script crea/actualiza `nivra_originality_url` y `nivra_originality_cron_secret`; rechaza rotar un secreto mientras el Cron de Nivra esté activo. No activa Cron. Requiere las credenciales PostgreSQL existentes de `backend/.env` y la extensión Vault de Supabase.

6. Habilitar `pg_cron` y `pg_net` si faltan, revisar las cuotas disponibles y confirmar que no hay consumidor Node activo. Cambiar explícitamente `ORIGINALITY_EDGE_ENABLED=true` en el entorno de la función y ejecutar el SQL revisado `supabase/deploy/nivra-originality-edge-enable.sql`. Este paso sí activa procesamiento y reconciliación de entregas históricas elegibles.

Cron revisa la cola cada diez segundos. Reconcilia páginas de 50 entregas con cursor persistente y solo envía HTTP cuando hay trabajo elegible y ningún lease activo. Una cola vacía no gasta invocaciones Edge. Hay 259.200 ticks SQL por 30 días; las invocaciones dependen de páginas, comparaciones y trabajo real. La cola global es serial: un lote grande o PDF largo puede tardar muchos ticks. **No se promete coste cero ni capacidad de producción** sin comprobar cuotas y medir carga del proyecto. Referencia: [Supabase Cron](https://supabase.com/docs/guides/cron).

## Detención y rollback

Ejecutar `supabase/deploy/nivra-originality-edge-stop.sql`, deshabilitar el procesamiento de la función y esperar el drenaje o vencimiento del lease de 120 segundos. Después se puede aplicar `supabase/rollback/0059_nivra_originality_edge.sql`; conserva 0058, entregas y archivos originales. No arrancar Node hasta que Edge esté detenido. La versión actual del rollback 0058 también elimina los checkpoints si posteriormente se revierte todo el módulo.

## Activación operativa verificada

El 2026-10-23, a las 14:43 America/Managua, se verificaron Vault, el flag de procesamiento activo y el job `nivra-originality` con frecuencia de diez segundos. Cron registraba 27 ejecuciones correctas y 27 respuestas HTTP 200; seis trabajos habían terminado como `insufficient_text`, sin trabajos fallidos. Quedaban 86 trabajos pendientes, incluido uno en procesamiento: el llenado histórico continúa de forma asíncrona. `insufficient_text` no significa similitud cero.

Evidencia: [supabase-edge-activation-2026-10-23.json](performance/originality/supabase-edge-activation-2026-10-23.json). Esta comprobación valida programación, invocaciones, checkpoints y finalización real; no mide memoria máxima ni garantiza capacidad para cualquier PDF permitido. El flujo completo del panel con usuarios autenticados no se validó de nuevo en esta activación.
