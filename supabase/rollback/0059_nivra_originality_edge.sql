-- Stop/unschedule the Edge consumer first. Keeps 0058 and all original academic data.
begin;
drop trigger if exists originality_edge_document_cleanup on public.originality_documents;
drop trigger if exists originality_edge_job_cleanup on public.originality_jobs;
do $$ declare f record; begin
 for f in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace and proname like 'originality_edge_%' loop
  execute format('drop function if exists %s cascade',f.sig);
 end loop;
end $$;
drop table public.originality_edge_state,public.originality_edge_control;
-- Yielded jobs become ordinary 0058 queue entries for a separately started Node consumer.
update public.originality_jobs set lock_token=null,lease_until=null where finished_at is null;
update public.originality_consumer set lock_token=null,lease_until=null where id=1;
commit;
