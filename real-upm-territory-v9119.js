(() => {
'use strict';
if (window.__RF_TERRITORY_9119__) return;
window.__RF_TERRITORY_9119__ = true;

const qs = new URLSearchParams(location.search);
const raw = (qs.get('dept') || '').trim().toUpperCase();
const ALIAS = {KR:'STITCHING',KARIGAR:'STITCHING',STITCH:'STITCHING',STITCHING:'STITCHING',OV:'OVERLOCK',OVERLOCK:'OVERLOCK',FLD:'FOLDING',FLATLOCK:'FOLDING',FOLDING:'FOLDING',KAAJ:'KAAJ',KAJ:'KAAJ',BUTTON:'BUTTON',BTN:'BUTTON',KAAJ_BUTTON:'KAAJ_BUTTON',TEAK:'TEAK_TANKI',TANKI:'TEAK_TANKI',TEAK_TANKI:'TEAK_TANKI',THREAD_CUT:'THREAD_CUT',THREAD_CUTTING:'THREAD_CUT',TH_CUT:'THREAD_CUT',QC:'QC',CHECKING:'QC',PRESS:'PRESS',FINISHING:'PRESS',PRINT:'PRINTING',PRINTING:'PRINTING',STICKER:'STICKER',ID:'METAL_ID',ID_WORK:'METAL_ID',METAL_ID:'METAL_ID',PACK:'PACKING',PACKING:'PACKING',DISPATCH:'DESPATCH',DESPATCH:'DESPATCH'};
const LABEL = {PRINTING:'Printing',STICKER:'Sticker',METAL_ID:'Metal ID',STITCHING:'Karigar / Stitching',OVERLOCK:'Overlock',FOLDING:'Folding',KAAJ:'Kaaj',BUTTON:'Button',KAAJ_BUTTON:'Kaaj / Button',TEAK_TANKI:'Teak / Tanki',THREAD_CUT:'Thread Cutting',QC:'QC',PRESS:'Press',PACKING:'Packing',DESPATCH:'Despatch'};
const dept = ALIAS[raw] || raw;
const label = LABEL[dept] || (qs.get('label') || dept || 'All Departments');
const sb = () => window.supabaseClient || window.supabaseDb || window.redzedSupabase || window.sb;
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const up = v => String(v || '').trim().toUpperCase();
const fmt = v => { const n=Number(v||0); return Number.isInteger(n)?String(n):n.toFixed(1).replace(/\.0$/,''); };
const age = s => { s=Math.max(0,Number(s||0)); const d=Math.floor(s/36000),h=Math.floor((s%36000)/3600),m=Math.floor((s%3600)/60); return d?`${d}d ${h}h`:h?`${h}h ${m}m`:`${m}m`; };

const style = document.createElement('style');
style.textContent = `
#rfTerritoryBadge9119{min-height:48px;display:flex;align-items:center;padding:10px 14px;border:1px solid #394252;border-radius:10px;background:#202635;color:#fff;font-weight:950}
html.rf-territory #homeDept{display:none!important}
html.rf-territory #board{display:none!important}
#rfAllDept9119{margin-top:12px}
.rfAllBar9119{display:grid;grid-template-columns:1fr 1fr;gap:8px;position:sticky;top:0;z-index:40;background:#07090d;padding:6px 0}
.rfAllBar9119 button{min-height:62px;font-weight:950;border-radius:12px}.rfAllBar9119 button.active{background:#d63b5a}
.rfAllCount9119{display:flex;justify-content:center;gap:12px;font-size:12px;margin-top:3px}.rfAllLot9119{color:#9ed3ff}.rfAllCol9119{color:#55efad}
.rfDeptGroup9119{margin:14px 0}.rfDeptGroup9119 h2{margin:0 0 8px;color:#9ec5ff}.rfAllGrid9119{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
.rfAllCard9119{background:#12151c;border:1px solid #303641;border-radius:14px;padding:12px}.rfAllHead9119{display:flex;justify-content:space-between;gap:8px}.rfAllHead9119 b{font-size:19px}.rfAllRows9119{display:grid;gap:6px;margin-top:8px}
.rfAllRow9119{display:grid;grid-template-columns:48px 78px minmax(90px,1fr) auto;gap:7px;align-items:center;padding:10px;border-radius:9px;font-weight:900;cursor:pointer}.rfAllRow9119.assign{background:#0f3556;border:1px solid #2877b4}.rfAllRow9119.submit{background:#4d3708;border:1px solid #7c5a17}.rfAllAge9119{font-size:11px;color:#ffd782}.rfAllRow9119.submit .rfAllAge9119{color:#8ce9b7}.rfAllEmpty9119{padding:16px;border:1px dashed #3c4655;border-radius:10px;color:#98a2b3}
@media(max-width:700px){.rfAllGrid9119{grid-template-columns:1fr}.rfAllRow9119{grid-template-columns:42px 70px 1fr}.rfAllAge9119{grid-column:1/-1}}
`;
document.head.appendChild(style);

function titleFix(){
  const h1 = document.querySelector('.top h1');
  if (h1 && raw && h1.textContent !== label) h1.textContent = label;
  const select = document.getElementById('homeDept');
  if (!select) return;
  let badge = document.getElementById('rfTerritoryBadge9119');
  if (!badge) { badge=document.createElement('div'); badge.id='rfTerritoryBadge9119'; select.after(badge); }
  const txt = raw ? `${label} ONLY` : 'ALL DEPARTMENTS';
  if (badge.textContent !== txt) badge.textContent = txt;
  if (raw) document.documentElement.classList.add('rf-territory');
}

function enforceTerritory(){
  titleFix();
  if (!raw) return;
  const select=document.getElementById('homeDept');
  if (select) {
    if (select.value !== dept) select.value=dept;
    if (!select.disabled) select.disabled=true;
    if (select.getAttribute('aria-hidden')!=='true') select.setAttribute('aria-hidden','true');
  }
  const inner=document.getElementById('dept');
  if (inner && [...inner.options].some(o=>up(o.value)===dept)) {
    if (inner.value !== dept) inner.value=dept;
    if (!inner.disabled) inner.disabled=true;
  }
}

async function rpc(name,args={}){ const c=sb(); if(!c) throw new Error('Supabase client not ready.'); const {data,error}=await c.rpc(name,args); if(error) throw error; return data; }

const ALL_DEPTS=['PRINTING','STICKER','METAL_ID','STITCHING','OVERLOCK','FOLDING','KAAJ_BUTTON','TEAK_TANKI','THREAD_CUT','QC','PRESS','PACKING','DESPATCH'];
let allPayload=[], allMode='ASSIGN', allBusy=false;
async function loadAll(){
  if (raw || allBusy) return;
  allBusy=true;
  try{
    await window.RRRefreshSupabaseSession?.(false);
    const settled=await Promise.all(ALL_DEPTS.map(async d=>{try{return {dept:d,data:await rpc('rr_upm_department_colour_due_card_v9109',{p_department_code:d})}}catch(error){console.warn('ALL DEPARTMENTS due skipped',d,error);return {dept:d,data:null,error}}}));
    allPayload=settled.filter(x=>x.data);
    renderAll();
  } finally { allBusy=false; }
}
function totals(kind){
  const lots=new Set(), cols=[];
  allPayload.forEach(x=>(x.data?.lots||[]).forEach(l=>{const rows=kind==='ASSIGN'?(l.assign_rows||[]):(l.submit_rows||[]); if(rows.length){lots.add(`${x.dept}|${l.lot_no}`); cols.push(...rows)}}));
  return {lots:lots.size,cols:cols.length};
}
function rowHtml(r,kind,d,l){
  const worker=kind==='SUBMIT'?(r.worker_first_name||r.worker_name||'RUNNING'):'OPEN';
  return `<div class="rfAllRow9119 ${kind==='ASSIGN'?'assign':'submit'}" data-go-dept="${esc(d)}" data-go-mode="${esc(kind)}" data-go-lot="${esc(l.lot_no)}"><span>${esc(r.colour_code)}</span><span>${esc(fmt(r.qty))} PCS</span><span>${esc(worker)}</span><span class="rfAllAge9119">${kind==='ASSIGN'?'QUEUE':'ACTIVE'} ${esc(age(r.working_seconds??r.age_seconds))}</span></div>`;
}
function renderAll(){
  if(raw)return;
  const board=document.getElementById('board'); if(!board)return;
  board.style.display='none';
  let root=document.getElementById('rfAllDept9119'); if(!root){root=document.createElement('section');root.id='rfAllDept9119';board.before(root)}
  const a=totals('ASSIGN'),s=totals('SUBMIT');
  const groups=allPayload.map(x=>{
    const cards=(x.data?.lots||[]).map(l=>{const rows=allMode==='ASSIGN'?(l.assign_rows||[]):(l.submit_rows||[]);if(!rows.length)return '';return `<article class="rfAllCard9119"><div class="rfAllHead9119"><div><b>${esc(l.lot_no)}</b><div style="color:#9ec5ff;font-weight:850">${esc(LABEL[x.dept]||x.dept)}</div></div><small>${rows.length} COLOUR</small></div><div class="rfAllRows9119">${rows.map(r=>rowHtml(r,allMode,x.dept,l)).join('')}</div></article>`}).join('');
    return cards?`<section class="rfDeptGroup9119"><h2>${esc(LABEL[x.dept]||x.dept)}</h2><div class="rfAllGrid9119">${cards}</div></section>`:'';
  }).join('');
  root.innerHTML=`<div class="rfAllBar9119"><button type="button" data-all-mode="SUBMIT" class="${allMode==='SUBMIT'?'active':''}">READY TO SUBMIT<div class="rfAllCount9119"><span class="rfAllLot9119">LOT ${s.lots}</span><span class="rfAllCol9119">COL ${s.cols}</span></div></button><button type="button" data-all-mode="ASSIGN" class="${allMode==='ASSIGN'?'active':''}">READY TO ASSIGN<div class="rfAllCount9119"><span class="rfAllLot9119">LOT ${a.lots}</span><span class="rfAllCol9119">COL ${a.cols}</span></div></button></div>${groups||'<div class="rfAllEmpty9119">No due work in any department.</div>'}`;
  root.querySelectorAll('[data-all-mode]').forEach(b=>b.onclick=()=>{allMode=b.dataset.allMode;renderAll()});
  root.querySelectorAll('[data-go-dept]').forEach(r=>r.onclick=()=>{const u=new URL(location.href);u.searchParams.set('dept',r.dataset.goDept);u.searchParams.set('label',LABEL[r.dataset.goDept]||r.dataset.goDept);u.searchParams.set('view',r.dataset.goMode);u.searchParams.set('focus_lot',r.dataset.goLot);u.searchParams.set('v','9119');location.href=u.toString()});
}

let scheduled=false;
const mo=new MutationObserver(()=>{
  if(scheduled)return;
  scheduled=true;
  requestAnimationFrame(()=>{scheduled=false;enforceTerritory()});
});
mo.observe(document.documentElement,{childList:true,subtree:true});
document.addEventListener('DOMContentLoaded',()=>{enforceTerritory(); if(!raw) setTimeout(loadAll,50)});
window.addEventListener('load',()=>{enforceTerritory(); if(!raw) loadAll()});

if(raw){
  const requested=up(qs.get('view'));
  const focusLot=qs.get('focus_lot');
  const focus=()=>{
    enforceTerritory();
    const bar=document.getElementById('rfbar');
    if(bar && requested){const b=bar.querySelector(`[data-mode="${requested}"]`); if(b && !b.classList.contains('active')) b.click();}
    if(focusLot){const rows=[...document.querySelectorAll('.rfcard')];const card=rows.find(x=>up(x.dataset.lot)===up(focusLot));card?.scrollIntoView({block:'center'});}
  };
  setTimeout(focus,250);setTimeout(focus,900);
}
})();
