alter table public.job_gmail_connections
  add column if not exists worker_seen_at timestamptz,
  add column if not exists inbox_checked_at timestamptz;
alter table public.job_gmail_outbox
  add column if not exists provider_message_id text,
  add column if not exists gmail_thread_id text;
alter table public.job_reviews
  add column if not exists application_subject text,
  add column if not exists application_body text;

create or replace function public.job_gmail_eligible(p_workspace uuid)
returns setof public.job_leads language sql stable set search_path='' as $$
  select l.* from public.job_leads l
  join public.job_reviews r on (r.workspace_id,r.job_id)=(l.workspace_id,l.id)
  join public.job_system_settings s on s.workspace_id=l.workspace_id
  join public.job_gmail_connections g on g.workspace_id=l.workspace_id
  where l.workspace_id=p_workspace and l.status in ('approved','applying')
    and l.application_channel in ('email','both') and r.approved_to_apply and r.meets_mandatory_requirements
    and s.auto_apply_to_suitable_jobs and not s.outlook_auto_send_enabled
    and g.connected_at is not null and g.send_enabled
    and lower(btrim(l.city)) in (select lower(btrim(city)) from unnest(s.priorities) city)
    and l.email_verified_at is not null and l.email_verification_source_url ~* '^https://[^/ ]+'
    and btrim(l.application_email) ~* '^[^[:space:]@,;<>]+@[^[:space:]@,;<>]+[.][a-z]{2,}$'
    and exists(select from storage.objects o where o.bucket_id='job-office-resumes'
      and o.name=p_workspace::text||'/resume.pdf' and o.metadata->>'mimetype'='application/pdf'
      and (o.metadata->>'size')::bigint>0)
    and not exists(select from public.job_applications a join public.job_leads old on old.id=a.job_id
      where a.workspace_id=p_workspace and (old.id=l.id or old.dedupe_fingerprint=l.dedupe_fingerprint)
      and (a.submitted_at is not null or a.status not in ('not_started','draft')))
    and not exists(select from public.job_outlook_queue q join public.job_leads old on old.id=q.job_id
      where q.workspace_id=p_workspace and q.status not in ('failed','cancelled')
      and (old.id=l.id or old.dedupe_fingerprint=l.dedupe_fingerprint))
    and not exists(select from public.job_gmail_outbox q join public.job_leads old on old.id=q.job_id
      where q.workspace_id=p_workspace and q.job_id<>l.id and q.status<>'cancelled'
      and old.dedupe_fingerprint=l.dedupe_fingerprint)
    and not exists(select from public.job_prior_submissions h
      where h.workspace_id=p_workspace and lower(btrim(h.recipient_email))=lower(btrim(l.application_email))
      and (position(lower(btrim(l.job_title)) in lower(h.email_subject))>0
        or lower(btrim(h.email_subject))=lower(btrim(r.application_subject))))
$$;

create or replace function public.job_gmail_fill_queue(p_workspace uuid)
returns integer language plpgsql set search_path='' as $$
declare added integer;
begin
  perform pg_advisory_xact_lock(hashtext(p_workspace::text),hashtext('job-gmail-dispatch'));
  update public.job_gmail_outbox set status='uncertain',last_error='confirmation_pending',updated_at=now()
    where workspace_id=p_workspace and status='claimed' and claimed_at<now()-interval '45 minutes';
  with candidates as (
    select distinct on(l.dedupe_fingerprint) l.*, r.application_subject, r.application_body, p.full_name
    from public.job_gmail_eligible(p_workspace) l
    join public.job_reviews r on r.job_id=l.id
    join public.job_candidate_profiles p on p.workspace_id=l.workspace_id
    order by l.dedupe_fingerprint, l.email_verified_at desc, l.id
  )
  insert into public.job_gmail_outbox(workspace_id,job_id,recipient_email,subject,body_text,resume_path)
  select workspace_id,id,lower(btrim(application_email)),
    coalesce(nullif(btrim(application_subject),''),'Application for '||job_title||' | '||full_name),
    coalesce(nullif(btrim(application_body),''),
    'Dear '||company||' hiring team,'||E'\n\n'||'I am applying for the '||job_title||' position in '||city||
    '. I hold a Bachelor''s degree in Computer Engineering from Taif University. '||
    case when job_title ~* '(network|support|systems|infrastructure|telecom)' then
      'My technical work includes Linux systems, network troubleshooting, and integrating connected devices.'
    when job_title ~* '(software|developer|web|programmer)' then
      'I have developed web applications and worked with Python, JavaScript, and REST APIs.'
    when job_title ~* '(machine learning|artificial intelligence|data|robotics|AI engineer)' then
      'I have applied Python and computer vision in robotics projects during my cooperative training.'
    else 'My cooperative training at Smart Methods included embedded systems, electronics, and technical problem-solving.' end||
    E'\n\nMy CV is attached. I would welcome the opportunity to discuss the role.\n\nBest regards,\n'||full_name),
    workspace_id::text||'/resume.pdf' from candidates
  on conflict(job_id) do update set recipient_email=excluded.recipient_email, subject=excluded.subject,
    body_text=excluded.body_text,resume_path=excluded.resume_path,updated_at=now()
    where job_gmail_outbox.status='queued' and (job_gmail_outbox.recipient_email,job_gmail_outbox.subject,job_gmail_outbox.body_text)
    is distinct from (excluded.recipient_email,excluded.subject,excluded.body_text);
  get diagnostics added=row_count;
  return added;
