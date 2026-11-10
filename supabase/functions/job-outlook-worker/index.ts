import {createClient} from "npm:@supabase/supabase-js@2.57.0";
const URL="https://jclycoagtotikxskgkju.supabase.co";
const SENT_CLOCK_SKEW_MS=30_000;
const res=(v:unknown,status=200)=>new Response(JSON.stringify(v),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});
function b64(bytes:Uint8Array){
 let binary="";
 for(let offset=0;offset<bytes.length;offset+=0x8000)binary+=String.fromCharCode(...bytes.subarray(offset,offset+0x8000));
 return btoa(binary);
}
const bytes=(s:string)=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
const endpoint="https://login.microsoftonline.com/common/oauth2/v2.0/token";
async function cryptoKey(db:any):Promise<CryptoKey>{
 const {data,error}=await db.rpc("job_outlook_aes_key_for_server");
 if(error||!data)throw Error("Missing server-side encrypted token key");
 return crypto.subtle.importKey("raw",bytes(data),{name:"AES-GCM"},false,["encrypt","decrypt"]);
}
async function seal(key:CryptoKey,str:string){
 const iv=crypto.getRandomValues(new Uint8Array(12));
 const cipher=new Uint8Array(await crypto.subtle.encrypt({name:"AES-GCM",iv},key,new TextEncoder().encode(str)));
 return {refresh_token_ciphertext:b64(cipher),refresh_token_iv:b64(iv)};
}
async function open(key:CryptoKey,cipher:string,iv:string){
 const raw=await crypto.subtle.decrypt({name:"AES-GCM",iv:bytes(iv)},key,bytes(cipher));
 return new TextDecoder().decode(raw);
}
async function accessToken(db:any,conn:any,clientId:string,clientSecret:string,key:CryptoKey){
 const refresh=await open(key,conn.refresh_token_ciphertext,conn.refresh_token_iv);
 const payload=new URLSearchParams({client_id:clientId,client_secret:clientSecret,refresh_token:refresh,grant_type:"refresh_token",scope:"openid profile email offline_access User.Read Mail.Send Mail.ReadBasic"});
 const resp=await fetch(endpoint,{method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},body:payload,signal:AbortSignal.timeout(15000)});
 const data=await resp.json().catch(()=>({}));
 if(!resp.ok||!data.access_token){
  if(data.error==="invalid_grant"){
   const {error}=await db.from("job_outlook_connections").update({status:"reauth_required",last_error:"OAuth grant needs renewal",updated_at:new Date().toISOString()})
    .eq("workspace_id",conn.workspace_id).eq("refresh_token_ciphertext",conn.refresh_token_ciphertext);
   if(error)throw Error("Could not record Outlook reconnection state");
   throw Error("Microsoft account needs reconnection");
  }
  throw Error("Microsoft token refresh is unavailable (HTTP "+resp.status+")");
 }
 const update=data.refresh_token?await seal(key,data.refresh_token):{};
 const {data:current,error}=await db.from("job_outlook_connections").update({...update,last_refreshed_at:new Date().toISOString(),last_error:null,updated_at:new Date().toISOString()})
  .eq("workspace_id",conn.workspace_id).eq("refresh_token_ciphertext",conn.refresh_token_ciphertext).eq("status","connected").select("workspace_id").maybeSingle();
 if(error||!current)throw Error("Outlook connection changed while refreshing");
 return data.access_token as string;
}
const safeError=(e:unknown)=>String(e instanceof Error?e.message:e).slice(0,450);
async function graph(access:string,path:string,method="GET",body?:unknown){
 const resp=await fetch("https://graph.microsoft.com/v1.0"+path,{method,headers:{
  Authorization:"Bearer "+access,Accept:"application/json","Content-Type":"application/json",'Prefer':'IdType="ImmutableId"'
 },...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(25000)});
 if(resp.status===202)return {accepted:true};
 const data=await resp.json().catch(()=>({}));
 if(!resp.ok)throw Error("Microsoft Graph HTTP "+resp.status+": "+String(data.error?.code||"unknown"));
 return data;
}
async function sentMatch(access:string,queue:any){
 const results=await graph(access,"/me/mailFolders/sentitems/messages?$select=id,subject,sentDateTime,toRecipients,hasAttachments&$orderby=sentDateTime%20desc&$top=70");
 const email=queue.recipient_email.toLowerCase(),since=Date.parse(queue.send_started_at||queue.created_at)-SENT_CLOCK_SKEW_MS;
 return (results.value||[]).find((x:any)=>
  x.id && x.subject===queue.subject && x.hasAttachments===true &&
  Array.isArray(x.toRecipients) && x.toRecipients.some((r:any)=>String(r.emailAddress?.address||"").toLowerCase()===email) &&
  Date.parse(x.sentDateTime)>=since
 )||null;
}
async function confirm(db:any,queue:any,record:any):Promise<boolean>{
 const {data,error}=await db.rpc("job_outlook_confirm_sent",{
  p_queue:queue.id,p_message_id:record.id,p_sent_at:new Date(record.sentDateTime).toISOString()
 });
 if(error)throw Error("Unable to record verified Outlook submission");
 return data===true;
}
const normalized=(value:unknown)=>String(value??"").trim().toLowerCase();
function replyKey(sender:unknown,subject:unknown){
 return JSON.stringify([normalized(sender),normalized(subject)]);
}
async function scanInbox(db:any,workspace:string,access:string){
 const {data:submissions,error}=await db.from("job_prior_submissions")
  .select("linked_application_id,recipient_email,email_subject,sent_at").eq("workspace_id",workspace)
  .not("linked_application_id","is",null).gte("sent_at",new Date(Date.now()-90*86400000).toISOString())
  .order("sent_at",{ascending:false}).limit(250);
 if(error)throw Error("Unable to read application history");
 const threads=new Map<string,any[]>();
 for(const submission of submissions||[]){
  const key=replyKey(submission.recipient_email,submission.email_subject);
  const matches=threads.get(key)||[];
  matches.push(submission);
  threads.set(key,matches);
 }
 if(threads.size===0)return {checked:0,found:0,partial:false};
 const since=new Date(Date.now()-7*86400000).toISOString();
 const params=new URLSearchParams({
  "$select":"id,subject,from,receivedDateTime","$filter":"receivedDateTime ge "+since,
  "$orderby":"receivedDateTime desc","$top":"80"
 });
 let path="/me/mailFolders/inbox/messages?"+params.toString(),checked=0,found=0;
 for(let page=0;page<2&&path;page++){
  const data=await graph(access,path);
  for(const mail of data.value||[]){
   checked++;
   const received=Date.parse(mail.receivedDateTime);
   const subject=String(mail.subject||"").trim();
   const reply=subject.replace(/^(?:(?:re|aw|sv|رد)\s*:\s*)+/i,"");
   if(!mail.id||!Number.isFinite(received)||reply===subject)continue;
   const sender=normalized(mail.from?.emailAddress?.address);
   const candidates=(threads.get(replyKey(sender,reply))||[]).filter(record=>Date.parse(record.sent_at)<=received);
   const ids=new Set(candidates.map(record=>record.linked_application_id));
   if(ids.size!==1)continue;
   const {data:inserted,error:saveError}=await db.rpc("job_outlook_record_reply",{
    p_workspace:workspace,p_application:candidates[0].linked_application_id,p_message_id:mail.id,
    p_sender:sender,p_subject:subject,p_received_at:mail.receivedDateTime
   });
   if(saveError)throw Error("Unable to record an Outlook reply");
   if(inserted)found++;
  }
  const next=data["@odata.nextLink"];
  if(!next){path="";continue;}
  const url=new URL(next);
  if(url.origin!=="https://graph.microsoft.com"||!url.pathname.startsWith("/v1.0/me/"))throw Error("Unexpected Outlook inbox continuation");
  path=url.pathname.slice("/v1.0".length)+url.search;
 }
 return {checked,found,partial:!!path};
}
async function finalSafety(db:any,q:any){
 const [l,r,app,history,settings,connection]=await Promise.all([
 db.from("job_leads").select("company,job_title,city,status,application_email,application_channel,email_verified_at,email_verification_source_url").eq("id",q.job_id).eq("workspace_id",q.workspace_id).single(),
 db.from("job_reviews").select("approved_to_apply,meets_mandatory_requirements").eq("job_id",q.job_id).eq("workspace_id",q.workspace_id).single(),
 db.from("job_applications").select("id,status").eq("workspace_id",q.workspace_id).eq("job_id",q.job_id).limit(1),
 db.from("job_prior_submissions").select("id").eq("workspace_id",q.workspace_id).ilike("recipient_email",q.recipient_email.replace(/[\\%_]/g,"\\$&")).limit(1),
 db.from("job_system_settings").select("outlook_auto_send_enabled").eq("workspace_id",q.workspace_id).single(),
 db.from("job_outlook_connections").select("status").eq("workspace_id",q.workspace_id).maybeSingle()
 ]);
 if(l.error||r.error||app.error||history.error||settings.error||connection.error)throw Error("Unable to verify independent safety checks");
 const lead=l.data,review=r.data;
 if(!settings.data?.outlook_auto_send_enabled)throw Error("Owner has paused automatic Outlook sending");
 if(connection.data?.status!=="connected")throw Error("Microsoft account needs reconnection");
 if(!lead||!review||!review.approved_to_apply||review.meets_mandatory_requirements===false)throw Error("Job approval no longer valid");
 if(!["approved","applying"].includes(lead.status))throw Error("Job is no longer approved for submission");
 if(!["email","both"].includes(lead.application_channel)||!lead.email_verified_at||!lead.email_verification_source_url?.startsWith("https://"))throw Error("Recipient email lacks verified official-source evidence");
 if(String(lead.application_email||"").trim().toLowerCase()!==q.recipient_email.trim().toLowerCase())throw Error("Job recipient changed after queueing");
 if(app.data?.length)throw Error("Application exists; deduplication blocked second email");
 if(history.data?.length)throw Error("Recipient appears in prior submissions; conservative deduplication blocked second email");
}
async function pdf(db:any,queue:any):Promise<string>{
 if(queue.resume_path!==queue.workspace_id+"/resume.pdf")throw Error("Unexpected CV path");
 const {data,error}=await db.storage.from("job-office-resumes").download(queue.resume_path);
 if(error||!data)throw Error("Private PDF not uploaded");
 if(data.size>3000000||data.size<100)throw Error("Invalid PDF size");
 const raw=new Uint8Array(await data.arrayBuffer());
 if(String.fromCharCode(...raw.subarray(0,4))!=="%PDF")throw Error("CV is not a PDF file");
 return b64(raw);
}
async function flag(db:any,id:string,status:string,msg:string){
 await db.from("job_outlook_queue").update({status,last_error:msg.slice(0,450),lease_until:null,updated_at:new Date().toISOString()}).eq("id",id);
}
Deno.serve(async(req)=>{
 if(req.method!=="POST")return res({error:"POST required"},405);
 const secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),clientId=Deno.env.get("OUTLOOK_GRAPH_CLIENT_ID")?.trim(),clientSecret=Deno.env.get("OUTLOOK_GRAPH_CLIENT_SECRET")?.trim();
 if(!secret)return res({error:"backend_missing"},503);
 const db=createClient(Deno.env.get("SUPABASE_URL")||URL,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const value=req.headers.get("x-outlook-cron-secret")||"";
 const {data:authorized,error:authError}=await db.rpc("job_outlook_verify_cron_token",{candidate:value});
 if(authError||!authorized)return res({error:"Unauthorized"},401);
 if(!clientId||!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(clientId)||!clientSecret)return res({status:"awaiting_microsoft_app_registration",sent:0,queued:0,detail:"Microsoft Graph client credentials have not been added to server secrets."});
 try{
  const {data:count,error:enqueueError}=await db.rpc("job_outlook_enqueue_ready");
  if(enqueueError)throw Error("Queue generation failed");
  const key=await cryptoKey(db);
  const {data:connections,error:connErr}=await db.from("job_outlook_connections").select("*").eq("status","connected");
  if(connErr)throw Error("Connection lookup failed");
  const connByWorkspace=new Map((connections||[]).map((c:any)=>[c.workspace_id,c]));
  let verified=0,manual=0,accepted=0;
  // Never automatically retry ambiguous send calls. Verify the previous accepted sends first.
  const {data:pending,error:pendingError}=await db.from("job_outlook_queue").select("*").eq("status","pending_verification").order("graph_accepted_at").limit(15);
  if(pendingError)throw Error("Pending Outlook verification lookup failed");
  const tokenCache=new Map<string,string>();
  async function tokenFor(workspace:string){
   if(tokenCache.has(workspace))return tokenCache.get(workspace)!;
   const conn=connByWorkspace.get(workspace);if(!conn)throw Error("Microsoft OAuth is not connected");
   const token=await accessToken(db,conn,clientId!,clientSecret!,key);
   tokenCache.set(workspace,token);return token;
  }
  for(const q of pending||[]){
   try{
    const access=await tokenFor(q.workspace_id),match=await sentMatch(access,q);
    if(match){if(await confirm(db,q,match))verified++;}
    else if(Date.now()-Date.parse(q.graph_accepted_at)>24*3600000){
     await flag(db,q.id,"manual_review","Graph accepted the email, but it could not be verified in Sent Items within 24 hours. Do NOT resend automatically.");
     manual++;
    }
   }catch(_e){/* Remain pending; no resend. Reconcile in later scheduled ticks. */}
  }
  // A crash after claim might have sent the message. Never automatically retry it.
  await db.from("job_outlook_queue").update({status:"manual_review",last_error:"Send attempt expired without a final outcome; inspect Sent Items before retrying.",updated_at:new Date().toISOString()}).eq("status","claimed").lt("lease_until",new Date().toISOString());

  const {data:claimed,error:claimErr}=await db.rpc("job_outlook_claim_ready",{p_limit:3});
  if(claimErr)throw Error("Queue claim failed");
  for(const q of claimed||[]){
   let attempted=false;
   try{
    const attachment=await pdf(db,q);
    const access=await tokenFor(q.workspace_id);
    await finalSafety(db,q);
    attempted=true;
    const response=await graph(access,"/me/sendMail","POST",{
      message:{subject:q.subject,body:{contentType:"Text",content:q.body_text},
       toRecipients:[{emailAddress:{address:q.recipient_email}}],
       attachments:[{"@odata.type":"#microsoft.graph.fileAttachment",name:"resume.pdf",contentType:"application/pdf",contentBytes:attachment}]},
      saveToSentItems:true
    });
    if(!response.accepted)throw Error("Unexpected Graph response, sending outcome uncertain");
    const {error}=await db.from("job_outlook_queue").update({status:"pending_verification",graph_accepted_at:new Date().toISOString(),lease_until:null,updated_at:new Date().toISOString()}).eq("id",q.id).eq("status","claimed");
    if(error)throw Error("Outlook accepted the message but queue verification could not start");
    accepted++;
    // 202 is NOT considered submitted until the PDF-bearing message appears in Sent Items.
    try{
     await new Promise(resolve=>setTimeout(resolve,1800));
     const match=await sentMatch(access,q);
     if(match){if(await confirm(db,q,match))verified++;}
    }catch(_e){/* remain pending, safe to reconcile later; NEVER resend */}
   }catch(e){
     const msg=safeError(e);
     if(!attempted&&/Owner has paused|needs reconnection|token refresh is unavailable|connection changed/i.test(msg)){
      const {error}=await db.from("job_outlook_queue").update({status:"queued",attempt_count:0,send_started_at:null,
       lease_until:null,next_attempt_at:new Date(Date.now()+5*60000).toISOString(),last_error:msg,updated_at:new Date().toISOString()}).eq("id",q.id).eq("status","claimed");
      if(error)throw Error("Could not release a paused Outlook queue item");
      continue;
     }
     const status=!attempted&&/approval|deduplication|Recipient|Application exists/i.test(msg)?"blocked":"manual_review";
     await flag(db,q.id,status,msg);
     manual++;
   }
  }
  let incoming=0,followupErrors=0;
  for(const workspace of connByWorkspace.keys()){
   const started=new Date().toISOString();
   let checked=0,found=0,outcome="completed";
   try{
    const result=await scanInbox(db,workspace,await tokenFor(workspace));
    checked=result.checked;found=result.found;
    if(result.partial)outcome="partial";
   }catch{
    outcome="failed";followupErrors++;
   }
   const {error}=await db.rpc("job_outlook_record_followup",{
    p_workspace:workspace,p_started_at:started,p_checked:checked,p_found:found,p_result:outcome
   });
   if(error)throw Error("Could not save the Outlook follow-up result");
   incoming+=found;
  }
  return res({status:followupErrors?"partial":"completed",new_queue_entries:count||0,claimed:claimed?.length||0,
   graph_accepted:accepted,verified_in_sent_items:verified,manual_review:manual,incoming_replies:incoming,followup_errors:followupErrors});
 }catch(e){return res({error:safeError(e)},500)}
});
