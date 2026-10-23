-- Additive, private derived data. No grants to student/parent clients.
-- Source-retention cascades must not scan the whole student table per person.
-- The existing (institution_id,person_id) index cannot serve this FK lookup alone.
create index if not exists originality_students_person_retention on public.students(person_id);
create table public.originality_documents (
 id bigserial primary key,
 institution_id bigint not null references public.institutions(id) on delete cascade,
 assignment_id bigint not null references public.assignments(id) on delete cascade,
 submission_id bigint not null references public.submissions(id) on delete cascade,
 file_id bigint references public.files(id) on delete cascade,
 revision text not null, source_key text not null,
 submitted_at timestamptz not null, created_at timestamptz not null default clock_timestamp(),
 active boolean not null default true,
 state text not null default 'queued' check(state in ('queued','processing','completed','failed','insufficient_text','unsupported_format')),
 algorithm_version text not null default 'nivra-1',
 source_notes text, binary_hash text, text_hash text,
 academic jsonb, fingerprints text[] not null default '{}',
 processed_at timestamptz, error_code text,
 unique(submission_id,revision,source_key)
);
create index originality_scope on public.originality_documents(institution_id,assignment_id,id) where active;
create index originality_fingerprints on public.originality_documents using gin(fingerprints) where active and state='completed';
create index originality_binary on public.originality_documents(institution_id,assignment_id,binary_hash) where active;
create index originality_text on public.originality_documents(institution_id,assignment_id,text_hash) where active;
create index originality_retention on public.originality_documents(institution_id,assignment_id);
create index originality_file_origin on public.originality_documents(file_id);

create table public.originality_jobs (
 id bigserial primary key, document_id bigint not null unique references public.originality_documents(id) on delete cascade,
 enqueued_at timestamptz not null default clock_timestamp(), available_at timestamptz not null default clock_timestamp(),
 attempts integer not null default 0 check(attempts>=0), lock_token uuid, lease_until timestamptz,
 finished_at timestamptz, error_code text, duration_ms integer
);
create index originality_queue on public.originality_jobs(available_at,id) where finished_at is null;
create table public.originality_consumer (
 id integer primary key check(id=1), lock_token uuid, lease_until timestamptz
);
insert into public.originality_consumer(id) values(1);
create table public.originality_pairs (
 a_id bigint not null references public.originality_documents(id) on delete cascade,
 b_id bigint not null references public.originality_documents(id) on delete cascade,
 a_coverage double precision not null check(a_coverage between 0 and 100),
 b_coverage double precision not null check(b_coverage between 0 and 100),
 a_intervals jsonb not null, b_intervals jsonb not null,
 binary_identical boolean not null, text_identical boolean not null,
 algorithm_version text not null, created_at timestamptz not null default clock_timestamp(),
 primary key(a_id,b_id,algorithm_version), check(a_id<b_id)
);
create index originality_pairs_reverse on public.originality_pairs(b_id);
create table public.originality_audit (
 id bigserial primary key, institution_id bigint references public.institutions(id) on delete cascade,
 submission_id bigint references public.submissions(id) on delete cascade,
 actor_id bigint references public.users(id) on delete cascade,
 action text not null, created_at timestamptz not null default clock_timestamp()
);
create index originality_audit_submission on public.originality_audit(submission_id);
create index originality_audit_institution on public.originality_audit(institution_id);
create index originality_audit_actor on public.originality_audit(actor_id);

