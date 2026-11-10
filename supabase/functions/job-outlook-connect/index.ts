import {createClient} from "npm:@supabase/supabase-js@2.57.0";
const ORIGIN="https://devrah0.github.io";
const PROJECT="https://jclycoagtotikxskgkju.supabase.co";
const CALLBACK=PROJECT+"/functions/v1/job-outlook-connect";
const OFFICE=ORIGIN+"/Web/job-office/manager.html";
const BUCKET="job-office-resumes";
const SCOPES="openid profile email offline_access User.Read Mail.Send Mail.ReadBasic";
const HEADERS={"Access-Control-Allow-Origin":ORIGIN,"Access-Control-Allow-Methods":"GET, POST, OPTIONS","Access-Control-Allow-Headers":"authorization,apikey,content-type","Cache-Control":"no-store"};
const respond=(v:unknown,status=200)=>new Response(JSON.stringify(v),{status,headers:{...HEADERS,"content-type":"application/json; charset=utf-8"}});
const toB64=(bytes:Uint8Array)=>btoa(Array.from(bytes,b=>String.fromCharCode(b)).join(""));
const fromB64=(s:string)=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
const random=(n:number)=>toB64(crypto.getRandomValues(new Uint8Array(n))).replaceAll("+","-").replaceAll("/","_").replace(/=+$/,"");
const digest=async(str:string)=>Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(str))),b=>b.toString(16).padStart(2,"0")).join("");
const challenge=async(verifier:string)=>toB64(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(verifier)))).replaceAll("+","-").replaceAll("/","_").replace(/=+$/,"");
const connectedURL=(status:string)=>OFFICE+"?outlook="+encodeURIComponent(status);
const callbackErrors:Record<string,string>={
 "50011":"redirect_mismatch", "50020":"wrong_account_type", "50058":"login_required",
 "700016":"invalid_client", "7000215":"invalid_client", "7000222":"expired_secret"
};
function microsoftError(codes:unknown,description:string,fallback:string){
 const list=Array.isArray(codes)?codes:[description.match(/AADSTS(\d+)/)?.[1]];
 return list.map(code=>callbackErrors[String(code)]).find(Boolean)||fallback;
}
async function encryptionKey(db:any):Promise<CryptoKey>{
 const {data,error}=await db.rpc("job_outlook_aes_key_for_server");
 if(error||!data)throw Error("Server encryption configuration is unavailable");
 const raw=fromB64(String(data));if(raw.length!==32)throw Error("Invalid server AES key");
 return crypto.subtle.importKey("raw",raw,{name:"AES-GCM"},false,["encrypt","decrypt"]);
}
async function seal(db:any,value:string){
 const key=await encryptionKey(db),iv=crypto.getRandomValues(new Uint8Array(12));
 const bytes=new Uint8Array(await crypto.subtle.encrypt({name:"AES-GCM",iv},key,new TextEncoder().encode(value)));
 return {cipher:toB64(bytes),iv:toB64(iv)};
}
async function userWorkspace(db:any,req:Request){
 const token=(req.headers.get("authorization")??"").replace(/^Bearer\s+/i,"");
 if(!token)throw Error("Missing session");
 const {data:auth,error:aErr}=await db.auth.getUser(token);
 if(aErr||!auth.user?.id)throw Error("Invalid session");
 const {data:ws,error:wErr}=await db.from("job_workspaces").select("id,owner_user_id").eq("owner_user_id",auth.user.id).maybeSingle();
 if(wErr||!ws)throw Error("Owner access required");
 return ws;
}
function redirect(dest:string){return new Response(null,{status:302,headers:{location:connectedURL(dest),"cache-control":"no-store","referrer-policy":"no-referrer"}})}
Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:HEADERS});
 const url=Deno.env.get("SUPABASE_URL")||PROJECT,secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!secret)return respond({error:"Backend is not configured"},503);
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const clientId=Deno.env.get("OUTLOOK_GRAPH_CLIENT_ID")?.trim()||"";
 const clientSecret=Deno.env.get("OUTLOOK_GRAPH_CLIENT_SECRET")?.trim()||"";
 const graphConfigured=/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(clientId)&&!!clientSecret;
 if(req.method==="GET"){
   const callback=new URL(req.url),state=callback.searchParams.get("state")||"",code=callback.searchParams.get("code")||"";
   if(!graphConfigured)return redirect("configuration_missing");
   if(!/^[A-Za-z0-9_-]{43}$/.test(state))return redirect("invalid_state");
   try{
     const hash=await digest(state);
     const {data:session,error:sErr}=await db.from("job_outlook_oauth_states").delete().eq("state_hash",hash).gte("expires_at",new Date().toISOString()).select("workspace_id,owner_user_id,code_verifier").maybeSingle();
     if(sErr||!session)return redirect("invalid_state");
     const callbackError=callback.searchParams.get("error");
     if(callbackError)return redirect(microsoftError(null,callback.searchParams.get("error_description")||"",callbackError==="login_required"?"login_required":"consent_denied"));
     if(!code)return redirect("invalid_state");
     const {data:workspace,error:workspaceError}=await db.from("job_workspaces").select("id").eq("id",session.workspace_id).eq("owner_user_id",session.owner_user_id).maybeSingle();
     if(workspaceError||!workspace)return redirect("invalid_state");
     const body=new URLSearchParams({client_id:clientId,client_secret:clientSecret,redirect_uri:CALLBACK,code,grant_type:"authorization_code",scope:SCOPES,code_verifier:session.code_verifier});
     const tokenResp=await fetch("https://login.microsoftonline.com/common/oauth2/v2.0/token",{method:"POST",body,headers:{"Content-Type":"application/x-www-form-urlencoded"},signal:AbortSignal.timeout(15000)});
     const tokenData=await tokenResp.json().catch(()=>({}));
     if(!tokenResp.ok||!tokenData.access_token||!tokenData.refresh_token)return redirect(microsoftError(tokenData.error_codes,tokenData.error_description||"","token_exchange_failed"));
     const granted=String(tokenData.scope||"").toLowerCase().split(/\s+/).map(scope=>scope.replace(/^https:\/\/graph\.microsoft\.com\//,""));
     if(!["user.read","mail.send","mail.readbasic"].every(scope=>granted.includes(scope)))return redirect("permissions_missing");
     const who=await fetch("https://graph.microsoft.com/v1.0/me?$select=id,mail,userPrincipalName",{headers:{Authorization:"Bearer "+tokenData.access_token},signal:AbortSignal.timeout(15000)});
     const profile=await who.json().catch(()=>({}));
     if(!who.ok||!profile.id)return redirect("profile_failed");
     const account=String(profile.mail||profile.userPrincipalName||"").trim().toLowerCase();
     const {data:candidate}=await db.from("job_candidate_profiles").select("email").eq("workspace_id",session.workspace_id).maybeSingle();
     if(!account||!candidate?.email||account!==String(candidate.email).trim().toLowerCase())return redirect("account_mismatch");
     const encrypted=await seal(db,tokenData.refresh_token);
     const {error:saveError}=await db.from("job_outlook_connections").upsert({
       workspace_id:session.workspace_id,account_email:account,graph_user_id:profile.id,refresh_token_ciphertext:encrypted.cipher,refresh_token_iv:encrypted.iv,
       scopes:String(tokenData.scope),status:"connected",connected_at:new Date().toISOString(),last_refreshed_at:new Date().toISOString(),
       last_error:null,updated_at:new Date().toISOString()
     },{onConflict:"workspace_id"});
     if(saveError)throw Error("Connection save failed");
     return redirect("connected");
   }catch(_e){return redirect("connection_failed")}
 }
 if(req.method!=="POST")return respond({error:"Unsupported method"},405);
 let workspace:any;try{workspace=await userWorkspace(db,req)}catch(e){return respond({error:String(e)},401)}
 let action="";try{const body=await req.json();action=String(body?.action||"status")}catch{return respond({error:"Invalid request"},400)}
 const [connection,settings,files]=await Promise.all([
  db.from("job_outlook_connections").select("account_email,status").eq("workspace_id",workspace.id).maybeSingle(),
  db.from("job_system_settings").select("outlook_auto_send_enabled").eq("workspace_id",workspace.id).single(),
  db.storage.from(BUCKET).list(workspace.id,{search:"resume.pdf",limit:20})
 ]);
 if(connection.error||settings.error||files.error)return respond({error:"تعذر التحقق من ربط Outlook أو التخزين الخاص."},503);
 const conn=connection.data;
 const resumeReady=files.data.some(file=>file.name==="resume.pdf");
 const summary={configured:graphConfigured,connected:conn?.status==="connected",connection_status:conn?.status||"disconnected",account:conn?.account_email||null,auto_send_enabled:settings.data.outlook_auto_send_enabled===true,resume_uploaded:resumeReady};
 const connector=action==="status"||action==="enqueue"
  ?await db.rpc("job_outlook_connector_state",{p_workspace:workspace.id}).maybeSingle()
  :{data:null,error:null};
 if(connector.error)return respond({error:"تعذر قراءة حالة اتصال Outlook عبر ChatGPT."},503);
 if(action==="status"){
  const waiting=["queued","claimed","pending_verification","drafted"];
  const [queue,portal,followup]=await Promise.all([
   Promise.all(waiting.map(status=>db.from("job_outlook_queue").select("id",{count:"exact",head:true}).eq("workspace_id",workspace.id).eq("status",status))),
   db.from("job_leads").select("id",{count:"exact",head:true}).eq("workspace_id",workspace.id).eq("status","approved").eq("application_channel","portal"),
   db.from("job_workflow_runs").select("status,started_at,completed_at,found_count").eq("workspace_id",workspace.id).eq("section","followup").like("notes","Outlook Graph inbox sync%").order("started_at",{ascending:false}).limit(1).maybeSingle()
  ]);
  if(queue.some(entry=>entry.error)||portal.error||followup.error)return respond({error:"تعذر التحقق من الطابور أو المتابعة."},503);
  return respond({...summary,connector:connector.data,queue:Object.fromEntries(waiting.map((status,index)=>[status,queue[index].count||0])),portal_ready:portal.count||0,followup:followup.data});
 }
 if(action==="begin"){
  if(!graphConfigured)return respond({...summary,error:"Microsoft Graph app registration is required (client ID and client secret)."},409);
  const state=random(32),verifier=random(32),hash=await digest(state),cc=await challenge(verifier);
  const {error}=await db.from("job_outlook_oauth_states").insert({state_hash:hash,workspace_id:workspace.id,owner_user_id:workspace.owner_user_id,code_verifier:verifier,expires_at:new Date(Date.now()+10*60*1000).toISOString()});
  if(error)return respond({error:"Unable to initialize Microsoft OAuth"},500);
  const auth=new URL("https://login.microsoftonline.com/common/oauth2/v2.0/authorize");
  for(const [k,v] of Object.entries({client_id:clientId,response_type:"code",redirect_uri:CALLBACK,response_mode:"query",scope:SCOPES,state,code_challenge:cc,code_challenge_method:"S256",prompt:"select_account"}))auth.searchParams.set(k,v);
  return respond({url:auth.toString()});
 }
 if(action==="enable"){
  if(!graphConfigured||!summary.connected||!resumeReady)return respond({...summary,error:"Connect Microsoft Graph and upload a private PDF before enabling automatic email."},409);
  const {error}=await db.from("job_system_settings").update({outlook_auto_send_enabled:true}).eq("workspace_id",workspace.id);
  if(error)return respond({error:"Could not enable Outlook"},500);
  return respond({...summary,auto_send_enabled:true});
 }
 if(action==="disable"){
  const {error}=await db.from("job_system_settings").update({outlook_auto_send_enabled:false}).eq("workspace_id",workspace.id);
  if(error)return respond({error:"Could not disable Outlook"},500);
  return respond({...summary,auto_send_enabled:false});
 }
 if(action==="disconnect"){
  const {error:pauseError}=await db.from("job_system_settings").update({outlook_auto_send_enabled:false}).eq("workspace_id",workspace.id);
  if(pauseError)return respond({error:"Could not pause Outlook sending"},500);
  const {error:stateError}=await db.from("job_outlook_oauth_states").delete().eq("workspace_id",workspace.id);
  if(stateError)return respond({error:"Could not clear pending Outlook authorizations"},500);
  const {error}=await db.from("job_outlook_connections").delete().eq("workspace_id",workspace.id);
  if(error)return respond({error:"Could not disconnect Outlook"},500);
  return respond({configured:graphConfigured,connected:false,auto_send_enabled:false,resume_uploaded:resumeReady});
 }
 if(action==="enqueue"){
  const provider=connector.data&&!(graphConfigured&&summary.connected)?"connector":"graph";
  if(provider==="graph"&&!graphConfigured)return respond({error:"انتظر أول جولة متابعة ناجحة لربط Outlook عبر ChatGPT."},409);
  const {data,error}=await db.rpc("job_outlook_enqueue_for_workspace",{p_workspace:workspace.id,p_provider:provider});
  if(error)return respond({error:"Could not prepare safe Outlook queue"},500);
  return respond({prepared:data||0,provider,...summary});
 }
 return respond({error:"Unsupported action"},400);
});
