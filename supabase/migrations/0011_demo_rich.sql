-- =============================================================================
-- 0011_demo_rich.sql — Datos de demo ABUNDANTES para ver "flujo" real.
-- Puebla 4to A con ~20 estudiantes, asistencia (varios días), más tareas +
-- entregas + notas, y cargos de pago. Idempotente: no hace nada si el grupo 1
-- ya tiene 10+ matrículas.
-- =============================================================================
do $$
declare
  v_inst        bigint := 1;
  v_group       bigint := 1;
  v_year        bigint := 1;
  v_teacher     bigint := 1;   -- teachers.id (Elena)  → assignments/class_sessions.recorded_by
  v_teacher_usr bigint;        -- users.id (teacher@)  → attendances.recorded_by
  v_class1      bigint := 1;   -- Matemáticas
  v_names text[][] := array[
    array['Ana','Martínez'], array['Bruno','García'], array['Carla','López'],
    array['Diego','Rivas'], array['Sofía','Méndez'], array['Javier','Sosa'],
    array['Lucía','Flores'], array['Mateo','Cruz'], array['Valeria','Ortiz'],
    array['Emilio','Reyes'], array['Camila','Núñez'], array['Andrés','Peña'],
    array['Isabela','Vega'], array['Tomás','Ríos'], array['Renata','Gil'],
    array['Pablo','Mora'], array['Daniela','Cano'], array['Hugo','Salas'],
    array['Marina','Duarte']
  ];
  nm text[];
  v_person bigint; v_student bigint;
  v_students bigint[] := array[]::bigint[];
  v_all bigint[];
  s bigint; i int; d int;
  v_session bigint;
  v_eval bigint; v_score numeric;
  v_conc1 bigint; v_conc2 bigint;
begin
  if (select count(*) from enrollments where group_id = v_group) >= 10 then
    raise notice 'Ya hay datos ricos; nada que hacer.';
    return;
  end if;

  select id into v_teacher_usr from users where email = 'teacher@educa360.com';
  select id into v_conc1 from payment_concepts order by id limit 1;
  select id into v_conc2 from payment_concepts order by id desc limit 1;

  -- 1) Estudiantes + matrícula en 4to A
  foreach nm slice 1 in array v_names loop
    insert into persons (institution_id, first_name, last_name)
      values (v_inst, nm[1], nm[2]) returning id into v_person;
    insert into students (person_id, institution_id, student_code)
      values (v_person, v_inst, 'S' || lpad(v_person::text, 4, '0'))
      returning id into v_student;
    insert into enrollments (institution_id, student_id, group_id, academic_year_id, enrollment_status_id, enrolled_at)
      values (v_inst, v_student, v_group, v_year, 1, now() - interval '6 month');
    v_students := array_append(v_students, v_student);
  end loop;

  -- Conjunto completo (incluye a Julián = student 1)
  v_all := array_append(v_students, 1);

  -- 2) Asistencia: 8 sesiones de Matemáticas, ~88% presente
  for d in 1..8 loop
    insert into class_sessions (institution_id, class_id, group_id, date, start_time, topic, recorded_by, synced)
      values (v_inst, v_class1, v_group, (now() - (d || ' day')::interval)::date, '08:00', 'Clase de Matemáticas', v_teacher, true)
      returning id into v_session;
    foreach s in array v_all loop
      insert into attendances (institution_id, class_session_id, student_id, attendance_status_id, recorded_at, recorded_by, source)
        values (v_inst, v_session, s,
          case when (s + d) % 8 = 0 then 2 when (s + d) % 13 = 0 then 3 else 1 end, -- 2=AUS,3=TAR,1=PRE
          now() - (d || ' day')::interval, v_teacher_usr, 'demo');
    end loop;
  end loop;

  -- 3) Más tareas (varias clases, fechas variadas), publicadas
  insert into assignments (institution_id, class_id, academic_period_id, title, description, assigned_at, due_at, max_score, allow_late, published, created_by)
  values
    (v_inst, 1, 1, 'Taller de Álgebra', 'Ejercicios 1-20', now()-interval '5 day', now()+interval '3 day', 100, true, true, v_teacher),
    (v_inst, 2, 1, 'Ensayo: Revolución Industrial', 'Mínimo 2 páginas', now()-interval '4 day', now()+interval '5 day', 100, false, true, v_teacher),
    (v_inst, 3, 1, 'Laboratorio de Óptica', 'Reporte de práctica', now()-interval '2 day', now()+interval '1 day', 100, true, true, v_teacher),
    (v_inst, 4, 1, 'Mapa conceptual: La Célula', 'Entrega digital', now()-interval '6 day', now()-interval '1 day', 100, false, true, v_teacher),
    (v_inst, 5, 1, 'Análisis de "El Quijote"', 'Capítulos I-V', now()-interval '3 day', now()+interval '7 day', 100, true, true, v_teacher);

  -- 4) Entregas para "Taller de Álgebra" y "Práctica de Ecuaciones": ~70% entrega
  declare
    v_assign bigint;
  begin
    for v_assign in (select id from assignments where class_id = 1 and deleted_at is null) loop
      i := 0;
      foreach s in array v_all loop
        i := i + 1;
        if i % 3 <> 0 then  -- ~66% entrega
          insert into submissions (institution_id, assignment_id, student_id, submitted_at, task_status_id, is_late)
          values (v_inst, v_assign, s, now() - interval '1 day',
                  case when i % 5 = 0 then 3 else 2 end, false)  -- 3=CALI (algunas), 2=ENTR
          on conflict (assignment_id, student_id) do nothing;
        end if;
      end loop;
    end loop;
  end;

  -- 5) Notas para evaluaciones existentes (1,2,3): todos los estudiantes, scores variados
  for v_eval in (select id from evaluations) loop
    foreach s in array v_all loop
      v_score := 60 + ((s * 7 + v_eval * 13) % 40);  -- 60..99
      insert into grades (institution_id, evaluation_id, student_id, score)
        values (v_inst, v_eval, s, v_score)
        on conflict (evaluation_id, student_id) do nothing;
    end loop;
  end loop;

  -- 6) Cargos de pago: matrícula (pagada) + mensualidad (mezcla) por estudiante
  foreach s in array v_all loop
    insert into charges (institution_id, student_id, concept_id, academic_year_id, description, amount, discount, late_fee, total_amount, due_at, status)
    values
      (v_inst, s, v_conc1, v_year, 'Matrícula 2026', 1500, 0, 0, 1500, now()-interval '30 day', 'paid'),
      (v_inst, s, v_conc2, v_year, 'Mensualidad Agosto', 1200, 0,
        case when s % 4 = 0 then 120 else 0 end, case when s % 4 = 0 then 1320 else 1200 end,
        now() - interval '2 day',
        case when s % 3 = 0 then 'paid' when s % 4 = 0 then 'overdue' else 'pending' end);
  end loop;

  raise notice 'Datos ricos sembrados: % estudiantes nuevos.', array_length(v_students, 1);
end $$;
