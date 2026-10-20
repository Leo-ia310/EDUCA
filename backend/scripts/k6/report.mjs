import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
const dir = process.argv[2] || 'backend/stress-results/2026-10-17';
const overview = JSON.parse(readFileSync(join(dir, 'overview.json'), 'utf8'));
const fmt = n => Number.isFinite(n) ? n.toFixed(2) : '—';
const pct = n => fmt(100 * n) + '%';
const lines = [
  '# Prueba de estrés de Nivra en Render — 17 de octubre de 2026', '',
  'Destino: https://nivra-backend-mcc4.onrender.com. Generador: k6 1.7.1, Windows, desde el equipo local. Zona horaria de los registros: America/Managua (UTC−06:00).', '',
  'Se probaron cuentas demo EDU360 y las cuatro cuentas facilitadas de BIGSCHOOL. Las claves y los tokens no se incluyen en los artefactos. Las peticiones de negocio atraviesan Render y sus dependencias reales; la carga no se ejecutó dentro de Render.', '',
  'El límite útil observado depende de la operación: en BIGSCHOOL el escalón de 5 solicitudes/s terminó sin errores, con p95 de 1,85 s; en el de 10 solicitudes/s el p95 subió a 12,53 s. No hay evidencia para afirmar que este despliegue soporte 10 solicitudes/s de esta mezcla con buena respuesta. Esto no se traduce directamente a una cantidad de personas conectadas.', '',
  'La comprobación sostenida posterior completó 601 peticiones durante 120 s a 5 solicitudes/s, sin errores ni 429. El p95 global fue 1,93 s y el p99, 2,62 s. La ruta de tareas de familia tuvo p95 de 3,29 s: cumplir el umbral global no significa que cada ruta cumpla individualmente.', '',
  'La prueba HTTP de `/health` completó 41.852 peticiones sin errores, pero alcanzó el tope configurado de 500 VUs y dejó 16.430 iteraciones sin iniciar. No se validaron 1000 solicitudes/s reales. Las escrituras completaron 90 actualizaciones de tareas a 2 solicitudes/s, sin errores, con p95 de 1,91 s; las ocho tareas temporales se archivaron y su ausencia del listado se verificó.', '',
  '| Cuenta BIGSCHOOL | Rol comprobado |', '|---|---|',
  '| Pablo | student |', '| Osmar | teacher |', '| Ernesto | director |', '| Maikel | parent |', '',
  '## Resultados', '',
  '| Perfil | Peticiones de carga completadas | Fallos | p50 ms | p95 ms | p99 ms | Iteraciones no iniciadas |',
  '|---|---:|---:|---:|---:|---:|---:|',
];
for (const file of ['reads.json', 'bigschool-reads.json', 'bigschool-soak.json', 'writes.json', 'login.json', 'health.json']) {
  const r = overview[file]; if (!r) continue;
  const labels = { 'reads.json': 'EDU360: subida de lecturas', 'bigschool-reads.json': 'BIGSCHOOL: subida de lecturas',
    'bigschool-soak.json': 'BIGSCHOOL: 5 solicitudes/s durante 120 s', 'writes.json': 'EDU360: tareas, 2 escrituras/s',
    'login.json': 'BIGSCHOOL: 1 login/s durante 30 s', 'health.json': 'HTTP /health: subida hasta objetivo 1000/s' };
  lines.push(`| ${labels[file]} | ${r.requests?.count ?? 0} | ${pct(r.failures?.rate)} | ${fmt(r.latency?.med)} | ${fmt(r.latency?.['p(95)'])} | ${fmt(r.latency?.['p(99)'])} | ${r.dropped?.count ?? 0} |`);
}
lines.push('', 'Los resúmenes de carga usan métricas personalizadas que excluyen el inventario y la autenticación inicial. `http_reqs` incluye esas solicitudes adicionales. Un timeout se cuenta como fallo HTTP 0. Las mesetas son cortas y no equivalen a una prueba prolongada de estabilidad.', '');
for (const file of ['reads.json', 'bigschool-reads.json', 'health.json']) {
  const r = overview[file]; if (!r) continue;
  lines.push(`## Escalones: ${file}`, '', '| Escalón | Respuestas completadas | Fallos | p95 ms | p99 ms |', '|---|---:|---:|---:|---:|');
  const order = ['ramp_5','hold_5','ramp_10','hold_10','ramp_20','hold_20','ramp_40','hold_40','warmup','50','100','200','500','1000','recovery'];
  for (const s of [...r.stages].sort((a,b) => order.indexOf(a.stage) - order.indexOf(b.stage))) {
    lines.push(`| ${s.stage} | ${s.requests} | ${pct(s.errors?.rate)} | ${fmt(s.latency?.['p(95)'])} | ${fmt(s.latency?.['p(99)'])} |`);
  }
  lines.push('', file === 'health.json'
    ? 'Los objetivos HTTP suben por 50, 100, 200, 500 y 1000 peticiones/s, con 20 s de meseta y transiciones intermedias. Salvo el grupo 50, cada etiqueta incluye la subida de 10 s anterior a su meseta. Revisar iteraciones no iniciadas: alcanzar el objetivo configurado no garantiza generar esa carga.'
    : 'Los escalones de negocio tienen objetivos de 5, 10, 20 y 40 solicitudes/s; cada meseta dura 30 s si no se activa el aborto. Los grupos se asignan al completar cada petición, por lo que una respuesta pendiente puede pasar al siguiente escalón. El objetivo configurado no es el rendimiento alcanzado.', '');
  if (r.slowest?.length) {
    lines.push('| Rutas con mayor p95 | p95 ms |', '|---|---:|');
    for (const e of r.slowest) lines.push(`| ${e.endpoint} | ${fmt(e['p(95)'])} |`);
    lines.push('');
  }
}
for (const file of ['reads.log', 'bigschool-reads.log', 'bigschool-soak.log', 'writes.log', 'login.log']) {
  const path = join(dir, file); if (!existsSync(path)) continue;
  const messages = readFileSync(path, 'utf8').split(/\r?\n/).flatMap(line => {
    const match = line.match(/msg=("(?:\\.|[^"\\])*") source=console/);
    if (!match) return []; try { return [JSON.parse(match[1])]; } catch { return []; }
  });
  const coverageLine = messages.find(x => x.startsWith('COVERAGE '));
  if (coverageLine) {
    const coverage = JSON.parse(coverageLine.slice(9));
    writeFileSync(join(dir, file.replace('.log', '-coverage.json')), JSON.stringify(coverage, null, 2));
    lines.push(`## Cobertura previa a la carga: ${file}`, '', '| Método | Ruta | Resultado |', '|---|---|---|');
    for (const e of coverage) lines.push(`| ${e.method || 'GET'} | ${e.path} | ${e.skipped || [e.status, e.error, e.message].filter(Boolean).join(' — ').replace(/\|/g, '/')} |`);
    lines.push('');
  }
  const cleanup = messages.filter(x => /^(FIXTURES |CLEANUP |CLEANUP_VERIFIED |RECOVERY )/.test(x));
  if (cleanup.length) lines.push(`### Fixtures y recuperación: ${file}`, '', '```text', ...cleanup, '```', '');
}
lines.push('## Interpretación y límites', '',
  '- El resultado de `/health` mide HTTP sin acceso a Supabase. No debe extrapolarse a usuarios, notas, tareas ni pagos.',
  '- Las pruebas de negocio usan cuatro cuentas y una mezcla equilibrada por rol, sin pausas entre iteraciones. VUs son trabajadores de carga, no personas reales conectadas.',
  '- Se conserva el rate limiting real. Un 429 señala cuotas, no demuestra saturación. Los timeouts de negocio con `/health` disponible sugieren revisar la ruta de datos y sus dependencias; sin telemetría de Render/Supabase no se puede atribuir el cuello de botella a CPU, RAM o base de datos.',
  '- Se aborta con más del 10% de fallos de servidor acumulados o más del 5% de respuestas 429 en negocio; `/health` aborta con más del 20% de fallos. Los umbrales de servicio usados son menos del 1% de errores y p95 menor de 2 s.',
  '- Las rutas que ya fallaron durante el inventario se excluyeron del tráfico repetido; los errores de validación iniciales no son fallos de capacidad. Las primeras ejecuciones del generador con cuerpo JSON null en GET se descartaron.',
  '- Escrituras de carga: actualización de ocho tareas borrador temporales en EDU360, con borrado lógico y comprobación posterior. No se ejecutaron escrituras masivas de notas, asistencia, pagos, chats, anuncios, 2FA ni archivos; tampoco se probó la generación masiva de boletines. Las rutas developer requieren una cuenta de ese rol. Por ello, esta ejecución no certifica todas las operaciones de la API.',
  '- Los logins iniciales de Pablo y Osmar sufrieron timeout durante la recuperación de la carga demo; ambos funcionaron al repetirlos tras recuperar el servicio. No fueron fallos de contraseña. La comprobación sostenida también encontró temporalmente un 429 por IP al preparar las sesiones; se respetó Retry-After antes de repetirla.',
  '', '## Trabajo recomendado según los hallazgos', '',
  '1. Corregir la correspondencia entre consultas y migraciones para `roles.updated_at`, `files.updated_at` y `change_log.changed_at`; los tres errores ocurrieron antes de aplicar carga.',
  '2. Repetir la zona de 5–10 solicitudes/s observando CPU, RAM y latencia de dependencias en Render/Supabase. Los datos de esta ejecución ubican la degradación, pero no identifican por sí solos el recurso agotado.',
  '3. Perfilar las rutas de tareas, familia, horarios y chat, junto con el coste de validar autenticación y permisos por petición. Priorizar las consultas repetidas y la cantidad de viajes a Supabase antes de aumentar indiscriminadamente los VUs.',
  '', '## Repetición', '',
  'Ver `backend/scripts/k6/README.md`. Los scripts admiten credenciales por entorno. No guardar claves en código ni habilitar HTTP debug. Ejecutar cada perfil por separado y dejar recuperar el servicio entre cargas.', '',
  'Referencia de metodología: [Grafana k6 — executors de llegada constante](https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/constant-arrival-rate/) y [umbrales](https://grafana.com/docs/k6/latest/using-k6/thresholds/).', '');
writeFileSync(join(dir, 'REPORTE.md'), lines.join('\n'));
console.log(join(dir, 'REPORTE.md'));
