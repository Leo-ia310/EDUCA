-- =============================================================================
-- Educa360 — Seed de datos operativos de demo
--
-- Vive fuera de `migrations/` a propósito: no es parte del versionado de
-- esquema, es data de ejemplo para poder probar el modo CONECTADO end-to-end
-- (asignaciones, notas, pagos, horario) contra la institución demo EDU360.
--
-- Requiere haber corrido antes: todas las migraciones + `seed_auth_users.sql`
-- (los 4 usuarios demo student@/teacher@/parent@/admin@educa360.com).
--
-- Idempotente: usa check-then-insert (o ON CONFLICT donde la tabla ya tiene
-- una unique constraint natural) en cada paso, así se puede re-ejecutar sin
-- duplicar filas.
-- =============================================================================

do $$
declare
  v_inst_id bigint;
  v_student_user_id bigint;
  v_teacher_user_id bigint;
  v_parent_user_id bigint;

  v_doc_type_id int;
  v_enrollment_status_act int;
  v_task_status_entr int;
  v_eval_type_exm int;
  v_eval_type_tar int;
  v_weekday_lun int;
  v_weekday_mar int;
  v_weekday_mie int;
  v_currency_nio int;
  v_education_level_primaria int;

  v_student_person_id bigint;
  v_teacher_person_id bigint;
  v_parent_person_id bigint;
  v_student_id bigint;
  v_teacher_id bigint;
  v_parent_id bigint;

  v_year_id bigint;
  v_period1_id bigint;
  v_period2_id bigint;
  v_period3_id bigint;
  v_level_id bigint;
  v_section_id bigint;
  v_classroom_id bigint;
  v_group_id bigint;

  v_subj_mat bigint;
  v_subj_hist bigint;
  v_subj_fis bigint;
  v_subj_bio bigint;
  v_subj_lit bigint;

  v_class_mat bigint;
  v_class_hist bigint;
  v_class_fis bigint;
  v_class_bio bigint;
  v_class_lit bigint;

  v_scale_id bigint;
  v_scale_is_new boolean := false;
  v_concept_matricula bigint;
  v_concept_mensualidad bigint;

  v_assignment1_id bigint;
  v_assignment2_id bigint;
  v_eval_mat_id bigint;
  v_eval_mat2_id bigint;
  v_eval_hist_id bigint;

  v_charge1_id bigint;
  v_charge2_id bigint;
  v_charge3_id bigint;