end $$;

create or replace function public.job_gmail_claim_one(p_workspace uuid)
returns setof public.job_gmail_outbox language plpgsql set search_path='' as $$
declare cap integer; used integer; day_start timestamptz; day_end timestamptz; candidate uuid;
begin
  perform pg_advisory_xact_lock(hashtext(p_workspace::text),hashtext('job-gmail-dispatch'));
  perform public.job_gmail_fill_queue(p_workspace);
  select greatest(0,s.daily_submission_target),
    date_trunc('day',now() at time zone s.timezone) at time zone s.timezone,
    (date_trunc('day',now() at time zone s.timezone)+interval '1 day') at time zone s.timezone
    into cap,day_start,day_end from public.job_system_settings s where s.workspace_id=p_workspace;
  select (select count(*) from public.job_applications a where a.workspace_id=p_workspace
    and a.submitted_at>=day_start and a.submitted_at<day_end)
    +(select count(*) from public.job_gmail_outbox q where q.workspace_id=p_workspace
    and q.status in ('claimed','uncertain') and q.claimed_at>=day_start and q.claimed_at<day_end) into used;
  if cap is null or used>=cap then return; end if;
  select q.id into candidate from public.job_gmail_outbox q
    join public.job_gmail_eligible(p_workspace) l on l.id=q.job_id
    where q.workspace_id=p_workspace and q.status='queued'
      and q.recipient_email=lower(btrim(l.application_email))
      and not exists(select from public.job_prior_submissions h where h.workspace_id=p_workspace
      and lower(btrim(h.recipient_email))=q.recipient_email and lower(btrim(h.email_subject))=lower(btrim(q.subject)))
    order by q.created_at,q.id limit 1 for update of q skip locked;
  if candidate is not null then
    return query update public.job_gmail_outbox set status='claimed',claimed_at=now(),updated_at=now()
       where id=candidate and status='queued' returning *;
  end if;
end $$;

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
    item.resume_path,'Gmail') on conflict(job_id) do update set
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

create or replace function public.job_gmail_reconcile_sent(p_workspace uuid,p_queue uuid,p_account text,p_recipient text,p_subject text,p_sent timestamptz,p_message text,p_thread text,p_pdf boolean)
returns boolean language plpgsql set search_path='' as $$
declare q public.job_gmail_outbox;
begin
  select * into q from public.job_gmail_outbox where id=p_queue and workspace_id=p_workspace for update;
  if not found or q.status not in('claimed','uncertain','sent') or p_pdf is not true or q.claimed_at is null
    or p_sent is null or p_sent<date_trunc('second',q.claimed_at) or p_sent>now()+interval '1 minute'
    or nullif(btrim(p_recipient),'') is null or lower(btrim(p_recipient))<>lower(q.recipient_email)
    or p_subject is distinct from q.subject or coalesce(p_message,'') !~ '^[a-fA-F0-9]+$'
    or coalesce(p_thread,'') !~ '^[a-fA-F0-9]+$'
    or (q.provider_message_id is not null and q.provider_message_id<>p_message) then return false; end if;
  if not public.job_gmail_ack_sent(p_workspace,q.id,p_account) then return false; end if;
  update public.job_gmail_outbox set provider_message_id=p_message,gmail_thread_id=p_thread,accepted_at=p_sent,updated_at=now() where id=q.id;
  update public.job_applications set submitted_at=p_sent,confirmation_evidence='Gmail Sent Items, PDF attachment, message '||p_message where workspace_id=p_workspace and job_id=q.job_id;
  update public.job_prior_submissions set sent_at=p_sent where workspace_id=p_workspace and message_id='gmail-queue:'||q.id;
  return true;