-- Queue ownership is backend-only; authenticated users cannot bypass the report RPC.
do $$ declare t text; begin
 foreach t in array array['originality_documents','originality_jobs','originality_consumer','originality_pairs','originality_audit'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end $$;
grant usage,select on sequence public.originality_documents_id_seq,public.originality_jobs_id_seq,public.originality_audit_id_seq to service_role;
revoke all on sequence public.originality_documents_id_seq,public.originality_jobs_id_seq,public.originality_audit_id_seq from public,anon,authenticated;

-- One transaction replaces the delivery and file links; deferred capture sees the final version.
create function public.assignment_submit(p_assignment bigint,p_student bigint,p_notes text,p_files bigint[]) returns jsonb
language plpgsql security invoker set search_path=public as $$
declare actor bigint:=public.chat_actor(); inst bigint:=public.current_institution_id();
 a public.assignments%rowtype; s public.submissions%rowtype; status_id integer; fid bigint;
begin
 if p_student is null or not public.portal_submit_scope(p_student) or length(p_notes)>50000 or cardinality(p_files)>20 or array_position(p_files,null) is not null then
  raise exception 'Entrega inválida.' using errcode='42501'; end if;
 select * into a from public.assignments where id=p_assignment and institution_id=inst and deleted_at is null and published;
 if a.id is null or a.due_at<clock_timestamp() and not a.allow_late or not exists(
  select 1 from public.enrollments e join public.classes c on c.group_id=e.group_id and c.academic_year_id=e.academic_year_id
   join public.catalog_enrollment_statuses es on es.id=e.enrollment_status_id and es.code='ACT'
   where c.id=a.class_id and e.student_id=p_student and e.institution_id=inst) then
  raise exception 'Actividad no disponible.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('submission:'||p_assignment||':'||p_student,0));
 select * into s from public.submissions where assignment_id=p_assignment and student_id=p_student and institution_id=inst for update;
 if p_files is null then
  select coalesce(array_agg(file_id order by file_id),'{}') into p_files from public.submission_files where submission_id=s.id;
 end if;
 if exists(select 1 from public.catalog_task_statuses where id=s.task_status_id and code='CALI') then
  raise exception 'Entrega ya calificada.' using errcode='23505'; end if;
 foreach fid in array coalesce(p_files,'{}') loop
  if not exists(select 1 from public.files where id=fid and institution_id=inst and uploaded_by=actor and deleted_at is null) then
   raise exception 'Archivo no disponible.' using errcode='42501'; end if;
 end loop;
 if s.id is not null and s.student_notes is not distinct from p_notes and
  (select coalesce(array_agg(file_id order by file_id),'{}') from public.submission_files where submission_id=s.id)=
  (select coalesce(array_agg(distinct x order by x),'{}') from unnest(p_files) x) then return jsonb_build_object('id',s.id); end if;
 select id into strict status_id from public.catalog_task_statuses where code='ENTR' limit 1;
 insert into public.submissions(institution_id,assignment_id,student_id,student_notes,submitted_at,task_status_id,is_late,updated_at)
  values(inst,p_assignment,p_student,p_notes,clock_timestamp(),status_id,a.due_at<clock_timestamp(),clock_timestamp())
  on conflict(assignment_id,student_id) do update set student_notes=excluded.student_notes,submitted_at=excluded.submitted_at,
   task_status_id=excluded.task_status_id,is_late=excluded.is_late,updated_at=excluded.updated_at returning * into s;
 delete from public.submission_files where submission_id=s.id and not(file_id=any(coalesce(p_files,'{}')));
 insert into public.submission_files(submission_id,file_id) select s.id,x from unnest(p_files) x on conflict(submission_id,file_id) do nothing;
 return jsonb_build_object('id',s.id);
end $$;
revoke all on function public.assignment_submit(bigint,bigint,text,bigint[]) from public,anon;
grant execute on function public.assignment_submit(bigint,bigint,text,bigint[]) to authenticated;

create function public.originality_source_allowed(p_submission bigint,p_file bigint) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.submissions s
  join public.students st on st.id=s.student_id and st.institution_id=s.institution_id
  join public.submission_files sf on sf.submission_id=s.id and sf.file_id=p_file
  join public.files f on f.id=sf.file_id and f.institution_id=s.institution_id and f.deleted_at is null
  join public.users u on u.id=f.uploaded_by and u.institution_id=s.institution_id and u.person_id=st.person_id
  where s.id=p_submission)
$$;
create function public.originality_eligible(p_submission bigint) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.submissions s
  join public.assignments a on a.id=s.assignment_id and a.institution_id=s.institution_id and a.deleted_at is null
  join public.classes c on c.id=a.class_id and c.institution_id=s.institution_id and c.active
  join public.students st on st.id=s.student_id and st.institution_id=s.institution_id and st.active
  join public.enrollments e on e.student_id=s.student_id and e.institution_id=s.institution_id and e.group_id=c.group_id and e.academic_year_id=c.academic_year_id
  join public.catalog_enrollment_statuses es on es.id=e.enrollment_status_id and es.code='ACT'
  where s.id=p_submission and s.submitted_at is not null)
