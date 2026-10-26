-- Datos ficticios de presentación solicitados para BIGSCHOOL (2026).
-- No cambia contraseñas, matrículas, horarios ni registros académicos existentes.
-- Ejecutar mediante backend/scripts/bigschool-presentation.mjs (transacción).
-- UUIDs estables y claves naturales permiten repetir sin duplicar registros.
select pg_advisory_xact_lock(hashtextextended('bigschool-presentation-v1',0));

create temporary table bs_context on commit drop as
select i.id institution_id,y.id year_id from institutions i
join academic_years y on y.institution_id=i.id and y.is_current and y.active
where i.code='BIGSCHOOL' and y.year=2026;
do $$ begin
  if (select count(*) from bs_context)<>1 then raise exception 'Se requiere un único año actual 2026 de BIGSCHOOL.'; end if;
  if not exists(select 1 from users u join bs_context b on b.institution_id=u.institution_id
    where lower(u.email)='osmar@bigschool.edu' and u.active and u.deleted_at is null)
    then raise exception 'Cuenta de Osmar no disponible.'; end if;
end $$;

create temporary table bs_classes on commit drop as
select c.*,s.name subject_name,u.id teacher_user_id
from classes c join bs_context b on b.institution_id=c.institution_id and b.year_id=c.academic_year_id
join subjects s on s.id=c.subject_id join groups g on g.id=c.group_id
join teachers t on t.id=c.teacher_id and t.active
join users u on u.person_id=t.person_id and u.institution_id=c.institution_id and u.active and u.deleted_at is null
where c.active and g.active and g.name in ('1er Grado A','2do Grado A','3er Grado A','Pabellon 400');

create temporary table bs_roster on commit drop as
select distinct e.student_id,e.group_id,e.academic_year_id,e.institution_id
from enrollments e join bs_context b on b.institution_id=e.institution_id and b.year_id=e.academic_year_id
join students s on s.id=e.student_id and s.active join persons p on p.id=s.person_id and p.deleted_at is null
join catalog_enrollment_statuses es on es.id=e.enrollment_status_id and es.code='ACT'
where exists(select 1 from bs_classes c where c.group_id=e.group_id);
do $$ begin
  if (select count(*) from bs_classes)<>13 or (select count(*) from bs_roster)<>13 then
    raise exception 'El alcance esperado cambió: revisar clases y matrículas antes de cargar.';
  end if;
end $$;

insert into grading_scales(institution_id,name,scale_type,min_value,max_value,pass_value,decimals)
select institution_id,'Escala numérica 0–100','numeric',0,100,60,1 from bs_context b
where not exists(select 1 from grading_scales s where s.institution_id=b.institution_id and s.active);
insert into grading_scale_ranges(scale_id,label,range_min,range_max,description,passed,color)
select s.id,v.label,v.lo,v.hi,v.description,v.passed,v.color
from grading_scales s join bs_context b on b.institution_id=s.institution_id
cross join (values
 ('Aprendizaje inicial',0,59.99,'Requiere acompañamiento y práctica adicional.',false,'#EF4444'),
 ('Aprendizaje elemental',60,75.99,'Alcanza los conocimientos esenciales.',true,'#F59E0B'),
 ('Aprendizaje satisfactorio',76,89.99,'Aplica los contenidos con autonomía.',true,'#3B82F6'),
 ('Aprendizaje avanzado',90,100,'Demuestra dominio y propone soluciones.',true,'#22C55E')
) v(label,lo,hi,description,passed,color)
where s.name='Escala numérica 0–100' and not exists(select 1 from grading_scale_ranges r where r.scale_id=s.id);
insert into institution_settings(institution_id,key,value,data_type)
select b.institution_id,'default_grading_scale_id',min(s.id)::text,'string'
from bs_context b join grading_scales s on s.institution_id=b.institution_id and s.active
group by b.institution_id on conflict(institution_id,key) do nothing;

