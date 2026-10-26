-- Extend the statement-scoped family grant batching from 0054 to attendance.
-- The same live actor, tenant, module and family checks apply. Other restrictive
-- policies (including teacher grants) remain in force. No data or grants change.
alter policy portal_module_read on public.class_sessions using (
  (select public.portal_can('attendance.view')) and
  ((select public.portal_staff_actor()) or class_id=any((select public.portal_family_class_ids())::bigint[])));
alter policy portal_module_read on public.attendances using (
  (select public.portal_can('attendance.view')) and
  ((select public.portal_staff_actor()) or student_id=any((select public.portal_family_student_ids())::bigint[])));