$$;
create function public.originality_capture(p_submission bigint) returns void
language plpgsql security definer set search_path=public as $$
declare s public.submissions%rowtype; rev text; f record; d bigint;
begin
 select * into s from public.submissions where id=p_submission for update;
 if s.id is null or s.submitted_at is null then return; end if;
 if not public.originality_eligible(s.id) then
  update public.originality_documents set active=false,academic=null,source_notes=null,fingerprints='{}' where submission_id=s.id;
  return;
 end if;
 rev:=md5(jsonb_build_array(s.submitted_at,s.student_notes,(select coalesce(jsonb_agg(file_id order by file_id),'[]') from public.submission_files where submission_id=s.id))::text);
 -- Retired versions retain hashes/status/times for audit, but purge full minor text.
 update public.originality_documents set active=false,academic=null,source_notes=null,fingerprints='{}' where submission_id=s.id and active
  and (revision<>rev or file_id is not null and not public.originality_source_allowed(s.id,file_id));
 for f in
  select sf.file_id,('file:'||sf.file_id) source_key,null::text notes from public.submission_files sf
   join public.files fi on fi.id=sf.file_id and fi.institution_id=s.institution_id and fi.deleted_at is null
   where sf.submission_id=s.id and public.originality_source_allowed(s.id,sf.file_id)
  union all select null,'notes',coalesce(s.student_notes,'') where nullif(trim(s.student_notes),'') is not null
   or not exists(select 1 from public.submission_files sf where sf.submission_id=s.id and public.originality_source_allowed(s.id,sf.file_id))
 loop
  insert into public.originality_documents(institution_id,assignment_id,submission_id,file_id,revision,source_key,submitted_at,source_notes)
   values(s.institution_id,s.assignment_id,s.id,f.file_id,rev,f.source_key,s.submitted_at,f.notes)
   on conflict(submission_id,revision,source_key) do update set active=true,state='queued',source_notes=excluded.source_notes,processed_at=null,error_code=null
    where not public.originality_documents.active returning id into d;
  if d is not null then
   insert into public.originality_jobs(document_id) values(d) on conflict(document_id) do update
    set finished_at=null,available_at=clock_timestamp(),attempts=0,lock_token=null,lease_until=null,error_code=null;
  end if;
 end loop;
end $$;
create function public.originality_capture_trigger() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if tg_table_name='submissions' then perform public.originality_capture(new.id);
 elsif tg_op='DELETE' then perform public.originality_capture(old.submission_id);
 else perform public.originality_capture(new.submission_id); end if;
 return null;
exception when others then
 -- Academic delivery remains valid. Periodic reconciliation recovers a missed outbox record.
 raise warning 'originality_capture_failed'; return null;
end $$;
create constraint trigger originality_submission_capture after insert or update on public.submissions
 deferrable initially deferred for each row execute function public.originality_capture_trigger();
create constraint trigger originality_file_capture after insert or update or delete on public.submission_files
 deferrable initially deferred for each row execute function public.originality_capture_trigger();

-- The DB clock is authoritative; grading does not change submission time.
create function public.originality_submission_clock() returns trigger language plpgsql as $$
begin
 if new.submitted_at is not null and (tg_op='INSERT' or new.submitted_at is distinct from old.submitted_at or new.student_notes is distinct from old.student_notes) then
  new.submitted_at:=clock_timestamp();
 end if;
 return new;
end $$;
create trigger originality_submission_clock before insert or update on public.submissions for each row execute function public.originality_submission_clock();

create function public.originality_claim() returns jsonb
language plpgsql security definer set search_path=public as $$
declare j public.originality_jobs%rowtype; token uuid:=gen_random_uuid();
begin
 perform 1 from public.originality_consumer where id=1 for update;
 if exists(select 1 from public.originality_consumer where id=1 and lease_until>clock_timestamp()) then return null; end if;
 -- Expired leases consume an attempt; exhaustion remains explicitly recoverable.
 update public.originality_documents d set state='failed',error_code='attempts_exhausted'
  from public.originality_jobs expired where expired.document_id=d.id and expired.finished_at is null and expired.attempts>=3 and expired.lease_until<clock_timestamp();
 update public.originality_jobs set finished_at=clock_timestamp(),error_code='attempts_exhausted'
  where finished_at is null and attempts>=3 and lease_until<clock_timestamp();
 select q.* into j from public.originality_jobs q join public.originality_documents d on d.id=q.document_id
  where q.finished_at is null and q.available_at<=clock_timestamp() and (q.lease_until is null or q.lease_until<clock_timestamp())
  and q.attempts<3 and d.active and public.originality_eligible(d.submission_id) order by q.id limit 1 for update of q;
 if j.id is null then return null; end if;
 update public.originality_jobs set lock_token=token,lease_until=clock_timestamp()+interval '120 seconds',attempts=attempts+1 where id=j.id returning * into j;
 update public.originality_consumer set lock_token=token,lease_until=j.lease_until where id=1;
 update public.originality_documents set state='processing',error_code=null where id=j.document_id;
 return to_jsonb(j);
