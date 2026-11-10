alter table public.job_outlook_queue
  add column execution_provider text not null default 'graph'
    check (execution_provider in ('graph', 'connector')),
  add column outlook_draft_id text;

alter table public.job_outlook_queue drop constraint job_outlook_queue_status_check;
alter table public.job_outlook_queue add constraint job_outlook_queue_status_check
  check (status in ('queued','claimed','pending_verification','drafted','sent','blocked','manual_review','failed','cancelled'));

create function public.job_outlook_connector_state(p_workspace uuid)
returns table(status text, started_at timestamptz, completed_at timestamptz, found_count integer, is_recent boolean)
language sql stable
set search_path = ''
as $$
  select r.status, r.started_at, r.completed_at, r.found_count,
    coalesce(r.status in ('completed','partial') and r.completed_at >= now()-interval '3 hours', false)
  from public.job_workflow_runs r
  where r.workspace_id = p_workspace and r.section = 'followup' and r.notes = 'Outlook connector sync'
  order by r.started_at desc, r.id desc limit 1;
$$;
revoke execute on function public.job_outlook_connector_state(uuid) from public, anon, authenticated;
grant execute on function public.job_outlook_connector_state(uuid) to service_role;

create function public.job_outlook_claim_connector_drafts(p_workspace uuid)
returns setof public.job_outlook_queue
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from public.job_outlook_connector_state(p_workspace) where is_recent) then
    return;
  end if;

  update public.job_outlook_queue
  set status = 'manual_review', lease_until = null, updated_at = now(),
      last_error = 'تحقق من مسودات Outlook قبل إعادة التجهيز.'
  where workspace_id = p_workspace and execution_provider = 'connector'
    and status = 'claimed' and lease_until < now();

  return query
  with chosen as (
    select q.id,
      coalesce(l.status in ('approved','applying')
        and r.approved_to_apply and r.meets_mandatory_requirements is distinct from false
        and l.application_channel in ('email','both') and l.email_verified_at is not null
        and l.email_verification_source_url ~* '^https://'
        and lower(btrim(l.application_email)) = q.recipient_email
        and not exists (select 1 from public.job_applications a
          where a.workspace_id = q.workspace_id and a.job_id = q.job_id)
        and not exists (select 1 from public.job_prior_submissions h
          where h.workspace_id = q.workspace_id and lower(btrim(h.recipient_email)) = q.recipient_email), false) as eligible
    from public.job_outlook_queue q
    join public.job_leads l on l.workspace_id = q.workspace_id and l.id = q.job_id
    left join public.job_reviews r on r.workspace_id = q.workspace_id and r.job_id = q.job_id
    where q.workspace_id = p_workspace and q.execution_provider = 'connector'
      and q.status = 'queued' and q.attempt_count = 0 and q.next_attempt_at <= now()
      and not exists (
        select 1 from public.job_outlook_queue other
        where other.workspace_id = q.workspace_id and lower(other.recipient_email) = q.recipient_email
          and (other.status in ('claimed','pending_verification','drafted','manual_review','sent')
            or (other.status = 'queued' and (other.created_at,other.id) < (q.created_at,q.id)))
      )
    order by q.created_at, q.id
    for update of q skip locked
    limit 2
  ), processed as (
    update public.job_outlook_queue q
    set status = case when chosen.eligible then 'claimed' else 'blocked' end,
        lease_until = case when chosen.eligible then now()+interval '15 minutes' end,
        attempt_count = q.attempt_count + case when chosen.eligible then 1 else 0 end,
        last_error = case when not chosen.eligible then 'الطلب يحتاج إعادة التحقق من اعتماده أو عنوان التوظيف.' end,
        updated_at = now()
    from chosen where q.id = chosen.id
    returning q.*
  )
  select * from processed where status = 'claimed';
end;
$$;
revoke execute on function public.job_outlook_claim_connector_drafts(uuid) from public, anon, authenticated;
grant execute on function public.job_outlook_claim_connector_drafts(uuid) to service_role;

create function public.job_outlook_record_connector_draft(p_workspace uuid, p_queue uuid, p_draft_id text)
returns boolean
language sql
set search_path = ''
as $$
  with updated as (
    update public.job_outlook_queue
    set status = 'drafted', outlook_draft_id = p_draft_id,
        lease_until = null, last_error = null, updated_at = now()
    where id = p_queue and workspace_id = p_workspace and execution_provider = 'connector'
      and status = 'claimed' and nullif(btrim(p_draft_id),'') is not null
    returning id
  )
  select exists (select 1 from updated);
