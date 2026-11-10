-- Quita resumen y plantilla por actividad. Conserva 0058/0059 y todos los datos académicos.
begin;
drop function if exists public.originality_summary(bigint);
drop function if exists public.originality_template_set(bigint, text);
drop function if exists public.originality_template_get(bigint);
drop function if exists public.originality_assignment_access(bigint, text);
drop table if exists public.originality_templates;
drop index if exists public.originality_audit_assignment;
alter table public.originality_audit drop column if exists assignment_id;
delete from public._applied_scripts where name = '0065_originality_summary_template.sql';
notify pgrst, 'reload schema';
commit;
