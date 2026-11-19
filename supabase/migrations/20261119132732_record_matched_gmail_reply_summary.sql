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
    insert into public.job_messages(workspace_id,application_id,external_message_id,channel,direction,sender_or_recipient,subject,message_summary,status,requires_user_action,occurred_at)
      values(p_workspace,app,'gmail:'||m.id,'email','incoming',left(m.sender,254),left(m.subject,700),'رد مرتبط بطلب التوظيف عبر Gmail.','received',true,m.received_at)
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