$$;
revoke execute on function public.job_outlook_record_connector_draft(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.job_outlook_record_connector_draft(uuid, uuid, text) to service_role;

CREATE OR REPLACE FUNCTION public.job_outlook_enqueue_for_workspace(p_workspace uuid, p_provider text)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare c integer;
begin
 if p_provider is null or p_provider not in ('graph','connector') then
   raise exception 'Unsupported Outlook provider';
 end if;
 insert into public.job_outlook_queue(workspace_id,job_id,recipient_email,subject,body_text,resume_path,execution_provider)
 select l.workspace_id,l.id,lower(btrim(l.application_email)),
   'Application – '||left(l.job_title,160)||' | Computer Engineering | '||l.city,
   case when lower(l.job_title) like '%expression of interest%' then
    'Dear Recruitment Team,'||E'\n\n'||'I would like to express interest in suitable engineering and technology positions at '||l.company||' in '||l.city||'.'
   else 'Dear Hiring Team,'||E'\n\n'||'I am applying for the '||l.job_title||' position in '||l.city||' at '||l.company||'.'
   end || E'\n\n'||'I hold a Bachelor''s degree in Computer Engineering from Taif University. My cooperative training at Smart Methods included technical projects across AI and robotics, electronics and IoT, and web development.'||
 E'\n\n'||'Please find my CV attached for your consideration.'||E'\n\n'||'Best regards,'||E'\n'||coalesce(nullif(p.full_name,''),'Applicant'),
 l.workspace_id::text||'/resume.pdf',p_provider
 from public.job_leads l
 join public.job_reviews r on r.job_id=l.id and r.workspace_id=l.workspace_id
 join public.job_candidate_profiles p on p.workspace_id=l.workspace_id
 where l.workspace_id=p_workspace and l.status in ('approved','applying')
 and r.approved_to_apply and r.meets_mandatory_requirements is distinct from false
 and l.application_channel in ('email','both')
 and lower(btrim(l.application_email)) ~ '^[a-z0-9._%+-]+@[a-z0-9.-]+[.][a-z]{2,}$'
 and l.email_verified_at is not null
 and l.email_verification_source_url ~* '^https://'
 and not exists(select 1 from public.job_applications a where a.workspace_id=l.workspace_id and a.job_id=l.id)
 and not exists(select 1 from public.job_prior_submissions hist where hist.workspace_id=l.workspace_id and lower(btrim(hist.recipient_email))=lower(btrim(l.application_email)))
 and not exists(select 1 from public.job_outlook_queue qq where qq.workspace_id=l.workspace_id and qq.job_id=l.id)
 on conflict(workspace_id,job_id) do nothing;
 get diagnostics c=row_count;
 return c;
end;
$function$;

revoke execute on function public.job_outlook_enqueue_for_workspace(uuid, text) from public, anon, authenticated;
grant execute on function public.job_outlook_enqueue_for_workspace(uuid, text) to service_role;

create or replace function public.job_outlook_enqueue_for_workspace(p_workspace uuid)
returns integer
language sql
set search_path = ''
as $$
  select public.job_outlook_enqueue_for_workspace(p_workspace, 'graph');
$$;

CREATE OR REPLACE FUNCTION public.job_outlook_claim_ready(p_limit integer DEFAULT 3)
 RETURNS SETOF job_outlook_queue
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  with chosen as (
    select q.id
    from public.job_outlook_queue q
    join public.job_system_settings s on s.workspace_id = q.workspace_id
    join public.job_outlook_connections c on c.workspace_id = q.workspace_id
    where s.outlook_auto_send_enabled and c.status = 'connected' and q.execution_provider = 'graph'
      and q.status = 'queued' and q.next_attempt_at <= now() and q.attempt_count = 0
      and not exists (
        select 1 from public.job_outlook_queue other
        where other.workspace_id = q.workspace_id and lower(other.recipient_email) = lower(q.recipient_email)
          and (other.status in ('claimed', 'pending_verification', 'drafted', 'manual_review', 'sent')
            or (other.status = 'queued' and (other.created_at, other.id) < (q.created_at, q.id)))
      )
    order by q.created_at, q.id
    for update of q skip locked
    limit greatest(1, least(coalesce(p_limit, 3), 5))
  )
  update public.job_outlook_queue q
  set status = 'claimed', lease_until = now() + interval '4 minutes', send_started_at = now(),
      attempt_count = attempt_count + 1, updated_at = now()
  from chosen where q.id = chosen.id
  returning q.*;
$function$;

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
  ) for update;
  if not found then return false; end if;
  if nullif(btrim(p_message_id), '') is null or p_sent_at is null then
    raise exception 'Sent Items evidence is required';
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
  values (item.workspace_id, item.job_id, application, 'applying', 'outlook_graph_sent_verified',
    'Outlook Sent Items verified.', jsonb_build_object('queue_id', item.id, 'sent_item_id', p_message_id));
  update public.job_leads set status = 'applied' where id = item.job_id and workspace_id = item.workspace_id
    and status in ('approved', 'applying');
  update public.job_outlook_queue set status = 'sent', confirmed_at = now(), graph_sent_item_id = p_message_id,
    lease_until = null, updated_at = now(), last_error = null where id = item.id;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.job_outlook_record_followup(p_workspace uuid, p_started_at timestamp with time zone, p_checked integer, p_found integer, p_result text, p_provider text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  result_status text := case p_result when 'completed' then 'completed' when 'partial' then 'partial' else 'failed' end;
  outcome text := case p_result
    when 'completed' then 'فُحص بريد Outlook المرتبط بالتقديمات. الردود الجديدة: ' || p_found
    when 'partial' then 'اكتمل فحص أحدث رسائل Outlook جزئيًا. الردود الجديدة: ' || p_found
    else 'تعذر فحص Outlook. تحقق من حالة التفويض في مكتب المدير.'
  end;
begin
  if p_provider is null or p_provider not in ('graph','connector') then
    raise exception 'Unsupported Outlook provider';
  end if;
  insert into public.job_workflow_runs(workspace_id, section, run_date, status, found_count, screened_count,
    errors_count, notes, started_at, completed_at)
  values (p_workspace, 'followup', (p_started_at at time zone 'Asia/Riyadh')::date, result_status, p_found, p_checked,
    case when result_status = 'failed' then 1 else 0 end, case when p_provider = 'connector' then 'Outlook connector sync' else 'Outlook Graph inbox sync' end, p_started_at, now());
  with processed as (
    update public.job_manager_commands set
      status = case when result_status = 'failed' then 'failed' else 'completed' end,
      result = jsonb_build_object('inbox_status', result_status, 'messages_checked', p_checked, 'new_replies', p_found),
      last_error = case when result_status = 'failed' then outcome else null end,
      started_at = p_started_at, completed_at = now(), updated_at = now()
    where workspace_id = p_workspace and action = 'followup_urgent' and status = 'queued' and created_at <= p_started_at
    returning id
  )
  insert into public.job_manager_messages(workspace_id, sender, target_section, body, message_kind, command_id)
  select p_workspace, 'system', 'followup', outcome, 'status', id from processed;
end;
$function$;

revoke execute on function public.job_outlook_record_followup(uuid, timestamptz, integer, integer, text, text) from public, anon, authenticated;
grant execute on function public.job_outlook_record_followup(uuid, timestamptz, integer, integer, text, text) to service_role;

create or replace function public.job_outlook_record_followup(p_workspace uuid, p_started_at timestamptz,
  p_checked integer, p_found integer, p_result text)
returns void
language sql
set search_path = ''
as $$
  select public.job_outlook_record_followup(p_workspace,p_started_at,p_checked,p_found,p_result,'graph');
$$;

CREATE OR REPLACE FUNCTION public.job_process_queued_manager_commands(p_limit integer DEFAULT 12)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 task record; n int:=0; total_backlog int; screened int; submissions int; newq int; connector boolean;
 target_status text; outcome text; info jsonb; is_enabled boolean; connected boolean;
begin
 update public.job_manager_commands
 set status='failed',last_error='تجاوز الأمر وقت التنفيذ. أعد الطلب إن لزم.',
     completed_at=now(),updated_at=now()
 where action in ('search_now','dispatch_all') and status='running' and started_at < now()-interval '5 minutes';
 for task in
  select id,workspace_id,target_section,action,instruction,created_at from public.job_manager_commands
  where status='queued'
    and (action<>'followup_urgent' or created_at < now()-interval '2 hours'
      or (not exists (
        select 1 from public.job_outlook_connector_state(job_manager_commands.workspace_id) s where s.is_recent
      ) and (created_at < now()-interval '15 minutes' or not exists (
        select 1 from public.job_outlook_connections c
        where c.workspace_id=job_manager_commands.workspace_id and c.status='connected'
      ))))
  order by priority desc,created_at
  for update skip locked
  limit least(greatest(coalesce(p_limit,12),1),25)
 loop
   update public.job_manager_commands set status='running',started_at=now(),updated_at=now() where id=task.id;
   n:=n+1; info:='{}'::jsonb; target_status:='completed';outcome:='';
   select exists(select 1 from public.job_outlook_connector_state(task.workspace_id) s where s.is_recent) into connector;
   if task.action='screening_urgent' then
     screened:=public.job_screen_obvious_mismatch();
     select count(*) into total_backlog from public.job_leads l
      where l.workspace_id=task.workspace_id and not exists(select 1 from public.job_reviews r where r.job_id=l.id);
     outcome:='تم تنفيذ تدقيق آلي أولي فقط على الحالات الواضحة. استبعاد جديد: '||screened||
       '؛ ما زال '||total_backlog||' إعلانًا بحاجة إلى مراجعة فعلية لشروط التوظيف. لم تُعتمد أي وظيفة للتقديم آليًا.';
     info:=jsonb_build_object('stage','preliminary_only','new_rejections',screened,'remaining_manual_reviews',total_backlog,'approved',0,'actual_full_screening',false);
   elsif task.action='applications_urgent' then
     select coalesce(s.outlook_auto_send_enabled,false) into is_enabled from public.job_system_settings s where s.workspace_id=task.workspace_id;
     select exists(select 1 from public.job_outlook_connections c where c.workspace_id=task.workspace_id and c.status='connected') into connected;
     if is_enabled and connected then
       newq:=public.job_outlook_enqueue_for_workspace(task.workspace_id);
       outcome:='تم تجهيز '||newq||' طلب بريد مؤهل في طابور Microsoft Graph. لا يوجد دليل على إرسال جديد من هذا الأمر قبل تحقق الرسالة في Outlook Sent Items. بوابات الشركات تحتاج محرك متصفح مستقل.';
       info:=jsonb_build_object('email_prepared',newq,'emails_sent',0,'portal_submissions',0,'stage','queued_for_independent_worker');
     elsif connector then
       newq:=public.job_outlook_enqueue_for_workspace(task.workspace_id,'connector');
       outcome:='تمت إضافة '||newq||' طلب إلى طابور المسودات. تظهر المسودة في Outlook بعد جولة المتابعة لتراجعها وترسلها بنفسك.';
       info:=jsonb_build_object('email_prepared',newq,'stage','queued_for_outlook_draft');
     else
       target_status:='failed';
       outcome:='تجهيز طلبات البريد يحتاج اتصال Outlook نشطًا. يمكن فتح بوابات الشركات من قائمة الوظائف المعتمدة.';
       info:=jsonb_build_object('emails_sent',0,'portal_submissions',0,'reason','independent_email_or_portal_worker_not_available');
     end if;
   elsif task.action='followup_urgent' then
     target_status:='failed';
     outcome:='لم يكتمل فحص ردود Outlook. راجع حالة ربط البريد في مكتب المدير ثم أعد التكليف.';
     info:=jsonb_build_object('incoming_messages_checked',0,'reason','outlook_inbox_not_ready');
   elsif task.action='audit_now' then
     select count(*) into total_backlog from public.job_leads l
      where l.workspace_id=task.workspace_id and not exists(select 1 from public.job_reviews r where r.job_id=l.id);
     select count(*) into submissions from public.job_applications a
      where a.workspace_id=task.workspace_id and a.status='submitted';
     select exists(select 1 from public.job_outlook_connections c where c.workspace_id=task.workspace_id and c.status='connected') into connected;
     select s.outlook_auto_send_enabled into is_enabled from public.job_system_settings s where s.workspace_id=task.workspace_id;
     outcome:='تقرير السجل: '||total_backlog||' وظيفة بحاجة إلى تدقيق، '||submissions||' تقديمات موثقة. Outlook '||
       case when connected and is_enabled then 'متصل والإرسال مفعّل.'
            when connected then 'متصل والإرسال متوقف.'
            when connector then 'متصل عبر ChatGPT للمتابعة والمسودات.'
            else 'بانتظار ربط البريد.' end;
     info:=jsonb_build_object('unreviewed',total_backlog,'verified_submissions',submissions,'outlook_connected',connected,'outlook_connector_active',connector,'outlook_enabled',coalesce(is_enabled,false));
   elsif task.action='general_directive' then
     target_status:='failed';
     outcome:='التوجيه الحر محفوظ، لكنه يحتاج موظفًا متصلًا فعليًا لتنفيذه؛ لا يوجد محرك مستقل متاح لتنفيذ تعليمات حرة من هذا النوع.';
     info:=jsonb_build_object('reason','freeform_agent_unavailable');
   else
     target_status:='failed';
     outcome:='لا توجد خدمة خلفية تنفذ هذا النوع من الأوامر؛ يرجى استخدام زر البحث الفوري أو الميزة المتخصصة المتاحة.';
     info:=jsonb_build_object('reason','no_handler');
   end if;
   update public.job_manager_commands
    set status=target_status,result=info,
        last_error=case when target_status='failed' then outcome else null end,
        completed_at=now(),updated_at=now()
    where id=task.id;
   insert into public.job_manager_messages(workspace_id,sender,target_section,body,message_kind,command_id)
    values(task.workspace_id,'system',task.target_section,outcome,'status',task.id);
   insert into public.job_activity(workspace_id,actor_section,event_type,note,event_data)
    values(task.workspace_id,'manager','manager_command_result',
      left(outcome,480),jsonb_build_object('command_id',task.id,'status',target_status,'actual_result',info));
 end loop;
 return n;
end $function$;
