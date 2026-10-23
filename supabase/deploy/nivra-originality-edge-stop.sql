-- Stops future dispatches; an invocation already in progress can retain its 120-second lease.
select cron.unschedule(jobid) from cron.job where jobname='nivra-originality';
-- Drain active invocations / wait for lease expiry before changing consumers or rolling back 0059.
