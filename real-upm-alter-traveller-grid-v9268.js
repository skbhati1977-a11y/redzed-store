(()=>{
'use strict';
if(window.__RR_ALTER_TRAVELLER_GRID_9268__)return;
window.__RR_ALTER_TRAVELLER_GRID_9268__=true;
const getClient=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const up=v=>String(v||'').trim().toUpperCase();
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const num=v=>Number(v||0);
const q=new URLSearchParams(location.search);
const ALIAS={KR:'STITCHING',KARIGAR:'STITCHING',STITCH:'STITCHING',STITCHING:'STITCHING',OV:'OVERLOCK',OVERLOCK:'OVERLOCK',FLD:'FOLDING',FLATLOCK:'FOLDING',FOLDING:'FOLDING',KAAJ:'KAAJ',KAJ:'KAAJ',BUTTON:'BUTTON',BTN:'BUTTON',KAAJ_BUTTON:'KAAJ_BUTTON',TEAK:'TEAK_TANKI',TANKI:'TEAK_TANKI',TEAK_TANKI:'TEAK_TANKI',THREAD_CUT:'THREAD_CUT',THREAD_CUTTING:'THREAD_CUT',TH_CUT:'THREAD_CUT',QC:'QC',CHECKING:'QC',PRESS:'PRESS',FINISHING:'PRESS',PRINT:'PRINTING',PRINTING:'PRINTING',STICKER:'STICKER',ID:'METAL_ID',ID_WORK:'METAL_ID',METAL_ID:'METAL_ID',PACK:'PACKING',PACKING:'PACKING',DISPATCH:'DESPATCH',DESPATCH:'DESPATCH',CUT:'CUTTING',CUTTING:'CUTTING'};
const raw=up(q.get('dept')||document.body?.dataset?.department||window.frameElement?.dataset?.upmDept||'');
const dept=ALIAS[raw]||raw;
if(!dept)return;
let busy=false,timer=null;
function ageText(ts){const t=new Date(ts||0).getTime();if(!Number.isFinite(t)||!t)return '';let m=Math.max(0,Math.floor((Date.now()-t)/60000));const d=Math.floor(m/1440);m-=d*1440;const h=Math.floor(m/60);m%=60;return [d?`${d}d`:'',h?`${h}h`:'',`${m}m`].filter(Boolean).join(' ')}
function orderSize(s){const m={XS:1,S:2,M:3,L:4,XL:5,XXL:6,'2XL':6,'3XL':7,'4XL':8,'5XL':9};return m[up(s)]||99}
async function sizeUniverse(client,lot){
 for(const args of [{p_lot_no:lot},{lot_no:lot}]){
  try{const r=await client.rpc('rr_upm_cut_size_rows_v726',args);if(!r.error&&Array.isArray(r.data))return r.data}catch(_){ }
 }
 return [];
}
function groupRows(rows,universeRows){
 const universeByColour=new Map();
 for(const r of universeRows||[]){const c=up(r.colour_code),s=up(r.size_code);if(!c||!s)continue;if(!universeByColour.has(c))universeByColour.set(c,new Set());universeByColour.get(c).add(s)}
 const groups=new Map();
 for(const r of rows||[]){
  const from=String(r.created_by_name||r.enrolled_lm_name||'Unknown').trim();
  const owner=String(r.responsible_name||r.karigar_name||r.cutting_master_name||r.enrolled_lm_name||'Owner pending').trim();
  const bucket=String(r.created_at||'').slice(0,16);
  const key=[r.lot_no,r.colour_code,from,owner,r.stage,bucket].join('|');
  if(!groups.has(key))groups.set(key,{lot:r.lot_no,colour:r.colour_code,from,owner,stage:r.stage,created_at:r.created_at,sizes:new Map()});
  const g=groups.get(key),s=up(r.size_code);if(s)g.sizes.set(s,(g.sizes.get(s)||0)+num(r.open_qty));
 }
 for(const g of groups.values()){
  const uni=universeByColour.get(up(g.colour));if(uni)for(const s of uni)if(!g.sizes.has(s))g.sizes.set(s,0);
 }
 return [...groups.values()];
}
function ensureStyle(){if(document.getElementById('rrAlterTraveller9268Style'))return;const s=document.createElement('style');s.id='rrAlterTraveller9268Style';s.textContent=`
#rrAlterTraveller9268{margin:12px 0;border:1px solid #5d4a18;border-radius:14px;background:#11151c;overflow:hidden}.rrat-head{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:11px 12px;background:#2b220c;border-bottom:1px solid #5d4a18}.rrat-head b{color:#ffd66f;font-size:14px}.rrat-count{color:#9ec5ff;font-size:11px;font-weight:900}.rrat-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;padding:9px}.rrat-card{border:1px solid #46505f;border-radius:11px;background:#0d1219;padding:9px;min-width:0}.rrat-top{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.rrat-lot{font-size:15px;font-weight:950;color:#fff}.rrat-colour{padding:3px 7px;border-radius:999px;border:1px solid #7b6320;color:#ffe08a;font-size:10px;font-weight:950}.rrat-stage{margin-left:auto;color:#9ec5ff;font-size:10px;font-weight:850}.rrat-line{margin-top:7px;font-size:12px;line-height:1.45;font-weight:850;color:#e5e9ef;overflow-wrap:anywhere}.rrat-zero{color:#7f8998}.rrat-from{color:#cbd5e1}.rrat-owner{color:#7ee7b8}.rrat-age{color:#ffc857}.rrat-empty{padding:12px;color:#98a2b3;font-size:12px}@media(max-width:700px){.rrat-grid{grid-template-columns:1fr}.rrat-card{padding:10px}}
`;document.head.appendChild(s)}
function host(){let h=document.getElementById('rrAlterTraveller9268');if(h)return h;h=document.createElement('section');h.id='rrAlterTraveller9268';const anchor=document.getElementById('rfbar')||document.querySelector('.rfbar')||document.getElementById('board');if(anchor?.parentNode)anchor.parentNode.insertBefore(h,anchor);else document.querySelector('.page')?.appendChild(h);return h}
function render(groups){ensureStyle();const h=host();if(!h)return;const total=groups.reduce((s,g)=>s+[...g.sizes.values()].reduce((a,b)=>a+num(b),0),0);h.innerHTML=`<div class="rrat-head"><b>ALTER TRAVELLER</b><span class="rrat-count">${groups.length} JOURNEY · ${total} PCS OPEN</span></div>`+(groups.length?`<div class="rrat-grid">${groups.map(g=>{const sizes=[...g.sizes.entries()].sort((a,b)=>orderSize(a[0])-orderSize(b[0])||a[0].localeCompare(b[0]));const line=sizes.map(([s,n])=>`<span class="${num(n)===0?'rrat-zero':''}">${esc(s)} ${num(n)}</span>`).join(' · ');return `<article class="rrat-card"><div class="rrat-top"><span class="rrat-lot">${esc(g.lot)}</span><span class="rrat-colour">${esc(g.colour)}</span><span class="rrat-stage">${esc(String(g.stage||'').replaceAll('_',' '))}</span></div><div class="rrat-line"><b>${line||'SIZE PENDING'}</b> · <span class="rrat-from">From ${esc(g.from)}</span> · <span class="rrat-owner">Owner ${esc(g.owner)}</span> · <span class="rrat-age">Age ${esc(ageText(g.created_at))}</span></div></article>`}).join('')}</div>`:'<div class="rrat-empty">No active ALTER traveller in this department.</div>')}
async function load(){const c=getClient();if(!c||busy)return;busy=true;try{const r=await c.from('rr_upm_alter_journey_v740').select('lot_no,origin_department_code,colour_code,size_code,open_qty,stage,enrolled_lm_name,cutting_master_name,karigar_name,responsible_name,created_by_name,created_at,updated_at').eq('origin_department_code',dept).gt('open_qty',0).not('stage','like','CLOSED%').order('created_at',{ascending:false});if(r.error)throw r.error;const rows=r.data||[];const byLot=new Map();for(const x of rows){const l=String(x.lot_no||'').trim();if(!byLot.has(l))byLot.set(l,[]);byLot.get(l).push(x)}const groups=[];for(const [lot,lotRows] of byLot){const uni=await sizeUniverse(c,lot);groups.push(...groupRows(lotRows,uni))}render(groups)}catch(e){console.warn('[ALTER TRAVELLER GRID 9268]',e?.message||e)}finally{busy=false}}
function start(){load();clearInterval(timer);timer=setInterval(load,15000);const mo=new MutationObserver(()=>{if(!document.getElementById('rrAlterTraveller9268'))setTimeout(()=>render([]),80)});mo.observe(document.body,{childList:true,subtree:true});document.addEventListener('click',e=>{if(e.target.closest?.('#refresh,[id*="refresh" i]'))setTimeout(load,350)},true)}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();