create or replace function public.job_claim_due_sources(p_limit integer, p_workspace uuid)
returns setof public.job_search_sources
language sql
set search_path = ''
as $$
  with chosen as (
    select s.id
    from public.job_search_sources s
    where s.workspace_id = p_workspace and s.is_enabled
      and (s.last_started_at is null or s.last_started_at <= now() - interval '3 minutes')
    order by s.next_check_at, s.id
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 4), 4))
  )
  update public.job_search_sources s
  set next_check_at = now() + interval '10 minutes', last_started_at = now()
  from chosen where s.id = chosen.id
  returning s.*;
$$;
revoke execute on function public.job_claim_due_sources(integer, uuid) from public, anon, authenticated;
grant execute on function public.job_claim_due_sources(integer, uuid) to service_role;

create or replace function public.job_outlook_enqueue_ready()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  target uuid;
  total integer := 0;
begin
  for target in
    select s.workspace_id from public.job_system_settings s
    join public.job_outlook_connections c on c.workspace_id = s.workspace_id
    where s.outlook_auto_send_enabled and c.status = 'connected'
      and exists (
        select 1 from storage.objects o
        where o.bucket_id = 'job-office-resumes' and o.name = s.workspace_id::text || '/resume.pdf'
      )
  loop
    total := total + public.job_outlook_enqueue_for_workspace(target);
  end loop;
  return total;
end;
$$;

