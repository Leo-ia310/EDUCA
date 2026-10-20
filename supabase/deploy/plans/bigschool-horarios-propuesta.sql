-- PROPUESTA: cambia 9 franjas de Big School; conserva días, duración,
-- maestros, materias, grupos y aulas. Algunas clases terminarán a las 13:00.
-- NO EJECUTAR sin confirmar disponibilidad real de alumnos/docentes/recesos.
-- Tras aprobar expresamente la tabla de cambios, cambiar solamente
-- horario_aprobado := false por horario_aprobado := true.
LOCK TABLE public.schedules IN SHARE ROW EXCLUSIVE MODE;
DO $schedule_plan$
DECLARE horario_aprobado boolean := false; matches integer;
BEGIN
 IF NOT horario_aprobado THEN
  RAISE EXCEPTION 'Propuesta de horarios pendiente de aprobación. Revisar PROPUESTA_HORARIOS_BIGSCHOOL.md antes de cambiar horario_aprobado a true.';
 END IF;
 CREATE TEMP TABLE approved_schedule_plan ON COMMIT DROP AS
 SELECT * FROM (VALUES
 (7,13,5,3,3,3,'10:00:00'::time,'11:30:00'::time,'11:30'::time,'13:00'::time),
 (10,15,7,8,5,1,'08:00:00'::time,'09:30:00'::time,'09:30'::time,'11:00'::time),
 (14,17,6,5,4,2,'08:00:00'::time,'09:30:00'::time,'09:30'::time,'11:00'::time),
 (15,17,6,5,4,4,'10:00:00'::time,'11:30:00'::time,'08:30'::time,'10:00'::time),
 (20,20,6,8,4,3,'08:00:00'::time,'09:30:00'::time,'11:30'::time,'13:00'::time),
 (21,20,6,8,4,5,'10:00:00'::time,'11:30:00'::time,'08:30'::time,'10:00'::time),
 (23,21,7,8,5,5,'10:00:00'::time,'11:30:00'::time,'11:30'::time,'13:00'::time),
 (25,22,5,7,3,5,'10:00:00'::time,'11:30:00'::time,'08:30'::time,'10:00'::time),
 (26,23,6,7,4,1,'08:00:00'::time,'09:30:00'::time,'09:30'::time,'11:00'::time)
 ) AS p(id,class_id,group_id,teacher_id,classroom_id,weekday_id,old_start,old_end,new_start,new_end);
 SELECT count(*) INTO matches FROM approved_schedule_plan p
 JOIN public.schedules s ON s.id=p.id JOIN public.classes c ON c.id=s.class_id
 WHERE s.institution_id=2 AND c.institution_id=2 AND c.academic_year_id=2
   AND s.kind='class' AND s.class_id=p.class_id AND c.group_id=p.group_id
   AND c.teacher_id=p.teacher_id AND s.classroom_id=p.classroom_id
   AND s.weekday_id=p.weekday_id AND s.start_time=p.old_start AND s.end_time=p.old_end;
 IF matches<>9 THEN
  RAISE EXCEPTION 'Los horarios o asignaciones ya cambiaron. Revisar una propuesta nueva; no se actualizó ningún horario.';
 END IF;
 UPDATE public.schedules s SET start_time=p.new_start,end_time=p.new_end
 FROM approved_schedule_plan p WHERE s.id=p.id;
 GET DIAGNOSTICS matches = ROW_COUNT;
 IF matches<>9 THEN RAISE EXCEPTION 'No se actualizaron exactamente los 9 bloques previstos.'; END IF;
END
$schedule_plan$;