begin
  -- ---------------- Resolución de institución / usuarios / catálogos ----------------
  select id into v_inst_id from institutions where code = 'EDU360';
  if v_inst_id is null then
    raise exception 'Institución EDU360 no existe. Ejecuta las migraciones primero.';
  end if;

  select id into v_student_user_id from users where institution_id = v_inst_id and email = 'student@educa360.com';
  select id into v_teacher_user_id from users where institution_id = v_inst_id and email = 'teacher@educa360.com';
  select id into v_parent_user_id from users where institution_id = v_inst_id and email = 'parent@educa360.com';
  if v_student_user_id is null or v_teacher_user_id is null or v_parent_user_id is null then
    raise exception 'Faltan usuarios demo. Ejecuta supabase/seed_auth_users.sql primero.';
  end if;

  select id into v_doc_type_id from catalog_document_types where code = 'CED';
  select id into v_enrollment_status_act from catalog_enrollment_statuses where code = 'ACT';
  select id into v_task_status_entr from catalog_task_statuses where code = 'ENTR';
  select id into v_eval_type_exm from catalog_evaluation_types where code = 'EXM';
  select id into v_eval_type_tar from catalog_evaluation_types where code = 'TAR';
  select id into v_weekday_lun from catalog_weekdays where abbreviation = 'Lun';
  select id into v_weekday_mar from catalog_weekdays where abbreviation = 'Mar';
  select id into v_weekday_mie from catalog_weekdays where abbreviation = 'Mié';
  select id into v_currency_nio from catalog_currencies where iso_code = 'NIO';
  select id into v_education_level_primaria from catalog_education_levels where name = 'Primaria';

  -- ---------------- Personas / roles de dominio ----------------
  insert into persons (institution_id, document_type_id, document_number, first_name, last_name, birth_date)
  values (v_inst_id, v_doc_type_id, 'DEMO-STU-001', 'Julián', 'Vargas', date '2015-03-10')
  on conflict (institution_id, document_number) do update set first_name = excluded.first_name
  returning id into v_student_person_id;

  insert into persons (institution_id, document_type_id, document_number, first_name, last_name, birth_date)
  values (v_inst_id, v_doc_type_id, 'DEMO-TEA-001', 'Elena', 'Ramírez', date '1988-07-22')
  on conflict (institution_id, document_number) do update set first_name = excluded.first_name
  returning id into v_teacher_person_id;

  insert into persons (institution_id, document_type_id, document_number, first_name, last_name, birth_date)
  values (v_inst_id, v_doc_type_id, 'DEMO-PAR-001', 'Marta', 'Hernández', date '1985-11-05')
  on conflict (institution_id, document_number) do update set first_name = excluded.first_name
  returning id into v_parent_person_id;

  select id into v_student_id from students where person_id = v_student_person_id;
  if v_student_id is null then
    insert into students (person_id, institution_id, student_code, enrollment_date)
    values (v_student_person_id, v_inst_id, 'EST-2026-001', date '2026-02-01')
    returning id into v_student_id;
  end if;

  select id into v_teacher_id from teachers where person_id = v_teacher_person_id;
  if v_teacher_id is null then
    insert into teachers (person_id, institution_id, teacher_code, specialty, hired_at)
    values (v_teacher_person_id, v_inst_id, 'DOC-2026-001', 'Matemáticas', date '2020-01-15')
    returning id into v_teacher_id;
  end if;

  select id into v_parent_id from parents where person_id = v_parent_person_id;
  if v_parent_id is null then
    insert into parents (person_id, institution_id, is_emergency_contact)
    values (v_parent_person_id, v_inst_id, true)
    returning id into v_parent_id;
  end if;

  insert into parent_students (student_id, parent_id, is_main_responsible, can_pickup, lives_with)
  values (v_student_id, v_parent_id, true, true, true)
  on conflict (student_id, parent_id) do nothing;

  update users set person_id = v_student_person_id where id = v_student_user_id and person_id is null;
  update users set person_id = v_teacher_person_id where id = v_teacher_user_id and person_id is null;
  update users set person_id = v_parent_person_id where id = v_parent_user_id and person_id is null;

  -- ---------------- Estructura académica ----------------
  select id into v_year_id from academic_years where institution_id = v_inst_id and year = 2026;
  if v_year_id is null then
    insert into academic_years (institution_id, name, year, start_date, end_date, active, is_current)
    values (v_inst_id, 'Año Escolar 2026', 2026, date '2026-02-01', date '2026-11-30', true, true)
    returning id into v_year_id;
  end if;

  select id into v_period1_id from academic_periods where academic_year_id = v_year_id and name = 'I Trimestre';
  if v_period1_id is null then
    insert into academic_periods (institution_id, academic_year_id, name, display_order, start_date, end_date, weight)
    values (v_inst_id, v_year_id, 'I Trimestre', 1, date '2026-02-01', date '2026-04-30', 1)
    returning id into v_period1_id;
  end if;

  select id into v_period2_id from academic_periods where academic_year_id = v_year_id and name = 'II Trimestre';
  if v_period2_id is null then
    insert into academic_periods (institution_id, academic_year_id, name, display_order, start_date, end_date, weight)
    values (v_inst_id, v_year_id, 'II Trimestre', 2, date '2026-05-01', date '2026-08-15', 1)
    returning id into v_period2_id;
  end if;

  select id into v_period3_id from academic_periods where academic_year_id = v_year_id and name = 'III Trimestre';
  if v_period3_id is null then
    insert into academic_periods (institution_id, academic_year_id, name, display_order, start_date, end_date, weight)
    values (v_inst_id, v_year_id, 'III Trimestre', 3, date '2026-08-16', date '2026-11-30', 1)
    returning id into v_period3_id;
  end if;

  select id into v_level_id from grade_levels where institution_id = v_inst_id and name = '4to Grado';
  if v_level_id is null then
    insert into grade_levels (institution_id, education_level_id, name, display_order)
    values (v_inst_id, v_education_level_primaria, '4to Grado', 4)
    returning id into v_level_id;
  end if;

  select id into v_section_id from sections where institution_id = v_inst_id and name = 'A';
  if v_section_id is null then
    insert into sections (institution_id, name) values (v_inst_id, 'A') returning id into v_section_id;
  end if;

  select id into v_classroom_id from classrooms where institution_id = v_inst_id and name = 'Aula 402';
  if v_classroom_id is null then
    insert into classrooms (institution_id, name, capacity)
    values (v_inst_id, 'Aula 402', 30)
    returning id into v_classroom_id;
  end if;

  insert into groups (institution_id, academic_year_id, grade_level_id, section_id, classroom_id, guide_teacher_id, name, max_capacity, active)
  values (v_inst_id, v_year_id, v_level_id, v_section_id, v_classroom_id, v_teacher_id, '4to A', 30, true)
  on conflict (academic_year_id, grade_level_id, section_id)
    do update set guide_teacher_id = excluded.guide_teacher_id
  returning id into v_group_id;

  -- ---------------- Materias y clases ----------------
  select id into v_subj_mat from subjects where institution_id = v_inst_id and name = 'Matemáticas Avanzadas';
  if v_subj_mat is null then
    insert into subjects (institution_id, name, code, education_level_id, area)
    values (v_inst_id, 'Matemáticas Avanzadas', 'MAT', v_education_level_primaria, 'Ciencias exactas')
    returning id into v_subj_mat;
  end if;

  select id into v_subj_hist from subjects where institution_id = v_inst_id and name = 'Historia Universal';
  if v_subj_hist is null then
    insert into subjects (institution_id, name, code, education_level_id, area)
    values (v_inst_id, 'Historia Universal', 'HIST', v_education_level_primaria, 'Ciencias sociales')
    returning id into v_subj_hist;
  end if;

  select id into v_subj_fis from subjects where institution_id = v_inst_id and name = 'Física Cuántica';
  if v_subj_fis is null then
    insert into subjects (institution_id, name, code, education_level_id, area)
    values (v_inst_id, 'Física Cuántica', 'FIS', v_education_level_primaria, 'Ciencias exactas')
    returning id into v_subj_fis;
  end if;

  select id into v_subj_bio from subjects where institution_id = v_inst_id and name = 'Biología Celular';
  if v_subj_bio is null then
    insert into subjects (institution_id, name, code, education_level_id, area)
    values (v_inst_id, 'Biología Celular', 'BIO', v_education_level_primaria, 'Ciencias naturales')
    returning id into v_subj_bio;
  end if;

  select id into v_subj_lit from subjects where institution_id = v_inst_id and name = 'Literatura';
  if v_subj_lit is null then
    insert into subjects (institution_id, name, code, education_level_id, area)
    values (v_inst_id, 'Literatura', 'LIT', v_education_level_primaria, 'Humanidades')
    returning id into v_subj_lit;
  end if;

  insert into classes (institution_id, group_id, subject_id, teacher_id, academic_year_id, active)
  values (v_inst_id, v_group_id, v_subj_mat, v_teacher_id, v_year_id, true)
  on conflict (group_id, subject_id) do update set teacher_id = excluded.teacher_id
  returning id into v_class_mat;

  insert into classes (institution_id, group_id, subject_id, teacher_id, academic_year_id, active)
  values (v_inst_id, v_group_id, v_subj_hist, v_teacher_id, v_year_id, true)
  on conflict (group_id, subject_id) do update set teacher_id = excluded.teacher_id
  returning id into v_class_hist;

  insert into classes (institution_id, group_id, subject_id, teacher_id, academic_year_id, active)
  values (v_inst_id, v_group_id, v_subj_fis, v_teacher_id, v_year_id, true)
  on conflict (group_id, subject_id) do update set teacher_id = excluded.teacher_id
  returning id into v_class_fis;

  insert into classes (institution_id, group_id, subject_id, teacher_id, academic_year_id, active)
  values (v_inst_id, v_group_id, v_subj_bio, v_teacher_id, v_year_id, true)
  on conflict (group_id, subject_id) do update set teacher_id = excluded.teacher_id
  returning id into v_class_bio;

  insert into classes (institution_id, group_id, subject_id, teacher_id, academic_year_id, active)
  values (v_inst_id, v_group_id, v_subj_lit, v_teacher_id, v_year_id, true)
  on conflict (group_id, subject_id) do update set teacher_id = excluded.teacher_id
  returning id into v_class_lit;

  -- ---------------- Horario ----------------
  if not exists (select 1 from schedules where class_id = v_class_mat) then
    insert into schedules (institution_id, class_id, weekday_id, start_time, end_time, classroom_id)
    values (v_inst_id, v_class_mat, v_weekday_lun, time '08:00', time '09:30', v_classroom_id);
  end if;
  if not exists (select 1 from schedules where class_id = v_class_hist) then
    insert into schedules (institution_id, class_id, weekday_id, start_time, end_time, classroom_id)
    values (v_inst_id, v_class_hist, v_weekday_lun, time '09:45', time '11:15', v_classroom_id);
  end if;
  if not exists (select 1 from schedules where class_id = v_class_fis) then
    insert into schedules (institution_id, class_id, weekday_id, start_time, end_time, classroom_id)
    values (v_inst_id, v_class_fis, v_weekday_mar, time '08:00', time '09:30', v_classroom_id);
  end if;
  if not exists (select 1 from schedules where class_id = v_class_bio) then
    insert into schedules (institution_id, class_id, weekday_id, start_time, end_time, classroom_id)
    values (v_inst_id, v_class_bio, v_weekday_mar, time '09:45', time '11:15', v_classroom_id);
  end if;
  if not exists (select 1 from schedules where class_id = v_class_lit) then
    insert into schedules (institution_id, class_id, weekday_id, start_time, end_time, classroom_id)
    values (v_inst_id, v_class_lit, v_weekday_mie, time '08:00', time '09:30', v_classroom_id);
  end if;

  -- ---------------- Matrícula ----------------
  insert into enrollments (institution_id, student_id, group_id, academic_year_id, enrollment_status_id, enrolled_at)
  values (v_inst_id, v_student_id, v_group_id, v_year_id, v_enrollment_status_act, date '2026-02-01')
  on conflict (student_id, academic_year_id) do update set group_id = excluded.group_id;

  -- ---------------- Escala de calificación por defecto ----------------
  select id into v_scale_id from grading_scales where institution_id = v_inst_id and name = 'Numérica 0-100';
  if v_scale_id is null then
    insert into grading_scales (institution_id, name, scale_type, min_value, max_value, pass_value, decimals, active)
    values (v_inst_id, 'Numérica 0-100', 'numeric', 0, 100, 60, 1, true)
    returning id into v_scale_id;
    v_scale_is_new := true;
  end if;

  if v_scale_is_new then
    insert into grading_scale_ranges (scale_id, label, range_min, range_max, description, passed, color) values
      (v_scale_id, 'Excelente', 90, 100, 'Dominio excelente', true, '#22C55E'),
      (v_scale_id, 'Muy bueno', 80, 89.99, 'Dominio muy bueno', true, '#84CC16'),
      (v_scale_id, 'Bueno', 60, 79.99, 'Dominio satisfactorio', true, '#F59E0B'),
      (v_scale_id, 'Insuficiente', 0, 59.99, 'Necesita refuerzo', false, '#EF4444');
  end if;

  insert into institution_settings (institution_id, key, value, data_type)
  values (v_inst_id, 'default_grading_scale_id', v_scale_id::text, 'string')
  on conflict (institution_id, key) do update set value = excluded.value;

  -- ---------------- Evaluaciones y notas (I Trimestre) ----------------
  select id into v_eval_mat_id from evaluations
    where class_id = v_class_mat and academic_period_id = v_period1_id and title = 'Examen I Trimestre';
  if v_eval_mat_id is null then
    insert into evaluations (institution_id, class_id, academic_period_id, evaluation_type_id, title, max_score, weight, date, published, created_by)
    values (v_inst_id, v_class_mat, v_period1_id, v_eval_type_exm, 'Examen I Trimestre', 100, 60, date '2026-04-10', true, v_teacher_id)
    returning id into v_eval_mat_id;
  end if;
  insert into grades (institution_id, evaluation_id, student_id, score, recorded_by)
  values (v_inst_id, v_eval_mat_id, v_student_id, 88, v_teacher_user_id)
  on conflict (evaluation_id, student_id) do update set score = excluded.score;

  select id into v_eval_mat2_id from evaluations
    where class_id = v_class_mat and academic_period_id = v_period1_id and title = 'Tarea integradora';
  if v_eval_mat2_id is null then
    insert into evaluations (institution_id, class_id, academic_period_id, evaluation_type_id, title, max_score, weight, date, published, created_by)
    values (v_inst_id, v_class_mat, v_period1_id, v_eval_type_tar, 'Tarea integradora', 100, 40, date '2026-04-15', true, v_teacher_id)
    returning id into v_eval_mat2_id;
  end if;
  insert into grades (institution_id, evaluation_id, student_id, score, recorded_by)
  values (v_inst_id, v_eval_mat2_id, v_student_id, 95, v_teacher_user_id)
  on conflict (evaluation_id, student_id) do update set score = excluded.score;

  select id into v_eval_hist_id from evaluations
    where class_id = v_class_hist and academic_period_id = v_period1_id and title = 'Examen I Trimestre';
  if v_eval_hist_id is null then
    insert into evaluations (institution_id, class_id, academic_period_id, evaluation_type_id, title, max_score, weight, date, published, created_by)
    values (v_inst_id, v_class_hist, v_period1_id, v_eval_type_exm, 'Examen I Trimestre', 100, 100, date '2026-04-12', true, v_teacher_id)
    returning id into v_eval_hist_id;
  end if;
  insert into grades (institution_id, evaluation_id, student_id, score, recorded_by)
  values (v_inst_id, v_eval_hist_id, v_student_id, 76, v_teacher_user_id)
  on conflict (evaluation_id, student_id) do update set score = excluded.score;

  -- ---------------- Tareas y entregas ----------------
  select id into v_assignment1_id from assignments where class_id = v_class_mat and title = 'Práctica de Ecuaciones';
  if v_assignment1_id is null then
    insert into assignments (institution_id, class_id, title, description, assigned_at, due_at, max_score, allow_late, published, created_by)
    values (v_inst_id, v_class_mat, 'Práctica de Ecuaciones', 'Resolver la guía de ecuaciones cuadráticas.',
            now(), now() + interval '5 days', 100, false, true, v_teacher_id)
    returning id into v_assignment1_id;
  end if;

  select id into v_assignment2_id from assignments where class_id = v_class_mat and title = 'Guía de repaso';
  if v_assignment2_id is null then
    insert into assignments (institution_id, class_id, title, description, assigned_at, due_at, max_score, allow_late, published, created_by)
    values (v_inst_id, v_class_mat, 'Guía de repaso', 'Repaso general para el examen del trimestre.',
            now() - interval '10 days', now() - interval '3 days', 100, true, true, v_teacher_id)
    returning id into v_assignment2_id;
  end if;

  insert into submissions (institution_id, assignment_id, student_id, submitted_at, student_notes, task_status_id, is_late)
  values (v_inst_id, v_assignment2_id, v_student_id, now() - interval '4 days', 'Entrega completa.', v_task_status_entr, false)
  on conflict (assignment_id, student_id) do nothing;

  -- ---------------- Pagos ----------------
  select id into v_concept_matricula from payment_concepts where institution_id = v_inst_id and name = 'Matrícula 2026';
  if v_concept_matricula is null then
    insert into payment_concepts (institution_id, name, description, base_amount, currency_id, recurring, periodicity)
    values (v_inst_id, 'Matrícula 2026', 'Matrícula anual', 1500, v_currency_nio, false, 'one-time')
    returning id into v_concept_matricula;
  end if;

  select id into v_concept_mensualidad from payment_concepts where institution_id = v_inst_id and name = 'Mensualidad';
  if v_concept_mensualidad is null then
    insert into payment_concepts (institution_id, name, description, base_amount, currency_id, recurring, periodicity)
    values (v_inst_id, 'Mensualidad', 'Colegiatura mensual', 350, v_currency_nio, true, 'monthly')
    returning id into v_concept_mensualidad;
  end if;

  select id into v_charge1_id from charges where student_id = v_student_id and concept_id = v_concept_matricula and academic_year_id = v_year_id;
  if v_charge1_id is null then
    insert into charges (institution_id, student_id, concept_id, academic_year_id, description, amount, discount, late_fee, total_amount, due_at, status)
    values (v_inst_id, v_student_id, v_concept_matricula, v_year_id, 'Matrícula 2026', 1500, 0, 0, 1500, date '2026-02-01', 'paid')
    returning id into v_charge1_id;
  end if;

  if not exists (select 1 from payments where charge_id = v_charge1_id) then
    insert into payments (institution_id, charge_id, student_id, payment_method, amount, currency_id, receipt_number, status, paid_at, recorded_by)
    values (v_inst_id, v_charge1_id, v_student_id, 'transfer', 1500, v_currency_nio, 'RC-DEMO-0001', 'paid', date '2026-02-01', v_teacher_user_id);
  end if;

  select id into v_charge2_id from charges
    where student_id = v_student_id and concept_id = v_concept_mensualidad and description = 'Mensualidad agosto';
  if v_charge2_id is null then
    insert into charges (institution_id, student_id, concept_id, academic_year_id, description, amount, discount, late_fee, total_amount, due_at, status)
    values (v_inst_id, v_student_id, v_concept_mensualidad, v_year_id, 'Mensualidad agosto', 350, 0, 0, 350, date '2026-08-05', 'pending');
  end if;

  select id into v_charge3_id from charges
    where student_id = v_student_id and concept_id = v_concept_mensualidad and description = 'Mensualidad julio';
  if v_charge3_id is null then
    insert into charges (institution_id, student_id, concept_id, academic_year_id, description, amount, discount, late_fee, total_amount, due_at, status)
    values (v_inst_id, v_student_id, v_concept_mensualidad, v_year_id, 'Mensualidad julio', 350, 0, 35, 385, date '2026-07-05', 'overdue');
  end if;

  raise notice 'Seed operativo listo para institución % (student_id=%, teacher_id=%, parent_id=%)',
    v_inst_id, v_student_id, v_teacher_id, v_parent_id;
end$$;
