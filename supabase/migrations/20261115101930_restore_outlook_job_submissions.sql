-- Keep the latest run per section visible even when fast search fills the run history.
create view public.job_latest_workflow_runs with (security_invoker = true) as
select distinct on (r.workspace_id, r.section)
  r.workspace_id, r.section, r.status, r.started_at, r.completed_at, r.submitted_count
from public.job_workflow_runs r
order by r.workspace_id, r.section, r.started_at desc, r.id desc;

revoke all on public.job_latest_workflow_runs from public, anon;
grant select on public.job_latest_workflow_runs to authenticated, service_role;

-- Reserve one Outlook send before crossing the provider boundary. A reservation is
-- reconciled from Sent Items and is never automatically sent a second time.
create function public.job_outlook_reserve_connector_send(
  p_workspace uuid,
  p_job uuid,
  p_account text,
  p_recipient text,
  p_subject text,
  p_body text
) returns uuid
language plpgsql
set search_path = ''
as $function$
declare
  reservation uuid;
begin
  perform pg_advisory_xact_lock(hashtext(p_workspace::text), hashtext('job-outlook-connector-send'));

  insert into public.job_outlook_queue(
    workspace_id, job_id, recipient_email, subject, body_text, resume_path,
    execution_provider, status, send_started_at, attempt_count
  )
  select l.workspace_id, l.id, lower(btrim(l.application_email)), p_subject, p_body,
    l.workspace_id::text || '/resume.pdf', 'connector', 'pending_verification', now(), 1
  from public.job_leads l
  join public.job_reviews r on r.workspace_id = l.workspace_id and r.job_id = l.id
  join public.job_system_settings s on s.workspace_id = l.workspace_id
  join public.job_candidate_profiles p on p.workspace_id = l.workspace_id
  where l.workspace_id = p_workspace and l.id = p_job
    and l.status in ('approved', 'applying')
    and r.approved_to_apply and r.meets_mandatory_requirements
    and s.auto_apply_to_suitable_jobs and not s.outlook_auto_send_enabled
    and l.city = any(s.priorities)
    and lower(btrim(p.email)) = lower(btrim(p_account))
    and l.application_channel in ('email', 'both')
    and l.email_verified_at is not null and l.email_verification_source_url ~* '^https://'
    and lower(btrim(l.application_email)) = lower(btrim(p_recipient))
    and exists (
      select 1 from storage.objects o
      where o.bucket_id = 'job-office-resumes' and o.name = l.workspace_id::text || '/resume.pdf'
    )
    and not exists (
      select 1 from public.job_applications a
      join public.job_leads earlier on earlier.workspace_id = a.workspace_id and earlier.id = a.job_id
      where a.workspace_id = l.workspace_id
        and (a.job_id = l.id or earlier.dedupe_fingerprint = l.dedupe_fingerprint)
        and a.status not in ('not_started', 'draft', 'blocked')
    )
    and not exists (
      select 1 from public.job_prior_submissions h
      where h.workspace_id = l.workspace_id and lower(btrim(h.recipient_email)) = lower(btrim(p_recipient))
        and lower(btrim(h.email_subject)) = lower(btrim(p_subject))
    )
    and not exists (
      select 1 from public.job_outlook_queue q
      join public.job_leads earlier on earlier.workspace_id = q.workspace_id and earlier.id = q.job_id
      where q.workspace_id = l.workspace_id
        and earlier.dedupe_fingerprint = l.dedupe_fingerprint
        and q.status not in ('failed', 'cancelled')
    )
  on conflict (workspace_id, job_id) do nothing
  returning id into reservation;

  return reservation;
end;
$function$;

revoke execute on function public.job_outlook_reserve_connector_send(uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.job_outlook_reserve_connector_send(uuid, uuid, text, text, text, text)
  to service_role;

CREATE OR REPLACE FUNCTION public.job_outlook_confirm_sent(p_queue uuid, p_message_id text, p_sent_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  item public.job_outlook_queue%rowtype;
  application uuid;
  evidence text;
  source_name text;
begin
  select * into item from public.job_outlook_queue where id = p_queue and (
    (execution_provider = 'graph' and status = 'pending_verification')
    or (execution_provider = 'connector' and status = 'drafted' and outlook_draft_id is not null)
    or (execution_provider = 'connector' and status = 'pending_verification' and send_started_at is not null)
  ) for update;
  if not found then return false; end if;
  if nullif(btrim(p_message_id), '') is null or p_sent_at is null then
    raise exception 'Sent Items evidence is required';
  end if;
  if item.execution_provider = 'connector' and item.status = 'pending_verification'
      and p_sent_at < item.send_started_at - interval '5 seconds' then
    raise exception 'Sent Items evidence predates the reserved send';
  end if;
  if exists (select 1 from public.job_prior_submissions
    where workspace_id = item.workspace_id and message_id = p_message_id) then
    raise exception 'Sent Items evidence has already been recorded';
  end if;
  source_name := case when item.execution_provider = 'connector' then 'chatgpt_outlook_sent_items' else 'graph_sent_items' end;
  evidence := 'Outlook Sent Items message ' || p_message_id || ' with attachment. Sent at ' || p_sent_at::text;
  insert into public.job_applications(workspace_id, job_id, method, status, submitted_at,
    confirmation_evidence, resume_version, application_notes, next_action_at)
  values (item.workspace_id, item.job_id, 'email', 'submitted', p_sent_at, evidence, 'private resume.pdf',
    'Outlook Sent Items matched the verified recipient and subject. Employer reply pending.', p_sent_at + interval '7 days')
  on conflict (workspace_id, job_id) do update set
    method = 'email', status = 'submitted', submitted_at = excluded.submitted_at,
    confirmation_evidence = excluded.confirmation_evidence, resume_version = excluded.resume_version,
    application_notes = excluded.application_notes, blocked_reason = null, next_action_at = excluded.next_action_at
  where job_applications.status in ('not_started', 'draft', 'blocked')
  returning id into application;
  if application is null then
    select id into strict application from public.job_applications
    where workspace_id = item.workspace_id and job_id = item.job_id;
  end if;
  insert into public.job_prior_submissions(workspace_id, message_id, recipient_email, email_subject,
    sent_at, source, linked_application_id)
  values (item.workspace_id, p_message_id, item.recipient_email, item.subject, p_sent_at, source_name, application);
  insert into public.job_messages(workspace_id, application_id, external_message_id, channel, direction,
    sender_or_recipient, subject, message_summary, status, occurred_at)
  values (item.workspace_id, application, p_message_id, 'email', 'outgoing', item.recipient_email, item.subject,
    'Verified matching message with an attachment in Outlook Sent Items.', 'sent', p_sent_at);
  insert into public.job_activity(workspace_id, job_id, application_id, actor_section, event_type, note, event_data)
  values (item.workspace_id, item.job_id, application, 'applying',
    case when item.execution_provider = 'connector' then 'outlook_connector_sent_verified' else 'outlook_graph_sent_verified' end,
    'Outlook Sent Items verified.', jsonb_build_object('queue_id', item.id, 'sent_item_id', p_message_id));
  update public.job_leads set status = 'applied' where id = item.job_id and workspace_id = item.workspace_id
    and status in ('approved', 'applying');
  update public.job_outlook_queue set status = 'sent', confirmed_at = now(), graph_sent_item_id = p_message_id,
    lease_until = null, updated_at = now(), last_error = null where id = item.id;
  return true;
end;
$function$
;
