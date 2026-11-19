alter table public.job_workflow_runs alter column run_date set default ((now() at time zone 'Asia/Riyadh')::date);
