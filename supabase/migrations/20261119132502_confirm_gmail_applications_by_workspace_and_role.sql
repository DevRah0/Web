create or replace function public.job_gmail_ack_sent(p_workspace uuid,p_queue_id uuid,p_sender_email text)
returns boolean language plpgsql set search_path='' as $$
declare item public.job_gmail_outbox; app uuid;
begin
  select * into item from public.job_gmail_outbox where workspace_id=p_workspace and id=p_queue_id for update;
  if not found or not exists(select from public.job_gmail_connections where workspace_id=p_workspace
     and lower(btrim(sender_email))=lower(btrim(p_sender_email))) then return false; end if;
  if item.status='sent' then return true; end if;
  if item.status not in ('claimed','uncertain') then return false; end if;
  update public.job_gmail_outbox set status='sent',accepted_at=coalesce(accepted_at,now()),
    sender_email=lower(btrim(p_sender_email)),last_error=null,updated_at=now() where id=item.id;
  insert into public.job_applications(workspace_id,job_id,status,method,submitted_at,confirmation_evidence,resume_version,application_notes)
    values(p_workspace,item.job_id,'submitted','email',now(),'Gmail accepted the message with the approved PDF. Queue reference '||item.id,
    item.resume_path,'Gmail') on conflict(workspace_id,job_id) do update set
    status=case when job_applications.submitted_at is null then 'submitted' else job_applications.status end,
    method='email',submitted_at=coalesce(job_applications.submitted_at,excluded.submitted_at),
    confirmation_evidence=coalesce(job_applications.confirmation_evidence,excluded.confirmation_evidence),
    resume_version=coalesce(job_applications.resume_version,excluded.resume_version),updated_at=now() returning id into app;
  update public.job_leads set status='applied',updated_at=now() where id=item.job_id and workspace_id=p_workspace;
  insert into public.job_prior_submissions(workspace_id,message_id,recipient_email,email_subject,sent_at,source,linked_application_id)
    values(p_workspace,'gmail-queue:'||item.id,item.recipient_email,item.subject,now(),'gmail',app)
    on conflict(workspace_id,message_id) do nothing;
  insert into public.job_activity(workspace_id,actor_section,event_type,note,job_id,application_id)
    values(p_workspace,'applying','gmail_accepted','قبل Gmail طلب التوظيف المرفق بالسيرة الذاتية.',item.job_id,app);
  insert into public.job_workflow_runs(workspace_id,section,status,submitted_count,notes,completed_at)
    values(p_workspace,'applying','completed',1,'Gmail accepted one application with its PDF attachment.',now());
  return true;
end $$;
