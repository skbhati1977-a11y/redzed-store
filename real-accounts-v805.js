(()=>{
  "use strict";
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const fmt=v=>{const n=Number(v);return Number.isFinite(n)?new Intl.NumberFormat("en-IN",{maximumFractionDigits:2}).format(n):String(v??"—")};
  const money=v=>`₹${fmt(v)}`;
  const today=()=>new Date().toISOString().slice(0,10);
  const monthStart=()=>{const d=new Date();d.setDate(1);return d.toISOString().slice(0,10)};
  const state={client:null,ledgers:[],suggestions:[],selected:null,bookRows:[],materialTypes:[],materials:[],busy:false};

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
  function dynamicLabel(){const code=$("type")?.value;const names={REGULAR_CLOTH:"Cloth Name",MATCHING_CLOTH:"Matching Cloth Name",STICKER:"Sticker Name",METAL_ID:"Metal ID Name",PANNI:"Panni Name",GATTA:"Gatta Name",BOX:"Box Name",PASTING_ROLL:"Pasting Name",KANDHI_TAPE:"Kandhi Tape Name"};const label=$("materialLabel");if(label?.childNodes?.[0])label.childNodes[0].nodeValue=names[code]||"Material Name";const rows=state.materials.filter(x=>x.material_type===code);if($("material"))$("material").innerHTML='<option value="">Select…</option>'+rows.map(x=>`<option value="${esc(x.material_id)}">${esc(x.material_name)}</option>`).join("")}

  function fillLedgerSelects(){const options='<option value="">Select ledger…</option>'+state.ledgers.map(x=>`<option value="${esc(x.id)}">${esc(x.ledger_name)}${x.ledger_code?` · ${esc(x.ledger_code)}`:""}</option>`).join("");["reportLedger","bookLedger","supplier","against","cashbank"].forEach(id=>{const el=$(id);if(el)el.innerHTML=options})}
  async function loadLedgers(){try{const c=resolveClient();const r=await c.from("rr_ledgers_v805").select("id,ledger_code,ledger_name,ledger_kind,is_active").eq("is_active",true).order("ledger_name",{ascending:true});if(r.error)throw r.error;state.ledgers=r.data||[];fillLedgerSelects()}catch(e){console.warn("Ledger list unavailable",e)}}

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

  async function refresh(){if(state.busy)return;state.busy=true;const btn=$("refreshAll");setBusy(btn,true,"Refreshing…");try{await Promise.all([loadLedgers(),searchReports($("reportSearch")?.value||"")]);$("modeMirror").value=mode()}catch(e){console.error(e);message("searchMsg",errorText(e),"error")}finally{state.busy=false;setBusy(btn,false)}}

  function initDates(){const t=today(),m=monthStart();["date","toDate","asOfDate","bookTo"].forEach(id=>{if($(id))$(id).value=t});["fromDate","bookFrom"].forEach(id=>{if($(id))$(id).value=m});if($("modeMirror"))$("modeMirror").value=mode()}
  function wire(){
    $("type")?.addEventListener("change",dynamicLabel);$("qty")?.addEventListener("input",calc);$("rate")?.addEventListener("input",calc);$("runReport")?.addEventListener("click",runSelectedReport);$("searchReports")?.addEventListener("click",()=>searchReports());$("reportSearch")?.addEventListener("input",()=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>searchReports(),220)});$("reportSearch")?.addEventListener("keydown",e=>{if(e.key==="Enter"){e.preventDefault();searchReports()}});$("loadDayBook")?.addEventListener("click",loadDayBook);$("bookSearch")?.addEventListener("input",renderBook);$("bookView")?.addEventListener("change",()=>{$("bookLedger").parentElement.classList.toggle("hidden",$("bookView").value!=="LEDGER")});$("dataMode")?.addEventListener("change",()=>{$("modeMirror").value=mode();refresh()});$("refreshAll")?.addEventListener("click",refresh);wirePreviewTemplates();zeroClean();enterFlow($("purchase"));enterFlow($("money"));
  }

  window.RR_ACCOUNTS_V805={
    setData:(d={})=>{state.materialTypes=d.material_types||[];state.materials=d.materials||[];if($("type"))$("type").innerHTML='<option value="">Select…</option>'+state.materialTypes.map(x=>`<option value="${esc(x.type_code)}">${esc(x.type_name)}</option>`).join("");dynamicLabel()},
    refresh,
    searchReports,
    runSelectedReport
  };

  document.addEventListener("DOMContentLoaded",()=>{initDates();wire();refresh()});
})();