end $$;

create unique index if not exists job_gmail_provider_message on public.job_gmail_outbox(workspace_id,provider_message_id) where provider_message_id is not null;

create or replace function public.job_gmail_record_inbox(p_workspace uuid,p_account text,p_checked integer,p_items jsonb,p_started timestamptz)
returns integer language plpgsql set search_path='' as $$
declare m record; app uuid; inserted integer:=0; changed integer;
begin
  if not exists(select from public.job_gmail_connections where workspace_id=p_workspace and lower(btrim(sender_email))=lower(btrim(p_account)))
    or p_checked is null or p_checked<0 or jsonb_typeof(p_items) is distinct from 'array' or p_started is null then raise exception 'Invalid mailbox check'; end if;
  for m in select * from jsonb_to_recordset(p_items) as t(id text,thread_id text,sender text,subject text,received_at timestamptz) loop
    if m.id is null or m.id !~ '^[a-fA-F0-9]+$' or nullif(btrim(m.sender),'') is null or m.received_at is null or m.received_at>now()+interval '1 minute' then continue; end if;
    select case when count(distinct a.id)=1 then min(a.id::text)::uuid end into app
    from public.job_gmail_outbox q join public.job_applications a on a.job_id=q.job_id and a.workspace_id=q.workspace_id
    where q.workspace_id=p_workspace and q.status='sent' and m.received_at>=date_trunc('second',q.accepted_at)
      and lower(btrim(m.sender))<>lower(btrim(p_account))
      and ((q.gmail_thread_id=m.thread_id and length(m.thread_id)>0)
       or (lower(q.recipient_email)=lower(btrim(m.sender)) and lower(btrim(regexp_replace(m.subject,'^([[:space:]]*(re|fw|fwd|رد)[[:space:]]*:[[:space:]]*)+','','i')))=lower(btrim(q.subject))));
    if app is null then continue; end if;
    insert into public.job_messages(workspace_id,application_id,external_message_id,channel,direction,sender_or_recipient,subject,status,requires_user_action,occurred_at)
      values(p_workspace,app,'gmail:'||m.id,'email','incoming',left(m.sender,254),left(m.subject,700),'received',true,m.received_at)
      on conflict do nothing;
    get diagnostics changed=row_count; inserted:=inserted+changed;
  end loop;
  update public.job_gmail_connections set inbox_checked_at=greatest(inbox_checked_at,p_started),updated_at=now() where workspace_id=p_workspace;
  insert into public.job_workflow_runs(workspace_id,section,status,started_at,completed_at,found_count,notes)
    values(p_workspace,'followup','completed',p_started,now(),inserted,'Gmail inbox inspected. Messages examined: '||p_checked);
  update public.job_manager_commands set status='completed',started_at=coalesce(started_at,p_started),completed_at=now(),updated_at=now(),
    result=jsonb_build_object('messages_checked',p_checked,'new_replies',inserted)
    where workspace_id=p_workspace and action='followup_urgent' and status='queued' and created_at<=p_started;
  return inserted;
end $$;

