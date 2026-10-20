-- Solo lectura. Revisar antes de ejecutar scalability-0029-0053.sql.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30s';
WITH blocks AS (
  SELECT s.id, s.institution_id, i.name institution, s.weekday_id,
    s.start_time, s.end_time, s.kind, s.label,
    coalesce(CASE WHEN s.kind = 'class' THEN c.academic_year_id ELSE g.academic_year_id END,
      (SELECT min(y.id) FROM public.academic_years y
        WHERE y.institution_id = s.institution_id AND y.is_current AND y.active)) year_id,
    CASE WHEN s.kind = 'class' THEN c.group_id ELSE s.group_id END group_id,
    CASE WHEN s.kind = 'class' THEN c.teacher_id END teacher_id,
    CASE WHEN s.kind = 'class' THEN lower(trim(room.name)) END room_key,
    g.name group_name, sub.name subject
  FROM public.schedules s
  JOIN public.institutions i ON i.id = s.institution_id
  LEFT JOIN public.classes c ON c.id = s.class_id
  LEFT JOIN public.groups g ON g.id = CASE WHEN s.kind = 'class' THEN c.group_id ELSE s.group_id END
  LEFT JOIN public.subjects sub ON sub.id = c.subject_id
  LEFT JOIN public.classrooms room ON room.id = s.classroom_id
)
SELECT a.institution, a.institution_id, a.year_id, a.weekday_id,
  a.id first_id, b.id second_id,
  a.group_name first_group, b.group_name second_group,
  a.subject first_subject, b.subject second_subject,
  a.start_time first_start, a.end_time first_end,
  b.start_time second_start, b.end_time second_end,
  a.room_key first_room, b.room_key second_room,
  array_remove(ARRAY[
    CASE WHEN a.group_id IS NULL OR b.group_id IS NULL OR a.group_id = b.group_id THEN 'grupo' END,
    CASE WHEN a.teacher_id = b.teacher_id THEN 'maestro' END,
    CASE WHEN a.room_key = b.room_key THEN 'aula' END
  ], NULL) reasons
FROM blocks a JOIN blocks b ON a.id < b.id
  AND a.institution_id = b.institution_id AND a.year_id = b.year_id
  AND a.weekday_id = b.weekday_id
  AND a.start_time < b.end_time AND a.end_time > b.start_time
WHERE a.group_id IS NULL OR b.group_id IS NULL OR a.group_id = b.group_id
  OR a.teacher_id = b.teacher_id OR a.room_key = b.room_key
ORDER BY a.institution_id, a.weekday_id, a.id, b.id;
ROLLBACK;