end $$;
create function public.originality_heartbeat(p_job bigint,p_lock uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
 update public.originality_consumer set lease_until=clock_timestamp()+interval '120 seconds' where id=1 and lock_token=p_lock and lease_until>clock_timestamp();
 if not found then raise exception 'lease_lost'; end if;
 update public.originality_jobs set lease_until=clock_timestamp()+interval '120 seconds' where id=p_job and lock_token=p_lock and finished_at is null;
 if not found then raise exception 'lease_lost'; end if;
end $$;
create function public.originality_candidates(p_document bigint,p_binary text,p_text text,p_fingerprints text[],p_after bigint,p_version text default 'nivra-1')
returns setof public.originality_documents language sql security definer set search_path=public as $$
 select c.* from public.originality_documents c join public.originality_documents d on d.id=p_document
 where c.institution_id=d.institution_id and c.assignment_id=d.assignment_id and c.submission_id<>d.submission_id
 and c.active and c.state in ('completed','insufficient_text','unsupported_format') and c.algorithm_version=p_version and c.id>p_after
 and public.originality_eligible(c.submission_id) and public.originality_eligible(d.submission_id)
 and c.submitted_at=(select live.submitted_at from public.submissions live where live.id=c.submission_id)
 and (c.file_id is null or public.originality_source_allowed(c.submission_id,c.file_id))
 and (c.binary_hash=p_binary or c.state='completed' and (c.text_hash=p_text or c.fingerprints && p_fingerprints))
 order by c.id limit 1
$$;
create function public.originality_finish(p_job bigint,p_lock uuid,p_result jsonb,p_pairs jsonb) returns void
language plpgsql security definer set search_path=public as $$
declare j public.originality_jobs%rowtype; d public.originality_documents%rowtype; pair jsonb; other public.originality_documents%rowtype;
begin
 perform public.originality_heartbeat(p_job,p_lock);
 select * into j from public.originality_jobs where id=p_job for update;
 select * into d from public.originality_documents where id=j.document_id for update;
 if not d.active then
  update public.originality_jobs set finished_at=clock_timestamp() where id=j.id;
 else
  d.algorithm_version:=p_result->>'algorithmVersion';
  update public.originality_documents set algorithm_version=d.algorithm_version,state=p_result->>'state',binary_hash=p_result->>'binaryHash',text_hash=p_result->>'textHash',
   academic=p_result->'academic',fingerprints=coalesce(array(select jsonb_array_elements_text(p_result->'fingerprints')),'{}'),
   processed_at=clock_timestamp(),source_notes=null,error_code=p_result->>'errorCode' where id=d.id;
  for pair in select value from jsonb_array_elements(p_pairs) loop
   select * into other from public.originality_documents where id=(pair->>'otherId')::bigint and active and state in ('completed','insufficient_text','unsupported_format')
    and institution_id=d.institution_id and assignment_id=d.assignment_id and submission_id<>d.submission_id and algorithm_version=d.algorithm_version;
   if other.id is null then raise exception 'invalid_pair'; end if;
   insert into public.originality_pairs values(least(d.id,other.id),greatest(d.id,other.id),
    case when d.id<other.id then (pair->>'aCoverage')::float else (pair->>'bCoverage')::float end,
    case when d.id<other.id then (pair->>'bCoverage')::float else (pair->>'aCoverage')::float end,
    case when d.id<other.id then pair->'aIntervals' else pair->'bIntervals' end,
    case when d.id<other.id then pair->'bIntervals' else pair->'aIntervals' end,
    (pair->>'binaryIdentical')::boolean,(pair->>'textIdentical')::boolean,d.algorithm_version,clock_timestamp()) on conflict do nothing;
  end loop;
  update public.originality_jobs set finished_at=clock_timestamp(),duration_ms=(p_result->>'durationMs')::integer where id=j.id;
 end if;
 update public.originality_consumer set lease_until=null,lock_token=null where id=1 and lock_token=p_lock;
end $$;
create function public.originality_fail(p_job bigint,p_lock uuid,p_code text) returns void
language plpgsql security definer set search_path=public as $$
declare j public.originality_jobs%rowtype;
begin
 perform public.originality_heartbeat(p_job,p_lock);
 update public.originality_jobs set error_code=p_code,lease_until=null,
  available_at=clock_timestamp()+make_interval(secs=>least(300,5*power(2,attempts)::integer)),
  finished_at=case when attempts>=3 then clock_timestamp() else null end
  where id=p_job and lock_token=p_lock returning * into j;
 update public.originality_documents set state=case when j.attempts>=3 then 'failed' else 'queued' end,error_code=p_code where id=j.document_id;
 update public.originality_consumer set lease_until=null,lock_token=null where id=1 and lock_token=p_lock;
end $$;

-- Reconcile only missing/current snapshots, in small pages; also prunes inactive queue work.
create function public.originality_reconcile(p_after bigint default 0) returns bigint
language plpgsql security definer set search_path=public as $$
declare s record; last_id bigint:=0;
begin
 for s in select id from public.submissions where id>p_after and submitted_at is not null order by id limit 50 loop
  perform public.originality_capture(s.id); last_id:=s.id;
 end loop;
 update public.originality_jobs j set finished_at=clock_timestamp() from public.originality_documents d where d.id=j.document_id and not d.active and j.finished_at is null and (j.lease_until is null or j.lease_until<clock_timestamp());
 return last_id;
end $$;
create function public.originality_metrics() returns jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object('queueDepth',count(*) filter(where j.finished_at is null and d.active),
  'oldestQueueAgeSeconds',coalesce(extract(epoch from clock_timestamp()-min(j.enqueued_at) filter(where j.finished_at is null and d.active)),0),
  'failed',count(*) filter(where d.active and d.state='failed'),
  'processing',count(*) filter(where d.active and d.state='processing'))
 from public.originality_jobs j join public.originality_documents d on d.id=j.document_id
$$;

-- Explicit read policy: review and student identity access; reject other actors.
create function public.originality_report(p_submission bigint,p_evidence boolean default false,p_retry boolean default false) returns jsonb
language plpgsql security definer set search_path=public as $$
declare s public.submissions%rowtype; a public.assignments%rowtype; doc jsonb; result jsonb;
begin
 select * into s from public.submissions where id=p_submission and institution_id=public.current_institution_id();
 select * into a from public.assignments where id=s.assignment_id and institution_id=s.institution_id and deleted_at is null;
 if s.id is null or a.id is null or not public.originality_eligible(s.id) or not public.is_teacher_actor() or not public.class_permission(a.class_id,'class.view') or not public.class_permission(a.class_id,'assignments.review') or not public.class_permission(a.class_id,'students.view') then
  raise exception 'Entrega no disponible.' using errcode='42501';
 end if;
 -- Repairs a missed fail-open capture before exposing a possibly stale report.
 perform public.originality_capture(s.id);
 if p_retry then
  update public.originality_jobs j set finished_at=null,available_at=clock_timestamp(),attempts=0,error_code=null,lease_until=null,lock_token=null
   from public.originality_documents d where d.id=j.document_id and d.submission_id=s.id and d.active and d.state='failed';
  update public.originality_documents set state='queued',error_code=null where submission_id=s.id and active and state='failed';
 end if;
 select coalesce(jsonb_agg(x.doc order by x.id),'[]') into doc from (
  select d.id,jsonb_build_object('id',d.id,'state',d.state,'name',coalesce(f.original_name,'Texto de la entrega'),
   'submittedAt',d.submitted_at,'processedAt',d.processed_at,'algorithmVersion',d.algorithm_version,'errorCode',d.error_code,
   'preliminary',coalesce(a.due_at>clock_timestamp(),true) or exists(select 1 from public.originality_documents pending where pending.institution_id=s.institution_id and pending.assignment_id=s.assignment_id and pending.active and pending.state in ('queued','processing','failed'))
    or exists(select 1 from public.submissions awaiting where awaiting.institution_id=s.institution_id and awaiting.assignment_id=s.assignment_id and public.originality_eligible(awaiting.id)
     and not exists(select 1 from public.originality_documents ready where ready.submission_id=awaiting.id and ready.active and ready.submitted_at=awaiting.submitted_at)),
   'compared',d.state='completed' and exists(select 1 from public.originality_documents c where c.active and c.state='completed' and c.institution_id=d.institution_id and c.assignment_id=d.assignment_id and c.submission_id<>d.submission_id and c.algorithm_version=d.algorithm_version and public.originality_eligible(c.submission_id)
    and c.submitted_at=(select live.submitted_at from public.submissions live where live.id=c.submission_id)),
   'topMatch',top.doc) doc
  from public.originality_documents d left join public.files f on f.id=d.file_id
  left join lateral (
   select jsonb_build_object('coverage',case when p.a_id=d.id then p.a_coverage else p.b_coverage end,
    'sourceId',o.id,'sourceName',coalesce(ofi.original_name,'Texto de la entrega'),'sourceStudent',coalesce(nullif(trim(concat_ws(' ',pe.first_name,pe.last_name)),''),'Estudiante'),
    'sourceSubmittedAt',o.submitted_at,'binaryIdentical',p.binary_identical,'textIdentical',p.text_identical,
    'fragments',case when p_evidence then (select coalesce(jsonb_agg(jsonb_build_object('text',substring(d.academic->>'text' from (v->>0)::int+1 for least(1500,(v->>1)::int-(v->>0)::int)),'start',(v->>0)::int,'end',(v->>1)::int)),'[]') from (select value v from jsonb_array_elements(case when p.a_id=d.id then p.a_intervals else p.b_intervals end) limit 10) ints) else null end,
    'sourceFragments',case when p_evidence then (select coalesce(jsonb_agg(jsonb_build_object('text',substring(o.academic->>'text' from (v->>0)::int+1 for least(1500,(v->>1)::int-(v->>0)::int)),'start',(v->>0)::int,'end',(v->>1)::int)),'[]') from (select value v from jsonb_array_elements(case when p.a_id=d.id then p.b_intervals else p.a_intervals end) limit 10) ints) else null end) doc
   from public.originality_pairs p join public.originality_documents o on o.id=case when p.a_id=d.id then p.b_id else p.a_id end
   join public.submissions os on os.id=o.submission_id join public.students st on st.id=os.student_id join public.persons pe on pe.id=st.person_id
   left join public.files ofi on ofi.id=o.file_id
   where d.state in ('completed','insufficient_text','unsupported_format') and (p.a_id=d.id or p.b_id=d.id) and o.active and o.state in ('completed','insufficient_text','unsupported_format') and o.institution_id=d.institution_id and o.assignment_id=d.assignment_id
    and p.algorithm_version=d.algorithm_version and o.algorithm_version=d.algorithm_version
    and public.originality_eligible(o.submission_id)
    and o.submitted_at=os.submitted_at
    and (o.file_id is null or public.originality_source_allowed(o.submission_id,o.file_id))
   order by case when p.a_id=d.id then p.a_coverage else p.b_coverage end desc,o.id asc limit 1
  ) top on true
  where d.submission_id=s.id and d.institution_id=s.institution_id and d.active
 ) x;
 insert into public.originality_audit(institution_id,submission_id,actor_id,action) values(s.institution_id,s.id,public.chat_actor(),case when p_retry then 'retry' when p_evidence then 'evidence' else 'report' end);
 result:=jsonb_build_object('documents',doc,'notice','Este resultado es orientativo; una coincidencia textual no demuestra plagio ni identifica al autor original. La valoración corresponde al docente.');
 return result;
end $$;

-- Source removal also removes derived contents/evidence, including historical versions.
create function public.originality_purge_source() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.deleted_at is not null then
  if tg_table_name='files' then delete from public.originality_documents where file_id=new.id;
  else delete from public.originality_documents where assignment_id=new.id; end if;
 end if;
 return new;
end $$;
create trigger originality_file_purge after update of deleted_at on public.files for each row execute function public.originality_purge_source();
create trigger originality_assignment_purge after update of deleted_at on public.assignments for each row execute function public.originality_purge_source();

do $$ declare f record; begin
 for f in select oid::regprocedure sig,proname from pg_proc where pronamespace='public'::regnamespace and proname like 'originality_%' loop
 execute format('revoke all on function %s from public,anon,authenticated',f.sig);
 if f.proname in ('originality_claim','originality_heartbeat','originality_finish','originality_fail','originality_reconcile','originality_candidates','originality_metrics','originality_source_allowed') then execute format('grant execute on function %s to service_role',f.sig); end if;
 end loop;
end $$;
grant execute on function public.originality_report(bigint,boolean,boolean) to authenticated;
