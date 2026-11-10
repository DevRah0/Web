import {createClient} from "npm:@supabase/supabase-js@2.57.0";

const PROJECT="https://jclycoagtotikxskgkju.supabase.co";
const origin="https://devrah0.github.io";
const cors={"Access-Control-Allow-Origin":origin,"Access-Control-Allow-Methods":"POST, OPTIONS","Access-Control-Allow-Headers":"authorization,apikey,content-type","Access-Control-Max-Age":"86400"};
const json=(v:unknown,status=200)=>new Response(JSON.stringify(v),{status,headers:{...cors,"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store"}});
const SECTION=new Set(["manager","research","screening","applying","followup"]);
const COMMANDS:Record<string,string>={search_now:"research",screening_urgent:"screening",applications_urgent:"applying",followup_urgent:"followup",audit_now:"manager",dispatch_all:"manager",general_directive:"manager"};
const labels:Record<string,string>={research:"البحث",screening:"التدقيق",applying:"التقديم",followup:"المتابعة",manager:"الإدارة"};
const text=(v:unknown)=>String(v??"").trim().slice(0,3000);
function proposedAction(s:string):string|null{
 const t=s.replace(/[\u064b-\u065f]/g,"").trim();
 if(/^(?:اضغط|استعجل|حرك|شغل|نبّه|نبه)/u.test(t)&&/(?:الكل|الموظفين|الأقسام|الجميع|عليهم)/u.test(t))return "dispatch_all";
 if(/^(?:ابدأ البحث|ابحث الآن|ابحث|كثف البحث|سرع البحث|شغل البحث)/u.test(t))return "search_now";
 if(/^(?:دقق|راجع الفرص|سرع التدقيق|عجل التدقيق)/u.test(t))return "screening_urgent";
 if(/^(?:قدم|قدّم|ابدأ التقديم|سرع التقديم|عجل التقديم)/u.test(t))return "applications_urgent";
 if(/^(?:تابع الردود|افحص البريد|راجع البريد|سرع المتابعة)/u.test(t))return "followup_urgent";
 return null;
}
async function counts(db:any,workspace:string){
 const q=await Promise.all([
  db.from("job_leads").select("id,status",{count:"exact",head:false}).eq("workspace_id",workspace).limit(700),
  db.from("job_reviews").select("job_id",{count:"exact",head:true}).eq("workspace_id",workspace),
  db.from("job_applications").select("id",{count:"exact",head:true}).eq("workspace_id",workspace).eq("status","submitted"),
  db.from("job_search_sources").select("id",{count:"exact",head:true}).eq("workspace_id",workspace).eq("is_enabled",true),
  db.from("job_workflow_runs").select("section,status,started_at").eq("workspace_id",workspace).order("started_at",{ascending:false}).limit(75),
  db.from("job_manager_commands").select("id",{count:"exact",head:true}).eq("workspace_id",workspace).eq("status","queued")
 ]);
 const [leads,reviews,submitted,sources,runs,queued]=q;
 if(q.some((x:any)=>x.error))throw Error("تعذر قراءة حالة الأقسام");
 const last:Record<string,any>={};for(const r of runs.data||[])if(!last[r.section])last[r.section]=r;
 const total=leads.count??leads.data?.length??0,screened=reviews.count??0;
 return {total,screened,unreviewed:Math.max(0,total-screened),submitted:submitted.count??0,sources:sources.count??0,queued:queued.count??0,latest:last,generated_at:new Date().toISOString()};
}
function digest(st:any):string{
 return "تقرير مباشر من قاعدة البيانات:\n"
   +"• إعلانات مسجلة: "+st.total+"\n"
   +"• دُققت: "+st.screened+"، بانتظار التدقيق: "+st.unreviewed+"\n"
   +"• طلبات مرسلة ومثبتة: "+st.submitted+"\n"
   +"• مصادر بحث فعّالة: "+st.sources+"\n"
   +"• أوامر تنتظر التنفيذ: "+st.queued+"\n"
   +"هذه أرقام السجل الفعلي، ولا تعني أن الموظفين يعملون كل ثانية.";
}
async function addMsg(db:any,workspace:string, sender:string,body:string,target="manager",kind="chat",cmdId:string|null=null,replyTo:string|null=null){
 const {data,error}=await db.from("job_manager_messages").insert({workspace_id:workspace,sender,target_section:target,body,message_kind:kind,command_id:cmdId,reply_to:replyTo}).select("id").single();
 if(error)throw Error("تعذر حفظ الرسالة: "+error.message);
 return data.id as string;
}
async function log(db:any,workspace:string,act:string,commandId:string,summary:string){
 await db.from("job_activity").insert({workspace_id:workspace,actor_section:"manager",event_type:"manager_directive_issued",note:summary.slice(0,500),event_data:{command_id:commandId,action:act}});
}
async function queue(db:any,workspace:string,user:string,action:string,instruction:string,target:string|undefined,priority=90){
 const section=COMMANDS[action];
 if(!section)throw Error("أمر غير مدعوم");
 const finalTarget=action==="general_directive"?(SECTION.has(target||"")?target:"manager"):section;
 const immediate=action==="search_now"||action==="dispatch_all";
 const {data,error}=await db.from("job_manager_commands").insert({
  workspace_id:workspace,requested_by:user,target_section:finalTarget,
  action,instruction,priority,status:immediate?"running":"queued",started_at:immediate?new Date().toISOString():null
 }).select("id,target_section,status").single();
 if(error)throw Error("تعذر إرسال أمر القسم: "+error.message);
 await log(db,workspace,action,data.id,labels[finalTarget]+": "+instruction);
 return data;
}
async function scanNow(db:any,token:string,commandId:string){
 try{
  const res=await fetch(PROJECT+"/functions/v1/job-search-fast",{
   method:"POST",headers:{"authorization":"Bearer "+token,"Content-Type":"application/json"},
   body:"{}",signal:AbortSignal.timeout(90000)
  });
  const body=await res.json().catch(()=>({error:"Empty response"}));
  if(!res.ok)throw Error(String(body.error||res.status));
  if(body.scanned>0&&body.errors===body.scanned)throw Error("تعذر فحص جميع المصادر في هذه الجولة.");
  const result={status:"completed",reason:body.scanned?"scanned":"recent_scan",scanned:body.scanned??0,inserted:body.inserted??0,errors:body.errors??0};
  const {error}=await db.from("job_manager_commands").update({status:"completed",result,completed_at:new Date().toISOString()}).eq("id",commandId);
  if(error)throw Error("تعذر حفظ نتيجة البحث.");
  return result;
 }catch(e){
  const msg=String(e instanceof Error?e.message:e).slice(0,350);
  await db.from("job_manager_commands").update({status:"failed",last_error:msg,completed_at:new Date().toISOString()}).eq("id",commandId);
  return {status:"failed",error:msg};
 }
}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
 if(req.method!=="POST")return json({error:"POST only"},405);
 const secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 const url=Deno.env.get("SUPABASE_URL")||PROJECT;
 if(!secret)return json({error:"Configuration unavailable"},503);
 const token=(req.headers.get("Authorization")||"").replace(/^Bearer\s+/i,"").trim();
 if(!token)return json({error:"تسجيل الدخول مطلوب"},401);
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:auth,error:authErr}=await db.auth.getUser(token);
 if(authErr||!auth.user)return json({error:"جلسة دخول غير صالحة"},401);
 const {data:workspaces,error:wErr}=await db.from("job_workspaces").select("id").eq("owner_user_id",auth.user.id).limit(1);
 if(wErr||!workspaces?.length)return json({error:"حساب غير مصرح له بإدارة هذه المنظومة"},403);
 const workspace=workspaces[0].id,user=auth.user.id;
 let payload:any;try{payload=await req.json()}catch{return json({error:"طلب غير صالح"},400)}
 const type=String(payload?.type??"");
 try{
  if(type==="status")return json({status:await counts(db,workspace)});
  if(type!=="message"&&type!=="command")return json({error:"نوع طلب غير مدعوم"},400);
  let action=type==="command"?String(payload.action||""):"";
  const raw=text(payload.text||payload.instruction);
  const target=SECTION.has(payload.target_section)?payload.target_section:"manager";
  if(type==="message"&&!raw)return json({error:"الرسالة فارغة"},400);
  if(type==="message"&&!action)action=proposedAction(raw)||"";
  if(type==="command"&&!COMMANDS[action])return json({error:"الأمر غير مدعوم"},400);
  const instruction=raw||({search_now:"ابدأ بحثًا عاجلًا",screening_urgent:"راجع الفرص المعلقة بالأولوية",applications_urgent:"ابدأ مراجعة طلبات التقديم المعتمدة",followup_urgent:"افحص الردود والرسائل",audit_now:"راجع جميع الأقسام",dispatch_all:"أصدر تعليمات عاجلة للأقسام الأربعة"}[action]||"مراجعة عاجلة");
  if(instruction.length>3000)return json({error:"الطلب طويل جدًا"},400);
  const recent=await db.from("job_manager_messages").select("id").eq("workspace_id",workspace).eq("sender","owner").gte("created_at",new Date(Date.now()-12000).toISOString()).limit(10);
  if((recent.data||[]).length>=5)return json({error:"طلبات كثيرة خلال ثوانٍ؛ جرّب بعد قليل"},429);
  const messageId=await addMsg(db,workspace,"owner",instruction,target,action?"command":"chat");
  let response="",commands:any[]=[];
  if(action){
   // Avoid duplicate queue floods of identical manager commands in two minutes.
   const since=new Date(Date.now()-120000).toISOString();
   const existing=await db.from("job_manager_commands").select("id,status").eq("workspace_id",workspace).eq("action",action).gte("created_at",since).order("created_at",{ascending:false}).limit(1);
   if(existing.data?.length)response="هذا الأمر وصل مسبقًا، وحالته الحالية: "+(existing.data[0].status==="completed"?"مكتمل":existing.data[0].status==="queued"?"بانتظار القسم":existing.data[0].status==="running"?"جارٍ التنفيذ":existing.data[0].status)+". لن أكرره.";
   else if(action==="dispatch_all"){
     const parent=await queue(db,workspace,user,"dispatch_all",instruction,"manager",95);
     commands.push(parent);
     for(const act of ["search_now","screening_urgent","applications_urgent","followup_urgent"]){
      const ch=await queue(db,workspace,user,act,"تكليف عاجل من المدير: "+instruction,undefined,95);
      commands.push(ch);
     }
     const scan=await scanNow(db,token,commands[1].id);
     commands[1].status=scan.status;
     const result={dispatched:4,search:scan};
     await db.from("job_manager_commands").update({status:"completed",result,completed_at:new Date().toISOString()}).eq("id",parent.id);
     parent.status="completed";
     response="أصدرت أوامر عاجلة للأقسام الأربعة وسجلتها في قاعدة البيانات.\nالبحث: "+(scan.status==="completed"?"جولة تمت/فُحصت مؤخرًا؛ فرص جديدة: "+(scan.inserted??0):"تعذر بدء الجولة: "+scan.error)+".\nالتدقيق والتقديم والمتابعة: تُعالَج أوامرها آليًا كل 3 دقائق عند توفر منفّذ فعلي. إذا تعذر وصول البريد أو المتصفح ستظهر الحالة فشلًا مع السبب، لا نجاحًا وهميًا.";
   }else{
     const cmd=await queue(db,workspace,user,action,instruction,target);
     commands.push(cmd);
     if(action==="search_now"){
      const scan=await scanNow(db,token,cmd.id);
      cmd.status=scan.status;
      response=scan.status==="completed"?"انتهى أمر البحث. "+(scan.reason==="recent_scan"?"لا توجد مصادر جاهزة لجولة جديدة الآن.":"فُحصت "+scan.scanned+" مصادر وسُجلت "+scan.inserted+" فرص جديدة."+(scan.errors?" تعثّر "+scan.errors+" من المصادر.":"")):"تعذّر البحث الفوري. "+scan.error;
     }else{
      response="أرسلت توجيهك إلى قسم "+labels[cmd.target_section]+". الحالة: «بانتظار التنفيذ». سيفحصه معالج الأوامر خلال نحو 3 دقائق. التنفيذ الكامل يتطلب وجود عامل مختص؛ عند عدم توفره سيظهر سبب التعذر بدل بقائه معلّقًا.";
     }
   }
  }else{
    const st=await counts(db,workspace);
    response=/(?:كم|تقرير|الحالة|النتائج|وظائف|طلبات|شغل|ماذا|وش|أخبار|انجاز|إنجاز|ملخص|مداومين|مداوم)/u.test(instruction)
      ?digest(st)
      :"وصلت رسالتك للمدير وحُفظت في سجل العمل. الرد الفوري هنا تشغيلي وليس محادثة مع إنسان. سيطّلع المدير المجدول عليها في جولته المقبلة، ويمكنك إصدار توجيه عاجل من الأزرار أسفل المحادثة.\n\n"+digest(st);
  }
  const replyId=await addMsg(db,workspace,"system",response,target,action?"command":"status",commands[0]?.id||null,messageId);
  return json({ok:true,message_id:messageId,reply_id:replyId,reply:response,commands:commands.map(x=>({id:x.id,target_section:x.target_section,status:x.status}))});
 }catch(e){return json({error:String(e instanceof Error?e.message:e).slice(0,500)},500)}
});
