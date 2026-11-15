-- Leave expedited requests for the scheduled application worker when it owns sending.
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
     select coalesce(s.outlook_auto_send_enabled,false),coalesce(s.auto_apply_to_suitable_jobs,false)
       into is_enabled,auto_apply from public.job_system_settings s where s.workspace_id=task.workspace_id;
     select exists(select 1 from public.job_outlook_connections c where c.workspace_id=task.workspace_id and c.status='connected') into connected;
     if is_enabled and connected then
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
     outcome:='لم يكتمل فحص ردود Outlook. راجع حالة ربط البريد في مكتب المدير ثم أعد التكليف.';
     info:=jsonb_build_object('incoming_messages_checked',0,'reason','outlook_inbox_not_ready');
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