create or replace function public.job_office_mail_state(p_workspace uuid)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object(
   'connected',g.connected_at is not null,'bridge_seen',g.last_seen_at,'worker_seen',g.worker_seen_at,
   'inbox_checked',g.inbox_checked_at,'account',g.sender_email,'enabled',coalesce(g.send_enabled,false),
   'auto_apply',s.auto_apply_to_suitable_jobs,'target',s.daily_submission_target,'timezone',s.timezone,
   'resume',exists(select from storage.objects where bucket_id='job-office-resumes' and name=p_workspace::text||'/resume.pdf' and metadata->>'mimetype'='application/pdf' and (metadata->>'size')::bigint>0),
   'queue',(select coalesce(jsonb_object_agg(status,n),'{}'::jsonb) from (select status,count(*) n from public.job_gmail_outbox where workspace_id=p_workspace group by status) counts),
   'queue_items',(select coalesce(jsonb_agg(to_jsonb(items)),'[]'::jsonb) from (select l.company,l.job_title,q.status,q.updated_at from public.job_gmail_outbox q join public.job_leads l on l.id=q.job_id where q.workspace_id=p_workspace order by q.updated_at desc limit 12) items))
 from public.job_system_settings s left join public.job_gmail_connections g using(workspace_id) where s.workspace_id=p_workspace;
$$;

create or replace function public.job_outlook_guard_gmail() returns trigger language plpgsql set search_path='' as $$
begin
  perform pg_advisory_xact_lock(hashtext(new.workspace_id::text),hashtext('job-gmail-dispatch'));
  if exists(select from public.job_gmail_connections c where c.workspace_id=new.workspace_id and c.send_enabled)
    or exists(select from public.job_gmail_outbox q where q.workspace_id=new.workspace_id and q.job_id=new.job_id and q.status<>'cancelled') then return null; end if;
  return new;
end $$;
create or replace trigger job_outlook_respect_gmail before insert on public.job_outlook_queue for each row execute function public.job_outlook_guard_gmail();

revoke all on function public.job_gmail_eligible(uuid),public.job_gmail_fill_queue(uuid),public.job_gmail_claim_one(uuid),
 public.job_gmail_ack_sent(uuid,uuid,text),public.job_gmail_reconcile_sent(uuid,uuid,text,text,text,timestamptz,text,text,boolean),
 public.job_gmail_record_inbox(uuid,text,integer,jsonb,timestamptz),public.job_office_mail_state(uuid),public.job_outlook_guard_gmail()
 from public,anon,authenticated;
grant execute on function public.job_gmail_eligible(uuid),public.job_gmail_fill_queue(uuid),public.job_gmail_claim_one(uuid),
 public.job_gmail_ack_sent(uuid,uuid,text),public.job_gmail_reconcile_sent(uuid,uuid,text,text,text,timestamptz,text,text,boolean),
 public.job_gmail_record_inbox(uuid,text,integer,jsonb,timestamptz),public.job_office_mail_state(uuid) to service_role;
select cron.schedule('job-office-gmail-queue-5m','*/5 * * * *',
  'select public.job_gmail_fill_queue(workspace_id) from public.job_gmail_connections where connected_at is not null');
CREATE OR REPLACE FUNCTION public.job_process_queued_manager_commands(p_limit integer DEFAULT 12)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 task record; n int:=0; total_backlog int; screened int; submissions int; newq int; connector boolean;
 target_status text; outcome text; info jsonb; is_enabled boolean; connected boolean; auto_apply boolean;
