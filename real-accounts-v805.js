(()=>{
  "use strict";
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const fmt=v=>{const n=Number(v);return Number.isFinite(n)?new Intl.NumberFormat("en-IN",{maximumFractionDigits:2}).format(n):String(v??"—")};
  const money=v=>`₹${fmt(v)}`;
  const today=()=>new Date().toISOString().slice(0,10);
  const monthStart=()=>{const d=new Date();d.setDate(1);return d.toISOString().slice(0,10)};
  const state={client:null,ledgers:[],suggestions:[],selected:null,bookRows:[],creditors:[],creditorOffset:0,accountsRows:[],materialTypes:[],materials:[],busy:false,addEntity:null,addTarget:null,masterRequests:[],accountCategories:[],exportSets:new Map(),activeEntry:null,summaryScope:"ALL",summaryRows:[],statementLedger:null,statementRows:[]};

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

  document.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-tab]').forEach(x=>x.classList.remove('active'));b.classList.add('active');document.querySelectorAll('.page').forEach(x=>x.classList.add('hidden'));$(b.dataset.tab)?.classList.remove('hidden');if(b.dataset.tab==="ledgers"&&!state.bookRows.length)loadDayBook().catch(()=>{});if(b.dataset.tab==="creditors"&&!state.creditors.length)loadCreditors().catch(()=>{});if(b.dataset.tab==="accountsMap"&&!state.accountsRows.length)loadAccountsMap().catch(()=>{})});

  function calc(){const q=Number($("qty")?.value||0),r=Number($("rate")?.value||0);if($("total"))$("total").value=(q*r).toFixed(2)}
  function materialLabelFor(code){return ({REGULAR_CLOTH:"Cloth Name",MATCHING_CLOTH:"Matching Cloth Name",STICKER:"Sticker Name",METAL_ID:"Metal ID Name",PANNI:"Panni Name",GATTA:"Gatta Name",BOX:"Box Name",PASTING_ROLL:"Pasting Name",KANDHI_TAPE:"Kandhi Tape Name"})[code]||"Material Name"}
  function applyMappedMaterial(r){
    if($("uom"))$("uom").value=r?.purchase_unit||r?.stock_unit||"";
    calc();
  }
  async function loadMappedMaterialsForType(){
    const code=$("type")?.value||"";
    const label=$("materialLabel");if(label?.childNodes?.[0])label.childNodes[0].nodeValue=materialLabelFor(code);
    const el=$("material");if(!el)return;
    if(!code){el.innerHTML='<option value="">Select material…</option>';if($("uom"))$("uom").value="";return}
    el.disabled=true;el.innerHTML='<option value="">Loading mapped materials…</option>';
    try{
      const rows=await rpc("rr_material_source_search_v805_1",{p_type_code:code,p_search:"",p_data_mode:mode(),p_limit:50});
      state.materials=Array.isArray(rows)?rows:[];
      el.innerHTML='<option value="">Select material…</option>'+state.materials.map((r,i)=>`<option value="${i}">${esc([r.material_no,r.material_name].filter(Boolean).join(" · "))}</option>`).join("");
      if(!state.materials.length)el.innerHTML='<option value="">No mapped material found</option>';
      if($("uom"))$("uom").value="";
    }catch(e){
      console.error("Mapped material load failed",e);state.materials=[];el.innerHTML='<option value="">Mapped material load failed</option>';
      message("pmsg",`Material mapping: ${errorText(e)}`,"error");
    }finally{el.disabled=false}
  }
  function dynamicLabel(){loadMappedMaterialsForType().catch(e=>console.error(e))}
  function syncMappedMaterial(){const i=Number($("material")?.value);const r=Number.isInteger(i)?state.materials[i]:null;applyMappedMaterial(r)}

  function normalizeLedger(x={}){
    return {id:x.id||x.ledger_id||"",ledger_name:x.ledger_name||x.name||x.ledger_code||"",ledger_code:x.ledger_code||x.code||"",ledger_kind:String(x.ledger_kind||x.kind||"").toUpperCase(),is_active:x.is_active!==false};
  }
  function fillLedgerSelects(){
    const rows=state.ledgers.filter(x=>x.id&&x.ledger_name&&x.is_active!==false);
    const opts=(first,filter=null)=>{
      const list=filter?rows.filter(filter):rows;
      return `<option value="">${first}</option>`+list.map(x=>`<option value="${esc(x.id)}">${esc(x.ledger_name)}${x.ledger_code?` · ${esc(x.ledger_code)}`:""}</option>`).join("");
    };
    if($("reportLedger"))$("reportLedger").innerHTML=opts("Select ledger…");
    if($("bookLedger"))$("bookLedger").innerHTML=opts("All / Select ledger…");
    if($("supplier"))$("supplier").innerHTML=opts("Select supplier…",x=>["SUPPLIER","PARTY","GENERAL"].includes(x.ledger_kind));
    if($("against"))$("against").innerHTML=opts("Select ledger…",x=>!["CASH","BANK"].includes(x.ledger_kind));
    if($("cashbank"))$("cashbank").innerHTML=opts("Select cash / bank…",x=>["CASH","BANK"].includes(x.ledger_kind));
    if($("journalDebit"))$("journalDebit").innerHTML=opts("Select debit ledger…");
    if($("journalCredit"))$("journalCredit").innerHTML=opts("Select credit ledger…");
  }
  async function loadLedgers(){
    const errors=[];
    const accept=rows=>{
      const seen=new Set();
      const out=(Array.isArray(rows)?rows:[]).map(normalizeLedger).filter(x=>{
        const k=String(x.id); if(!x.id||!x.ledger_name||seen.has(k)||x.is_active===false)return false;seen.add(k);return true;
      }).sort((a,b)=>a.ledger_name.localeCompare(b.ledger_name));
      if(!out.length)return false;state.ledgers=out;fillLedgerSelects();return true;
    };
    try{
      const d=await rpc("rr_material_purchase_bootstrap_v805_1",{p_data_mode:mode()});
      if(accept(d?.ledgers))return;
    }catch(e){errors.push(`material bootstrap: ${errorText(e)}`)}
    try{
      const c=resolveClient();const r=await c.from("rr_ledgers_v805").select("*").eq("is_active",true).order("ledger_name",{ascending:true});
      if(!r.error&&accept(r.data))return;if(r.error)errors.push(r.error.message);
    }catch(e){errors.push(errorText(e))}
    try{
      const d=await rpc("rr_accounts_bootstrap_v805",{p_data_mode:mode()});
      if(accept(d?.ledgers))return;
    }catch(e){errors.push(`accounts bootstrap: ${errorText(e)}`)}
    state.ledgers=[];fillLedgerSelects();throw new Error(`Ledger mapping unavailable. ${errors.join(" | ")}`);
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

  function renderTable(rows){if(!Array.isArray(rows)||!rows.length)return '<div class="empty">No rows for selected filters.</div>';const setId=`set-${Date.now()}-${Math.random().toString(36).slice(2,7)}`;state.exportSets.set(setId,rows);const cols=[...new Set(rows.flatMap(r=>Object.keys(r||{})))];return `<div class="actions" style="margin-bottom:8px"><button type="button" data-export-set="${setId}">Export All CSV</button><button type="button" data-share-set="${setId}">Share All</button></div><div class="scroll"><table class="freeze-first"><thead><tr>${cols.map(c=>`<th>${esc(c.replaceAll("_"," "))}</th>`).join("")}<th>Actions</th></tr></thead><tbody>${rows.map((r,i)=>`<tr>${cols.map(c=>`<td>${renderCell(r?.[c],c)}</td>`).join("")}<td><button type="button" data-view-entry="${setId}" data-row="${i}">View</button> <button type="button" data-share-entry="${setId}" data-row="${i}">Share</button> <button type="button" data-export-entry="${setId}" data-row="${i}">Export</button></td></tr>`).join("")}</tbody></table></div>`}
  function renderCell(v,key=""){if(v===null||v===undefined||v==="")return "—";if(typeof v==="boolean")return v?"Yes":"No";if(typeof v==="object")return `<span title="${esc(JSON.stringify(v))}">${esc(JSON.stringify(v).slice(0,90))}${JSON.stringify(v).length>90?"…":""}</span>`;if(/amount|debit|credit|value|profit|income|expense|purchase|salary|balance/i.test(key)&&!Number.isNaN(Number(v)))return money(v);return esc(v)}
  function csvValue(v){const x=typeof v==="object"&&v!==null?JSON.stringify(v):String(v??"");return `"${x.replaceAll('"','""')}"`}
  function rowsCsv(rows){const cols=[...new Set((rows||[]).flatMap(r=>Object.keys(r||{})))];return [cols.map(csvValue).join(","),...(rows||[]).map(r=>cols.map(c=>csvValue(r?.[c])).join(","))].join("\n")}
  function downloadCsv(rows,name="accounts-export.csv"){const a=document.createElement("a");a.href=URL.createObjectURL(new Blob(["\ufeff",rowsCsv(rows)],{type:"text/csv;charset=utf-8"}));a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)}
  function entryText(row){return Object.entries(row||{}).map(([k,v])=>`${humanKey(k)}: ${typeof v==="object"?JSON.stringify(v):v??"—"}`).join("\n")}
  async function shareRows(rows,title="Accounts entry") {const list=Array.isArray(rows)?rows:[];if(!list.length)return;const text=list.length===1?entryText(list[0]):`${title}\n${list.length} entries attached.`;const file=new File(["\ufeff",rowsCsv(list)],"accounts-export.csv",{type:"text/csv"});try{if(navigator.canShare?.({files:[file]}))return await navigator.share({title,text,files:[file]});if(navigator.share)return await navigator.share({title,text:text.slice(0,6000)});window.open(`https://wa.me/?text=${encodeURIComponent(text.slice(0,3500))}`,"_blank","noopener")}catch(e){if(e?.name!=="AbortError")downloadCsv(list)}}
  function openEntry(row){state.activeEntry=row;const body=$("entryPopupBody");body.innerHTML=`<div class="kv">${Object.entries(row||{}).map(([k,v])=>`<div>${esc(humanKey(k))}</div><div>${renderCell(v,k)}</div>`).join("")}</div>`;const modal=$("entryPopup");modal.classList.remove("hidden");modal.style.display="grid"}
  function closeEntry(){const modal=$("entryPopup");modal.classList.add("hidden");modal.style.display=""}
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

  const scopeNames={DEBTORS:"Sundry Debtors",CREDITORS:"Sundry Creditors",SALARY:"Salary & Wages",EXPENSE:"Expenses",CASH_BANK:"Cash & Bank",LOAN_ADVANCE:"Loans & Advances",ALL:"All Ledgers"};
  const balanceText=n=>`${money(Math.abs(Number(n||0)))} ${Number(n||0)>=0?"Dr":"Cr"}`;
  async function openLedgerSummary(scope){state.summaryScope=scope||"ALL";$("ledgerSummaryTitle").textContent=scopeNames[state.summaryScope]||"Ledger Summary";document.querySelectorAll(".page").forEach(x=>x.classList.add("hidden"));$("ledgerSummary").classList.remove("hidden");$("accountsDrawer")?.classList.add("hidden");document.body.classList.remove("accounts-focus");await loadLedgerSummary()}
  async function loadLedgerSummary(){message("ledgerSummaryMsg","Loading…");try{const rows=await rpc("rr_accounts_ledger_summary_v9767",{p_scope:state.summaryScope,p_search:$("ledgerSummarySearch").value||"",p_from_date:$("summaryFrom").value,p_to_date:$("summaryTo").value,p_data_mode:mode()});state.summaryRows=Array.isArray(rows)?rows:[];$("ledgerSummaryResult").innerHTML=renderLedgerSummary(state.summaryRows);message("ledgerSummaryMsg",`${state.summaryRows.length} ledger${state.summaryRows.length===1?"":"s"}.`,"ok")}catch(e){state.summaryRows=[];$("ledgerSummaryResult").innerHTML=`<div class="empty">${esc(errorText(e))}</div>`;message("ledgerSummaryMsg",errorText(e),"error")}}
  function renderLedgerSummary(rows){if(!rows.length)return '<div class="empty">No matching ledger.</div>';return `<div class="scroll"><table class="freeze-first"><thead><tr><th>Party / Ledger</th><th>Opening</th><th>Total Debit</th><th>Total Credit</th><th>Closing</th></tr></thead><tbody>${rows.map(r=>`<tr class="ledger-row" data-ledger-id="${esc(r.ledger_id)}" data-ledger-name="${esc(r.ledger_name)}"><td><button type="button" class="suggestion" style="min-height:34px;padding:6px;width:100%;text-align:left">${esc(r.ledger_name)}</button></td><td>${balanceText(r.opening_balance)}</td><td>${money(r.total_debit)}</td><td>${money(r.total_credit)}</td><td><b>${balanceText(r.closing_balance)}</b></td></tr>`).join("")}</tbody></table></div>`}
  async function openLedgerStatement(id,name){state.statementLedger={id,name};$("statementLedgerName").textContent=name;$("statementScope").textContent=scopeNames[state.summaryScope]||"Ledger Statement";$("statementFrom").value=$("summaryFrom").value;$("statementTo").value=$("summaryTo").value;$("statementSearch").value="";document.body.classList.add("ledger-focus");$("ledgerStatementPage").classList.remove("hidden");history.pushState({accountsView:"statement"},"",`${location.pathname}${location.search}#ledger-statement`);await loadLedgerStatement()}
  function closeLedgerStatement(fromPop=false){$("ledgerStatementPage").classList.add("hidden");document.body.classList.remove("ledger-focus");state.statementLedger=null;if(!fromPop&&location.hash==="#ledger-statement")history.back()}
  async function loadLedgerStatement(){if(!state.statementLedger)return;message("statementMsg","Loading…");try{const rows=await rpc("rr_accounts_ledger_statement_v9767",{p_ledger_id:state.statementLedger.id,p_from_date:$("statementFrom").value,p_to_date:$("statementTo").value,p_data_mode:mode()});state.statementRows=Array.isArray(rows)?rows:[];renderLedgerStatement();const latest=state.statementRows.at(-1),amount=latest?(Number(latest.debit||0)?`${money(latest.debit)} Dr`:`${money(latest.credit)} Cr`):"";message("statementMsg",latest?`${state.statementRows.length} entries · Latest: ${latest.particulars||latest.voucher_type} · ${latest.voucher_no} · ${amount}`:"No entries.","ok");requestAnimationFrame(()=>$("statementResult")?.querySelector("tbody tr:last-child")?.scrollIntoView({block:"center",behavior:"smooth"}))}catch(e){state.statementRows=[];renderLedgerStatement();message("statementMsg",errorText(e),"error")}}
  function renderLedgerStatement(){const q=String($("statementSearch").value||"").trim().toLowerCase(),rows=q?state.statementRows.filter(r=>`${r.particulars} ${r.voucher_no} ${r.voucher_type}`.toLowerCase().includes(q)):state.statementRows,source=state.summaryRows.find(r=>r.ledger_id===state.statementLedger?.id)||{},dr=rows.reduce((n,r)=>n+Number(r.debit||0),0),cr=rows.reduce((n,r)=>n+Number(r.credit||0),0),opening=Number(source.opening_balance||0),closing=opening+dr-cr;$("statementTotals").innerHTML=`<div class="metric"><small>Opening Balance</small><strong>${balanceText(opening)}</strong></div><div class="metric"><small>Total Debit</small><strong>${money(dr)}</strong></div><div class="metric"><small>Total Credit</small><strong>${money(cr)}</strong></div><div class="metric"><small>Closing Balance</small><strong>${balanceText(closing)}</strong></div>`;$("statementResult").innerHTML=rows.length?`<div class="scroll"><table class="freeze-first"><thead><tr><th>Date</th><th>Particulars</th><th>Voucher No.</th><th>Debit</th><th>Credit</th><th>Running Balance</th></tr></thead><tbody>${rows.map(r=>`<tr data-voucher-no="${esc(r.voucher_no)}"><td>${esc(r.entry_date)}</td><td>${esc(r.particulars||r.voucher_type)}</td><td><button type="button" data-voucher-no="${esc(r.voucher_no)}">${esc(r.voucher_no)}</button></td><td>${Number(r.debit||0)?money(r.debit):"—"}</td><td>${Number(r.credit||0)?money(r.credit):"—"}</td><td><b>${balanceText(r.running_balance)}</b></td></tr>`).join("")}</tbody></table></div>`:'<div class="empty">No matching entries.</div>'}
  async function openVoucher(voucher){if(!voucher)return;try{const rows=await rpc("rr_accounts_voucher_detail_v9767",{p_voucher_no:voucher,p_data_mode:mode()});state.activeEntry={voucher_no:voucher,posting_lines:rows};$("entryPopupBody").innerHTML=`<h3>${esc(voucher)}</h3><div class="scroll"><table><thead><tr><th>Date</th><th>Particulars</th><th>Ledger</th><th>Debit</th><th>Credit</th><th>Status</th></tr></thead><tbody>${(rows||[]).map(r=>`<tr><td>${esc(r.entry_date)}</td><td>${esc(r.particulars||r.voucher_type)}</td><td>${esc(r.ledger_name)}</td><td>${Number(r.debit||0)?money(r.debit):"—"}</td><td>${Number(r.credit||0)?money(r.credit):"—"}</td><td>${esc(r.status)}</td></tr>`).join("")}</tbody></table></div>`;const modal=$("entryPopup");modal.classList.remove("hidden");modal.style.display="grid"}catch(e){message("statementMsg",errorText(e),"error")}}

  async function loadCreditors(reset=false){if(reset)state.creditorOffset=0;const btn=$("loadCreditors");setBusy(btn,true,"Loading…");message("creditorMsg","Loading canonical mapping…");try{const rows=await rpc("rr_accounts_creditor_search_v9763",{p_search:$("creditorSearch")?.value||"",p_limit:100,p_offset:state.creditorOffset,p_data_mode:mode()});state.creditors=Array.isArray(rows)?rows:[];$("creditorResult").innerHTML=renderTable(state.creditors);$("creditorPrev").disabled=state.creditorOffset===0;$("creditorNext").disabled=state.creditors.length<100;message("creditorMsg",`${state.creditors.length} canonical creditor mapping(s) loaded · offset ${state.creditorOffset}.`,`ok`)}catch(e){state.creditors=[];$("creditorResult").innerHTML=`<div class="empty">${esc(errorText(e))}</div>`;message("creditorMsg",errorText(e),"error")}finally{setBusy(btn,false)}}

  async function postJournal(){const btn=$("postJournal");try{const debit=$("journalDebit").value,credit=$("journalCredit").value,amount=Number($("journalAmount").value||0),note=$("journalNote").value.trim();if(!debit||!credit||debit===credit)throw new Error("Distinct Debit and Credit ledgers required.");if(!(amount>0))throw new Error("Amount must be greater than zero.");if(!note)throw new Error("Narration required.");setBusy(btn,true,"Posting…");const out=await rpc("rr_accounts_post_journal_v9763",{p_debit_ledger_id:debit,p_credit_ledger_id:credit,p_amount:amount,p_ref_no:$("journalRef").value||null,p_narration:note,p_data_mode:mode()});message("journalMsg",`Journal ${out.voucher_no||""} posted ${money(amount)}.`,`ok`);$("journalAmount").value="0";await Promise.all([loadDayBook(),loadCreditors()])}catch(e){message("journalMsg",errorText(e),"error")}finally{setBusy(btn,false)}}

  async function reverseVoucher(){const btn=$("reverseVoucherBtn");try{const voucher=$("reverseVoucher").value.trim(),reason=$("reverseReason").value.trim();if(!voucher||!reason)throw new Error("Voucher No and reversal reason required.");setBusy(btn,true,"Reversing…");await rpc("rr_accounts_reverse_voucher_v9763",{p_voucher_no:voucher,p_reason:reason,p_data_mode:mode()});message("reverseMsg",`${voucher} reversed with audit trail.`,`ok`);await Promise.all([loadDayBook(),loadCreditors()])}catch(e){message("reverseMsg",errorText(e),"error")}finally{setBusy(btn,false)}}

  async function loadAccountsMap(){const btn=$("loadAccountsMap");setBusy(btn,true,"Loading…");message("accountsMapMsg","Loading Balance Sheet and P&L structure…");try{const rows=await rpc("rr_accounts_structure_v9765",{p_search:$("accountsMapSearch")?.value||"",p_group_code:$("accountsMapGroup")?.value||null,p_data_mode:mode()});state.accountsRows=Array.isArray(rows)?rows:[];const groups={};for(const r of state.accountsRows){const g=groups[r.group_code]||(groups[r.group_code]={name:r.group_name,dr:0,cr:0});g.dr+=Number(r.debit_balance||0);g.cr+=Number(r.credit_balance||0)}$("accountsMapSummary").innerHTML=Object.entries(groups).map(([code,g])=>`<div class="metric"><small>${esc(g.name)}</small><strong>${money(Math.abs(g.dr-g.cr))}</strong><span class="chip">${g.dr>=g.cr?"Dr":"Cr"}</span></div>`).join("");$("accountsMapResult").innerHTML=renderAccountsStructure(state.accountsRows);message("accountsMapMsg",`${state.accountsRows.length} ledger/head rows · empty heads shown at zero.`,`ok`)}catch(e){$("accountsMapResult").innerHTML=`<div class="empty">${esc(errorText(e))}</div>`;message("accountsMapMsg",errorText(e),"error")}finally{setBusy(btn,false)}}
  function renderAccountsStructure(rows){if(!rows.length)return '<div class="empty">No matching account head.</div>';let current="",html="";for(const r of rows){if(r.group_code!==current){if(current)html+='</tbody></table></div>';current=r.group_code;html+=`<h3 class="section-title">${esc(r.group_name)} · ${esc(r.group_code)}</h3><div class="scroll"><table><thead><tr><th>Account Head</th><th>Ledger</th><th>Code</th><th>Debit</th><th>Credit</th><th>Entries</th><th>Action</th></tr></thead><tbody>`}html+=`<tr><td><b>${esc(r.category_name)}</b><br><small class="muted">${esc(r.category_code)}</small></td><td>${esc(r.ledger_name||"No ledger yet")}</td><td>${esc(r.ledger_code||"—")}</td><td>${money(r.debit_balance||0)}</td><td>${money(r.credit_balance||0)}</td><td>${fmt(r.entry_count||0)}</td><td><button type="button" data-create-category="${esc(r.category_id)}">+ Create Account</button></td></tr>`}return html+'</tbody></table></div>'}

  function wirePreviewTemplates(){
    $("previewPurchase")?.addEventListener("click",()=>{calc();message("pmsg",`Preview total ${money($("total").value)}. Posting continues through the dedicated material/purchase backend.`,"ok")});
    let receipt=true;const syncMoney=()=>{if($("receiptMode"))$("receiptMode").classList.toggle("active",receipt);if($("paymentMode"))$("paymentMode").classList.toggle("active",!receipt);if($("againstLabel"))$("againstLabel").childNodes[0].nodeValue=receipt?"Received From":"Paid To";if($("saveMoney"))$("saveMoney").textContent=`Post ${receipt?"Receipt":"Payment"}`};
    $("receiptMode")?.addEventListener("click",()=>{receipt=true;syncMoney()});$("paymentMode")?.addEventListener("click",()=>{receipt=false;syncMoney()});$("saveMoney")?.addEventListener("click",async()=>{const btn=$("saveMoney");try{const against=$("against").value,cash=$("cashbank").value,amount=Number($("amount").value||0);if(!against||!cash)throw new Error("Ledger and Cash / Bank required.");if(!(amount>0))throw new Error("Amount must be greater than zero.");setBusy(btn,true,"Posting…");const fn=receipt?"rr_accounts_post_receipt_v805":"rr_accounts_post_payment_v805";const args=receipt?{p_party_ledger_id:against,p_cash_bank_ledger_id:cash,p_amount:amount,p_ref_no:$("ref").value||null,p_narration:$("note").value||null,p_data_mode:mode()}:{p_against_ledger_id:against,p_cash_bank_ledger_id:cash,p_amount:amount,p_ref_no:$("ref").value||null,p_narration:$("note").value||null,p_data_mode:mode()};const out=await rpc(fn,args);message("mmsg",`${receipt?"Receipt":"Payment"} ${out.voucher_no||""} posted ${money(amount)}. Delete के बदले Day Book से Reverse करें.`,"ok");$("amount").value="0";await loadDayBook()}catch(e){message("mmsg",errorText(e),"error")}finally{setBusy(btn,false);syncMoney()}});syncMoney();
  }

  async function refresh(){if(state.busy)return;state.busy=true;const btn=$("refreshAll");setBusy(btn,true,"Refreshing…");try{
      const rs=await Promise.allSettled([loadLedgers(),loadMaterialBootstrap(),searchReports($("reportSearch")?.value||""),loadAccountCategories(),loadMasterRequests()]);
      rs.filter(x=>x.status==="rejected").forEach(x=>console.warn("Accounts mapping warning",x.reason));
      if($("modeMirror"))$("modeMirror").value=mode();
    }finally{state.busy=false;setBusy(btn,false)}}

  function initDates(){const t=today(),m=monthStart();["date","toDate","asOfDate","bookTo","summaryTo","statementTo"].forEach(id=>{if($(id))$(id).value=t});["fromDate","bookFrom","summaryFrom","statementFrom"].forEach(id=>{if($(id))$(id).value=m});if($("modeMirror"))$("modeMirror").value=mode()}
  function wire(){
    $("loadAccountsMap")?.addEventListener("click",loadAccountsMap);$("accountsMapGroup")?.addEventListener("change",loadAccountsMap);$("accountsMapSearch")?.addEventListener("input",()=>{clearTimeout(searchTimer);searchTimer=setTimeout(loadAccountsMap,220)});
    $("openAccountsMenu")?.addEventListener("click",()=>{document.body.classList.add("accounts-focus");$("accountsDrawer")?.classList.remove("hidden")});$("closeAccountsMenu")?.addEventListener("click",()=>{$("accountsDrawer")?.classList.add("hidden");document.body.classList.remove("accounts-focus")});
    document.querySelectorAll("[data-open-tab]").forEach(b=>b.addEventListener("click",()=>{document.querySelector(`[data-tab='${b.dataset.openTab}']`)?.click();$("accountsDrawer")?.classList.add("hidden");document.body.classList.remove("accounts-focus");if(b.dataset.reportQuery&&$("reportSearch")){$("reportSearch").value=b.dataset.reportQuery;searchReports(b.dataset.reportQuery)}if(b.dataset.focusId)setTimeout(()=>$(b.dataset.focusId)?.focus(),80)}));
    document.querySelectorAll("[data-ledger-scope]").forEach(b=>b.addEventListener("click",()=>openLedgerSummary(b.dataset.ledgerScope)));
    $("ledgerSummarySearch")?.addEventListener("input",()=>{clearTimeout(searchTimer);searchTimer=setTimeout(loadLedgerSummary,220)});$("summaryFrom")?.addEventListener("change",loadLedgerSummary);$("summaryTo")?.addEventListener("change",loadLedgerSummary);
    $("closeLedgerStatement")?.addEventListener("click",()=>closeLedgerStatement());$("statementSearch")?.addEventListener("input",renderLedgerStatement);$("statementFrom")?.addEventListener("change",loadLedgerStatement);$("statementTo")?.addEventListener("change",loadLedgerStatement);
    window.addEventListener("popstate",()=>{if(!$("ledgerStatementPage")?.classList.contains("hidden")&&location.hash!=="#ledger-statement")closeLedgerStatement(true)});
    document.addEventListener("click",e=>{const row=e.target.closest(".ledger-row");if(row)openLedgerStatement(row.dataset.ledgerId,row.dataset.ledgerName)});
    let lastVoucherTap={no:"",at:0};document.addEventListener("click",e=>{const b=e.target.closest("[data-voucher-no]");if(!b||!$("ledgerStatementPage")?.contains(b))return;const no=b.dataset.voucherNo,now=Date.now();if(lastVoucherTap.no===no&&now-lastVoucherTap.at<500)openVoucher(no);lastVoucherTap={no,at:now}});document.addEventListener("dblclick",e=>{const b=e.target.closest("[data-voucher-no]");if(b&&$("ledgerStatementPage")?.contains(b))openVoucher(b.dataset.voucherNo)});
    $("closeEntryPopup")?.addEventListener("click",closeEntry);$("sharePopupEntry")?.addEventListener("click",()=>shareRows([state.activeEntry]));$("exportPopupEntry")?.addEventListener("click",()=>downloadCsv([state.activeEntry],"accounts-entry.csv"));$("printPopupEntry")?.addEventListener("click",()=>window.print());
    document.addEventListener("click",e=>{const b=e.target.closest("[data-view-entry],[data-share-entry],[data-export-entry],[data-share-set],[data-export-set]");if(!b)return;const id=b.dataset.viewEntry||b.dataset.shareEntry||b.dataset.exportEntry||b.dataset.shareSet||b.dataset.exportSet,rows=state.exportSets.get(id)||[],row=rows[Number(b.dataset.row||0)];if(b.dataset.viewEntry)openEntry(row);else if(b.dataset.shareEntry)shareRows([row]);else if(b.dataset.exportEntry)downloadCsv([row],"accounts-entry.csv");else if(b.dataset.shareSet)shareRows(rows,"Accounts entries");else downloadCsv(rows)});
    document.addEventListener("click",e=>{const b=e.target.closest("[data-create-category]");if(!b)return;openFieldAdd({dataset:{addEntity:"LEDGER",target:"accountsMap",ledgerKind:"GENERAL"}});if($("addMasterCategory"))$("addMasterCategory").value=b.dataset.createCategory});
    let holdTimer=null,holdStart=null;document.addEventListener("pointerdown",e=>{const row=e.target.closest("tbody tr");const btn=row?.querySelector("[data-share-entry]");if(!btn)return;holdStart={x:e.clientX,y:e.clientY,btn};holdTimer=setTimeout(()=>{navigator.vibrate?.(35);btn.click();holdTimer=null},550)});document.addEventListener("pointermove",e=>{if(holdStart&&Math.hypot(e.clientX-holdStart.x,e.clientY-holdStart.y)>12){clearTimeout(holdTimer);holdTimer=null;holdStart=null}});["pointerup","pointercancel"].forEach(n=>document.addEventListener(n,()=>{clearTimeout(holdTimer);holdTimer=null;holdStart=null}));
    $("type")?.addEventListener("change",dynamicLabel);$("material")?.addEventListener("change",syncMappedMaterial);$("qty")?.addEventListener("input",calc);$("rate")?.addEventListener("input",calc);document.querySelectorAll("[data-add-entity]").forEach(b=>b.addEventListener("click",()=>openFieldAdd(b)));$("closeAddMaster")?.addEventListener("click",closeFieldAdd);$("checkAddMaster")?.addEventListener("click",checkFieldAdd);$("submitAddMaster")?.addEventListener("click",submitFieldAdd);$("loadMasterRequests")?.addEventListener("click",loadMasterRequests);$("runReport")?.addEventListener("click",runSelectedReport);
  const ADD_LABELS={
    PARTY:"Party / Supplier",
    MATERIAL_TYPE:"Material Type",
    MATERIAL:"Material",
    LEDGER:"Ledger"
  };
  function normMaster(v){return String(v||"").trim().toLowerCase().replace(/[^a-z0-9]+/g,"")}
  function levMaster(a,b){a=normMaster(a);b=normMaster(b);const m=a.length,n=b.length;if(!m)return n;if(!n)return m;let p=Array.from({length:n+1},(_,i)=>i);for(let i=1;i<=m;i++){const c=[i];for(let j=1;j<=n;j++)c[j]=Math.min(c[j-1]+1,p[j]+1,p[j-1]+(a[i-1]===b[j-1]?0:1));p=c}return p[n]}
  function simMaster(a,b){a=normMaster(a);b=normMaster(b);if(!a||!b)return 0;if(a===b)return 1;return 1-levMaster(a,b)/Math.max(a.length,b.length)}

  async function loadAccountCategories(){
    try{
      const c=resolveClient();
      const r=await c.from("rr_account_categories_v805").select("id,category_code,category_name,group_id,is_active").eq("is_active",true).order("category_name",{ascending:true});
      if(r.error)throw r.error;
      state.accountCategories=r.data||[];
    }catch(e){console.warn("Account categories unavailable",e);state.accountCategories=[]}
    const el=$("addMasterCategory");if(el)el.innerHTML='<option value="">Select category…</option>'+state.accountCategories.map(x=>`<option value="${esc(x.id)}">${esc(x.category_name)} · ${esc(x.category_code)}</option>`).join("");
  }

  function fieldCurrentText(target){
    const el=$(target); if(!el)return "";
    const opt=el.selectedOptions?.[0];
    const t=String(opt?.textContent||"").trim();
    return /select|all/i.test(t)?"":t.split(" · ")[0].trim();
  }

  function openFieldAdd(btn){
    state.addEntity=btn.dataset.addEntity||"";
    state.addTarget=btn.dataset.target||"";
    const entity=state.addEntity;
    const title=ADD_LABELS[entity]||entity;
    $("addMasterTitle").textContent=`Add New ${title}`;
    $("addMasterSub").textContent=`${title} not found? Type the exact new name. Existing spelling/similarity will be checked first.`;
    $("addMasterName").value=fieldCurrentText(state.addTarget);
    $("addMasterCode").value="";
    $("addMasterMatches").innerHTML="";$("addMasterMatches").classList.add("hidden");
    $("addMasterMsg").textContent="";$("submitAddMaster").disabled=true;

    const isLedger=entity==="PARTY"||entity==="LEDGER";
    $("addMasterKindWrap").classList.toggle("hidden",!isLedger);
    $("addMasterCategoryWrap").classList.toggle("hidden",!isLedger);
    $("addMasterUnitWrap").classList.toggle("hidden",entity!=="MATERIAL_TYPE");
    $("addMasterCodeWrap").classList.toggle("hidden",false);

    if(entity==="PARTY")$("addMasterKind").value="SUPPLIER";
    else if(entity==="LEDGER"){
      const k=btn.dataset.ledgerKind||"GENERAL";
      $("addMasterKind").value=k==="CASH_BANK"?"CASH":"GENERAL";
    }

    const m=$("addMasterModal");m.classList.remove("hidden");m.style.display="grid";
    setTimeout(()=>$("addMasterName")?.focus(),30);
  }
  function closeFieldAdd(){const m=$("addMasterModal");m.classList.add("hidden");m.style.display=""}

  async function checkFieldAdd(){
    const name=String($("addMasterName").value||"").trim(),entity=state.addEntity;
    if(!name)return message("addMasterMsg","Name required.","error");
    message("addMasterMsg","Checking existing names…");
    $("submitAddMaster").disabled=true;
    try{
      let rows=[];
      if(entity==="MATERIAL"){
        const type=$("type")?.value||"";
        if(!type)throw new Error("Select Material Type first.");
        rows=await rpc("rr_material_source_search_v805_1",{p_type_code:type,p_search:name,p_data_mode:mode(),p_limit:20});
        rows=(Array.isArray(rows)?rows:[]).map(r=>({id:r.existing_material_id||r.source_id,display_name:r.material_name||r.material_no,detail:r.material_no||r.source_type}));
      }else{
        rows=await rpc("rr_master_name_candidates_v8078",{p_entity_type:entity,p_search:name,p_limit:20});
        rows=Array.isArray(rows)?rows:[];
      }
      const scored=rows.map(r=>({...r,_score:Number(r.similarity_score||simMaster(name,r.display_name||r.name))})).sort((a,b)=>b._score-a._score);
      const close=scored.filter(r=>r._score>=0.72||normMaster(r.display_name).includes(normMaster(name))||normMaster(name).includes(normMaster(r.display_name))).slice(0,8);
      const box=$("addMasterMatches");
      if(close.length){
        box.innerHTML=close.map(r=>`<div class="suggestion"><b>${esc(r.display_name||r.name)}</b><small>${esc(r.detail||r.code||"Existing")} · ${Math.round(r._score*100)}% match</small></div>`).join("");
        box.classList.remove("hidden");
        message("addMasterMsg","Existing / similar name found. Select existing in the original field; duplicate creation is blocked.","error");
        $("submitAddMaster").disabled=true;
      }else{
        box.innerHTML='<div class="empty">No close spelling/similarity match found.</div>';box.classList.remove("hidden");
        message("addMasterMsg","No close match found. You can send this as a new master request.","ok");
        $("submitAddMaster").disabled=false;
      }
    }catch(e){message("addMasterMsg",errorText(e),"error")}
  }

  async function submitFieldAdd(){
    const name=String($("addMasterName").value||"").trim(),entity=state.addEntity;
    if(!name)return;
    const btn=$("submitAddMaster");setBusy(btn,true,"Sending…");
    try{
      const payload={
        target_field:state.addTarget,
        ledger_kind:$("addMasterKind")?.value||null,
        category_id:$("addMasterCategory")?.value||null,
        type_code:$("type")?.value||null,
        default_unit:$("addMasterUnit")?.value||null,
        code_no:String($("addMasterCode")?.value||"").trim()||null,
        data_mode:mode()
      };
      const d=await rpc("rr_master_name_request_v8078",{p_entity_type:entity,p_requested_name:name,p_payload:payload});
      if(d?.blocked_by_match){
        message("addMasterMsg","Similar existing name found. Creation blocked; use existing option.","error");
      }else{
        message("addMasterMsg",`Request sent for Super Admin approval${d?.request_id?` · ${d.request_id}`:""}.`,"ok");
        $("submitAddMaster").disabled=true;
        await loadMasterRequests().catch(()=>{});
      }
    }catch(e){message("addMasterMsg",errorText(e),"error")}
    finally{setBusy(btn,false)}
  }

  async function loadMasterRequests(){
    const box=$("masterRequestResult");if(!box)return;
    try{
      const rows=await rpc("rr_master_name_requests_v8078",{p_status:null,p_limit:100});
      state.masterRequests=Array.isArray(rows)?rows:[];
      if(!state.masterRequests.length){box.innerHTML='<div class="empty">No new master requests.</div>';return}
      box.innerHTML=`<div class="scroll"><table><thead><tr><th>Requested</th><th>Entity</th><th>Name</th><th>Suggested</th><th>Status</th><th>Action</th></tr></thead><tbody>`+
        state.masterRequests.map(r=>`<tr><td>${esc(new Date(r.requested_at).toLocaleString())}</td><td>${esc(r.entity_type)}</td><td><b>${esc(r.requested_name)}</b></td><td>${esc((r.suggested_matches||[]).slice(0,3).map(x=>x.display_name).join(", ")||"—")}</td><td>${esc(r.status)}</td><td>${r.status==="PENDING"?`<button data-approve-master="${r.id}" class="primary">Approve</button> <button data-reject-master="${r.id}">Reject</button>`:"—"}</td></tr>`).join("")+
        `</tbody></table></div>`;
      box.querySelectorAll("[data-approve-master]").forEach(b=>b.onclick=()=>decideMasterRequest(b.dataset.approveMaster,"APPROVE_NEW"));
      box.querySelectorAll("[data-reject-master]").forEach(b=>b.onclick=()=>decideMasterRequest(b.dataset.rejectMaster,"REJECT"));
    }catch(e){box.innerHTML=`<div class="empty">${esc(errorText(e))}</div>`}
  }

  async function decideMasterRequest(id,decision){
    const remark=prompt(decision==="REJECT"?"Rejection reason:":"Super Admin remark (optional):","")??"";
    try{
      const d=await rpc("rr_master_name_decide_v8078",{p_request_id:id,p_decision:decision,p_remark:remark});
      alert(d?.message||"Decision saved.");
      await Promise.allSettled([loadMasterRequests(),loadLedgers(),loadMaterialBootstrap()]);
      if($("type")?.value)await loadMappedMaterialsForType("");
    }catch(e){alert(errorText(e))}
  }

$("searchReports")?.addEventListener("click",()=>searchReports());$("reportSearch")?.addEventListener("input",()=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>searchReports(),220)});$("reportSearch")?.addEventListener("keydown",e=>{if(e.key==="Enter"){e.preventDefault();searchReports()}});$("loadDayBook")?.addEventListener("click",loadDayBook);$("bookSearch")?.addEventListener("input",renderBook);$("bookView")?.addEventListener("change",()=>{$("bookLedger").parentElement.classList.toggle("hidden",$("bookView").value!=="LEDGER")});$("loadCreditors")?.addEventListener("click",()=>loadCreditors(true));$("creditorSearch")?.addEventListener("input",()=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>loadCreditors(true),220)});$("creditorPrev")?.addEventListener("click",()=>{state.creditorOffset=Math.max(0,state.creditorOffset-100);loadCreditors()});$("creditorNext")?.addEventListener("click",()=>{state.creditorOffset+=100;loadCreditors()});$("postJournal")?.addEventListener("click",postJournal);$("reverseVoucherBtn")?.addEventListener("click",reverseVoucher);$("dataMode")?.addEventListener("change",()=>{$("modeMirror").value=mode();state.creditorOffset=0;refresh()});$("refreshAll")?.addEventListener("click",refresh);wirePreviewTemplates();zeroClean();enterFlow($("purchase"));enterFlow($("money"));
  }

  window.RR_ACCOUNTS_V805={
    setData:(d={})=>{if(Array.isArray(d.material_types)){state.materialTypes=d.material_types;if($("type"))$("type").innerHTML='<option value="">Select material type…</option>'+state.materialTypes.map(x=>`<option value="${esc(x.type_code)}">${esc(x.type_name)}</option>`).join("")}},
    refresh,
    searchReports,
    runSelectedReport
  };

  document.addEventListener("DOMContentLoaded",()=>{initDates();wire();refresh()});
})();
