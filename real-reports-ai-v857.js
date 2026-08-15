(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const DEPTS = ["PRINTING","STICKER","METAL_ID","STITCHING","OVERLOCK","FOLDING","KAAJ","BUTTON","TEAK_TANKI","THREAD_CUT","QC","PRESS","PACKING","DESPATCH"];
  const DEPT_LABEL = {PRINTING:"Printing",STICKER:"Sticker",METAL_ID:"Metal ID",STITCHING:"Karigar / Stitching",OVERLOCK:"Overlock",FOLDING:"Folding",KAAJ:"Kaaj",BUTTON:"Button",TEAK_TANKI:"Teak / Tanki",THREAD_CUT:"Thread Cut",QC:"QC",PRESS:"Press",PACKING:"Packing",DESPATCH:"Despatch"};

  const templates = [
    {id:"daily_control",title:"Daily Factory Control",hint:"आज कहाँ काम stuck है, क्या priority है",question:"आज REAL FACTORY में production, open queue, submit due, packing/despatch और stock में सबसे जरूरी pending काम और priority बताओ।",source:"upm_summary"},
    {id:"stuck_wip",title:"Stuck WIP",hint:"Department/worker पर रुका काम",question:"कौन से production lots या colours सबसे ज्यादा समय से stuck हैं? Department-wise priority और next action बताओ।",source:"upm_summary"},
    {id:"production_due",title:"Print / Sticker / ID Due",hint:"Cutting के बाद explicit due",question:"Print, Sticker और Metal ID में क्या pending है? Lot-wise important due और action बताओ।",table:"rr_print_due_activation_v839"},
    {id:"upm_flow",title:"UPM Open Queue",hint:"Assign due + Submit due current state",question:"UPM में department-wise assign due और submit due बताओ। किस department पर सबसे ज्यादा load है?",source:"upm_summary"},
    {id:"packing",title:"Packing Ready",hint:"Press-ready / packing pending",question:"Packing ready lots, pending packing और despatch readiness का summary बताओ।",rpc:"rr_fg_ready_packing_cards_v788",rpcArgs:{p_data_mode:"TEST"}},
    {id:"webstore",title:"Webstore Stock",hint:"Saleable और low stock",question:"Webstore saleable stock, low stock और sales attention वाले lots बताओ।",table:"rr_universal_sale_lot_v849"},
    {id:"sales_return",title:"Sales / Return",hint:"CPI, stock-out और return",question:"Latest sales CPI, sales return और stock impact का business summary बताओ।",table:"rr_fg_final_cpi_v787"},
    {id:"attendance",title:"Salary / Attendance",hint:"Payable, pending, attendance",question:"Workers की attendance, salary payable, outstanding और payment attention का summary बताओ।",table:"rr_monthly_payroll_management_v779_5"},
    {id:"accounts",title:"Accounts / Costing",hint:"Costing और financial attention",question:"Accounts और costing में important pending, unusual cost या management attention वाली चीजें बताओ।",table:"rr_costing_effective_result_v850"}
  ];

  let active = templates[0];
  let lastRows = [];
  let aiReady = false;
  const safe = (v) => String(v ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  const msg = (text, type="") => { $("pageMessage").textContent = text || ""; $("pageMessage").className = `rf-msg ${type}`.trim(); };
  const compactValue = (v) => {
    if (v == null || v === "") return "-";
    if (typeof v === "object") { try { const s = JSON.stringify(v); return s.length > 120 ? s.slice(0,117)+"…" : s; } catch { return String(v); } }
    const s = String(v); return s.length > 140 ? s.slice(0,137)+"…" : s;
  };

  async function requireAccess(){
    const {data,error}=await supabaseClient.auth.getSession();
    if(error||!data.session){location.replace("real-login.html");throw new Error("Login required.");}
    const {data:profile,error:pe}=await supabaseClient.from("rr_user_profiles").select("role_code,is_active").eq("auth_user_id",data.session.user.id).single();
    if(pe||!profile?.is_active) throw new Error("Active user profile required.");
    $("ownerName").textContent=["owner","admin"].includes(profile.role_code)?"SUPER ADMIN":String(profile.role_code||"USER").toUpperCase();
  }

  function renderTemplates(){
    const q=$("reportSearch").value.trim().toLowerCase();
    const list=templates.filter(t=>!q||`${t.title} ${t.hint} ${t.question}`.toLowerCase().includes(q));
    $("templateList").innerHTML=list.map(t=>`<button class="rf-template ${t.id===active.id?"active":""}" type="button" data-template="${safe(t.id)}"><b>${safe(t.title)}</b><small>${safe(t.hint)}</small></button>`).join("")||'<div class="rf-empty">No matching report.</div>';
    document.querySelectorAll("[data-template]").forEach(b=>b.onclick=()=>selectTemplate(b.dataset.template));
    $("suggestions").innerHTML=templates.slice(0,6).map(t=>`<button class="rf-chip" type="button" data-suggest="${safe(t.id)}">${safe(t.title)}</button>`).join("");
    document.querySelectorAll("[data-suggest]").forEach(b=>b.onclick=()=>selectTemplate(b.dataset.suggest));
  }

  async function selectTemplate(id){
    active=templates.find(t=>t.id===id)||active;
    $("activeTitle").textContent=active.title;
    $("questionBox").value=active.question;
    $("reportResult").textContent="";
    renderTemplates();
    await loadTemplateRows();
  }

  function pickKeys(row){
    const preferred=["lot_no","cb_no","art_no","department","department_code","worker_name","colour_code","colour","status","assign_due","submit_due","pending_qty","qty","pcs","available_pcs","sale_rate","amount","payable","outstanding","created_at","updated_at"];
    const all=Object.keys(row||{});
    const found=preferred.filter(k=>all.includes(k));
    return [...found,...all.filter(k=>!found.includes(k))].slice(0,7);
  }

  function renderRows(rows){
    lastRows=Array.isArray(rows)?rows:[];
    $("sourceMeta").textContent=`${lastRows.length} source row${lastRows.length===1?"":"s"}`;
    if(!lastRows.length){$("tableResult").innerHTML='<div class="rf-empty">No source rows found.</div>';return;}
    const cards=lastRows.slice(0,24).map((row,i)=>{
      const keys=pickKeys(row);
      const heading=row.lot_no||row.department||row.department_code||row.worker_name||`Row ${i+1}`;
      return `<article class="rf-data-card"><strong>${safe(heading)}</strong>${keys.map(k=>`<div class="rf-kv"><span>${safe(k.replaceAll("_"," "))}</span><span>${safe(compactValue(row[k]))}</span></div>`).join("")}</article>`;
    }).join("");
    $("tableResult").innerHTML=`<div class="rf-data-grid">${cards}</div>${lastRows.length>24?`<div class="rf-empty">Showing first 24 of ${lastRows.length} rows.</div>`:""}`;
  }

  async function loadUpmSummary(){
    const calls=DEPTS.map(async dept=>{
      const {data,error}=await supabaseClient.rpc("rr_upm_department_colour_due_card_v9109",{p_department_code:dept});
      if(error) return {department:DEPT_LABEL[dept]||dept,department_code:dept,error:error.message,assign_due:0,submit_due:0,lot_count:0};
      const lots=Array.isArray(data?.lots)?data.lots:[];
      const assign=Number(data?.assign_col_count ?? lots.reduce((s,l)=>s+(Array.isArray(l.assign_rows)?l.assign_rows.length:0),0));
      const submit=Number(data?.submit_col_count ?? lots.reduce((s,l)=>s+(Array.isArray(l.submit_rows)?l.submit_rows.length:0),0));
      let oldest=0;
      for(const l of lots){for(const r of [...(l.assign_rows||[]),...(l.submit_rows||[])]) oldest=Math.max(oldest,Number(r.working_seconds||0));}
      return {department:DEPT_LABEL[dept]||dept,department_code:dept,lot_count:lots.length,assign_due:assign,submit_due:submit,total_due:assign+submit,oldest_working_hours:Math.round(oldest/3600*10)/10};
    });
    return (await Promise.all(calls)).sort((a,b)=>(b.total_due||0)-(a.total_due||0));
  }

  async function loadTemplateRows(){
    msg(""); $("refreshBtn").disabled=true; $("refreshBtn").textContent="LOADING…";
    try{
      let rows=[];
      if(active.source==="upm_summary") rows=await loadUpmSummary();
      else if(active.rpc){const {data,error}=await supabaseClient.rpc(active.rpc,active.rpcArgs||{});if(error)throw error;rows=Array.isArray(data)?data:(Array.isArray(data?.rows)?data.rows:(data?[data]:[]));}
      else if(active.table){const {data,error}=await supabaseClient.from(active.table).select("*").limit(60);if(error)throw error;rows=data||[];}
      renderRows(rows); msg(`${active.title} source refreshed.`,"success");
    }catch(e){console.warn(e);lastRows=[];$("tableResult").innerHTML='<div class="rf-empty">Source unavailable या permission blocked.</div>';$("sourceMeta").textContent="source unavailable";msg(e.message||"Report source failed.","error");}
    finally{$("refreshBtn").disabled=false;$("refreshBtn").textContent="REFRESH SOURCE";}
  }

  async function checkAi(){
    const el=$("aiHealth");
    try{
      const {data,error}=await supabaseClient.functions.invoke("real-factory-ai",{body:{action:"HEALTH_CHECK"}});
      if(error)throw error;
      aiReady=Boolean(data?.ok&&data?.openai_configured);
      el.textContent=aiReady?`● AI connected · ${data?.version||"ready"}`:"● AI service connected · OpenAI not configured";
      el.className=`rf-ai-health ${aiReady?"ok":"bad"}`;
    }catch(e){aiReady=false;el.textContent="● AI connection unavailable";el.className="rf-ai-health bad";}
  }

  async function askAi(){
    const question=$("questionBox").value.trim();
    if(!question){msg("Question type karein.","error");return;}
    $("askAiBtn").disabled=true;$("askAiBtn").textContent="ANALYSING…";$("reportResult").textContent="";msg("");
    try{
      const body={action:"REPORT_ASK",question,report_type:active.id,data_mode:"TEST",source:"REPORTS_V9131",from_date:$("fromDate").value||null,to_date:$("toDate").value||null};
      const {data,error}=await supabaseClient.functions.invoke("real-factory-ai",{body});
      if(error)throw error;
      if(!data?.ok) throw new Error(data?.error||"AI report failed.");
      const answer=data.answer||data.text||data.message;
      if(!answer) throw new Error("AI returned no business answer.");
      $("reportResult").textContent=answer;
      const tier=data?.ai?.router?.tier||"AI"; const model=data?.ai?.model||"";
      $("sourceMeta").textContent=`${lastRows.length} source rows · ${tier}${model?" · "+model:""}`;
      msg("AI report generated from connected REAL FACTORY data.","success");
    }catch(e){console.warn(e);$("reportResult").textContent="AI answer नहीं मिला। नीचे source data सुरक्षित है; data देखकर manual decision लिया जा सकता है.";msg(e.message||"AI function unavailable.","error");}
    finally{$("askAiBtn").disabled=false;$("askAiBtn").textContent="ASK AI";}
  }

  async function copyAnswer(){
    const text=$("reportResult").textContent.trim();
    if(!text){msg("Copy करने के लिए AI answer नहीं है.","error");return;}
    try{await navigator.clipboard.writeText(text);msg("Answer copied.","success");}catch{msg("Copy blocked by browser.","error");}
  }

  $("reportSearch").addEventListener("input",renderTemplates);
  $("refreshBtn").addEventListener("click",loadTemplateRows);
  $("askAiBtn").addEventListener("click",askAi);
  $("copyBtn").addEventListener("click",copyAnswer);
  $("logoutBtn").addEventListener("click",async()=>{await supabaseClient.auth.signOut();location.replace("real-login.html");});

  document.addEventListener("DOMContentLoaded",async()=>{
    try{
      await requireAccess();
      const today=new Date().toISOString().slice(0,10);$("toDate").value=today;
      const d=new Date();d.setDate(d.getDate()-7);$("fromDate").value=d.toISOString().slice(0,10);
      renderTemplates();
      await Promise.all([checkAi(),loadTemplateRows()]);
    }catch(e){console.error(e);msg(e.message||"Reports page failed.","error");}
  });
})();
