(()=>{
'use strict';
if(window.__RR_ALTER_QUEUE_COMPACT_9264__)return;
window.__RR_ALTER_QUEUE_COMPACT_9264__=true;
const getClient=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const up=v=>String(v||'').trim().toUpperCase();
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let cache=[],busy=false;
async function load(){
 const c=getClient();if(!c||busy)return;busy=true;
 try{
  const {data,error}=await c.from('rr_upm_alter_journey_v740').select('lot_no').not('stage','like','CLOSED%').gt('open_qty',0);if(error)throw error;
  const lots=[...new Set((data||[]).map(x=>String(x.lot_no||'').trim()).filter(Boolean))];const out=[];
  for(const lot of lots){try{const r=await c.rpc('rr_upm_lot_colour_matrix_v755',{p_canonical_lot_id:null,p_lot_no:lot});if(!r.error)for(const x of r.data?.colours||[]){const a=x.alter_journey;if(a?.qty>0)out.push({lot,colour:x.colour_code,sizes:a.compact_line||a.size_details||'',ownerLine:a.compact_owner_line||''});}}catch(_){}}
  cache=out;render();
 }catch(e){console.warn('[ALTER QUEUE COMPACT]',e?.message||e);}finally{busy=false;}
}
function exact(root,text){return [...root.querySelectorAll('b,strong,h1,h2,h3,h4,span,div')].find(e=>e.children.length===0&&up(e.textContent)===up(text));}
function findLotCard(lot){const n=exact(document,lot);if(!n)return null;let e=n;for(let i=0;i<7&&e;i++,e=e.parentElement){const t=up(e.textContent);if(t.includes(up(lot))&&t.includes('PCS')&&(t.includes('OPEN')||t.includes('ACTIVE')))return e;}return n.parentElement;}
function findColourRow(card,colour){if(!card)return null;const n=exact(card,colour);if(!n)return null;let e=n;for(let i=0;i<5&&e&&e!==card;i++,e=e.parentElement){const t=up(e.textContent);if(t.includes('PCS')&&(t.includes('OPEN')||t.includes('ACTIVE')))return e;}return n.parentElement;}
function render(){document.querySelectorAll('.rr-alter-queue-compact').forEach(e=>e.remove());for(const g of cache){const row=findColourRow(findLotCard(g.lot),g.colour);if(!row)continue;const box=document.createElement('div');box.className='rr-alter-queue-compact';box.innerHTML=`<div>${esc(g.sizes)}</div><small>${esc(g.ownerLine)}</small>`;row.appendChild(box);}}
const style=document.createElement('style');style.textContent='.rr-alter-queue-compact{width:100%;margin-top:7px;padding-top:6px;border-top:1px solid #ffffff24;font-size:12px;line-height:1.25;font-weight:850;color:#f3f5f8}.rr-alter-queue-compact small{display:block;margin-top:3px;font-size:11px;font-weight:750;color:#cbd3df}.rr-alter-queue-compact div{white-space:normal}';document.head.appendChild(style);
const mo=new MutationObserver(()=>{clearTimeout(window.__rrAlterQueueRenderT);window.__rrAlterQueueRenderT=setTimeout(render,120)});mo.observe(document.body,{childList:true,subtree:true});
load();setInterval(()=>{render();load();},60000);
})();