-- Completar únicamente campos profesionales vacíos de los perfiles existentes.
update teachers t set
 specialty=coalesce(nullif(t.specialty,''),case when lower(u.email)='osmar@bigschool.edu' then 'Matemáticas y Física' else
 (select string_agg(distinct c.subject_name, ', ') from bs_classes c where c.teacher_id=t.id) end),
 academic_title=coalesce(nullif(t.academic_title,''),'Licenciatura en Ciencias de la Educación')
from users u,bs_context b where t.person_id=u.person_id and t.institution_id=b.institution_id
and exists(select 1 from bs_classes c where c.teacher_id=t.id);
update parents p set occupation=coalesce(nullif(p.occupation,''),'Profesional independiente'),
 workplace=coalesce(nullif(p.workplace,''),'Actividad independiente — perfil de presentación')
from bs_context b where p.institution_id=b.institution_id
and exists(select 1 from parent_students ps join bs_roster r on r.student_id=ps.student_id where ps.parent_id=p.id);

create temporary table bs_plan on commit drop as
select c.id class_id,c.institution_id,c.teacher_id,c.teacher_user_id,c.subject_name,
 p.id period_id,p.display_order term,n.slot,
 md5('bigschool-presentation-v1/task/'||c.id||'/'||p.id||'/'||n.slot)::uuid task_uuid,
 md5('bigschool-presentation-v1/evaluation/'||c.id||'/'||p.id||'/'||n.slot)::uuid evaluation_uuid,
 case n.slot when 1 then 'quiz' when 2 then 'homework' when 3 then 'project' else 'exam' end kind,
 case n.slot when 1 then 20 when 2 then 25 when 3 then 25 else 30 end weight,
 case p.display_order
 when 1 then date '2026-03-02'+(n.slot-1)*14
 when 2 then date '2026-06-08'+(n.slot-1)*14
 else date '2026-09-11'+(n.slot-1)*14 end activity_date,
 case n.slot
 when 1 then 'Diagnóstico y conceptos fundamentales'
 when 2 then 'Guía de aplicación y resolución de problemas'
 when 3 then 'Proyecto: lo que aprendemos en nuestra comunidad'
 else 'Evaluación integradora de la unidad' end activity_title
from bs_classes c join academic_periods p on p.institution_id=c.institution_id and p.academic_year_id=c.academic_year_id
cross join generate_series(1,4) n(slot);

insert into assignments(uuid,institution_id,class_id,academic_period_id,title,description,instructions,assigned_at,due_at,max_score,is_graded,allow_late,task_status_id,created_by,kind,published)
select task_uuid,institution_id,class_id,period_id,activity_title||' · '||subject_name,
 'Actividad de presentación del trimestre '||term||'. Fortalece la comprensión, la práctica y la participación en '||subject_name||'.',
 '1. Repasa los contenidos de la unidad. 2. Desarrolla los ejercicios y explica el procedimiento. 3. Incluye una conclusión con lo aprendido. Se valora comprensión (40%), aplicación (40%) y presentación (20%).',
 (activity_date-7)+time '08:00:00' at time zone 'America/Managua',
 activity_date+time '17:00:00' at time zone 'America/Managua',100,true,true,
 (select id from catalog_task_statuses where code='PEND' order by id limit 1),teacher_id,kind,true
from bs_plan on conflict(uuid) do nothing;

insert into evaluations(uuid,institution_id,class_id,academic_period_id,assignment_id,title,description,max_score,weight,date,published,created_by)
select p.evaluation_uuid,p.institution_id,p.class_id,p.period_id,a.id,p.activity_title||' · '||p.subject_name,
 'Datos ficticios para presentación de Big School. Criterios: comprensión, aplicación y comunicación de resultados.',100,p.weight,p.activity_date,true,p.teacher_id
from bs_plan p join assignments a on a.uuid=p.task_uuid on conflict(uuid) do nothing;

insert into submissions(uuid,institution_id,assignment_id,student_id,submitted_at,student_notes,task_status_id,is_late)
select md5('bigschool-presentation-v1/submission/'||p.task_uuid||'/'||r.student_id)::uuid,
 p.institution_id,a.id,r.student_id,(p.activity_date-1)+time '15:30:00' at time zone 'America/Managua',
 'Actividad de ejemplo: desarrollé los ejercicios, revisé el procedimiento y redacté una conclusión sobre lo aprendido.',
 (select id from catalog_task_statuses where code='CALI' order by id limit 1),false