begin
 update public.job_manager_commands
 set status='failed',last_error='تجاوز الأمر وقت التنفيذ. أعد الطلب إن لزم.',
     completed_at=now(),updated_at=now()
 where action in ('search_now','dispatch_all') and status='running' and started_at < now()-interval '5 minutes';
 for task in
  select id,workspace_id,target_section,action,instruction,created_at from public.job_manager_commands
  where status='queued'
    and (action<>'applications_urgent'
      or exists(select from public.job_gmail_connections g where g.workspace_id=job_manager_commands.workspace_id and g.connected_at is not null)
      or created_at < now()-interval '2 hours'
      or not exists (
        select 1 from public.job_system_settings s
        where s.workspace_id=job_manager_commands.workspace_id and s.auto_apply_to_suitable_jobs
      )
      or exists (
        select 1 from public.job_system_settings s
        join public.job_outlook_connections c on c.workspace_id=s.workspace_id
        where s.workspace_id=job_manager_commands.workspace_id and s.outlook_auto_send_enabled and c.status='connected'
      ))
    and (action<>'followup_urgent' or created_at < now()-interval '2 hours'
      or (not exists(select from public.job_gmail_connections g where g.workspace_id=job_manager_commands.workspace_id and g.connected_at is not null)
      and (not exists (
        select 1 from public.job_outlook_connector_state(job_manager_commands.workspace_id) s where s.is_recent
      ) and (created_at < now()-interval '15 minutes' or not exists (
        select 1 from public.job_outlook_connections c
        where c.workspace_id=job_manager_commands.workspace_id and c.status='connected'
      ))))
      )
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
     select coalesce(s.outlook_auto_send_enabled,false),coalesce(s.auto_apply_to_suitable_jobs,false)
       into is_enabled,auto_apply from public.job_system_settings s where s.workspace_id=task.workspace_id;
     select exists(select 1 from public.job_outlook_connections c where c.workspace_id=task.workspace_id and c.status='connected') into connected;
     if exists(select from public.job_gmail_connections g where g.workspace_id=task.workspace_id and g.connected_at is not null) then
       newq:=public.job_gmail_fill_queue(task.workspace_id);
       info:=public.job_office_mail_state(task.workspace_id);
       outcome:=case when not (info->>'enabled')::boolean then 'الإرسال متوقف من إعدادات Gmail.'
          else 'فُحص طابور Gmail. جُهزت '||newq||' رسائل جديدة. يُسجَّل الإرسال عند قبول Gmail للرسالة.' end;
       info:=jsonb_build_object('email_prepared',newq,'queue',info->'queue','emails_sent',0);
     elsif is_enabled and connected then
       newq:=public.job_outlook_enqueue_for_workspace(task.workspace_id);
       outcome:='تم تجهيز '||newq||' طلب بريد مؤهل في طابور Microsoft Graph. لا يوجد دليل على إرسال جديد من هذا الأمر قبل تحقق الرسالة في Outlook Sent Items. بوابات الشركات تحتاج محرك متصفح مستقل.';
       info:=jsonb_build_object('email_prepared',newq,'emails_sent',0,'portal_submissions',0,'stage','queued_for_independent_worker');
     elsif auto_apply then
       target_status:='failed';
       outcome:='انتهت مهلة التكليف قبل أن تُسجّل مهمة التقديم معالجة الطلب.';
       info:=jsonb_build_object('emails_sent',0,'portal_submissions',0,'reason','application_round_timeout');
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
     outcome:=case when exists(select from public.job_gmail_connections g where g.workspace_id=task.workspace_id and g.connected_at is not null) then 'لم يصل فحص وارد Gmail بعد طلب المتابعة.' else 'لم يكتمل فحص ردود Outlook. راجع حالة ربط البريد في مكتب المدير ثم أعد التكليف.' end;
     info:=jsonb_build_object('incoming_messages_checked',0,'reason','inbox_check_overdue');
   elsif task.action='audit_now' then
     select count(*) into total_backlog from public.job_leads l
      where l.workspace_id=task.workspace_id and not exists(select 1 from public.job_reviews r where r.job_id=l.id);
     select count(*) into submissions from public.job_applications a
      where a.workspace_id=task.workspace_id and a.submitted_at is not null;
     select exists(select 1 from public.job_outlook_connections c where c.workspace_id=task.workspace_id and c.status='connected') into connected;
     select s.outlook_auto_send_enabled into is_enabled from public.job_system_settings s where s.workspace_id=task.workspace_id;
     outcome:='تقرير السجل: '||total_backlog||' وظيفة بحاجة إلى تدقيق، '||submissions||' تقديمات موثقة. Outlook '||
       case when connected and is_enabled then 'متصل والإرسال مفعّل.'
            when connected then 'متصل والإرسال متوقف.'
            when connector then 'متصل عبر ChatGPT. تفاصيل الإرسال تظهر في آخر جولة للتقديم.'
            else 'بانتظار ربط البريد.' end;
     info:=jsonb_build_object('unreviewed',total_backlog,'verified_submissions',submissions,'outlook_connected',connected,'outlook_connector_active',connector,'outlook_enabled',coalesce(is_enabled,false));
     if exists(select from public.job_gmail_connections where workspace_id=task.workspace_id and connected_at is not null) then
       outcome:='بانتظار التدقيق '||total_backlog||'، والتقديمات المثبتة '||submissions||'. قناة البريد المهنية Gmail.';
       info:=jsonb_build_object('unreviewed',total_backlog,'verified_submissions',submissions,'mail',public.job_office_mail_state(task.workspace_id)-'account'-'queue_items');
     end if;
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