create or replace function public.job_outlook_claim_ready(p_limit integer default 3)
returns setof public.job_outlook_queue
language sql
set search_path = ''
as $$
  with chosen as (
    select q.id
    from public.job_outlook_queue q
    join public.job_system_settings s on s.workspace_id = q.workspace_id
    join public.job_outlook_connections c on c.workspace_id = q.workspace_id
    where s.outlook_auto_send_enabled and c.status = 'connected'
      and q.status = 'queued' and q.next_attempt_at <= now() and q.attempt_count = 0
      and not exists (
        select 1 from public.job_outlook_queue other
        where other.workspace_id = q.workspace_id and lower(other.recipient_email) = lower(q.recipient_email)
          and (other.status in ('claimed', 'pending_verification', 'manual_review', 'sent')
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
$$;

create or replace function public.job_outlook_confirm_sent(p_queue uuid, p_message_id text, p_sent_at timestamptz)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  item public.job_outlook_queue%rowtype;
  application uuid;
  evidence text;
begin
  select * into item from public.job_outlook_queue where id = p_queue and status = 'pending_verification' for update;
  if not found then return false; end if;
  if nullif(btrim(p_message_id), '') is null or p_sent_at is null then
    raise exception 'Sent Items evidence is required';
  end if;
  if exists (select 1 from public.job_prior_submissions
    where workspace_id = item.workspace_id and message_id = p_message_id) then
    raise exception 'Sent Items evidence has already been recorded';
  end if;
  evidence := 'Microsoft Graph Sent Items message ' || p_message_id || ' with attachment. Sent at ' || p_sent_at::text;
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
  values (item.workspace_id, p_message_id, item.recipient_email, item.subject, p_sent_at, 'graph_sent_items', application);
  insert into public.job_messages(workspace_id, application_id, external_message_id, channel, direction,
    sender_or_recipient, subject, message_summary, status, occurred_at)
  values (item.workspace_id, application, p_message_id, 'email', 'outgoing', item.recipient_email, item.subject,
    'Verified matching message with an attachment in Outlook Sent Items.', 'sent', p_sent_at);
  insert into public.job_activity(workspace_id, job_id, application_id, actor_section, event_type, note, event_data)
  values (item.workspace_id, item.job_id, application, 'applying', 'outlook_graph_sent_verified',
    'Microsoft Graph Sent Items verified.', jsonb_build_object('queue_id', item.id, 'sent_item_id', p_message_id));
  update public.job_leads set status = 'applied' where id = item.job_id and workspace_id = item.workspace_id
    and status in ('approved', 'applying');
  update public.job_outlook_queue set status = 'sent', confirmed_at = now(), graph_sent_item_id = p_message_id,
    lease_until = null, updated_at = now(), last_error = null where id = item.id;
  return true;
end;
$$;
revoke execute on function public.job_outlook_confirm_sent(uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.job_outlook_confirm_sent(uuid, text, timestamptz) to service_role;

create or replace function public.job_outlook_record_reply(p_workspace uuid, p_application uuid, p_message_id text,
  p_sender text, p_subject text, p_received_at timestamptz)
returns boolean
language sql
set search_path = ''
as $$
  with inserted as (
    insert into public.job_messages(workspace_id, application_id, external_message_id, channel, direction,
      sender_or_recipient, subject, message_summary, status, requires_user_action, occurred_at)
    values (p_workspace, p_application, p_message_id, 'email', 'incoming', p_sender, p_subject,
      'Outlook reply matched to a recorded application.', 'received', true, p_received_at)
    on conflict (workspace_id, channel, external_message_id) where external_message_id is not null
    do nothing
    returning id
  )
  select exists (select 1 from inserted);
$$;
revoke execute on function public.job_outlook_record_reply(uuid, uuid, text, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.job_outlook_record_reply(uuid, uuid, text, text, text, timestamptz) to service_role;

create or replace function public.job_outlook_record_followup(p_workspace uuid, p_started_at timestamptz,
  p_checked integer, p_found integer, p_result text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  result_status text := case p_result when 'completed' then 'completed' when 'partial' then 'partial' else 'failed' end;
  outcome text := case p_result
    when 'completed' then 'فُحص بريد Outlook المرتبط بالتقديمات. الردود الجديدة: ' || p_found
    when 'partial' then 'اكتمل فحص أحدث رسائل Outlook جزئيًا. الردود الجديدة: ' || p_found
    else 'تعذر فحص Outlook. تحقق من حالة التفويض في مكتب المدير.'
  end;
begin
  insert into public.job_workflow_runs(workspace_id, section, run_date, status, found_count, screened_count,
    errors_count, notes, started_at, completed_at)
  values (p_workspace, 'followup', (p_started_at at time zone 'Asia/Riyadh')::date, result_status, p_found, p_checked,
    case when result_status = 'failed' then 1 else 0 end, 'Outlook Graph inbox sync', p_started_at, now());
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
$$;
revoke execute on function public.job_outlook_record_followup(uuid, timestamptz, integer, integer, text) from public, anon, authenticated;
grant execute on function public.job_outlook_record_followup(uuid, timestamptz, integer, integer, text) to service_role;

CREATE OR REPLACE FUNCTION public.job_process_queued_manager_commands(p_limit integer DEFAULT 12)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 task record; n int:=0; total_backlog int; screened int; submissions int; newq int; healthy boolean;
 target_status text; outcome text; info jsonb; is_enabled boolean; connected boolean;
begin
 update public.job_manager_commands
 set status='failed',last_error='تجاوز الأمر وقت التنفيذ. أعد الطلب إن لزم.',
     completed_at=now(),updated_at=now()
 where action in ('search_now','dispatch_all') and status='running' and started_at < now()-interval '5 minutes';
 for task in
  select id,workspace_id,target_section,action,instruction,created_at from public.job_manager_commands
  where status='queued'
    and (action<>'followup_urgent' or created_at < now()-interval '15 minutes'
      or not exists (
        select 1 from public.job_outlook_connections c
        where c.workspace_id=job_manager_commands.workspace_id and c.status='connected'
      ))
  order by priority desc,created_at
  for update skip locked
  limit least(greatest(coalesce(p_limit,12),1),25)
 loop
   update public.job_manager_commands set status='running',started_at=now(),updated_at=now() where id=task.id;
   n:=n+1; info:='{}'::jsonb; target_status:='completed';outcome:='';
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
     else
       target_status:='failed';
       outcome:='لم أتمكن من التقديم تلقائيًا: Microsoft Graph غير مرتبط ومفعّل على هذا الخادم؛ كما أن وظائف بوابات الشركات تحتاج جلسة تقديم حقيقية. اتصال Outlook داخل ChatGPT منفصل عن الخادم. لا توجد رسالة مرسلة بسبب هذا التكليف.';
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
            else 'بانتظار ربط البريد.' end;
     info:=jsonb_build_object('unreviewed',total_backlog,'verified_submissions',submissions,'outlook_connected',connected,'outlook_enabled',coalesce(is_enabled,false));
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
end $function$
;