from bs_plan p join bs_classes c on c.id=p.class_id join bs_roster r on r.group_id=c.group_id
join assignments a on a.uuid=p.task_uuid on conflict(assignment_id,student_id) do nothing;

insert into grades(institution_id,evaluation_id,student_id,score,notes,recorded_by)
select p.institution_id,e.id,r.student_id,
 least(99,64+mod(r.student_id*7+p.class_id*3+p.slot*5,28)+p.term*2),
 case when mod(r.student_id+p.slot,4)=0 then 'Buen avance. Practica la explicación de los pasos y revisa tus resultados.'
 when mod(r.student_id+p.slot,4)=1 then 'Excelente participación y aplicación de los contenidos. Sigue así.'
 when mod(r.student_id+p.slot,4)=2 then 'Trabajo ordenado. Refuerza la justificación de tus respuestas con ejemplos.'
 else 'Demuestra comprensión y perseverancia. Continúa con la práctica diaria.' end||' [Presentación]',p.teacher_user_id
from bs_plan p join bs_classes c on c.id=p.class_id join bs_roster r on r.group_id=c.group_id
join evaluations e on e.uuid=p.evaluation_uuid on conflict(evaluation_id,student_id) do nothing;

-- Dos actividades próximas por materia: pendientes visibles en los tres portales.
insert into assignments(uuid,institution_id,class_id,academic_period_id,title,description,instructions,assigned_at,due_at,max_score,is_graded,allow_late,task_status_id,created_by,kind,published)
select md5('bigschool-presentation-v1/upcoming/'||c.id||'/'||n.slot)::uuid,c.institution_id,c.id,p.id,
 case n.slot when 1 then 'Reto de la semana: ' else 'Proyecto final: ' end||c.subject_name,
 case n.slot when 1 then 'Aplica lo aprendido en una situación de tu entorno y comparte cómo llegaste a la solución.'
 else 'Prepara una presentación breve con los aprendizajes del trimestre y un ejemplo de aplicación en tu comunidad.' end,
 'Trabaja con orden. Incluye título, desarrollo y conclusión. Puedes entregar tu explicación por escrito en la plataforma. Consulta al docente si necesitas orientación.',
 timestamptz '2026-10-26 08:00:00-06',case n.slot when 1 then timestamptz '2026-10-29 17:00:00-06' else timestamptz '2026-11-03 17:00:00-06' end,
 100,true,true,(select id from catalog_task_statuses where code='PEND' order by id limit 1),c.teacher_id,
 case n.slot when 1 then 'homework' else 'project' end,true
from bs_classes c join academic_periods p on p.academic_year_id=c.academic_year_id and p.institution_id=c.institution_id and p.display_order=3
cross join generate_series(1,2) n(slot) on conflict(uuid) do nothing;

-- Algunas entregas recientes quedan sin calificar para mostrar la revisión docente.
insert into submissions(uuid,institution_id,assignment_id,student_id,submitted_at,student_notes,task_status_id,is_late)
select md5('bigschool-presentation-v1/review/'||c.id||'/'||r.student_id)::uuid,c.institution_id,a.id,r.student_id,
 timestamptz '2026-10-26 11:00:00-06',
 'Entrega de presentación: identifiqué una situación cotidiana, apliqué los conceptos de la unidad y expliqué mi solución. Quedo atento a la retroalimentación del docente.',
 (select id from catalog_task_statuses where code='ENTR' order by id limit 1),false
from bs_classes c join bs_roster r on r.group_id=c.group_id
join assignments a on a.uuid=md5('bigschool-presentation-v1/upcoming/'||c.id||'/1')::uuid
where mod(r.student_id,3)=1 on conflict(assignment_id,student_id) do nothing;

