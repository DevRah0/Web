import {createClient} from "npm:@supabase/supabase-js@2.57.0";
const ok=(x:unknown,status=200)=>new Response(JSON.stringify(x),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});
const hash=async(s:string)=>Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(s))),v=>v.toString(16).padStart(2,"0")).join("");
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return ok({error:"method_not_allowed"},405);
 const token=String(req.headers.get("x-gmail-bridge-token")??"");
 if(!/^[a-f0-9]{64}$/.test(token))return ok({error:"unauthorized"},401);
 const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!key)return ok({error:"unavailable"},503);
 const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const conn=await db.from("job_gmail_connections").select("workspace_id,send_enabled").eq("token_hash",await hash(token)).not("connected_at","is",null).maybeSingle();
 if(conn.error||!conn.data)return ok({error:"unauthorized"},401);
 let input:any;
 try{input=await req.json()}catch{return ok({error:"invalid_json"},400)}
 const action=String(input?.action??"");
 const workspace=conn.data.workspace_id;
 if(action==="status"){
   const seen=await db.from("job_gmail_connections").update({worker_seen_at:new Date().toISOString()}).eq("workspace_id",workspace);
   if(seen.error)return ok({error:"heartbeat_unavailable"},503);
   const {count}=await db.from("job_gmail_outbox").select("id",{head:true,count:"exact"}).eq("workspace_id",workspace).eq("status","queued");
   return ok({connected:true,send_enabled:conn.data.send_enabled,queue_pending:count??0});
 }
 if(action==="claim"){
  if(!conn.data.send_enabled)return ok({status:"paused"});
  const {data,error}=await db.rpc("job_gmail_claim_one",{p_workspace:workspace});
  if(error)return ok({error:"queue_unavailable"},503);
  const item=data?.[0];
  if(!item){
    const audit=await db.from("job_workflow_runs").insert({workspace_id:workspace,section:"applying",status:"completed",submitted_count:0,completed_at:new Date().toISOString(),notes:"Gmail checked for an eligible application. No message claimed."});
    if(audit.error)return ok({error:"audit_unavailable"},503);
    return ok({status:"empty"});
  }
  const sign=await db.storage.from("job-office-resumes").createSignedUrl(item.resume_path,120);
  if(sign.error||!sign.data?.signedUrl){
    await db.from("job_gmail_outbox").update({status:"queued",claimed_at:null,last_error:"resume_unavailable"}).eq("workspace_id",workspace).eq("id",item.id).eq("status","claimed");
    return ok({status:"attachment_missing"});
  }
  return ok({status:"ready",item:{id:item.id,to:item.recipient_email,subject:item.subject,body:item.body_text,
    resume_url:sign.data.signedUrl.startsWith("http")?sign.data.signedUrl:url+sign.data.signedUrl}});
 }
 if(action==="ack"){
   const sender=String(input?.sender??"").trim();
   const id=String(input?.id??"").trim();
   if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(sender)||!/^[a-f0-9-]{36}$/i.test(id))return ok({error:"invalid_ack"},400);
   const {data,error}=await db.rpc("job_gmail_ack_sent",{p_workspace:workspace,p_queue_id:id,p_sender_email:sender});
   if(error)return ok({error:"ack_failed"},503);
   return ok({acknowledged:data===true});
 }
 if(action==="uncertain"){
   const id=String(input?.id??"").trim();
   if(!/^[a-f0-9-]{36}$/i.test(id))return ok({error:"invalid_id"},400);
   await db.from("job_gmail_outbox").update({status:"uncertain",last_error:"send_result_unverified",updated_at:new Date().toISOString()})
     .eq("workspace_id",workspace).eq("id",id).eq("status","claimed");
   return ok({status:"manual_review_required"});
 }
 return ok({error:"unsupported_action"},400);
});