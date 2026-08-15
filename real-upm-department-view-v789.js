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

  let mode = "SUBMIT";
  let payload = null;
  let refreshToken = 0;
  let applyTimer = null;
  let observer = null;

  const style = document.createElement("style");
  style.id = "rf-v9095-style";
  style.textContent = `
    .rf-v9095-toolbar{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin:12px 0}
    .rf-v9095-toolbar button{min-height:54px;border:1px solid #394252;border-radius:12px;background:#202635;color:#fff;font-size:15px;font-weight:950}
    .rf-v9095-toolbar button.active{background:#d63b5a;border-color:#ef6b83}
    .rf-v9095-count{color:#55efad;margin-left:5px}
    .rf-v9095-hidden{display:none!important}
    .rf-v9095-colours{display:grid;gap:6px;margin:8px 0}
    .rf-v9095-row{display:grid;grid-template-columns:minmax(42px,.65fr) minmax(72px,.9fr) minmax(110px,1.35fr);gap:7px;align-items:center;padding:8px 10px;border:1px solid #7c5a17;border-radius:9px;background:#4d3708;color:#fff;font-size:12px;font-weight:900}
    .rf-v9095-row .c{font-size:14px}.rf-v9095-row .q{color:#ffe39a}.rf-v9095-row .w{text-align:right}
    .rf-v9095-row.assign{border-color:#2877b4;background:#0f3556;cursor:pointer}
    .rf-v9095-row.assign .q{color:#9ed3ff}.rf-v9095-empty{padding:12px;border:1px dashed #3c4655;border-radius:10px;color:#98a2b3;font-weight:800}
    .rf-v9095-queue{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-top:12px}
    .rf-v9095-qcard{background:#12151c;border:1px solid #303641;border-radius:14px;padding:12px}
    .rf-v9095-qhead{display:flex;justify-content:space-between;gap:8px;margin-bottom:8px}.rf-v9095-qhead b{font-size:18px}.rf-v9095-qhead span{color:#98a2b3;font-size:11px}
    .rf-v9095-assign-section{margin-top:12px}
    .rf-v9095-assign-section h2{margin:4px 0}.rf-v9095-note{color:#98a2b3;margin:0 0 8px}
    .rf-v9095-loading #board{visibility:hidden}
    .lot-card .lot-live-list.rf-v9095-owned{min-height:0}
    @media(max-width:700px){.rf-v9095-queue{grid-template-columns:1fr}.rf-v9095-toolbar{position:sticky;top:0;z-index:20;background:#07090d;padding:6px 0}.rf-v9095-row{grid-template-columns:48px 72px 1fr}}
  `;
  document.head.appendChild(style);

  function lotNoFromCard(card){
    return up(card.querySelector(".lot-no")?.textContent || "");
  }
  function lotIndex(){
    return new Map((payload?.lots || []).map(x => [up(x.lot_no), x]));
  }
  function fmtQty(v){
    const n=Number(v||0); return Number.isInteger(n)?String(n):n.toFixed(1).replace(/\.0$/,"");
  }
  function rowHtml(r, kind){
    const worker = r.worker_first_name ? `${r.worker_first_name}/${r.dept_short || ""}` : `OPEN/${r.dept_short || ""}`;
    return `<div class="rf-v9095-row ${kind==="ASSIGN"?"assign":""}" data-rf-colour="${esc(r.colour_code)}">
      <span class="c">${esc(r.colour_code)}</span>
      <span class="q">${esc(fmtQty(r.qty))} PCS</span>
      <span class="w">${esc(worker)}</span>
    </div>`;
  }

  function ensureShell(){
    const board=document.getElementById("board");
    if(!board) return false;
    let bar=document.getElementById("rfV9095Toolbar");
    if(!bar){
      bar=document.createElement("section");
      bar.id="rfV9095Toolbar";
      bar.className="rf-v9095-toolbar";
      bar.innerHTML=`<button type="button" data-rf-mode="SUBMIT">SUBMIT DUE <b class="rf-v9095-count" id="rfV9095Submit">0</b></button>
                     <button type="button" data-rf-mode="ASSIGN">ASSIGN DUE <b class="rf-v9095-count" id="rfV9095Assign">0</b></button>`;
      board.insertAdjacentElement("beforebegin",bar);
      bar.querySelectorAll("[data-rf-mode]").forEach(b=>b.onclick=()=>{mode=b.dataset.rfMode; apply();});
    }
    let assign=document.getElementById("rfV9095AssignSection");
    if(!assign){
      assign=document.createElement("section");
      assign.id="rfV9095AssignSection";
      assign.className="rf-v9095-assign-section rf-v9095-hidden";
      assign.innerHTML=`<h2>OPEN RANDOM QUEUE</h2><p class="rf-v9095-note">Only ${esc(label)} ASSIGN DUE colours · one separate row per colour.</p><div id="rfV9095Queue" class="rf-v9095-queue"></div>`;
      board.insertAdjacentElement("afterend",assign);
    }
    return true;
  }

  function decorateSubmit(){
    const map=lotIndex();
    const cards=[...document.querySelectorAll("#board .lot-card[data-lot]")];
    cards.forEach(card=>{
      const row=map.get(lotNoFromCard(card));
      const submit=row?.submit_rows || [];
      card.classList.toggle("rf-v9095-hidden",submit.length===0);
      let host=card.querySelector(".lot-live-list");
      if(!host){
        host=document.createElement("div");host.className="lot-live-list";
        card.querySelector(".lot-head")?.insertAdjacentElement("afterend",host);
      }
      host.classList.add("rf-v9095-owned");
      host.innerHTML=submit.length ? `<div class="rf-v9095-colours">${submit.map(r=>rowHtml(r,"SUBMIT")).join("")}</div>` : "";
      const old=card.querySelector(".checkin"); if(old) old.hidden=true;
      let acts=card.querySelector(".rf-card-actions");
      if(!acts){
        acts=document.createElement("div");acts.className="rf-card-actions";
        acts.innerHTML='<button type="button" data-rf-act="rect">RECTIFICATION</button><button type="button" data-rf-act="submit">SUBMIT DUE</button>';
        card.append(acts);
        acts.onclick=e=>{
          e.stopPropagation();
          const a=e.target.closest("[data-rf-act]")?.dataset.rfAct;if(!a)return;
          card.querySelector("[data-open-lot]")?.click();
          const id=a==="submit"?"submitBtn":"alterBtn";
          let t=0;const iv=setInterval(()=>{const el=document.getElementById(id);if(el){clearInterval(iv);el.scrollIntoView({block:"center"});}else if(++t>30)clearInterval(iv);},100);
        };
      }
    });
  }

  function lotMetaFromCore(lotNo){
    const snap=window.RealFactoryUPM?.snapshot?.();
    return (snap?.lots || []).find(x=>up(x.lot_no)===up(lotNo));
  }
  async function openAssign(lotNo, colour){
    const lot=lotMetaFromCore(lotNo);
    if(!lot) return;
    try{
      if(window.RealFactoryUPM?.openLotAtDepartment){
        await window.RealFactoryUPM.openLotAtDepartment(lot.canonical_lot_id, requestedRaw);
      }else{
        const card=[...document.querySelectorAll("#board .lot-card[data-lot]")].find(c=>lotNoFromCard(c)===up(lotNo));
        card?.querySelector("[data-open-lot]")?.click();
      }
      setTimeout(()=>{
        const colourCard=[...document.querySelectorAll("#colours .colour-card")].find(c=>up(c.querySelector("h3")?.textContent).includes(up(colour)));
        colourCard?.scrollIntoView({behavior:"smooth",block:"center"});
      },450);
    }catch(e){console.warn("V9095 open assign",e);}
  }

  function renderAssign(){
    const q=document.getElementById("rfV9095Queue"); if(!q)return;
    const lots=(payload?.lots||[]).filter(x=>(x.assign_rows||[]).length);
    q.innerHTML=lots.length?lots.map(x=>`<article class="rf-v9095-qcard">
      <div class="rf-v9095-qhead"><b>${esc(x.lot_no)}</b><span>${(x.assign_rows||[]).length} COLOUR DUE</span></div>
      <div class="rf-v9095-colours">${(x.assign_rows||[]).map(r=>rowHtml(r,"ASSIGN")).join("")}</div>
    </article>`).join(""):`<div class="rf-v9095-empty">No ASSIGN DUE colours for ${esc(label)}.</div>`;
    q.querySelectorAll(".rf-v9095-qcard").forEach(card=>{
      const lotNo=card.querySelector(".rf-v9095-qhead b")?.textContent;
      card.querySelectorAll(".rf-v9095-row.assign").forEach(r=>r.onclick=()=>openAssign(lotNo,r.dataset.rfColour));
    });
  }

  function apply(){
    if(!payload || !ensureShell()) return;
    document.getElementById("rfV9095Submit").textContent=String(payload.submit_count||0);
    document.getElementById("rfV9095Assign").textContent=String(payload.assign_count||0);
    document.querySelectorAll("[data-rf-mode]").forEach(b=>b.classList.toggle("active",b.dataset.rfMode===mode));
    const board=document.getElementById("board"), assign=document.getElementById("rfV9095AssignSection");
    if(mode==="SUBMIT"){
      board?.classList.remove("rf-v9095-hidden");assign?.classList.add("rf-v9095-hidden");
      decorateSubmit();
    }else{
      board?.classList.add("rf-v9095-hidden");assign?.classList.remove("rf-v9095-hidden");
      renderAssign();
    }
    document.documentElement.classList.remove("rf-v9095-loading");
  }

  async function refresh(){
    const sb=client(); if(!sb)return;
    const token=++refreshToken;
    document.documentElement.classList.add("rf-v9095-loading");
    const {data,error}=await sb.rpc("rr_upm_department_colour_due_card_v9095",{p_department_code:requested});
    if(token!==refreshToken)return;
    if(error){console.warn("V9095 due RPC",error);document.documentElement.classList.remove("rf-v9095-loading");return;}
    payload=data||{};
    apply();
  }

  function lockDept(){
    const s=document.getElementById("homeDept");if(!s)return;
    const wanted=[...s.options].find(o=>(alias[up(o.value)]||up(o.value))===requested);
    if(wanted && s.value!==wanted.value){s.value=wanted.value;s.dispatchEvent(new Event("change",{bubbles:true}));}
    if(wanted)s.disabled=true;
  }

  function boot(){
    ensureShell(); lockDept();
    clearTimeout(applyTimer); applyTimer=setTimeout(refresh,120);
    observer?.disconnect();
    const board=document.getElementById("board");
    if(board){
      observer=new MutationObserver(()=>{clearTimeout(applyTimer);applyTimer=setTimeout(()=>{lockDept();apply();},80);});
      observer.observe(board,{childList:true});
    }
    document.getElementById("refresh")?.addEventListener("click",()=>setTimeout(refresh,250));
  }

  document.documentElement.classList.add("rf-v9095-loading");
  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded",()=>setTimeout(boot,0));
  else setTimeout(boot,0);
  setTimeout(boot,800);
})();