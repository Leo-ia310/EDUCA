// =============================================================================
// business_api_e2e.mjs - E2E del backend Node contra Supabase real.
//
// Arranca backend/dist/server.js en un puerto temporal, inicia sesion con los
// 4 usuarios demo y ejecuta acciones business-api por rol. Las escrituras usan
// un marcador E2E y se limpian por DB al terminar.
//
// Uso:
//   cd backend
//   npm run build
//   cd scripts
//   node business_api_e2e.mjs
// =============================================================================
import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import pg from 'pg';
import { loadEnv, pgConfig, BACKEND_DIR } from './env.mjs';

const env = loadEnv();
const SUPABASE_URL = env.SUPABASE_URL;
const ANON = env.SUPABASE_ANON_KEY;
const PORT = Number(process.env.E2E_BACKEND_PORT || 3377);
const API_BASE = `http://127.0.0.1:${PORT}`;
const BUSINESS_API = `${API_BASE}/api/business-api`;
const MARK = `E2E-${Date.now()}`;

if (!SUPABASE_URL || !ANON) {
  console.error('Faltan SUPABASE_URL/SUPABASE_ANON_KEY en backend/.env');
  process.exit(1);
}

let pass = 0;
let fail = 0;
const cleanupJobs = [];

function check(name, ok, detail = '') {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` (${detail})` : ''}`);
  ok ? pass++ : fail++;
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, options);
  let body = null;
  try {
    body = await response.json();
  } catch {
    body = null;
  }
  return { response, body };
}

async function waitForHealth(child) {
  for (let i = 0; i < 40; i++) {
    if (child.exitCode != null) {
      throw new Error(`El backend termino antes de responder /health (code=${child.exitCode}).`);
    }
    try {
      const { response, body } = await fetchJson(`${API_BASE}/health`);
      if (response.ok && body?.ok === true) return;
    } catch {
      // Esperar al siguiente intento.
    }
    await sleep(250);
  }
  throw new Error('El backend no respondio /health a tiempo.');
}

async function startBackend() {
  const child = spawn(process.execPath, ['dist/server.js'], {
    cwd: BACKEND_DIR,
    env: {
      ...process.env,
      ...env,
      PORT: String(PORT),
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.on('data', (chunk) => process.stdout.write(`[backend] ${chunk}`));
  child.stderr.on('data', (chunk) => process.stderr.write(`[backend] ${chunk}`));
  await waitForHealth(child);
  return child;
}

async function login(email) {
  const { response, body } = await fetchJson(
    `${SUPABASE_URL}/auth/v1/token?grant_type=password`,
    {
      method: 'POST',
      headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'demo1234' }),
    },
  );
  if (!response.ok || !body?.access_token) {
    throw new Error(`No se pudo iniciar sesion con ${email}`);
  }
  return body.access_token;
}

async function callBusiness(token, action, payload = {}) {
  return fetchJson(BUSINESS_API, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      apikey: ANON,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ action, payload }),
  });
}

async function expectOk(name, token, action, payload, validate = () => true) {
  const { response, body } = await callBusiness(token, action, payload);
  const ok = response.ok && body?.ok === true && validate(body.data);
  check(name, ok, ok ? '' : `${response.status} ${JSON.stringify(body)}`);
  return ok ? body.data : null;
}

async function expectError(name, token, action, payload, expectedStatus) {
  const { response, body } = await callBusiness(token, action, payload);
  const ok = response.status === expectedStatus && body?.ok === false;
  check(name, ok, ok ? body.error?.code : `${response.status} ${JSON.stringify(body)}`);
  return ok ? body : null;
}

async function queryOne(client, sql, params = []) {
  const { rows } = await client.query(sql, params);
  if (rows.length === 0) throw new Error(`Sin datos para query: ${sql}`);
  return rows[0];
}

async function queryMaybe(client, sql, params = []) {
  const { rows } = await client.query(sql, params);
  return rows[0] ?? null;
}

async function cleanup(client) {
  for (const job of cleanupJobs.reverse()) {
    try {
      await job(client);
    } catch (error) {
      console.error(`Cleanup fallo: ${error.message}`);
    }
  }
}

async function main() {
  const backend = await startBackend();
  const client = new pg.Client(pgConfig(env));
  await client.connect();

  try {
    const tokens = {
      teacher: await login('teacher@educa360.com'),
      student: await login('student@educa360.com'),
      parent: await login('parent@educa360.com'),
      admin: await login('admin@educa360.com'),
    };
    check('login usuarios demo', true);

    const teacher = await queryOne(client, `
      select u.id as user_id, t.id as teacher_id
      from users u
      join teachers t on t.person_id = u.person_id
      where u.email = 'teacher@educa360.com'
      limit 1
    `);
    const student = await queryOne(client, `
      select u.id as user_id, s.id as student_id
      from users u
      join students s on s.person_id = u.person_id
      where u.email = 'student@educa360.com'
      limit 1
    `);
    const parent = await queryOne(client, `
      select u.id as user_id, p.id as parent_id
      from users u
      join parents p on p.person_id = u.person_id
      where u.email = 'parent@educa360.com'
      limit 1
    `);
    const cls = await queryOne(client, `
      select c.id, c.group_id
      from classes c
      join enrollments e on e.group_id = c.group_id
      where c.teacher_id = $1
        and e.student_id = $2
        and c.active = true
      order by c.id
      limit 1
    `, [teacher.teacher_id, student.student_id]);
    const attendanceStatus = await queryOne(
      client,
      `select id from catalog_attendance_statuses order by id limit 1`,
    );
    const evaluation = await queryOne(client, `
      select e.id
      from evaluations e
      where e.class_id = $1
      order by e.id
      limit 1
    `, [cls.id]);
    const paymentCharge = await queryOne(client, `
      select c.id, c.status
      from charges c
      join parent_students ps on ps.student_id = c.student_id
      where ps.parent_id = $1
        and c.status not in ('paid', 'cancelled')
      order by c.id
      limit 1
    `, [parent.parent_id]);
    const paymentConcept = await queryOne(
      client,
      `select id from payment_concepts where institution_id = 1 order by id limit 1`,
    );
    const academicYear = await queryOne(
      client,
      `select id from academic_years where institution_id = 1 order by id limit 1`,
    );

    const classList = await expectOk(
      'teacher assignments.teacherClasses',
      tokens.teacher,
      'assignments.teacherClasses',
      {},
      (data) => Array.isArray(data) && data.length > 0,
    );

    const assignmentTitle = `${MARK} assignment`;
    const assignment = await expectOk(
      'teacher assignments.upsert',
      tokens.teacher,
      'assignments.upsert',
      {
        classId: Number(cls.id),
        title: assignmentTitle,
        description: 'Created by automated E2E',
        instructions: 'Submit normally',
        dueAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
        maxScore: 100,
        allowLate: true,
        published: true,
        attachments: [],
      },
      (data) => data?.assignment?.id != null,
    );
    const assignmentId = Number(assignment?.assignment?.id);
    cleanupJobs.push(async (db) => {
      const ids = (await db.query(
        `select id from assignments where title like $1`,
        [`${MARK}%`],
      )).rows.map((row) => row.id);
      if (ids.length === 0) return;
      const evalIds = (await db.query(
        `select id from evaluations where assignment_id = any($1::bigint[])`,
        [ids],
      )).rows.map((row) => row.id);
      const submissionIds = (await db.query(
        `select id from submissions where assignment_id = any($1::bigint[])`,
        [ids],
      )).rows.map((row) => row.id);
      if (evalIds.length > 0) {
        await db.query(`delete from grades where evaluation_id = any($1::bigint[])`, [evalIds]);
        await db.query(`delete from evaluations where id = any($1::bigint[])`, [evalIds]);
      }
      if (submissionIds.length > 0) {
        await db.query(`delete from submission_files where submission_id = any($1::bigint[])`, [submissionIds]);
        await db.query(`delete from submissions where id = any($1::bigint[])`, [submissionIds]);
      }
      await db.query(`delete from assignment_files where assignment_id = any($1::bigint[])`, [ids]);
      await db.query(`delete from assignments where id = any($1::bigint[])`, [ids]);
    });

    if (assignmentId) {
      await expectOk(
        'teacher assignments.publish false',
        tokens.teacher,
        'assignments.publish',
        { id: assignmentId, published: false },
      );
      await expectOk(
        'teacher assignments.publish true',
        tokens.teacher,
        'assignments.publish',
        { id: assignmentId, published: true },
      );
      const submission = await expectOk(
        'student assignments.submit',
        tokens.student,
        'assignments.submit',
        {
          assignmentId,
          studentId: Number(student.student_id),
          attachments: [],
          notes: `${MARK} submission`,
        },
        (data) => data?.submission?.id != null,
      );
      const submissionId = Number(submission?.submission?.id);
      if (submissionId) {
        await expectOk(
          'teacher assignments.gradeSubmission',
          tokens.teacher,
          'assignments.gradeSubmission',
          { submissionId, score: 95, feedback: `${MARK} feedback` },
          (data) => data?.submission?.status === 'graded',
        );
      }
      await expectOk(
        'teacher assignments.delete',
        tokens.teacher,
        'assignments.delete',
        { id: assignmentId },
      );
    }

    const sessionDate = new Date(Date.UTC(2099, 0, 2));
    const attendanceUuid = randomUUID();
    const classSession = await expectOk(
      'teacher attendance.upsertClassSession',
      tokens.teacher,
      'attendance.upsertClassSession',
      { classId: Number(cls.id), dateMs: sessionDate.getTime() },
      (data) => Number(data?.id) > 0,
    );
    cleanupJobs.push(async (db) => {
      await db.query(`delete from attendances where uuid = $1`, [attendanceUuid]);
      await db.query(
        `delete from class_sessions where class_id = $1 and date = $2 and recorded_by = $3`,
        [cls.id, '2099-01-02', teacher.teacher_id],
      );
    });
    await expectOk(
      'teacher attendance.upsertAttendance',
      tokens.teacher,
      'attendance.upsertAttendance',
      {
        uuid: attendanceUuid,
        classId: Number(cls.id),
        classSessionId: Number(classSession?.id),
        studentId: Number(student.student_id),
        statusId: Number(attendanceStatus.id),
        recordedAtMs: sessionDate.getTime(),
        notes: MARK,
      },
      (data) => Number(data?.id) > 0,
    );

    const eventTitle = `${MARK} event`;
    await expectOk(
      'teacher events.create',
      tokens.teacher,
      'events.create',
      {
        title: eventTitle,
        description: 'Evento de prueba E2E',
        date: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString(),
        audience: 'all',
      },
      (data) => data?.event?.id != null,
    );
    cleanupJobs.push((db) =>
      db.query(`delete from calendar_events where title = $1`, [eventTitle]),
    );

    const scaleName = `${MARK} scale`;
    const previousDefaultScale = await queryMaybe(
      client,
      `select value from institution_settings where institution_id = 1 and key = 'default_grading_scale_id'`,
    );
    const scale = await expectOk(
      'admin grades.upsertScale',
      tokens.admin,
      'grades.upsertScale',
      {
        name: scaleName,
        type: 'numeric',
        minValue: 0,
        maxValue: 100,
        passValue: 60,
        decimals: 0,
        ranges: [
          { label: 'OK', rangeMin: 60, rangeMax: 100, passed: true, color: '#22c55e' },
          { label: 'NO', rangeMin: 0, rangeMax: 59, passed: false, color: '#ef4444' },
        ],
      },
      (data) => data?.scale?.id != null,
    );
    const scaleId = Number(scale?.scale?.id);
    cleanupJobs.push(async (db) => {
      if (previousDefaultScale?.value) {
        await db.query(
          `update institution_settings set value = $1 where institution_id = 1 and key = 'default_grading_scale_id'`,
          [previousDefaultScale.value],
        );
      }
      await db.query(
        `delete from grading_scales where name = $1 and institution_id = 1`,
        [scaleName],
      );
    });
    if (scaleId) {
      await expectOk(
        'admin grades.setDefaultScale',
        tokens.admin,
        'grades.setDefaultScale',
        { id: scaleId },
      );
    }

    const existingGrade = await queryMaybe(client, `
      select id, score, notes, recorded_by, updated_at
      from grades
      where evaluation_id = $1 and student_id = $2
      limit 1
    `, [evaluation.id, student.student_id]);
    cleanupJobs.push(async (db) => {
      if (existingGrade) {
        await db.query(
          `update grades
             set score = $1, notes = $2, recorded_by = $3, updated_at = $4
           where id = $5`,
          [
            existingGrade.score,
            existingGrade.notes,
            existingGrade.recorded_by,
            existingGrade.updated_at,
            existingGrade.id,
          ],
        );
      } else {
        await db.query(
          `delete from grades where evaluation_id = $1 and student_id = $2`,
          [evaluation.id, student.student_id],
        );
      }
    });
    await expectOk(
      'teacher grades.setGrade',
      tokens.teacher,
      'grades.setGrade',
      {
        evaluationId: Number(evaluation.id),
        studentId: Number(student.student_id),
        rawScore: 88,
        notes: MARK,
      },
    );

    const chat = await expectOk(
      'teacher chat.ensureIndividual',
      tokens.teacher,
      'chat.ensureIndividual',
      { otherUserId: Number(student.user_id) },
      (data) => data?.conversationId != null,
    );
    const conversationId = Number(chat?.conversationId);
    const messageContent = `${MARK} chat message`;
    await expectOk(
      'teacher chat.sendMessage',
      tokens.teacher,
      'chat.sendMessage',
      { conversationId, content: messageContent },
      (data) => data?.message?.id != null,
    );
    await expectOk(
      'student chat.markAsRead',
      tokens.student,
      'chat.markAsRead',
      { conversationId },
    );
    cleanupJobs.push((db) =>
      db.query(`delete from messages where content = $1`, [messageContent]),
    );

    const endpoint = `https://e2e.local/${MARK}`;
    await expectOk(
      'student notifications.saveWebPushDevice',
      tokens.student,
      'notifications.saveWebPushDevice',
      {
        endpoint,
        pushToken: JSON.stringify({ endpoint, keys: { p256dh: 'x', auth: 'y' } }),
      },
    );
    cleanupJobs.push((db) =>
      db.query(`delete from devices where device_uuid = $1`, [endpoint]),
    );

    const paymentReference = `${MARK} payment`;
    const originalChargeStatus = paymentCharge.status;
    await expectOk(
      'parent payments.register',
      tokens.parent,
      'payments.register',
      {
        chargeId: Number(paymentCharge.id),
        amount: 0.01,
        method: 'cash',
        payerName: 'E2E Parent',
        reference: paymentReference,
        gatewayName: 'E2E',
      },
      (data) => data?.payment?.id != null,
    );
    cleanupJobs.push(async (db) => {
      await db.query(`delete from payments where reference = $1`, [paymentReference]);
      await db.query(`update charges set status = $1 where id = $2`, [
        originalChargeStatus,
        paymentCharge.id,
      ]);
    });

    const tempCharge = await queryOne(client, `
      insert into charges (
        institution_id, student_id, concept_id, academic_year_id, description,
        amount, discount, late_fee, total_amount, due_at, status
      )
      values (1, $1, $2, $3, $4, 1, 0, 0, 1, current_date, 'pending')
      returning id
    `, [student.student_id, paymentConcept.id, academicYear.id, `${MARK} temp charge`]);
    cleanupJobs.push((db) =>
      db.query(`delete from charges where description = $1`, [`${MARK} temp charge`]),
    );
    await expectOk(
      'admin payments.cancelCharge',
      tokens.admin,
      'payments.cancelCharge',
      { chargeId: Number(tempCharge.id) },
    );

    await expectError(
      'student cannot use teacher action',
      tokens.student,
      'assignments.teacherClasses',
      {},
      403,
    );
    await expectError(
      'parent cannot cancel charge',
      tokens.parent,
      'payments.cancelCharge',
      { chargeId: Number(paymentCharge.id) },
      403,
    );
    check('teacherClasses returned current class', classList?.some?.((c) => Number(c.classId) === Number(cls.id)));
  } finally {
    await cleanup(client);
    await client.end();
    backend.kill();
  }

  console.log(`\n${pass} PASS - ${fail} FAIL\n`);
  process.exit(fail ? 1 : 0);
}

main().catch((error) => {
  console.error(`FATAL: ${error.message}`);
  process.exit(1);
});
