-- Local/reviewed rollback only. First stop the worker and restore the previous backend/frontend.
-- This removes derived analysis, never original files, submissions or grades.
begin;
drop table if exists public.originality_edge_state,public.originality_edge_control;
drop trigger if exists originality_submission_capture on public.submissions;
drop trigger if exists originality_file_capture on public.submission_files;
drop trigger if exists originality_submission_clock on public.submissions;
drop trigger if exists originality_file_purge on public.files;
drop trigger if exists originality_assignment_purge on public.assignments;
drop function if exists public.assignment_submit(bigint,bigint,text,bigint[]);
do $$ declare f record; begin
 for f in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace and proname like 'originality_%' loop
 execute format('drop function if exists %s cascade',f.sig);
 end loop;
end $$;
drop table public.originality_pairs,public.originality_jobs,public.originality_consumer,public.originality_audit,public.originality_documents;
drop index if exists public.originality_students_person_retention;
commit;
