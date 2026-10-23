-- REVIEW/EXECUTE SEPARATELY after 0059, function deployment and hosted resource tests.
-- Required Vault secrets, created securely outside this tracked file:
-- nivra_originality_url = https://<project-ref>.supabase.co/functions/v1/nivra-originality
-- nivra_originality_cron_secret = same random >=32-character ORIGINALITY_CRON_SECRET as the function
-- No service-role key is stored in the schedule. Do not run alongside the Node consumer.
-- Set ORIGINALITY_EDGE_ENABLED=true only AFTER the fixed synthetic hosted probes pass.
begin;
do $$ begin
 if not exists(select 1 from pg_extension where extname='pg_cron') or
    not exists(select 1 from pg_extension where extname='pg_net') then
  raise exception 'Enable pg_cron and pg_net before scheduling';
 end if;
 if (select count(*) from vault.decrypted_secrets where name='nivra_originality_url'
     and decrypted_secret ~ '^https://[a-z0-9]+\.supabase\.co/functions/v1/nivra-originality$')<>1 or
    (select count(*) from vault.decrypted_secrets where name='nivra_originality_cron_secret' and length(decrypted_secret)>=32)<>1 then
  raise exception 'Missing, duplicate or invalid Nivra Vault configuration';
 end if;
end $$;
select cron.unschedule(jobid) from cron.job where jobname='nivra-originality';
-- 259,200 SQL ticks per 30 days. Empty/busy queues do not invoke Edge.
-- Check the project's remaining function/CPU/egress quotas before activation.
select cron.schedule('nivra-originality','10 seconds',$job$
 select public.originality_edge_reconcile();
 select net.http_post(
  url:=(select decrypted_secret from vault.decrypted_secrets where name='nivra_originality_url'),
  headers:=jsonb_build_object('Content-Type','application/json','x-originality-secret',
   (select decrypted_secret from vault.decrypted_secrets where name='nivra_originality_cron_secret')),
  body:='{}'::jsonb,timeout_milliseconds:=90000
 ) where exists(select 1 from public.originality_jobs j join public.originality_documents d on d.id=j.document_id
  where j.finished_at is null and j.available_at<=clock_timestamp() and d.active
   and (j.lease_until is null or j.lease_until<clock_timestamp()) and public.originality_edge_live(d.id))
 and not exists(select 1 from public.originality_consumer where id=1 and lease_until>clock_timestamp());
$job$);
commit;
