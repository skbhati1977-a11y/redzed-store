(()=>{
  "use strict";
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const fmt=v=>{const n=Number(v);return Number.isFinite(n)?new Intl.NumberFormat("en-IN",{maximumFractionDigits:2}).format(n):String(v??"—")};
  const money=v=>`₹${fmt(v)}`;
  const today=()=>new Date().toISOString().slice(0,10);
  const monthStart=()=>{const d=new Date();d.setDate(1);return d.toISOString().slice(0,10)};
  const state={client:null,ledgers:[],suggestions:[],selected:null,bookRows:[],materialTypes:[],materials:[],materialSourceRows:[],materialRequests:[],profile:null,busy:false};

  function message(id,text,type=""){const el=$(id);if(!el)return;el.textContent=text||"";el.className=`msg ${type}`.trim()}
  function errorText(e){return e?.message||e?.error_description||e?.details||String(e||"Unknown error")}
  function setBusy(btn,on,label="Working…"){if(!btn)return;if(on){btn.dataset.old=btn.textContent;btn.textContent=label;btn.disabled=true}else{btn.textContent=btn.dataset.old||btn.textContent;btn.disabled=false}}
  function mode(){return String($("dataMode")?.value||"TEST").toUpperCase()}

  function resolveClient(){
    if(state.client)return state.client;
    if(window.supabaseClient){state.client=window.supabaseClient;return state.client}
    if(window.RR?.client){state.client=window.RR.client;return state.client}
    if(window.RR?.supabaseClient){state.client=window.RR.supabaseClient;return state.client}
    const cfg=window.RR_CONFIG||{};
    const url=cfg.supabaseUrl||cfg.supabase_url||cfg.url||window.SUPABASE_URL;
    const key=cfg.supabaseAnonKey||cfg.supabase_anon_key||cfg.anonKey||cfg.anon_key||window.SUPABASE_ANON_KEY;
    if(url&&key&&window.supabase?.createClient){state.client=window.supabase.createClient(url,key);return state.client}
    throw new Error("Accounts connection is not ready. Keep the existing canonical config.js in the GitHub root.");
  }

  async function rpc(name,args={}){const c=resolveClient();const r=await c.rpc(name,args);if(r.error)throw r.error;return r.data}
  async function table(name,select="*"){const c=resolveClient();const r=await c.from(name).select(select);if(r.error)throw r.error;return r.data||[]}

  function zeroClean(root=document){root.querySelectorAll('input[type=number]').forEach(i=>{i.addEventListener('focus',()=>{if(Number(i.value||0)===0)i.value=""});i.addEventListener('blur',()=>{if(i.value==="")i.value="0"})})}
  function enterFlow(root){if(!root)return;root.addEventListener('keydown',e=>{if(e.key!=="Enter"||e.shiftKey||e.ctrlKey||e.altKey)return;const t=e.target;if(!["INPUT","SELECT"].includes(t.tagName)||t.type==="search")return;const els=[...root.querySelectorAll('input,select,button.primary')].filter(x=>!x.disabled&&x.tabIndex!==-1&&x.offsetParent!==null);const i=els.indexOf(t);if(i<0)return;e.preventDefault();(els[i+1]||root.querySelector('button.primary'))?.focus();if(!els[i+1])root.querySelector('button.primary')?.click()})}

  document.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-tab]').forEach(x=>x.classList.remove('active'));b.classList.add('active');document.querySelectorAll('.page').forEach(x=>x.classList.add('hidden'));$(b.dataset.tab)?.classList.remove('hidden');if(b.dataset.tab==="ledgers"&&!state.bookRows.length)loadDayBook().catch(()=>{})});

  function calc(){const q=Number($("qty")?.value||0),r=Number($("rate")?.value||0);if($("total"))$("total").value=(q*r).toFixed(2)}
  function materialLabelFor(code){return ({REGULAR_CLOTH:"Cloth Name",MATCHING_CLOTH:"Matching Cloth Name",STICKER:"Sticker Name",METAL_ID:"Metal ID Name",PANNI:"Panni Name",GATTA:"Gatta Name",BOX:"Box Name",PASTING_ROLL:"Pasting Name",KANDHI_TAPE:"Kandhi Tape Name"})[code]||"Material Name"}
  const sourceManagedTypes=new Set(["REGULAR_CLOTH","MATCHING_CLOTH","STICKER","METAL_ID"]);
  function normalizeText(s){return String(s||"").trim().toLowerCase().replace(/[^a-z0-9]+/g,"")}
  function levenshtein(a,b){a=normalizeText(a);b=normalizeText(b);const m=a.length,n=b.length;if(!m)return n;if(!n)return m;let prev=Array.from({length:n+1},(_,i)=>i);for(let i=1;i<=m;i++){let cur=[i];for(let j=1;j<=n;j++){cur[j]=Math.min(cur[j-1]+1,prev[j]+1,prev[j-1]+(a[i-1]===b[j-1]?0:1))}prev=cur}return prev[n]}
  function clientSimilarity(a,b){a=normalizeText(a);b=normalizeText(b);if(!a||!b)return 0;if(a===b)return 1;const d=levenshtein(a,b),mx=Math.max(a.length,b.length);return mx?1-d/mx:0}

  function renderMaterialSuggestions(rows,query){
    const box=$("materialSuggestions"),note=$("materialMatchNote"),add=$("requestNewMaterial");
    if(!box)return;
    const q=String(query||"").trim();
    if(!q){box.classList.add("hidden");box.innerHTML="";note.textContent="";add.classList.add("hidden");return}
    const scored=(rows||[]).map((r,i)=>({...r,_i:i,_score:clientSimilarity(q,r.material_name||r.material_no)}))
      .sort((a,b)=>b._score-a._score);
    const close=scored.filter(r=>r._score>=0.72||normalizeText(r.material_name).includes(normalizeText(q))||normalizeText(q).includes(normalizeText(r.material_name))).slice(0,8);
    if(close.length){
      box.innerHTML=close.map(r=>`<button type="button" class="suggestion" data-mi="${r._i}"><b>${esc(r.material_name||r.material_no)}</b><small>${esc(r.material_no||r.source_type||"Mapped")} · match ${Math.round(r._score*100)}%</small></button>`).join("");
      box.classList.remove("hidden");
      box.querySelectorAll("[data-mi]").forEach(b=>b.onclick=()=>selectMappedMaterial(Number(b.dataset.mi)));
      note.textContent="Similar/existing name found — select existing instead of creating duplicate.";
      add.classList.add("hidden");
    }else{
      box.innerHTML='<div class="empty">No similar mapped name found.</div>';
      box.classList.remove("hidden");
      note.textContent="No spelling/similarity match. Add New request is available.";
      add.classList.remove("hidden");
    }
  }
  function selectMappedMaterial(index){
    const r=state.materialSourceRows[index];if(!r)return;
    $("materialSearch").value=r.material_name||r.material_no||"";
    $("material").value=String(index);
    if($("uom"))$("uom").value=r.purchase_unit||r.stock_unit||"";
    $("materialSuggestions").classList.add("hidden");
    $("requestNewMaterial").classList.add("hidden");
    $("materialMatchNote").textContent=`Mapped existing: ${r.material_name||r.material_no}`;
    calc();
  }
  async function loadMappedMaterialsForType(search=""){
    const code=$("type")?.value||"",label=$("materialLabel");
    if(label?.childNodes?.[0])label.childNodes[0].nodeValue=materialLabelFor(code)+" ";
    const hidden=$("material");
    if(!code){state.materialSourceRows=[];hidden.innerHTML='<option value="">Select material…</option>';if($("uom"))$("uom").value="";return}
    try{
      const rows=await rpc("rr_material_source_search_v805_1",{p_type_code:code,p_search:String(search||""),p_data_mode:mode(),p_limit:50});
      state.materialSourceRows=Array.isArray(rows)?rows:[];
      hidden.innerHTML='<option value="">Select material…</option>'+state.materialSourceRows.map((r,i)=>`<option value="${i}">${esc([r.material_no,r.material_name].filter(Boolean).join(" · "))}</option>`).join("");
      if(search)renderMaterialSuggestions(state.materialSourceRows,search);
    }catch(e){
      console.error("Mapped material load failed",e);state.materialSourceRows=[];message("pmsg",`Material mapping: ${errorText(e)}`,"error");
    }
  }
  function dynamicLabel(){
    if($("materialSearch"))$("materialSearch").value="";
    if($("materialMatchNote"))$("materialMatchNote").textContent="";
    if($("requestNewMaterial"))$("requestNewMaterial").classList.add("hidden");
    loadMappedMaterialsForType("").catch(console.error);
  }
  function syncMappedMaterial(){const i=Number($("material")?.value);selectMappedMaterial(i)}

  let materialSearchTimer=null;
  function searchMaterialInput(){
    clearTimeout(materialSearchTimer);
    materialSearchTimer=setTimeout(()=>loadMappedMaterialsForType($("materialSearch")?.value||"").catch(console.error),180);
  }

  function openNewMaterialRequest(){
    const code=$("type")?.value||"",name=String($("materialSearch")?.value||"").trim();
    if(!code||!name)return;
    $("newMaterialType").value=code;
    $("newMaterialName").value=name;
    $("newMaterialNo").value="";
    const type=state.materialTypes.find(t=>String(t.type_code)===code)||{};
    const pu=String(type.default_purchase_unit||"PCS").toUpperCase();
    const cu=String(type.default_consumption_unit||pu||"PCS").toUpperCase();
    for(const [id,val] of [["newMaterialPurchaseUnit",pu],["newMaterialStockUnit",pu],["newMaterialConsumptionUnit",cu]]){if($(id)&&[...$(id).options].some(o=>o.value===val))$(id).value=val}
    $("newMaterialSimilar").textContent=sourceManagedTypes.has(code)
      ? `${code.replaceAll("_"," ")} is source-managed. Approval will not create a generic duplicate; Super Admin must map/create it in its canonical source master.`
      : "No similar mapped material found. This request will remain pending until Super Admin approves.";
    $("newMaterialMsg").textContent="";
    $("newMaterialModal").classList.remove("hidden");
  }
  function closeNewMaterialRequest(){$("newMaterialModal").classList.add("hidden")}

  async function submitNewMaterialRequest(){
    const btn=$("submitNewMaterialRequest"),code=$("newMaterialType").value,name=$("newMaterialName").value.trim();
    if(!name)return message("newMaterialMsg","Material Name required.","error");
    setBusy(btn,true,"Sending…");
    try{
      const data=await rpc("rr_material_name_request_v8076",{
        p_type_code:code,p_requested_name:name,p_material_no:$("newMaterialNo").value||null,
        p_purchase_unit:$("newMaterialPurchaseUnit").value,p_stock_unit:$("newMaterialStockUnit").value,
        p_consumption_unit:$("newMaterialConsumptionUnit").value,p_data_mode:mode()
      });
      const matches=Array.isArray(data?.suggested_matches)?data.suggested_matches:[];
      if(data?.blocked_by_match){
        message("newMaterialMsg",`Similar existing name found: ${matches.slice(0,3).map(x=>x.display_name).join(", ")}. Select existing; Add New blocked.`,"error");
      }else{
        message("newMaterialMsg",`Request ${data?.request_id||""} sent for Super Admin approval.`,"ok");
        await loadMaterialRequests().catch(()=>{});
      }
    }catch(e){message("newMaterialMsg",errorText(e),"error")}
    finally{setBusy(btn,false)}
  }

  async function loadMaterialRequests(){
    const box=$("materialRequestResult");if(!box)return;
    try{
      const data=await rpc("rr_material_name_requests_v8076",{p_status:null,p_limit:100});
      state.materialRequests=Array.isArray(data)?data:[];
      if(!state.materialRequests.length){box.innerHTML='<div class="empty">No material name requests.</div>';return}
      box.innerHTML=`<div class="scroll"><table><thead><tr><th>Requested</th><th>Type</th><th>Name</th><th>Suggested</th><th>Status</th><th>Action</th></tr></thead><tbody>`+
        state.materialRequests.map(r=>`<tr><td>${esc(new Date(r.requested_at).toLocaleString())}</td><td>${esc(r.type_code||r.entity_type)}</td><td><b>${esc(r.requested_name)}</b></td><td>${esc((r.suggested_matches||[]).slice(0,3).map(x=>x.display_name).join(", ")||"—")}</td><td>${esc(r.status)}</td><td>${r.status==="PENDING"?`<button data-mapreq="${r.id}">Map Existing</button> <button data-apreq="${r.id}" class="primary">Approve New</button> <button data-rejreq="${r.id}">Reject</button>`:"—"}</td></tr>`).join("")+
        `</tbody></table></div>`;
      box.querySelectorAll("[data-apreq]").forEach(b=>b.onclick=()=>decideMaterialRequest(b.dataset.apreq,"APPROVE_NEW"));
      box.querySelectorAll("[data-rejreq]").forEach(b=>b.onclick=()=>decideMaterialRequest(b.dataset.rejreq,"REJECT"));
      box.querySelectorAll("[data-mapreq]").forEach(b=>b.onclick=()=>mapMaterialRequest(b.dataset.mapreq));
    }catch(e){box.innerHTML=`<div class="empty">${esc(errorText(e))}</div>`}
  }
  async function decideMaterialRequest(id,decision){
    const remark=prompt(decision==="REJECT"?"Rejection reason:":"Super Admin remark (optional):","")??"";
    try{
      const d=await rpc("rr_material_name_decide_v8076",{p_request_id:id,p_decision:decision,p_existing_source_id:null,p_remark:remark});
      alert(d?.message||"Decision saved.");await loadMaterialRequests();await loadMappedMaterialsForType("");
    }catch(e){alert(errorText(e))}
  }
  async function mapMaterialRequest(id){
    const r=state.materialRequests.find(x=>String(x.id)===String(id));if(!r)return;
    const choices=(r.suggested_matches||[]);if(!choices.length)return alert("No suggested existing match is attached to this request.");
    const text=choices.map((x,i)=>`${i+1}. ${x.display_name}`).join("\n");
    const n=Number(prompt(`Map to existing:\n${text}\n\nEnter number:`,"1"));
    const pick=choices[n-1];if(!pick)return;
    try{
      const d=await rpc("rr_material_name_decide_v8076",{p_request_id:id,p_decision:"MAP_EXISTING",p_existing_source_id:String(pick.source_id||pick.id||""),p_remark:"Mapped to existing by Super Admin"});
      alert(d?.message||"Mapped.");await loadMaterialRequests();
    }catch(e){alert(errorText(e))}
  }

  async function loadMaterialBootstrap(){
    const d=await rpc("rr_material_purchase_bootstrap_v805_1",{p_data_mode:mode()});
    const types=Array.isArray(d?.material_types)?d.material_types:[];
    state.materialTypes=types;
    if($("type"))$("type").innerHTML='<option value="">Select material type…</option>'+types.map(t=>`<option value="${esc(t.type_code)}">${esc(t.type_name)}</option>`).join("");
    return d;
  }

  function suggestionHtml(x){const req=[x.requires_from_date?"From":"",x.requires_to_date?"To":"",x.requires_as_of_date?"As-of":"",x.requires_ledger?"Ledger":""].filter(Boolean).join(" · ");return `<button type="button" class="suggestion ${state.selected?.report_code===x.report_code?"active":""}" data-report="${esc(x.report_code)}"><b>${esc(x.report_name)}</b><small>${esc(x.report_description||"")}</small><span class="chip" style="margin-top:6px">${esc(x.report_family||"REPORT")}${req?` · ${esc(req)}`:""}</span></button>`}
  function renderSuggestions(){const box=$("reportSuggestions");if(!box)return;if(!state.suggestions.length){box.innerHTML='<div class="empty">No matching report template.</div>';return}box.innerHTML=state.suggestions.map(suggestionHtml).join("");box.querySelectorAll("[data-report]").forEach(btn=>btn.onclick=()=>selectReport(btn.dataset.report))}
  function selectReport(code){const row=state.suggestions.find(x=>x.report_code===code)||state.selected;if(!row)return;state.selected=row;$("selectedReportName").textContent=row.report_name||code;$("selectedReportDesc").textContent=row.report_description||"";$("selectedFamily").textContent=row.report_family||"REPORT";$("runReport").disabled=false;$("fromWrap").classList.toggle("hidden",!row.requires_from_date);$("toWrap").classList.toggle("hidden",!row.requires_to_date);$("asOfWrap").classList.toggle("hidden",!row.requires_as_of_date);$("ledgerWrap").classList.toggle("hidden",!row.requires_ledger);renderSuggestions();message("reportMsg","")}

  let searchTimer=null;
  async function searchReports(text=$("reportSearch")?.value||""){
    clearTimeout(searchTimer);message("searchMsg","Searching…");
    try{const data=await rpc("rr_report_search_bridge_v807",{p_search_text:String(text||""),p_limit:10});state.suggestions=Array.isArray(data)?data:[];renderSuggestions();if(!state.selected&&state.suggestions.length)selectReport(state.suggestions[0].report_code);message("searchMsg",`${state.suggestions.length} report suggestion${state.suggestions.length===1?"":"s"}.`,"ok")}
    catch(e){console.error(e);state.suggestions=[];renderSuggestions();message("searchMsg",errorText(e),"error")}
  }

  function renderTable(rows){if(!Array.isArray(rows)||!rows.length)return '<div class="empty">No rows for selected filters.</div>';const cols=[...new Set(rows.flatMap(r=>Object.keys(r||{})))];return `<div class="scroll"><table class="freeze-first"><thead><tr>${cols.map(c=>`<th>${esc(c.replaceAll("_"," "))}</th>`).join("")}</tr></thead><tbody>${rows.map(r=>`<tr>${cols.map(c=>`<td>${renderCell(r?.[c],c)}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`}
  function renderCell(v,key=""){if(v===null||v===undefined||v==="")return "—";if(typeof v==="boolean")return v?"Yes":"No";if(typeof v==="object")return `<span title="${esc(JSON.stringify(v))}">${esc(JSON.stringify(v).slice(0,90))}${JSON.stringify(v).length>90?"…":""}</span>`;if(/amount|debit|credit|value|profit|income|expense|purchase|salary|balance/i.test(key)&&!Number.isNaN(Number(v)))return money(v);return esc(v)}
  function humanKey(k){return String(k).replaceAll("_"," ").replace(/\b\w/g,m=>m.toUpperCase())}
  function renderJsonReport(obj){if(!obj||typeof obj!=="object")return `<div class="json-block">${esc(String(obj??""))}</div>`;const omit=new Set(["sections","asset_rows","liability_rows","equity_rows"]);const scalar=Object.entries(obj).filter(([k,v])=>!omit.has(k)&&!(v&&typeof v==="object"));const cards=scalar.filter(([k,v])=>typeof v==="number"||/profit|income|expense|purchase|asset|liabilit|equity|difference/i.test(k)).slice(0,8);let html=cards.length?`<div class="cards">${cards.map(([k,v])=>`<div class="metric"><small>${esc(humanKey(k))}</small><strong>${renderCell(v,k)}</strong></div>`).join("")}</div>`:"";const meta=scalar.filter(([k])=>!cards.some(([ck])=>ck===k));if(meta.length)html+=`<div class="section-title">Report details</div><div class="kv">${meta.map(([k,v])=>`<div>${esc(humanKey(k))}</div><div>${renderCell(v,k)}</div>`).join("")}</div>`;for(const key of ["sections","asset_rows","liability_rows","equity_rows"]){if(Array.isArray(obj[key]))html+=`<div class="section-title">${esc(humanKey(key))}</div>${renderTable(obj[key])}`}return html||`<div class="json-block">${esc(JSON.stringify(obj,null,2))}</div>`}

  async function runSelectedReport(){const r=state.selected;if(!r)return;const btn=$("runReport");setBusy(btn,true,"Running…");message("reportMsg","Running report…");try{const common={from:$("fromDate").value,to:$("toDate").value,asOf:$("asOfDate").value,ledger:$("reportLedger").value,dataMode:mode()};let data;
      switch(r.report_code){
        case "TRIAL_BALANCE":data=await rpc("rr_trial_balance_v806",{p_from_date:common.from,p_to_date:common.to,p_data_mode:common.dataMode});break;
        case "PROFIT_LOSS":data=await rpc("rr_profit_loss_v806",{p_from_date:common.from,p_to_date:common.to,p_data_mode:common.dataMode});break;
        case "BALANCE_SHEET":data=await rpc("rr_balance_sheet_v806",{p_as_of_date:common.asOf,p_data_mode:common.dataMode});break;
        case "DAY_BOOK":data=await rpc("rr_day_book_v806",{p_from_date:common.from,p_to_date:common.to,p_data_mode:common.dataMode});break;
        case "LEDGER_STATEMENT":if(!common.ledger)throw new Error("Select Ledger first.");data=await rpc("rr_ledger_statement_v806",{p_ledger_id:common.ledger,p_from_date:common.from,p_to_date:common.to,p_data_mode:common.dataMode});break;
        case "PURCHASE_RETURN":{const c=resolveClient();let q=c.from("rr_purchase_return_status_universal_v806").select("*").eq("data_mode",common.dataMode).order("created_at",{ascending:false}).limit(500);const out=await q;if(out.error)throw out.error;data=out.data||[];break}
        default:throw new Error(`Report ${r.report_code} is not wired in this UI.`)
      }
      $("reportResult").innerHTML=Array.isArray(data)?renderTable(data):renderJsonReport(data);message("reportMsg",`${r.report_name} loaded.`,"ok")
    }catch(e){console.error(e);$("reportResult").innerHTML=`<div class="empty">${esc(errorText(e))}</div>`;message("reportMsg",errorText(e),"error")}finally{setBusy(btn,false)}}

  async function loadDayBook(){const btn=$("loadDayBook");setBusy(btn,true,"Loading…");message("bookMsg","Loading…");try{const view=$("bookView").value;let data;if(view==="LEDGER"){const ledger=$("bookLedger").value;if(!ledger)throw new Error("Select Ledger for Ledger Statement.");data=await rpc("rr_ledger_statement_v806",{p_ledger_id:ledger,p_from_date:$("bookFrom").value,p_to_date:$("bookTo").value,p_data_mode:mode()})}else{data=await rpc("rr_day_book_v806",{p_from_date:$("bookFrom").value,p_to_date:$("bookTo").value,p_data_mode:mode()})}state.bookRows=Array.isArray(data)?data:[];renderBook();message("bookMsg",`${state.bookRows.length} row${state.bookRows.length===1?"":"s"} loaded.`,"ok")}catch(e){console.error(e);state.bookRows=[];renderBook();message("bookMsg",errorText(e),"error")}finally{setBusy(btn,false)}}
  function renderBook(){const q=String($("bookSearch")?.value||"").trim().toLowerCase();const rows=q?state.bookRows.filter(r=>JSON.stringify(r).toLowerCase().includes(q)):state.bookRows;$("bookResult").innerHTML=renderTable(rows)}

  function wirePreviewTemplates(){
    $("previewPurchase")?.addEventListener("click",()=>{calc();message("pmsg",`Preview total ${money($("total").value)}. Posting continues through the dedicated material/purchase backend.`,"ok")});
    let receipt=true;const syncMoney=()=>{if($("receiptMode"))$("receiptMode").classList.toggle("active",receipt);if($("paymentMode"))$("paymentMode").classList.toggle("active",!receipt);if($("againstLabel"))$("againstLabel").childNodes[0].nodeValue=receipt?"Received From":"Paid To"};
    $("receiptMode")?.addEventListener("click",()=>{receipt=true;syncMoney()});$("paymentMode")?.addEventListener("click",()=>{receipt=false;syncMoney()});$("saveMoney")?.addEventListener("click",()=>message("mmsg",`${receipt?"Receipt":"Payment"} preview ${money($("amount").value)}.`,"ok"));syncMoney();
  }

  async function refresh(){if(state.busy)return;state.busy=true;const btn=$("refreshAll");setBusy(btn,true,"Refreshing…");try{
      const rs=await Promise.allSettled([loadLedgers(),loadMaterialBootstrap(),searchReports($("reportSearch")?.value||""),loadMaterialRequests()]);
      rs.filter(x=>x.status==="rejected").forEach(x=>console.warn("Accounts mapping warning",x.reason));
      if($("modeMirror"))$("modeMirror").value=mode();
    }finally{state.busy=false;setBusy(btn,false)}}

  function initDates(){const t=today(),m=monthStart();["date","toDate","asOfDate","bookTo"].forEach(id=>{if($(id))$(id).value=t});["fromDate","bookFrom"].forEach(id=>{if($(id))$(id).value=m});if($("modeMirror"))$("modeMirror").value=mode()}
  function wire(){
    $("type")?.addEventListener("change",dynamicLabel);$("material")?.addEventListener("change",syncMappedMaterial);$("materialSearch")?.addEventListener("input",searchMaterialInput);$("requestNewMaterial")?.addEventListener("click",openNewMaterialRequest);$("closeNewMaterial")?.addEventListener("click",closeNewMaterialRequest);$("submitNewMaterialRequest")?.addEventListener("click",submitNewMaterialRequest);$("loadMaterialRequests")?.addEventListener("click",loadMaterialRequests);$("qty")?.addEventListener("input",calc);$("rate")?.addEventListener("input",calc);$("runReport")?.addEventListener("click",runSelectedReport);$("searchReports")?.addEventListener("click",()=>searchReports());$("reportSearch")?.addEventListener("input",()=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>searchReports(),220)});$("reportSearch")?.addEventListener("keydown",e=>{if(e.key==="Enter"){e.preventDefault();searchReports()}});$("loadDayBook")?.addEventListener("click",loadDayBook);$("bookSearch")?.addEventListener("input",renderBook);$("bookView")?.addEventListener("change",()=>{$("bookLedger").parentElement.classList.toggle("hidden",$("bookView").value!=="LEDGER")});$("dataMode")?.addEventListener("change",()=>{$("modeMirror").value=mode();refresh()});$("refreshAll")?.addEventListener("click",refresh);wirePreviewTemplates();zeroClean();enterFlow($("purchase"));enterFlow($("money"));
  }

  window.RR_ACCOUNTS_V805={
    setData:(d={})=>{if(Array.isArray(d.material_types)){state.materialTypes=d.material_types;if($("type"))$("type").innerHTML='<option value="">Select material type…</option>'+state.materialTypes.map(x=>`<option value="${esc(x.type_code)}">${esc(x.type_name)}</option>`).join("")}},
    refresh,
    searchReports,
    runSelectedReport
  };

  document.addEventListener("DOMContentLoaded",()=>{initDates();wire();refresh()});
})();
