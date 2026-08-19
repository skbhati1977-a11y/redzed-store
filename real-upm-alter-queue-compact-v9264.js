(()=>{
'use strict';
if(window.__RR_ALTER_QUEUE_COMPACT_9267__)return;
window.__RR_ALTER_QUEUE_COMPACT_9267__=true;
const getClient=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const up=v=>String(v||'').trim().toUpperCase();
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const n=v=>Number(v||0);
const sizeRank=s=>({XS:1,S:2,M:3,L:4,XL:5,XXL:6,'2XL':6,'3XL':7,'4XL':8,'5XL':9}[up(s)]||99);
let cache=[],busy=false;

function ageText(raw){
 const t=new Date(raw||0).getTime();if(!Number.isFinite(t)||t<=0)return '';
 let m=Math.max(0,Math.floor((Date.now()-t)/60000));const d=Math.floor(m/1440);m-=d*1440;const h=Math.floor(m/60);m%=60;
 return [d?`${d}d`:'',h?`${h}h`:'',`${m}m`].filter(Boolean).join(' ');
}
function exact(root,text){return [...root.querySelectorAll('b,strong,h1,h2,h3,h4,span,div')].find(e=>e.children.length===0&&up(e.textContent)===up(text));}
function findLotCard(lot){const x=exact(document,lot);if(!x)return null;let e=x;for(let i=0;i<8&&e;i++,e=e.parentElement){const t=up(e.textContent);if(t.includes(up(lot))&&t.includes('PCS')&&(t.includes('OPEN')||t.includes('ACTIVE')))return e;}return x.parentElement;}
function findColourRow(card,colour){if(!card)return null;const x=exact(card,colour);if(!x)return null;let e=x;for(let i=0;i<6&&e&&e!==card;i++,e=e.parentElement){const t=up(e.textContent);if(t.includes('PCS')&&(t.includes('OPEN')||t.includes('ACTIVE')))return e;}return x.parentElement;}

async function sizeUniverse(c,lot){
 const out=new Map();
 try{
  let r=await c.rpc('rr_upm_cut_size_rows_v726',{p_lot_no:lot});
  if(r.error)r=await c.rpc('rr_upm_cut_size_rows_v726',{lot_no:lot});
  for(const x of Array.isArray(r.data)?r.data:[]){const col=up(x.colour_code),sz=up(x.size_code);if(!col||!sz)continue;if(!out.has(col))out.set(col,new Set());out.get(col).add(sz);}
 }catch(_){ }
 return out;
}
function groupRows(rows,universes){
 const groups=new Map();
 for(const j of rows){
  const created=String(j.created_at||'');
  const key=[up(j.lot_no),up(j.colour_code),String(j.created_by_name||'Unknown'),String(j.responsible_name||'Owner pending'),up(j.stage),created].join('|');
  if(!groups.has(key))groups.set(key,{lot:String(j.lot_no||''),colour:up(j.colour_code),from:String(j.created_by_name||'Unknown'),owner:String(j.responsible_name||'Owner pending'),stage:String(j.stage||''),createdAt:j.created_at,sizes:new Map()});
  const g=groups.get(key);g.sizes.set(up(j.size_code),(g.sizes.get(up(j.size_code))||0)+n(j.open_qty));
 }
 for(const g of groups.values()){
  const u=universes.get(up(g.lot))?.get(up(g.colour));
  if(u)for(const s of u)if(!g.sizes.has(s))g.sizes.set(s,0);
 }
 return [...groups.values()];
}
async function load(){
 const c=getClient();if(!c||busy)return;busy=true;
 try{
  const {data,error}=await c.from('rr_upm_alter_journey_v740')
   .select('id,canonical_lot_id,lot_no,colour_code,size_code,open_qty,stage,created_by_name,responsible_name,responsible_role_code,responsible_department_code,created_at,updated_at')
   .not('stage','like','CLOSED%').gt('open_qty',0);
  if(error)throw error;
  const rows=(data||[]).filter(x=>n(x.open_qty)>0);
  const lots=[...new Set(rows.map(x=>String(x.lot_no||'').trim()).filter(Boolean))];
  const universes=new Map();
  await Promise.all(lots.map(async lot=>universes.set(up(lot),await sizeUniverse(c,lot))));
  cache=groupRows(rows,universes);render();
 }catch(e){console.warn('[ALTER QUEUE COMPACT V9267]',e?.message||e);}finally{busy=false;}
}
function render(){
 document.querySelectorAll('.rr-alter-queue-compact').forEach(e=>e.remove());
 for(const g of cache){
  const row=findColourRow(findLotCard(g.lot),g.colour);if(!row)continue;
  const sizes=[...g.sizes.entries()].sort((a,b)=>sizeRank(a[0])-sizeRank(b[0])||a[0].localeCompare(b[0]));
  const sizeLine=sizes.map(([s,q])=>`${s} ${n(q)}`).join(' · ');
  const age=ageText(g.createdAt);
  const box=document.createElement('div');box.className='rr-alter-queue-compact';
  box.innerHTML=`<span class="rr-aq-size">${esc(sizeLine)}</span> · <span class="rr-aq-from">From ${esc(g.from)}</span> · <span class="rr-aq-owner">Owner ${esc(g.owner)}</span>${age?` · <span class="rr-aq-age">Age ${esc(age)}</span>`:''}`;
  row.appendChild(box);
 }
}
const style=document.createElement('style');style.textContent=`
.rr-alter-queue-compact{width:100%;margin-top:7px;padding-top:7px;border-top:1px solid #ffffff24;font-size:12px;line-height:1.45;font-weight:850;color:#f3f5f8;display:block;white-space:normal;overflow:visible;overflow-wrap:anywhere}
.rr-aq-size{color:#fff}.rr-aq-from{color:#cbd5e1}.rr-aq-owner{color:#7ee7b8}.rr-aq-age{color:#ffc857}
`;
document.head.appendChild(style);
const mo=new MutationObserver(()=>{clearTimeout(window.__rrAlterQueueRenderT);window.__rrAlterQueueRenderT=setTimeout(render,120)});mo.observe(document.body,{childList:true,subtree:true});
load();setInterval(()=>{render();load();},15000);
})();