-- Resumen calculado usando todas las evaluaciones publicadas, incluidas las previas.
insert into period_grades(institution_id,student_id,class_id,subject_id,academic_period_id,final_score,passed,notes,calculated_at)
select c.institution_id,r.student_id,c.id,c.subject_id,e.academic_period_id,
 round(sum(g.score/e.max_score*100*e.weight)/nullif(sum(e.weight),0),2),
 sum(g.score/e.max_score*100*e.weight)/nullif(sum(e.weight),0)>=60,
 'Resumen de presentación; incluye las evaluaciones publicadas con nota.',now()
from bs_classes c join bs_roster r on r.group_id=c.group_id
join evaluations e on e.class_id=c.id and e.institution_id=c.institution_id and e.published and e.max_score>0
join grades g on g.evaluation_id=e.id and g.student_id=r.student_id and g.institution_id=c.institution_id
group by c.institution_id,r.student_id,c.id,c.subject_id,e.academic_period_id
on conflict(student_id,class_id,academic_period_id) do nothing;

create temporary table bs_session_plan on commit drop as
select c.id class_id,c.institution_id,c.group_id,c.teacher_id,c.teacher_user_id,c.subject_name,d.day::date date,min(sc.start_time) start_time
from bs_classes c join schedules sc on sc.class_id=c.id
join catalog_weekdays wd on wd.id=sc.weekday_id
cross join generate_series(timestamp '2026-09-01',timestamp '2026-10-23',interval '1 day') d(day)
where extract(isodow from d.day)=wd.display_order and exists(select 1 from bs_roster r where r.group_id=c.group_id)
group by c.id,c.institution_id,c.group_id,c.teacher_id,c.teacher_user_id,c.subject_name,d.day;
insert into class_sessions(institution_id,class_id,group_id,date,start_time,topic,recorded_by,synced)
select p.institution_id,p.class_id,p.group_id,p.date,p.start_time,'Presentación: práctica y participación en '||p.subject_name,p.teacher_id,true
from bs_session_plan p where not exists(select 1 from class_sessions s where s.class_id=p.class_id and s.date=p.date);
insert into attendances(institution_id,class_session_id,student_id,attendance_status_id,recorded_at,notes,recorded_by,source)
select p.institution_id,s.id,r.student_id,
 (select id from catalog_attendance_statuses where code=case when mod(r.student_id+extract(day from p.date)::int,23)=0 then 'JUS'
 when mod(r.student_id+extract(day from p.date)::int,17)=0 then 'TAR' else 'PRE' end order by id limit 1),
 p.date+p.start_time at time zone 'America/Managua','Registro ficticio de presentación.',p.teacher_user_id,'web'
from bs_session_plan p join class_sessions s on s.class_id=p.class_id and s.date=p.date
join bs_roster r on r.group_id=p.group_id on conflict(class_session_id,student_id) do nothing;

insert into calendar_events(institution_id,title,description,type,start_at,end_at,audience,created_by)
select b.institution_id,v.title,v.description,v.type,v.starts,v.ends,'all',
 (select id from users where institution_id=b.institution_id and lower(email)='ernesto@bigschool.edu')
from bs_context b cross join (values
 ('Feria de ciencias y creatividad','Presentación de proyectos de aula. Las familias podrán conocer los experimentos y trabajos de cada grupo. Evento de ejemplo.','academic',timestamptz '2026-10-30 09:00:00-06',timestamptz '2026-10-30 12:00:00-06'),
 ('Encuentro de familias y docentes','Espacio para revisar los avances del trimestre y acordar metas de acompañamiento. Evento de ejemplo.','meeting',timestamptz '2026-11-05 15:00:00-06',timestamptz '2026-11-05 17:00:00-06'),
 ('Jornada de lectura compartida','Trae tu cuento favorito y participa en actividades de lectura y expresión oral. Evento de ejemplo.','academic',timestamptz '2026-11-10 09:00:00-06',timestamptz '2026-11-10 11:00:00-06')
) v(title,description,type,starts,ends)
where not exists(select 1 from calendar_events e where e.institution_id=b.institution_id and e.title=v.title and e.start_at=v.starts);
