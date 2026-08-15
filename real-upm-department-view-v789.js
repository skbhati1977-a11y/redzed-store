(() => {
  "use strict";

  const params = new URLSearchParams(location.search);
  const requestedRaw = String(params.get("dept") || "").trim().toUpperCase();
  if (!requestedRaw) return;

  const alias = {
    KR:"STITCHING", KARIGAR:"STITCHING", STITCH:"STITCHING", STITCHING:"STITCHING",
    OV:"OVERLOCK", OVERLOCK:"OVERLOCK",
    FLD:"FOLDING", FLATLOCK:"FOLDING", FOLDING:"FOLDING",
    KAAJ:"KAAJ", KAJ:"KAAJ", BUTTON:"BUTTON", BTN:"BUTTON", KAAJ_BUTTON:"KAAJ_BUTTON",
    TEAK:"TEAK_TANKI", TANKI:"TEAK_TANKI", TEAK_TANKI:"TEAK_TANKI",
    THREAD_CUT:"THREAD_CUT", THREAD_CUTTING:"THREAD_CUT", TH_CUT:"THREAD_CUT",
    QC:"QC", CHECKING:"QC", PRESS:"PRESS", FINISHING:"PRESS",
    PRINT:"PRINTING", PRINTING:"PRINTING", STICKER:"STICKER",
    ID:"METAL_ID", ID_WORK:"METAL_ID", METAL_ID:"METAL_ID",
    PACK:"PACKING", PACKING:"PACKING", DISPATCH:"DESPATCH", DESPATCH:"DESPATCH",
    CUT:"CUTTING", CUTTING:"CUTTING"
  };
  const requested = alias[requestedRaw] || requestedRaw;
  const label = String(params.get("label") || requestedRaw).trim();
  const up = v => String(v || "").trim().toUpperCase();
  const esc = v => String(v ?? "").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const client = () => window.supabaseClient || window.supabaseDb || window.redzedSupabase || window.sb || null;
  const cacheKey = `rf:v9098:boundary:${requested}`;

  let mode = "SUBMIT";
  let payload = null;
  let busy = false;
  let booted = false;
  let observer = null;
  let renderTimer = null;

  try {
    const cached = JSON.parse(sessionStorage.getItem(cacheKey) || "null");
    if (cached?.ok && cached.department_code === requested && Array.isArray(cached.lots)) payload = cached;
  } catch (_) {}

  const style = document.createElement("style");
  style.id = "rf-v9098-boundary-style";
  style.textContent = `
    #board.rf-v9098-core-hidden{display:none!important}
    .rf-v9098-toolbar{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin:12px 0}
    .rf-v9098-toolbar button{min-height:58px;border:1px solid #394252;border-radius:12px;background:#202635;color:#fff;font-size:15px;font-weight:950;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px}
    .rf-v9098-toolbar button.active{background:#d63b5a;border-color:#ef6b83}
    .rf-v9098-countline{display:flex;gap:10px;font-size:12px}.rf-v9098-lot{color:#9ed3ff}.rf-v9098-col{color:#55efad}
    .rf-v9098-section{margin-top:12px}.rf-v9098-section.hidden{display:none!important}
    .rf-v9098-title{display:flex;align-items:flex-end;justify-content:space-between;gap:10px;margin:0 0 8px}.rf-v9098-title h2{margin:0}.rf-v9098-title p{margin:3px 0 0;color:#98a2b3}
    .rf-v9098-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
    .rf-v9098-card{background:#12151c;border:1px solid #303641;border-radius:14px;padding:12px;min-height:180px;display:flex;flex-direction:column}
    .rf-v9098-head{display:flex;justify-content:space-between;gap:8px}.rf-v9098-head b{font-size:19px}.rf-v9098-meta{color:#98a2b3;font-size:11px;text-align:right}
    .rf-v9098-submeta{color:#9ec5ff;font-size:12px;font-weight:850;margin-top:2px}.rf-v9098-art{color:#ffc857;font-weight:850}
    .rf-v9098-thumbs{display:flex;gap:6px;overflow:auto;min-height:54px;margin:6px 0}.rf-v9098-thumbs .thumb{width:52px;height:52px;flex:0 0 52px}
    .rf-v9098-rows{display:grid;gap:6px;margin:8px 0}
    .rf-v9098-row{display:grid;grid-template-columns:48px 72px 1fr;gap:8px;align-items:center;padding:8px 10px;border:1px solid #7c5a17;border-radius:9px;background:#4d3708;color:#fff;font-size:12px;font-weight:900}
    .rf-v9098-row.assign{border-color:#2877b4;background:#0f3556;cursor:pointer}.rf-v9098-row .w{text-align:right}.rf-v9098-row .q{color:#ffe39a}.rf-v9098-row.assign .q{color:#9ed3ff}
    .rf-v9098-actions{display:grid;grid-template-columns:1fr 1fr;gap:7px;margin-top:auto}.rf-v9098-actions button{min-height:42px}
    .rf-v9098-empty{padding:16px;border:1px dashed #3c4655;border-radius:10px;color:#98a2b3;font-weight:850}
    .rf-v9098-refreshing{opacity:.72}
    @media(max-width:700px){.rf-v9098-grid{grid-template-columns:1fr}.rf-v9098-toolbar{position:sticky;top:0;z-index:20;background:#07090d;padding:6px 0}.rf-v9098-title{align-items:flex-start;flex-direction:column}}
  `;
  document.head.appendChild(style);

  const fmtQty = v => { const n=Number(v||0); return Number.isInteger(n)?String(n):n.toFixed(1).replace(/\.0$/,""); };
  const valid = data => !!data && data.ok === true && data.department_code === requested && Array.isArray(data.lots);
  const coreSnap = () => window.RealFactoryUPM?.snapshot?.() || {lots:[]};
  const coreLot = lotNo => (coreSnap().lots || []).find(x => up(x.lot_no) === up(lotNo));
  const nativeCard = lotNo => [...document.querySelectorAll("#board .lot-card[data-lot]")].find(c => up(c.querySelector(".lot-no")?.textContent) === up(lotNo));
  const counts = () => {
    const lots = payload?.lots || [];
    return {
      submitLots: lots.filter(x => (x.submit_rows||[]).length).length,
      submitCols: Number(payload?.submit_count||0),
      assignLots: lots.filter(x => (x.assign_rows||[]).length).length,
      assignCols: Number(payload?.assign_count||0)
    };
  };

  function ensureShell(){
    const board=document.getElementById("board"); if(!board) return false;
    board.classList.add("rf-v9098-core-hidden");
    let bar=document.getElementById("rfV9098Toolbar");
    if(!bar){
      bar=document.createElement("section"); bar.id="rfV9098Toolbar"; bar.className="rf-v9098-toolbar";
      bar.innerHTML=`<button type="button" data-rf9098-mode="SUBMIT"><span>SUBMIT DUE</span><span class="rf-v9098-countline"><span class="rf-v9098-lot">LOT <b id="rf9098SubmitLots">—</b></span><span class="rf-v9098-col">COL <b id="rf9098SubmitCols">—</b></span></span></button><button type="button" data-rf9098-mode="ASSIGN"><span>ASSIGN DUE</span><span class="rf-v9098-countline"><span class="rf-v9098-lot">LOT <b id="rf9098AssignLots">—</b></span><span class="rf-v9098-col">COL <b id="rf9098AssignCols">—</b></span></span></button>`;
      board.insertAdjacentElement("beforebegin",bar);
      bar.querySelectorAll("[data-rf9098-mode]").forEach(b=>b.onclick=()=>{mode=b.dataset.rf9098Mode;render();});
    }
    let submit=document.getElementById("rfV9098SubmitSection");
    if(!submit){ submit=document.createElement("section");submit.id="rfV9098SubmitSection";submit.className="rf-v9098-section";submit.innerHTML=`<div class="rf-v9098-title"><div><h2>${esc(label)} · SUBMIT DUE</h2><p>Only current ${esc(label)} running work. No other department and no Open Random Queue.</p></div></div><div id="rfV9098SubmitGrid" class="rf-v9098-grid"></div>`;board.insertAdjacentElement("afterend",submit); }
    let assign=document.getElementById("rfV9098AssignSection");
    if(!assign){ assign=document.createElement("section");assign.id="rfV9098AssignSection";assign.className="rf-v9098-section hidden";assign.innerHTML=`<div class="rf-v9098-title"><div><h2>OPEN RANDOM QUEUE</h2><p>Only colours physically OPEN and assignable to ${esc(label)}.</p></div></div><div id="rfV9098AssignGrid" class="rf-v9098-grid"></div>`;submit.insertAdjacentElement("afterend",assign); }
    return true;
  }

  function identityHtml(lotNo){
    const lot=coreLot(lotNo)||{};
    const card=nativeCard(lotNo);
    const cb=lot.cb_no||lot.cb_number||card?.querySelector(".cb-no")?.textContent?.replace(/^CB NO\s*·?\s*/i,"")||"—";
    const art=lot.art_no||card?.querySelector(".art-no")?.textContent?.replace(/^ART\s*/i,"")||"—";
    const total=lot.total_qty||card?.querySelector(".cut")?.textContent?.replace(/\s*PCS.*$/i,"")||"—";
    const thumbs=card?.querySelector(".thumbs")?.innerHTML||"";
    return `<div class="rf-v9098-head"><div><b>${esc(lotNo)}</b><div class="rf-v9098-submeta">CB NO · ${esc(cb)}</div><div class="rf-v9098-art">ART ${esc(art)}</div></div><div class="rf-v9098-meta">TOTAL CUT<br><strong>${esc(total)} PCS</strong></div></div>${thumbs?`<div class="rf-v9098-thumbs">${thumbs}</div>`:""}`;
  }

  function rowHtml(r,kind){
    const worker=r.worker_first_name?`${r.worker_first_name}/${r.dept_short||""}`:`OPEN/${r.dept_short||""}`;
    return `<div class="rf-v9098-row ${kind==='ASSIGN'?'assign':''}" data-colour="${esc(r.colour_code)}"><span>${esc(r.colour_code)}</span><span class="q">${esc(fmtQty(r.qty))} PCS</span><span class="w">${esc(worker)}</span></div>`;
  }

  async function openLot(lotNo, targetId, colour){
    const lot=coreLot(lotNo); if(!lot) return;
    try{
      if(window.RealFactoryUPM?.openLotAtDepartment) await window.RealFactoryUPM.openLotAtDepartment(lot.canonical_lot_id, requestedRaw);
      else nativeCard(lotNo)?.querySelector("[data-open-lot]")?.click();
      setTimeout(()=>{
        if(colour){ const cc=[...document.querySelectorAll("#colours .colour-card")].find(c=>up(c.querySelector("h3")?.textContent).includes(up(colour))); cc?.scrollIntoView({behavior:"smooth",block:"center"}); }
        else document.getElementById(targetId)?.scrollIntoView({behavior:"smooth",block:"center"});
      },450);
    }catch(e){console.warn("V9098 open lot",e);}
  }

  function renderSubmit(){
    const host=document.getElementById("rfV9098SubmitGrid"); if(!host)return;
    const q=up(document.getElementById("search")?.value||"");
    const lots=(payload?.lots||[]).filter(x=>(x.submit_rows||[]).length).filter(x=>!q||up(x.lot_no).includes(q));
    host.innerHTML=lots.length?lots.map(x=>`<article class="rf-v9098-card" data-lot="${esc(x.lot_no)}">${identityHtml(x.lot_no)}<div class="rf-v9098-rows">${x.submit_rows.map(r=>rowHtml(r,"SUBMIT")).join("")}</div><div class="rf-v9098-actions"><button type="button" data-act="rect">RECTIFICATION</button><button type="button" data-act="submit">SUBMIT DUE</button></div></article>`).join(""):`<div class="rf-v9098-empty">No ${esc(label)} SUBMIT DUE work.</div>`;
    host.querySelectorAll(".rf-v9098-card").forEach(card=>card.querySelector(".rf-v9098-actions").onclick=e=>{const a=e.target.closest("[data-act]")?.dataset.act;if(!a)return;openLot(card.dataset.lot,a==='submit'?'submitBtn':'alterBtn');});
  }

  function renderAssign(){
    const host=document.getElementById("rfV9098AssignGrid"); if(!host)return;
    const q=up(document.getElementById("search")?.value||"");
    const lots=(payload?.lots||[]).filter(x=>(x.assign_rows||[]).length).filter(x=>!q||up(x.lot_no).includes(q));
    host.innerHTML=lots.length?lots.map(x=>`<article class="rf-v9098-card" data-lot="${esc(x.lot_no)}">${identityHtml(x.lot_no)}<div class="rf-v9098-rows">${x.assign_rows.map(r=>rowHtml(r,"ASSIGN")).join("")}</div></article>`).join(""):`<div class="rf-v9098-empty">No ${esc(label)} ASSIGN DUE colours.</div>`;
    host.querySelectorAll(".rf-v9098-card").forEach(card=>card.querySelectorAll(".rf-v9098-row.assign").forEach(r=>r.onclick=()=>openLot(card.dataset.lot,null,r.dataset.colour)));
  }

  function render(){
    if(!ensureShell()) return;
    if(payload){
      const c=counts();
      document.getElementById("rf9098SubmitLots").textContent=c.submitLots;
      document.getElementById("rf9098SubmitCols").textContent=c.submitCols;
      document.getElementById("rf9098AssignLots").textContent=c.assignLots;
      document.getElementById("rf9098AssignCols").textContent=c.assignCols;
    }
    document.querySelectorAll("[data-rf9098-mode]").forEach(b=>b.classList.toggle("active",b.dataset.rf9098Mode===mode));
    document.getElementById("rfV9098SubmitSection")?.classList.toggle("hidden",mode!=="SUBMIT");
    document.getElementById("rfV9098AssignSection")?.classList.toggle("hidden",mode!=="ASSIGN");
    if(mode==="SUBMIT") renderSubmit(); else renderAssign();
  }

  async function refresh(){
    if(busy) return; const sb=client(); if(!sb)return; busy=true;
    document.getElementById("rfV9098Toolbar")?.classList.add("rf-v9098-refreshing");
    try{
      const {data,error}=await sb.rpc("rr_upm_department_colour_due_card_v9095",{p_department_code:requested});
      if(error) throw error;
      if(!valid(data)) throw new Error("Cross-department or incomplete snapshot rejected");
      payload=data; try{sessionStorage.setItem(cacheKey,JSON.stringify(data));}catch(_){}
      render();
    }catch(e){ console.warn("V9098 retained last valid department snapshot",e); render(); }
    finally{ busy=false; document.getElementById("rfV9098Toolbar")?.classList.remove("rf-v9098-refreshing"); }
  }

  function lockDept(){
    const s=document.getElementById("homeDept");if(!s)return;
    const wanted=[...s.options].find(o=>(alias[up(o.value)]||up(o.value))===requested);
    if(wanted&&s.value!==wanted.value){s.value=wanted.value;s.dispatchEvent(new Event("change",{bubbles:true}));}
    if(wanted)s.disabled=true;
  }

  function boot(){
    if(booted)return;booted=true;ensureShell();lockDept();render();setTimeout(refresh,120);
    const board=document.getElementById("board");
    if(board){observer=new MutationObserver(()=>{clearTimeout(renderTimer);renderTimer=setTimeout(()=>{lockDept();render();},100);});observer.observe(board,{childList:true});}
    document.getElementById("refresh")?.addEventListener("click",()=>setTimeout(refresh,180));
    document.getElementById("search")?.addEventListener("input",()=>render());
    document.addEventListener("visibilitychange",()=>{if(!document.hidden)setTimeout(refresh,180);});
  }

  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",boot,{once:true});else boot();
})();