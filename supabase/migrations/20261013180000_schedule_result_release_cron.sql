-- Publish AI-graded results automatically once each administrator-configured release time arrives.
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

select cron.unschedule(jobid)
from cron.job
where jobname = 'publish-fise-evaluation-results';

select cron.schedule(
  'publish-fise-evaluation-results',
  '* * * * *',
  'select public.publish_due_assignment_results();'
);
