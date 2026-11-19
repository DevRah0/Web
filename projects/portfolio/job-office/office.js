(() => {
  "use strict";
  const auth = window.JobOfficeAuth;
  const $ = s => document.querySelector(s);
  const all = s => [...document.querySelectorAll(s)];
  const { node, icon, setIcons } = window.OfficeUI;
  const num = value => new Intl.NumberFormat("ar-SA").format(value);
  const format = (value, options) => {
    if (!value || !Number.isFinite(+new Date(value))) return "—";
    return new Intl.DateTimeFormat("ar-SA-u-ca-gregory", {timeZone:"Asia/Riyadh",...options}).format(new Date(value));
  };
  const stamp = t => format(t,{month:"short",day:"numeric",hour:"numeric",minute:"2-digit"});
  const dayKey = t => new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Riyadh",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date(t));
  const cities = {Jeddah:"جدة",Makkah:"مكة المكرمة",Madinah:"المدينة المنورة",Taif:"الطائف",Riyadh:"الرياض"};
  const city = s => cities[s] || s || "—";
  const departments = {research:["البحث عن فرص","search"],screening:["تدقيق الأهلية","review"],applying:["إرسال الطلبات","send"],followup:["متابعة الردود","mail"],manager:["إدارة المكتب","case"]};
  const views = {overview:"نظرة عامة",applications:"الفرص والطلبات",events:"سجل النشاط",connections:"الاتصالات"};
  const blank = () => ({jobs:[],reviews:[],applications:[],replies:[],events:[],runs:[],sources:[],mail:null});
  const demo = blank();
  demo.jobs = [["1","مهندس شبكات","شركة المثال للتقنية","Jeddah","applied","email"],["2","مطوّر تطبيقات","مؤسسة المثال الرقمية","Makkah","approved","portal"],["3","أخصائي دعم فني","مركز المثال","Taif","discovered","email"]].map(([id,job_title,company,city,status,application_channel])=>({id,job_title,company,city,status,application_channel}));
  demo.reviews=[{job_id:"1",approved_to_apply:true},{job_id:"2",approved_to_apply:true}];
  demo.applications=[{job_id:"1",submitted_at:new Date().toISOString(),status:"submitted",confirmation_evidence:"إثبات توضيحي"}];
  let data=blank(),mode="locked",workspace=null,page="overview",limit=24,serial=0,pending=null,lastSync=null,mailError="";
  const jobMap=key=>new Map(data[key].map(r=>[r.job_id,r]));
  const pill=(s,cls="")=>node("span","state "+cls,s);
  function empty(message, isLocked=false){
    const e=node("div","empty");e.append(icon(isLocked?"lock":"file"),node("span","",message));return e;
  }
  const locked=()=>mode==="locked"||mode==="loading";
  function notice(t=""){const el=$("#notice");el.textContent=t;el.hidden=!t;}
  function row(title,sub,extra,mark){
    const e=node("div","row"),body=node("div","row-main");const label=node("b","",title);label.dir="auto";
    body.append(label);if(sub){const small=node("small","",sub);small.dir="auto";body.append(small);}
    if(mark)e.append(icon(mark,"team-icon"));e.append(body);if(extra)e.append(extra);return e;
  }
  function status(j,a){
    const labels={submitted:["تم التقديم","good"],interview:["مقابلة","info"],offer:["عرض وظيفي","good"],hired:["تم التوظيف","good"],withdrawn:["منسحب",""],blocked:["يحتاج إجراء","warn"],draft:["مسودة","info"],rejected:["مرفوض",""]};
    if(a&&labels[a.status])return labels[a.status];
    return ({approved:["مؤهلة","good"],in_review:["قيد التدقيق","info"],applied:["مسجّل كمقدّم",""],applying:["قيد التقديم","info"],discovered:["مكتشفة","info"],closed:["مغلقة",""],rejected:["غير مناسبة",""]})[j.status]||["بانتظار التدقيق",""];
  }
  const sent=a=>Boolean(a?.submitted_at&&(a.confirmation_evidence||a.confirmation_code));
  function jobsList(entries){
    const frag=document.createDocumentFragment(), apps=jobMap("applications");
    if(!entries.length){frag.append(empty(locked()?"تظهر فرصك بعد تسجيل الدخول.":"لا توجد فرص تطابق هذا العرض.",locked()));return frag;}
    for(const j of entries){
      const b=node("button","job-row");b.type="button";const m=node("span","row-main");const t=node("b","",j.job_title),c=node("small","",j.company);t.dir=c.dir="auto";m.append(t,c);
      b.append(m,node("span","city",city(j.city)),pill(...status(j,apps.get(j.id))),icon("chevron"));
      b.addEventListener("click",()=>jobDetails(j));frag.append(b);
    }return frag;
  }
  function jobDetails(j){
    const a=jobMap("applications").get(j.id),r=jobMap("reviews").get(j.id);
    const wrap=node("div"),title=node("h2","",j.job_title);title.dir="auto";title.id="dialog-title";wrap.append(icon("case","dialog-icon"),title,node("p","",j.company));
    const dl=node("dl","details-grid"), fields=[["المدينة",city(j.city)],["الحالة",status(j,a)[0]],["القناة",({email:"البريد",portal:"بوابة الشركة",both:"البريد أو البوابة"})[j.application_channel]||"غير محددة"],["آخر تحقق من الشروط",r?.reviewed_at?stamp(r.reviewed_at):null],["تاريخ التقديم",a?.submitted_at?stamp(a.submitted_at):null],["دليل الإرسال",a?.confirmation_evidence||a?.confirmation_code],["سبب التعثر",a?.blocked_reason],["ملاحظة التدقيق",r?.reviewer_notes]];
    for(const [k,v] of fields){if(!v)continue;const e=node("div"),dd=node("dd","",v);dd.dir="auto";e.append(node("dt","",k),dd);dl.append(e);}wrap.append(dl);
    const href=j.posting_url||j.application_url;
    if(href&&/^https:\/\//i.test(href)){const link=node("a","btn note-link","فتح الإعلان الأصلي");link.href=href;link.target="_blank";link.rel="noopener noreferrer";wrap.append(link);}
    show(wrap,"dialog-title");
  }
  function paintJobs(){
    const apps=jobMap("applications"),reviews=jobMap("reviews"),q=$("#query").value.trim().toLocaleLowerCase(),f=$("#filter").value;
    const jobs=data.jobs.filter(j=>{const a=apps.get(j.id);return (!q||[j.company,j.job_title,j.city,city(j.city)].join(" ").toLocaleLowerCase().includes(q)) &&
      (f==="all" || (f==="submitted"&&sent(a)) || (f==="approved"&&j.status==="approved") || (f==="pending"&&["in_review","discovered"].includes(j.status)&&!reviews.has(j.id)) || (f==="blocked"&&a?.status==="blocked"&&j.status!=="closed") || (["email","portal"].includes(f)&&[f,"both"].includes(j.application_channel)));});
    $("#jobs").replaceChildren(jobsList(jobs.slice(0,limit)));$("#more").hidden=jobs.length<=limit;
    $("#list-count").textContent=locked()?"":num(jobs.length)+" من الفرص";
    $("#recent").replaceChildren(jobsList(data.jobs.slice(0,4)));
  }
  function paintStats(){
    const today=dayKey(Date.now()), qualified=data.jobs.filter(j=>j.status==="approved").length;
    const submissions=data.applications.filter(sent), n=submissions.filter(a=>dayKey(a.submitted_at)===today).length;
    const work=[["search","فرص مكتشفة",data.jobs.length,"إجمالي الفرص في المكتب"],["review","فرص معتمدة",qualified,"اجتازت تدقيق الملاءمة"],["send","تقديمات اليوم",n, data.mail?.target!=null?"الهدف اليومي "+num(data.mail.target):"بحسب توقيت الرياض"],["mail","ردود تحتاجك",data.replies.filter(r=>r.requires_user_action).length,"تنتظر مراجعتك"]];
    $("#stats").replaceChildren(...work.map(([ic,label,v,s])=>{const e=node("div","stat"),h=node("div","stat-top");h.append(node("span","",label),icon(ic));e.append(h,node("b","stat-value",locked()?"—":num(v)),node("small","",s));return e;}));
    const chart=$("#chart");chart.replaceChildren();
    if(locked()){const e=node("div","chart-locked");e.append(icon("chart"),node("span","","يعرض المخطط تقديماتك المسجلة."));const b=node("button","","عرض بياناتي");b.onclick=login;e.append(b);chart.append(e);return;}
    const days=Array.from({length:7},(_,i)=>{const date=Date.now()-(6-i)*86400000;return {date,n:submissions.filter(a=>dayKey(a.submitted_at)===dayKey(date)).length};});
    const head=node("div","chart-top");head.append(node("b","",num(days.reduce((s,d)=>s+d.n,0))),node("span","","طلبات خلال الأسبوع"));
    const bars=node("div","bars"),max=Math.max(1,...days.map(d=>d.n));
    for(const [i,d] of days.entries()){const col=node("div","bar-cell"),track=node("div","bar-track"),bar=node("div","bar"+(i===6?" last":""));bar.style.height=(100*d.n/max)+"%";track.append(bar);col.append(node("strong","",num(d.n)),track,node("small","",format(d.date,{weekday:"short"})));bars.append(col);}
    chart.append(head,bars);
  }
  function paintTeam(){
    $("#team").replaceChildren(...Object.entries(departments).map(([id,[name,ic]])=>{
      const r=data.runs.find(r=>r.section===id),age=r?(Date.now()-Date.parse(r.started_at))/60000:Infinity;
      let val=["بانتظار سجل",""];if(locked())val=["خاص",""];else if(mode==="demo")val=["مثال",""];else if(r)val=r.status==="failed"?["متعثر","warn"]:age>120?["آخر جولة قديمة","warn"]:r.status==="started"?["قيد التنفيذ","info"]:r.status==="partial"?["فحص جزئي","warn"]:["جولة مكتملة","good"];
      const e=row(name,r?stamp(r.started_at):"",pill(...val),ic);const link=node("a","");link.href="./manager.html?target="+id;link.append(...e.childNodes);link.className="row";return link;
    }));
  }
  function paintActivity(){
    const host=$("#events-list"),replies=$("#replies");
    host.replaceChildren(...data.events.slice(0,45).map(e=>row(departments[e.actor_section]?.[0]||"المكتب",(e.note||e.event_type)+" · "+stamp(e.occurred_at),null,departments[e.actor_section]?.[1]||"activity")));
    if(!host.childElementCount)host.append(empty(locked()?"سجّل الدخول لعرض سجل النشاط.":"لا توجد أحداث في هذا العرض.",locked()));
    replies.replaceChildren(...data.replies.slice(0,35).map(e=>row(e.subject||"ردّ على طلب",stamp(e.occurred_at),e.requires_user_action?pill("للمراجعة","warn"):null,"mail")));
    if(!replies.childElementCount)replies.append(empty(locked()?"ردود الشركات خاصة بحسابك.":"لم يُسجّل رد مرتبط بطلب في هذا العرض.",locked()));
  }
  function paintMail(){
    const mail=$("#mail"),queue=$("#queue"),list=$("#sources"),m=data.mail;mail.replaceChildren();queue.replaceChildren();list.replaceChildren();
    $("#source-count").textContent=locked()?"":num(data.sources.filter(s=>s.is_enabled).length)+" مصادر مفعّلة";
    for(const s of data.sources){const fresh=s.last_checked_at && Date.now()-Date.parse(s.last_checked_at)<3600000;
      list.append(row(s.company,s.last_checked_at?stamp(s.last_checked_at):"بانتظار أول فحص",!s.is_enabled?pill("موقوف"):s.last_status==="error"?pill("تعثر","warn"):fresh?pill("فحص حديث","good"):pill("بانتظار فحص","warn"),"links"));}
    if(!list.childElementCount)list.append(empty(locked()?"سجّل الدخول لعرض المصادر.":"لا توجد مصادر في هذا العرض.",locked()));
    if(!m){const msg=locked()?"سجّل الدخول لعرض حالة الربط.":mailError||"حالة الربط غير متاحة في المعاينة.";mail.append(empty(msg,locked()));queue.append(empty(locked()?"يظهر الطابور في حساب المدير.":"لا تتوفر بيانات الطابور.",locked()));return;}
    const state=(v,yes,no)=>v?pill(yes,"good"):pill(no,"warn");
    const fresh=v=>v&&Date.now()-Date.parse(v)<=45*60000;
    mail.append(row("Gmail المهني",m.account||"لم يُحدد الحساب",state(m.connected&&fresh(m.bridge_seen),"متصل","بانتظار اتصال"),"mail"),
      row("عامل الإرسال",m.worker_seen?"آخر فحص "+stamp(m.worker_seen):"بانتظار أول فحص",!m.enabled?pill("متوقف"):state(fresh(m.worker_seen),"جاهز","بانتظار فحص"),"send"),
      row("آخر فحص للوارد",m.inbox_checked?stamp(m.inbox_checked):"بانتظار أول فحص",null,"clock"),
      row("السيرة الذاتية","PDF",state(m.resume,"محفوظة","مطلوبة"),"file"));
    const b=node("button","btn note-link",m.enabled?"إيقاف إرسال Gmail مؤقتًا":"تشغيل إرسال Gmail");b.type="button";b.onclick=async()=>{b.disabled=true;try{if(!await auth.valid())return expired();const next=await control({type:"mail_switch",enabled:!m.enabled});data.mail=next;paintMail();notice(next.enabled?"تم تشغيل إرسال Gmail.":"أُوقف إرسال Gmail للطلبات الجديدة.");}catch(err){notice(err.message);}finally{b.disabled=false;}};mail.append(b);
    const settings=node("a","text-link note-link","إدارة ملف السيرة");settings.style.marginInlineStart=".7rem";settings.href="./manager.html#resume";mail.append(settings);
    const labels={queued:"جاهز للإرسال",claimed:"جارٍ الإرسال",uncertain:"بانتظار التحقق",sent:"قُبل الإرسال",cancelled:"ملغى"};
    for(const item of m.queue_items||[]){queue.append(row(item.job_title,item.company,pill(labels[item.status]||item.status,item.status==="sent"?"good":item.status==="uncertain"?"warn":"info")));}
    if(!queue.childElementCount)queue.append(empty("الطابور فارغ. تظهر هنا الطلبات المعتمدة ذات بريد تقديم موثّق."));
  }
  function render(){
    const isLive=mode==="live",isDemo=mode==="demo";$("#mode-label").textContent=isLive?"آخر تحديث "+stamp(lastSync):isDemo?"بيانات توضيحية":"بيانات خاصة";
    $("#hero-title").textContent=isLive?"نظرة على يومك":isDemo?"معاينة المكتب":"مكتبك للتوظيف";
    $("#hero-copy").textContent=isDemo?"هذه أمثلة توضيحية للفرص وحالات الطلبات.":"تابع فرصك في الغربية، من اكتشاف الإعلان حتى وصول ردّ الشركة.";
    $("#hero-action").textContent=isLive?"تصفّح الفرص":"دخول مساحة العمل";$("#hero-secondary").textContent=isLive?"حالة الاتصالات":isDemo?"إنهاء المعاينة":"معاينة المكتب";
    $("#authbtn span").textContent=auth.session?"حساب المدير":"دخول الحساب";
    paintStats();paintTeam();paintJobs();paintActivity();paintMail();
  }
  function setMenu(open){document.body.classList.toggle("menu-open",open);$("#scrim").hidden=!open;$("#menu").setAttribute("aria-expanded",String(open));if(open)$("#navigation nav a").focus();}
  function route(){
    const routeMap={office:"overview",settings:"connections",activity:"events"};const key=location.hash.slice(1);page=Object.hasOwn(views,key)?key:routeMap[key]||"overview";
    all("[data-view]").forEach(e=>e.hidden=e.dataset.view!==page);
    all("[data-page]").forEach(e=>{if(e.dataset.page===page)e.setAttribute("aria-current","page");else e.removeAttribute("aria-current");});
    $("#crumb").textContent=views[page];document.title="مكتب التوظيف | "+views[page];setMenu(false);window.scrollTo(0,0);
  }
  function show(content,title){const dlg=$("#dialog");$("#dialog-content").replaceChildren(content);dlg.setAttribute("aria-labelledby",title);if(!dlg.open)dlg.showModal();}
  function login(){
    const form=$("#auth-form").content.cloneNode(true);setIcons(form);show(form,"auth-title");
    async function submit(signUp){
      const f=$("#login-form");if(!f.reportValidity()||f.getAttribute("aria-busy")==="true")return;
      f.setAttribute("aria-busy","true");const b=[...f.querySelectorAll("button")];b.forEach(x=>x.disabled=true);$("#form-msg").textContent="جار التحقق…";
      try{const email=f.elements.email.value.trim(),password=f.elements.password.value;
        if(signUp){if(!await auth.signUp(email,password)){$("#form-msg").textContent="افتح رسالة تأكيد البريد ثم عُد إلى المكتب.";return;}}
        else await auth.signIn(email,password); f.elements.password.value="";$("#dialog").close();await refresh();
      }catch(err){const msg=$("#form-msg");if(msg)msg.textContent=err.message;else notice(err.message);}
      finally{f.removeAttribute("aria-busy");b.forEach(x=>x.disabled=false);}
    }
    $("#login-form").addEventListener("submit",e=>{e.preventDefault();submit(false);});$("#register").onclick=()=>submit(true);
  }
  function expired(){serial++;pending=null;mode="locked";workspace=null;data=blank();lastSync=null;notice("انتهت الجلسة. سجّل الدخول لعرض بياناتك.");render();}
  function control(payload){return auth.request(auth.project+"/functions/v1/job-manager-control",{method:"POST",headers:{...auth.headers(),"Content-Type":"application/json"},body:JSON.stringify(payload)});}
  const get=(table,q)=>auth.request(auth.project+"/rest/v1/"+table+"?"+q,{headers:auth.headers()});
  async function records(table,cols,w,order){
    const out=[];let batch;
    do{batch=await get(table,"select="+cols+"&"+w+"&order="+order+"&limit=400&offset="+out.length);out.push(...batch);}while(batch.length===400);
    return out;
  }
  async function load(id){
    if(!await auth.valid()){if(id===serial)expired();return;}
    const ws=await get("job_workspaces","select=id&order=created_at&limit=1");if(!ws.length)throw Error("لم يُربط الحساب بمكتب التوظيف. استخدم حساب المدير المعتمد.");
    const w="workspace_id=eq."+encodeURIComponent(ws[0].id);
    const [jobs,reviews,applications,replies,events,runs,sources,connection]=await Promise.all([
      records("job_leads","id,company,job_title,city,status,application_channel,posting_url,application_url,created_at",w,"created_at.desc,id"),
      records("job_reviews","job_id,approved_to_apply,reviewer_notes,reviewed_at",w,"job_id"),
      records("job_applications","job_id,status,submitted_at,confirmation_evidence,confirmation_code,blocked_reason",w,"job_id"),
      records("job_messages","id,subject,requires_user_action,occurred_at",w+"&direction=eq.incoming&application_id=not.is.null","occurred_at.desc,id"),
      get("job_activity","select=actor_section,event_type,note,occurred_at&"+w+"&order=occurred_at.desc&limit=70"),
      get("job_latest_workflow_runs","select=section,status,started_at,completed_at&"+w),
      get("job_search_sources","select=company,is_enabled,last_checked_at,last_status&"+w+"&order=company"),
      control({type:"mail_status"}).then(mail=>({mail})).catch(err=>({error:err.message}))]);
    if(!auth.session||id!==serial)return;data={jobs,reviews,applications,replies,events,runs,sources,mail:connection.mail||null};
    workspace=ws[0].id;mailError=connection.error||"";mode="live";lastSync=Date.now();notice();render();
  }
  async function refresh(){
    if(!auth.session)return;if(pending)return pending;const id=++serial;
    pending=load(id).catch(err=>{if(id!==serial)return;if(!auth.session){expired();return;}notice("تعذّر تحديث البيانات. "+err.message);if(mode!=="live"){mode="locked";data=blank();}render();}).finally(()=>{if(id===serial)pending=null;});return pending;
  }
  function logout(){auth.signOut();expired();notice();$("#dialog").close();}
  $("#authbtn").onclick=()=>{if(!auth.session)return login();const w=node("div"),h=node("h2","","حساب المدير");h.id="account-title";const retry=node("button","btn primary","تحديث البيانات"),b=node("button","btn","تسجيل الخروج"),buttons=node("div","form-actions");retry.onclick=()=>{$("#dialog").close();refresh();};b.onclick=logout;buttons.append(retry,b);w.append(h,buttons);show(w,"account-title");};
  $("#hero-action").onclick=()=>{if(mode==="live")location.hash="applications";else if(auth.session)refresh();else login();};
  $("#hero-secondary").onclick=()=>{if(mode==="live"){location.hash="connections";return;}if(auth.session)return refresh();mode=mode==="demo"?"locked":"demo";data=mode==="demo"?demo:blank();render();};
  $("#scan").onclick=async e=>{if(locked()||mode==="demo")return login();const b=e.currentTarget;b.disabled=true;try{if(!await auth.valid())return expired();const r=await control({type:"command",action:"search_now",target_section:"research"});await refresh();notice(r.reply||"تم تسجيل جولة البحث.");}catch(err){notice(err.message);}finally{b.disabled=false;}};
  $("#refresh").onclick=async e=>{if(!auth.session){if(mode!=="demo")login();return;}const b=e.currentTarget;b.disabled=true;try{await refresh();}finally{b.disabled=false;}};
  $("#more").onclick=()=>{limit+=24;paintJobs();};for(const id of ["#query","#filter"])$(id).addEventListener("input",()=>{limit=24;paintJobs();});
  $("#menu").onclick=()=>setMenu(!document.body.classList.contains("menu-open"));$("#scrim").onclick=()=>{setMenu(false);$("#menu").focus();};
  $("#dialog .close").onclick=()=>$("#dialog").close();
  document.addEventListener("keydown",e=>{if(e.key==="Escape"&&document.body.classList.contains("menu-open")){setMenu(false);$("#menu").focus();}});
  window.addEventListener("hashchange",route);
  window.addEventListener("storage",e=>{if(e.key!==null&&e.key!=="job-office-manager-session-v1")return;serial++;pending=null;data=blank();mode="locked";render();if(auth.session)refresh();else if($("#dialog").open)$("#dialog").close();});
  const clock=()=>$("#clock").textContent="الرياض · "+format(Date.now(),{hour:"numeric",minute:"2-digit"});
  const filter=new URLSearchParams(location.search).get("filter");if([...$("#filter").options].some(o=>o.value===filter))$("#filter").value=filter;
  setIcons();clock();route();render();setInterval(clock,30000);
  setInterval(()=>{if(auth.session&&!document.hidden)refresh();},60000);
  document.addEventListener("visibilitychange",()=>{if(auth.session&&!document.hidden)refresh();});
  (async()=>{try{await auth.readConfirmation();}catch(err){notice(err.message);}if(auth.session)await refresh();})();
})();
