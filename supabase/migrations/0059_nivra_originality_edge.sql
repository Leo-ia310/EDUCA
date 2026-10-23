-- Resumable Edge execution; no extensions, HTTP calls or schedules are activated here.
-- 0058 remains compatible. Never run the Node consumer and Edge consumer together.
create table public.originality_edge_state (
 job_id bigint primary key references public.originality_jobs(id) on delete cascade,
 checkpoint jsonb not null check(jsonb_typeof(checkpoint)='object' and octet_length(checkpoint::text)<=8388608),
 updated_at timestamptz not null default clock_timestamp()
);
create table public.originality_edge_control (
 id integer primary key check(id=1), after_id bigint not null default 0,
 reconcile_at timestamptz not null default 'epoch'
);
insert into public.originality_edge_control(id) values(1);
alter table public.originality_edge_state enable row level security;
alter table public.originality_edge_control enable row level security;
revoke all on public.originality_edge_state,public.originality_edge_control from public,anon,authenticated;
grant select,insert,update,delete on public.originality_edge_state,public.originality_edge_control to service_role;

create function public.originality_edge_live(p_document bigint) returns boolean
language sql security definer set search_path=public as $$
 select exists(select 1 from public.originality_documents d join public.submissions s on s.id=d.submission_id
 where d.id=p_document and d.active and d.submitted_at=s.submitted_at and public.originality_eligible(s.id)
 and (d.file_id is null or public.originality_source_allowed(s.id,d.file_id)))
$$;

create function public.originality_edge_cleanup() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if tg_table_name='originality_documents' then
  if not new.active or new.state in ('completed','failed','insufficient_text','unsupported_format') then
   delete from public.originality_edge_state where job_id in(select id from public.originality_jobs where document_id=new.id);
  end if;
 elsif new.finished_at is not null then
  delete from public.originality_edge_state where job_id=new.id;
 end if;
 return new;
end $$;
create trigger originality_edge_document_cleanup after update of active,state on public.originality_documents
for each row execute function public.originality_edge_cleanup();
create trigger originality_edge_job_cleanup after update of finished_at on public.originality_jobs
for each row execute function public.originality_edge_cleanup();

create function public.originality_edge_claim() returns jsonb
language plpgsql security definer set search_path=public as $$
declare j public.originality_jobs%rowtype; token uuid:=gen_random_uuid(); saved jsonb;
begin
 perform 1 from public.originality_consumer where id=1 for update;
 if exists(select 1 from public.originality_consumer where id=1 and lease_until>clock_timestamp()) then return null; end if;
 update public.originality_documents d set state='failed',error_code='attempts_exhausted'
 from public.originality_jobs q where q.document_id=d.id and q.finished_at is null and q.attempts>=3 and q.lease_until<clock_timestamp();
 update public.originality_jobs set finished_at=clock_timestamp(),error_code='attempts_exhausted'
 where finished_at is null and attempts>=3 and lease_until<clock_timestamp();
 select q.* into j from public.originality_jobs q join public.originality_documents d on d.id=q.document_id
 where q.finished_at is null and q.available_at<=clock_timestamp() and (q.lease_until is null or q.lease_until<clock_timestamp())
 and (q.attempts<3 or q.lock_token is null and exists(select 1 from public.originality_edge_state where job_id=q.id))
 and public.originality_edge_live(d.id) order by q.id limit 1 for update of q;
 if j.id is null then return null; end if;
 select checkpoint into saved from public.originality_edge_state where job_id=j.id;
 update public.originality_jobs set lock_token=token,lease_until=clock_timestamp()+interval '120 seconds',
 attempts=case when saved is not null and j.lock_token is null then attempts else attempts+1 end
 where id=j.id returning * into j;
 update public.originality_consumer set lock_token=token,lease_until=j.lease_until where id=1;
 update public.originality_documents set state='processing',error_code=null where id=j.document_id;
 return to_jsonb(j)||jsonb_build_object('checkpoint',saved);
end $$;

create function public.originality_edge_yield(p_job bigint,p_lock uuid,p_state jsonb) returns boolean
language plpgsql security definer set search_path=public as $$
declare doc bigint;
begin
 perform public.originality_heartbeat(p_job,p_lock);
 select document_id into strict doc from public.originality_jobs where id=p_job and lock_token=p_lock for update;
 if not public.originality_edge_live(doc) then
  update public.originality_documents set active=false,source_notes=null,academic=null,fingerprints='{}' where id=doc;
  update public.originality_jobs set finished_at=clock_timestamp() where id=p_job;
 else
  if p_state is null or jsonb_typeof(p_state)<>'object' or octet_length(p_state::text)>8388608 or
   coalesce(p_state->>'stage','') not in ('extract','pdf','prepare','compare','finish') then
   raise exception 'invalid_checkpoint';
  end if;
  insert into public.originality_edge_state(job_id,checkpoint) values(p_job,p_state)
   on conflict(job_id) do update set checkpoint=excluded.checkpoint,updated_at=clock_timestamp();
  update public.originality_jobs set lock_token=null,lease_until=null,available_at=clock_timestamp() where id=p_job;
 end if;
 update public.originality_consumer set lock_token=null,lease_until=null where id=1 and lock_token=p_lock;
 return public.originality_edge_live(doc);
end $$;

create function public.originality_edge_finish(p_job bigint,p_lock uuid,p_result jsonb,p_pairs jsonb) returns boolean
language plpgsql security definer set search_path=public as $$
declare doc bigint;
begin
 perform public.originality_heartbeat(p_job,p_lock);
 select document_id into strict doc from public.originality_jobs where id=p_job and lock_token=p_lock for update;
 if not public.originality_edge_live(doc) then
  perform public.originality_edge_yield(p_job,p_lock,jsonb_build_object('stage','finish'));
  return false;
 end if;
 perform public.originality_finish(p_job,p_lock,p_result,p_pairs);
 delete from public.originality_edge_state where job_id=p_job;
 return true;
end $$;

create function public.originality_edge_reconcile() returns bigint
language plpgsql security definer set search_path=public as $$
declare ctl public.originality_edge_control%rowtype; last_id bigint;
begin
 select * into ctl from public.originality_edge_control where id=1 for update skip locked;
 if ctl.id is null or ctl.reconcile_at>clock_timestamp() then return null; end if;
 last_id:=public.originality_reconcile(ctl.after_id);
 update public.originality_edge_control set after_id=last_id,
 reconcile_at=clock_timestamp()+case when last_id=0 then interval '60 seconds' else interval '1 second' end where id=1;
 return last_id;
end $$;

do $$ declare f record; begin
 for f in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace and proname like 'originality_edge_%' loop
  execute format('revoke all on function %s from public,anon,authenticated',f.sig);
  execute format('grant execute on function %s to service_role',f.sig);
 end loop;
end $$;
