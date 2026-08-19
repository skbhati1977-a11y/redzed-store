(()=>{
'use strict';
if(window.__RR_ALTER_QUEUE_COMPACT_9264__)return;
window.__RR_ALTER_QUEUE_COMPACT_9264__=true;
const getClient=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const up=v=>String(v||'').trim().toUpperCase();
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const owner=j=>{
 const s=up(j.stage);
 if(['ALTER_LM_ACCEPT_PENDING','LM_ALTER_PENDING','LM_DELIVERY_PENDING'].includes(s))return j.enrolled_lm_name||j.responsible_name||'-';
 if(s==='CM_REMAKE_READY')return j.cutting_master_name||j.responsible_name||'-';
 if(s==='KARIGAR_REMAKE_PENDING')return j.karigar_name||j.responsible_name||'-';
 return j.responsible_name||'-';
};
const from=j=>{
 const s=up(j.stage);
 if(s==='ALTER_LM_ACCEPT_PENDING')return j.karigar_name||'-';
 if(s==='KARIGAR_REMAKE_PENDING')return j.enrolled_lm_name||'-';
 if(s==='LM_DELIVERY_PENDING')return j.karigar_name||'-';
 return j.karigar_name||j.responsible_name||'-';
};
const age=t=>{const sec=Math.max(0,Math.floor((Date.now()-new Date(t).getTime())/1000));if(sec<3600)return Math.floor(sec/60)+'m';if(sec<86400)return Math.floor(sec/3600)+'h '+Math.floor((sec%3600)/60)+'m';return Math.floor(sec/86400)+'d '+Math.floor((sec%86400)/3600)+'h';};
const sizeOrder=s=>({S:1,M:2,L:3,XL:4,XXL:5,'2XL':5,'3XL':6,'4XL':7,'5XL':8}[up(s)]||99);
let cache=[],busy=false;
async function load(){
 const c=getClient(); if(!c||busy)return; busy=true;
 try{
  const {data,error}=await c.from('rr_upm_alter_journey_v740').select('lot_no,colour_code,size_code,open_qty,stage,enrolled_lm_name,cutting_master_name,karigar_name,responsible_name,holder_since,updated_at,created_at').not('stage','like','CLOSED%').gt('open_qty',0);
  if(error)throw error; cache=data||[]; render();
 }catch(e){console.warn('[ALTER QUEUE COMPACT]',e?.message||e);}finally{busy=false;}
}
function exact(root,text){return [...root.querySelectorAll('b,strong,h1,h2,h3,h4,span,div')].find(e=>e.children.length===0&&up(e.textContent)===up(text));}
function findLotCard(lot){const n=exact(document,lot);if(!n)return null;let e=n;for(let i=0;i<7&&e;i++,e=e.parentElement){const t=up(e.textContent);if(t.includes(up(lot))&&t.includes('PCS')&&(t.includes('OPEN')||t.includes('ACTIVE')))return e;}return n.parentElement;}
function findColourRow(card,colour){if(!card)return null;const n=exact(card,colour);if(!n)return null;let e=n;for(let i=0;i<5&&e&&e!==card;i++,e=e.parentElement){const t=up(e.textContent);if(t.includes('PCS')&&(t.includes('OPEN')||t.includes('ACTIVE')))return e;}return n.parentElement;}
function groups(){const m=new Map();for(const j of cache){const k=[up(j.lot_no),up(j.colour_code),owner(j),from(j),j.holder_since||j.updated_at||j.created_at].join('|');if(!m.has(k))m.set(k,{lot:j.lot_no,colour:j.colour_code,owner:owner(j),from:from(j),since:j.holder_since||j.updated_at||j.created_at,sizes:new Map()});const g=m.get(k),s=up(j.size_code);g.sizes.set(s,(g.sizes.get(s)||0)+Number(j.open_qty||0));}return [...m.values()];}
function render(){document.querySelectorAll('.rr-alter-queue-compact').forEach(e=>e.remove());for(const g of groups()){const card=findLotCard(g.lot),row=findColourRow(card,g.colour);if(!row)continue;const all=[...g.sizes.keys()].sort((a,b)=>sizeOrder(a)-sizeOrder(b)||a.localeCompare(b));const sizes=all.map(s=>`${s} ${g.sizes.get(s)}`).join(' · ');const box=document.createElement('div');box.className='rr-alter-queue-compact';box.dataset.key=up(g.lot)+'|'+up(g.colour);box.innerHTML=`<div>${esc(sizes)}</div><small>From ${esc(g.from)} · Owner ${esc(g.owner)} · Age ${esc(age(g.since))}</small>`;row.appendChild(box);}}
const style=document.createElement('style');style.textContent='.rr-alter-queue-compact{width:100%;margin-top:7px;padding-top:6px;border-top:1px solid #ffffff24;font-size:12px;line-height:1.25;font-weight:850;color:#f3f5f8}.rr-alter-queue-compact small{display:block;margin-top:3px;font-size:11px;font-weight:750;color:#cbd3df}.rr-alter-queue-compact div{white-space:normal}';document.head.appendChild(style);
const mo=new MutationObserver(()=>{clearTimeout(window.__rrAlterQueueRenderT);window.__rrAlterQueueRenderT=setTimeout(render,120)});mo.observe(document.body,{childList:true,subtree:true});
load();setInterval(()=>{render();load();},60000);
})();