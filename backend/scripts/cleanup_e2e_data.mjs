// =============================================================================
// cleanup_e2e_data.mjs - borra los datos que dejan las pruebas e2e del panel web.
//
// Las pruebas (repo NivraAdminWeb, carpeta e2e/) crean salones, clases y alumnos temporales cuyo nombre
// empieza por «E2E ». Las APIs de administración solo los ARCHIVAN y no pueden borrar lo que cuelga de
// ellos (asistencia, tareas, entregas, notas, cargos, horarios, boletines, archivos); este script lo hace.
//
// Uso (desde backend/):   node scripts/cleanup_e2e_data.mjs [prefijo]      (prefijo por defecto: "E2E ")
// Solo toca clases cuyo salón se llama «<prefijo>…»; no borra usuarios (quedan archivados).
// =============================================================================
import { createClient } from '@supabase/supabase-js';
import pg from 'pg';
import { loadEnv, pgConfig } from './env.mjs';

const prefix = process.argv[2] ?? 'E2E ';
if (prefix.trim().length < 3) {
  console.error('El prefijo es demasiado corto: podría borrar datos reales.');
  process.exit(1);
}
const env = loadEnv();
const db = new pg.Client(pgConfig(env));
const storage = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
await db.connect();

const rows = async (sql, params = []) => (await db.query(sql, params)).rows;
const ids = (list) => list.map((r) => Number(r.id));
const out = {};
const del = async (label, sql, params) => { out[label] = (await db.query(sql, params)).rowCount; };

try {
  await db.query('begin');
  const groups = ids(await rows("select id from groups where name like $1", [`${prefix}%`]));
  if (groups.length === 0) {
    await db.query('rollback');
    console.log(`No hay salones «${prefix}…»: nada que limpiar.`);
  } else {
    const classes = ids(await rows('select id from classes where group_id = any($1)', [groups]));
    const students = ids(await rows('select distinct student_id as id from enrollments where group_id = any($1)', [groups]));
    const assignments = ids(await rows('select id from assignments where class_id = any($1)', [classes]));
    const submissions = ids(await rows('select id from submissions where assignment_id = any($1)', [assignments]));
    const evaluations = ids(await rows('select id from evaluations where class_id = any($1) or assignment_id = any($2)', [classes, assignments]));
    const sessions = ids(await rows('select id from class_sessions where class_id = any($1)', [classes]));
    const cards = ids(await rows('select id from report_cards where student_id = any($1)', [students]));
    const charges = ids(await rows('select id from charges where student_id = any($1)', [students]));

    // Archivos adjuntos de esas tareas y entregas, y los que subieron los usuarios de prueba aunque ya no
    // estén enlazados (fila y objeto de almacenamiento). Los correos de prueba empiezan por «<prefijo>.».
    const files = await rows(
      `select distinct f.id, f.storage_path from files f
        where f.id in (select file_id from assignment_files where assignment_id = any($1))
           or f.id in (select file_id from submission_files where submission_id = any($2))
           or f.uploaded_by in (select id from users where lower(email) like $3)`,
      [assignments, submissions, `${prefix.trim().toLowerCase()}.%`],
    );
    const fileIds = files.map((f) => Number(f.id));

    await del('submission_files', 'delete from submission_files where submission_id = any($1) or file_id = any($2)', [submissions, fileIds]);
    await del('assignment_files', 'delete from assignment_files where assignment_id = any($1) or file_id = any($2)', [assignments, fileIds]);
    await del('grades', 'delete from grades where evaluation_id = any($1)', [evaluations]);
    await del('evaluations', 'delete from evaluations where id = any($1)', [evaluations]);
    await del('submissions', 'delete from submissions where id = any($1)', [submissions]);
    await del('assignments', 'delete from assignments where id = any($1)', [assignments]);
    await del('attendances', 'delete from attendances where class_session_id = any($1)', [sessions]);
    await del('class_sessions', 'delete from class_sessions where id = any($1)', [sessions]);
    await del('report_card_lines', 'delete from report_card_lines where report_card_id = any($1)', [cards]);
    await del('report_cards', 'delete from report_cards where id = any($1)', [cards]);
    await del('payments', 'delete from payments where charge_id = any($1)', [charges]);
    await del('charges', 'delete from charges where id = any($1)', [charges]);
    await del('schedules', 'delete from schedules where class_id = any($1)', [classes]);
    await del('files', 'delete from files where id = any($1)', [fileIds]);
    await db.query('commit');

    if (files.length) {
      const removed = await storage.storage.from('files').remove(files.map((f) => f.storage_path));
      out.objetos_borrados = removed.data?.length ?? 0;
    }
    console.log(`Limpieza «${prefix}…» (${groups.length} salones, ${classes.length} clases, ${students.length} alumnos):`, JSON.stringify(out));
  }
} catch (e) {
  await db.query('rollback').catch(() => {});
  console.error('Falló la limpieza:', e.message);
  process.exitCode = 1;
} finally {
  await db.end();
}
