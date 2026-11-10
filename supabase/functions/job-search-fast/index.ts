import { createClient } from "npm:@supabase/supabase-js@2.57.0";
type Source={id:string;workspace_id:string;provider:"greenhouse"|"lever"|"smartrecruiters"|"workable";slug:string;company:string;source_url:string};
type Candidate={id:string;title:string;location:string;description:string;url:string;applyUrl:string};
const cors={"Access-Control-Allow-Origin":"https://devrah0.github.io","Access-Control-Allow-Headers":"authorization,apikey,content-type,x-job-cron-secret","Access-Control-Allow-Methods":"POST,OPTIONS"};
const send=(v:unknown,status=200)=>new Response(JSON.stringify(v),{status,headers:{...cors,"content-type":"application/json; charset=utf-8","cache-control":"no-store"}});
const clean=(s:unknown)=>String(s??"").replace(/&lt;/gi,"<").replace(/&gt;/gi,">").replace(/&quot;/gi,'"').replace(/&nbsp;|&#160;/gi," ").replace(/<[^>]*>/g," ").replace(/&amp;/gi,"&").replace(/\s+/g," ").trim();
const locationPatterns=[
  ["Jeddah",/(?:jeddah|jiddah|جدة|جدّه)/i],
  ["Makkah",/(?:makkah|mecca|مكة|مكه)/i],
  ["Madinah",/(?:madinah|medina|medinah|المدينة المنورة|المدينه المنوره)/i],
  ["Taif",/(?:taif|الطائف)/i],
] as const;
const rejectOtherOnly=/(?:riyadh|الرياض|khobar|الخبر|dammam|الدمام|jubail|الجبيل|dubai|دبي)/i;
function cityFor(where:string,desc:string):string|null{
 for(const [city,re] of locationPatterns)if(re.test(where))return city;
 if(rejectOtherOnly.test(where))return null;
 for(const [city,re] of locationPatterns){
  const short=desc.slice(0,2200);
  if(new RegExp("(?:based in|location[:\\s]+|workplace[:\\s]+|مقر العمل|موقع العمل).{0,45}"+re.source,"i").test(short))return city;
 }
 return null;
}
const roleMatch=/(?:engineer|engineering|developer|software|data|analyst|\bit\b|network|systems?|technical|security|cyber|support|graduate|trainee|intern|associate|ict|elv|automation|robot|cloud|quality|electronics|maintenance|technolog|bms|project coordinator|information|computer|consultant|operations specialist|مهندس|هندسة|تقنية|شبكات|حاسب|تدريب|خريج|برمجة)/i;
const senior=/(?:^|[\s(-])(?:senior|principal|staff|director|manager|head|lead|chief|vp|vice president|expert)(?:$|[\s)-])/i;
const nonTechnicalTitle=/(?:accountant|accounting|social media|people and culture|human resources|chef|^sales intern$|^operations specialist$|^security manager$)/i;
const technicalRoleTitle=/(?:engineer|engineering|developer|software|data|analyst|\bit\b|network|systems?|technical|cyber|support|graduate program|training program|trainee program|ict|elv|automation|robot|cloud|quality|electronics|maintenance|technolog|bms|project coordinator|project management|pmo|information|computer|database|telecom|مهندس|هندسة|تقنية|شبكات|حاسب|برمجة|نظم|بيانات)/i;
function worthReviewing(title:string):boolean{
 if(nonTechnicalTitle.test(title))return false;
 return technicalRoleTitle.test(title)||roleMatch.test(title)&&/^(?:graduate|internship|trainee)(?:\b|[\/ ])/i.test(title);
}
function priority(title:string,desc:string,city:string):number{
 const t=title.toLowerCase(),d=desc.toLowerCase().slice(0,1500);
 let score=40+(city==="Jeddah"?8:5);
 if(/(?:junior|entry.level|fresh graduate|graduate|trainee|intern|associate|early career|حديث|تدريب)/i.test(t+" "+d.slice(0,400)))score+=24;
 if(/(?:software|computer|electronic|network|\bit\b|linux|cloud|cyber|support|embedded|iot|automation|systems?)/i.test(t))score+=18;
 if(/(?:computer engineering|computer science|engineering degree|bachelor|هندسة الحاسب)/i.test(d))score+=10;
 if(senior.test(t))score-=45;
 if(/(?:looking for|seeking|hiring|role for)\s+(?:an?\s+)?(?:experienced\s+)?senior/i.test(d.slice(0,650)))score-=30;
 if(/(?:minimum|at least|over)\s+(?:[5-9]|1[0-9])\+?\s+years|[5-9]\+\s+years/i.test(d))score-=15;
 return Math.min(100,Math.max(0,score));
}
async function getCandidates(source:Source):Promise<Candidate[]>{
 if(!/^[a-z0-9_-]{2,80}$/i.test(source.slug))throw new Error("Invalid source slug");
 const headers={"Accept":"application/json","User-Agent":"JobOfficeJobDiscovery/2.1 (public ATS job boards)","Cache-Control":"no-cache"};
 let arr:any[]=[];
 if(source.provider==="smartrecruiters"){
  for(let offset=0;offset<300;offset+=100){
    const endpoint="https://api.smartrecruiters.com/v1/companies/"+encodeURIComponent(source.slug)+"/postings?country=sa&limit=100&offset="+offset;
    const response=await fetch(endpoint,{headers,signal:AbortSignal.timeout(18000)});
    if(!response.ok)throw new Error("SmartRecruiters public API HTTP "+response.status);
    const payload=await response.json();
    const batch=Array.isArray(payload?.content)?payload.content:[];
    arr.push(...batch);
    if(batch.length<100||offset+batch.length>=Number(payload.totalFound??0))break;
  }
 }else{
  let endpoint="";
  if(source.provider==="greenhouse")endpoint="https://boards-api.greenhouse.io/v1/boards/"+encodeURIComponent(source.slug)+"/jobs?content=true";
  if(source.provider==="lever")endpoint="https://api.lever.co/v0/postings/"+encodeURIComponent(source.slug)+"?mode=json";
  if(source.provider==="workable")endpoint="https://www.workable.com/api/accounts/"+encodeURIComponent(source.slug)+"?details=true";
  if(!endpoint)throw new Error("Unsupported job source");
  const response=await fetch(endpoint,{headers,signal:AbortSignal.timeout(22000)});
  if(!response.ok)throw new Error("Public job API HTTP "+response.status);
  const payload=await response.json();
  if(source.provider==="greenhouse")arr=Array.isArray(payload?.jobs)?payload.jobs:[];
  if(source.provider==="lever")arr=Array.isArray(payload)?payload:[];
  if(source.provider==="workable")arr=(Array.isArray(payload?.jobs)?payload.jobs:[]).filter((v:any)=>{
   const countries=[v.country,...(Array.isArray(v.locations)?v.locations.map((l:any)=>l?.country):[])].filter(Boolean).map((v:unknown)=>String(v).toLowerCase());
   return countries.some((c:string)=>c==="sa"||c==="saudi arabia"||c==="ksa"||c==="kingdom of saudi arabia");
  });
 }
 return arr.slice(0,1500).map((v:any)=>{
  const isGH=source.provider==="greenhouse";
  const isSR=source.provider==="smartrecruiters";
  const isW=source.provider==="workable";
  const title=clean(isGH?v.title:isSR?v.name:isW?v.title:v.text);
  const location=clean(isGH?v.location?.name:isSR?
    (v.location?.city||"")+", "+(v.location?.region||"")+", "+(v.location?.country||""):
    isW? [v.city,...(Array.isArray(v.locations)?v.locations.filter((l:any)=>{
      const c=String(l.country||"").toLowerCase();return c==="sa"||c==="saudi arabia"||c==="ksa";
    }).map((l:any)=>l.city):[])].filter(Boolean).join(", "):
    v.categories?.allLocations?.join(", ")||v.categories?.location||"");
  const description=clean(isGH?v.content:isSR?(v.jobAd?.sections?.jobDescription?.text||""):isW?v.description:(v.descriptionPlain||v.description||""));
  const id=String(isW?v.shortcode:(v.id??""));
  const fallback=isSR?("https://jobs.smartrecruiters.com/"+encodeURIComponent(source.slug)+"/"+encodeURIComponent(id)):
    isW?("https://apply.workable.com/j/"+encodeURIComponent(id)):"";
  const url=String(isGH?v.absolute_url:isSR?(v.postingUrl||fallback):isW?(v.url||fallback):v.hostedUrl||"");
  const applyUrl=String(isGH?v.absolute_url:isSR?(v.applyUrl||url):isW?(v.application_url||url):(v.applyUrl||v.hostedUrl||""));
  return {id,title,location,description,url,applyUrl};
 }).filter(v=>v.id.length>0&&/^https:\/\//.test(v.url)&&v.title.length>0);
}
Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
 if(req.method!=="POST")return send({error:"Method not allowed"},405);
 const url=Deno.env.get("SUPABASE_URL")??"";
 const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"";
 if(!url||!key)return send({error:"Server credentials unavailable"},503);
 const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 let allowed=false,authMethod="cron",workspace:string|null=null;
 const cronSecret=req.headers.get("x-job-cron-secret");
 if(cronSecret){
  const {data,error}=await db.rpc("job_verify_fast_search_token",{candidate:cronSecret});
  allowed=!error&&data===true;
 } else {
  const bearer=req.headers.get("authorization")?.replace(/^Bearer\s+/i,"")??"";
  if(bearer){
    const {data,error}=await db.auth.getUser(bearer);
    if(!error&&data.user?.id){
      const {data:ws}=await db.from("job_workspaces").select("id").eq("owner_user_id",data.user.id).limit(1);
      workspace=ws?.[0]?.id??null;
      allowed=!!workspace;authMethod="owner";
    }
  }
 }
 if(!allowed)return send({error:"Unauthorized"},401);
 const {data:sources,error:claimError}=await db.rpc("job_claim_due_sources",workspace?{p_limit:4,p_workspace:workspace}:{p_limit:8});
 if(claimError)return send({error:"Could not claim sources",detail:claimError.message},500);
 if(!Array.isArray(sources)||sources.length===0)return send({status:"idle",scanned:0,inserted:0,detail:"Next source scans are not due"});
 const startedAt=new Date().toISOString();
 const summary:{workspace:string;source:string;found:number;matched:number;inserted:number;error?:string}[]=[];
 for(const src of sources as Source[]){
  let found=0,matchedRegion=0,matchedRoles=0,newCount=0,err="";
  const now=new Date().toISOString();
  try {
   const candidates=await getCandidates(src);
   found=candidates.length;
   const match=candidates.map(j=>({j,city:cityFor(j.location,j.description)}))
     .filter(x=>x.city).map(x=>{matchedRegion++;return {...x,rank:priority(x.j.title,x.j.description,x.city!)};})
     .filter(x=>worthReviewing(x.j.title)&&x.rank>=35)
     .sort((a,b)=>b.rank-a.rank);
   matchedRoles=match.length;
   const cap=src.slug==="canonicaljobs"?20:25;
   const shortlist=match.slice(0,cap);
   if(src.provider==="smartrecruiters"){
     for(let offset=0;offset<shortlist.length;offset+=4){
       await Promise.all(shortlist.slice(offset,offset+4).map(async ({j})=>{
         try{
           const endpoint="https://api.smartrecruiters.com/v1/companies/"+encodeURIComponent(src.slug)+"/postings/"+encodeURIComponent(j.id);
           const res=await fetch(endpoint,{headers:{"Accept":"application/json"},signal:AbortSignal.timeout(12000)});
           if(!res.ok)return;
           const detail=await res.json();
           const sections=detail?.jobAd?.sections||{};
           const body=[sections.jobDescription?.text,sections.qualifications?.text,sections.additionalInformation?.text].filter(Boolean).join(" ");
           if(body)j.description=clean(body);
           if(/^https:\/\//.test(detail?.postingUrl||""))j.url=detail.postingUrl;
           if(/^https:\/\//.test(detail?.applyUrl||""))j.applyUrl=detail.applyUrl;
         }catch(_e){/* still send to human screening with title and location; no claim of validated requirements */}
       }));
     }
   }
   const {data:old,error:oldError}=shortlist.length
    ?await db.from("job_leads").select("posting_url").eq("workspace_id",src.workspace_id).in("posting_url",shortlist.map(entry=>entry.j.url))
    :{data:[],error:null};
   if(oldError)throw new Error("Existing lead lookup failed: "+oldError.message);
   const known=new Set((old??[]).map(x=>x.posting_url));
   for(const candidate of shortlist){
     if(known.has(candidate.j.url))continue;
     const data={
       workspace_id:src.workspace_id,
       company:src.company,
       job_title:candidate.j.title.slice(0,300),
       city:candidate.city,
       country:"Saudi Arabia",
       source:"ATS "+src.provider+": "+src.company,
       external_job_id:candidate.j.id,
       posting_url:candidate.j.url,
       application_url:candidate.j.applyUrl||candidate.j.url,
       description:candidate.j.description.slice(0,6500),
       eligibility_notes:"اكتشاف آلي من بوابة وظائف عامة للشركة؛ لم يُتحقق بعد من شروط المؤهل والخبرة، وممنوع التقديم قبل تدقيق مستقل.",
       status:"discovered",
       scan_source_id:src.id,
       machine_priority:candidate.rank,
       machine_flags:{stage:"discovered_unreviewed",location_source:candidate.j.location,provider:src.provider},
       last_seen_at:now
     };
     const {data:inserted,error:e}=await db.from("job_leads").insert(data).select("id").single();
     if(e){
      if(e.code==="23505")continue;
      throw new Error("Lead insertion error: "+e.message);
     }
     newCount++;
     known.add(candidate.j.url);
     if(inserted?.id){
       await db.from("job_activity").insert({workspace_id:src.workspace_id,job_id:inserted.id,actor_section:"research",event_type:"job_discovered_ats",note:src.company+" • "+candidate.j.title+" • "+candidate.city,event_data:{provider:src.provider,source_id:src.id,machine_priority:candidate.rank}});
     }
   }
   const {error:sourceError}=await db.from("job_search_sources").update({last_status:"ok",last_total:found,last_matched:matchedRoles,last_inserted:newCount,last_checked_at:now,last_success_at:now,consecutive_errors:0,last_error:null}).eq("id",src.id);
   if(sourceError)throw new Error("Source update: "+sourceError.message);
  } catch(e){
    err=String(e instanceof Error?e.message:e).slice(0,450);
    const {data:record}=await db.from("job_search_sources").select("consecutive_errors").eq("id",src.id).single();
    const failures=Math.min(8,Number(record?.consecutive_errors??0)+1);
    await db.from("job_search_sources").update({last_status:"error",last_error:err,last_checked_at:now,consecutive_errors:failures,next_check_at:new Date(Date.now()+Math.min(failures*15,180)*60_000).toISOString()}).eq("id",src.id);
  }
  await db.from("job_search_scans").insert({workspace_id:src.workspace_id,source_id:src.id,provider:src.provider,company:src.company,status:err?"failed":"completed",started_at:now,total_found:found,matched_region:matchedRegion,matched_roles:matchedRoles,new_leads:newCount,error_text:err||null});
  summary.push({workspace:src.workspace_id,source:src.company,found,matched:matchedRoles,inserted:newCount,...(err?{error:err}:{})});
 }
 const inserted=summary.reduce((n,s)=>n+s.inserted,0);
 const scanned=summary.length;
 const errors=summary.filter(s=>s.error).length;
 const day=new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Riyadh",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date());
 for(const id of new Set(summary.map(item=>item.workspace))){
  const items=summary.filter(item=>item.workspace===id),failed=items.filter(item=>item.error).length;
  const {error}=await db.from("job_workflow_runs").insert({workspace_id:id,section:"research",run_date:day,status:failed===items.length?"failed":failed?"partial":"completed",found_count:items.reduce((n,item)=>n+item.inserted,0),errors_count:failed,started_at:startedAt,completed_at:new Date().toISOString(),notes:"ATS scan: "+items.length+" sources. Source-level details in job_search_scans."});
  if(error)return send({error:"Could not record search results"},500);
 }
 return send({status:errors?"partial":"completed",scanned,inserted,errors,results:summary.map(({workspace:_workspace,...item})=>item),auth_method:authMethod});
});
