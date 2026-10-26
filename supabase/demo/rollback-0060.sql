BEGIN;
alter policy portal_module_read on public.attendances using ((( SELECT portal_can('attendance.view'::text) AS portal_can) AND portal_student_scope(student_id)));
alter policy portal_module_read on public.class_sessions using ((( SELECT portal_can('attendance.view'::text) AS portal_can) AND portal_class_scope(class_id)));
delete from public._applied_scripts where name='0060_batched_attendance_portal_scope.sql';
COMMIT;