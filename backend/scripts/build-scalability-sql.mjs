import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';

// Offline packaging only: never connects to a database or reads credentials.
const root = new URL('../../', import.meta.url);
const migrations = new URL('supabase/migrations/', root);
const names = (await readdir(migrations)).filter(name => /^00(?:2[9]|[34][0-9]|5[0-3])_.*\.sql$/.test(name)).sort();
if (names.length !== 25) throw new Error(`Expected 25 migrations; found ${names.length}.`);
const preflight = await readFile(new URL('backend/scripts/schedules-preflight.sql', root), 'utf8');
const first = preflight.indexOf('with source as (');
const second = preflight.indexOf('\nwith normalized as (');
if (first < 0 || second < first) throw new Error('Unknown schedule preflight format.');
const checks = [preflight.slice(first, second), preflight.slice(second)].map(sql => sql.trim().replace(/;$/, ''));
const parts = [`-- NIVRA: actualización completa 0029–0053. Generado; no editar manualmente.
-- Ejecutar en Supabase SQL Editor como postgres, DESPUÉS de backup recuperable
-- y de detener escritores/workers antiguos. Actualizar backend, Edge y clientes.
-- Requiere esquema anterior compatible con 0028. No activa 2FA a ningún usuario.
-- No modifica ni elimina horarios existentes para eludir conflictos.
-- Una sola transacción: cualquier error revierte TODAS las migraciones.
-- Si falla, ejecutar ROLLBACK antes de reutilizar la misma conexión.
-- Repetir este archivo después de una aplicación completa se rechaza expresamente.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SELECT pg_advisory_xact_lock(hashtextextended('nivra/scalability-0029-0053', 0));

DO $baseline$
BEGIN
  IF to_regprocedure('public.backend_readiness_v1()') IS NOT NULL THEN
    RAISE EXCEPTION 'El marcador de esta actualización ya existe. Revisar el historial antes de repetir el script.';
  END IF;
  IF to_regprocedure('public.auth_2fa_session_allowed()') IS NULL THEN
    RAISE EXCEPTION 'Falta el esquema base 0028. No aplicar este paquete sobre una base incompleta.';
  END IF;
END
$baseline$;

-- Mantener estable el conjunto de horarios entre la revisión y las exclusiones.
LOCK TABLE public.schedules IN SHARE ROW EXCLUSIVE MODE;
DO $preflight$
DECLARE issues jsonb := '[]'::jsonb; found_issues jsonb;
BEGIN
${checks.map(sql => `  SELECT coalesce(jsonb_agg(to_jsonb(check_row)), '[]'::jsonb)
    INTO found_issues FROM (${sql}) check_row;
  issues := issues || found_issues;`).join('\n')}
  IF jsonb_array_length(issues) > 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23P01',
      MESSAGE = 'Actualización detenida: corregir los horarios incompatibles antes de migrar.',
      DETAIL = issues::text,
      HINT = 'No se aplicó ninguna migración. Revisar IDs y motivos; no borrar ni desplazar clases automáticamente.';
  END IF;
END
$preflight$;
`];
for (const name of names) {
  const source = await readFile(new URL(name, migrations), 'utf8');
  const sha256 = createHash('sha256').update(source).digest('hex');
  parts.push(`\n-- BEGIN ${name}\n-- SHA256 ${sha256}\n${source.trim()}\n-- END ${name}\n`);
}
parts.push(`
DO $verify$
BEGIN
  IF (public.backend_readiness_v1()->>'schemaVersion')::integer IS DISTINCT FROM 53 THEN
    RAISE EXCEPTION 'La verificación final del contrato SQL falló.';
  END IF;
END
$verify$;
NOTIFY pgrst, 'reload schema';
COMMIT;
SELECT 53 AS schema_version, 'Actualización SQL completada. Verificar /ready y clientes compatibles.' AS resultado;
`);
const withScheduleProposal = process.argv.includes('--with-schedule-proposal');
let content = parts.join('\n');
if (withScheduleProposal) {
  const plan = await readFile(new URL('supabase/deploy/plans/bigschool-horarios-propuesta.sql', root), 'utf8');
  const marker = '-- Mantener estable el conjunto de horarios entre la revisión y las exclusiones.';
  if (!plan.includes('horario_aprobado boolean := false') || content.split(marker).length !== 2) {
    throw new Error('Unknown schedule proposal or insertion point.');
  }
  content = content.replace(marker, `${plan}\n${marker}`).replace(
    '-- No modifica ni elimina horarios existentes para eludir conflictos.',
    '-- Contiene una propuesta de 9 franjas, bloqueada por defecto; requiere aprobación expresa.\n-- La única edición manual permitida es confirmar horario_aprobado tras revisar la propuesta.',
  );
}
const output = new URL(`supabase/deploy/${withScheduleProposal ? 'scalability-con-propuesta-horarios' : 'scalability-0029-0053'}.sql`, root);
await mkdir(new URL('.', output), { recursive: true });
await writeFile(output, content, 'utf8');
console.log(`Generated ${output.pathname}: ${names.length} migrations, one transaction.`);
