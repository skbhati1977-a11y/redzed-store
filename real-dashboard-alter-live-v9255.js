(()=>{
'use strict';
if(window.__RR_DASH_ALTER_LIVE_9255__)return;
window.__RR_DASH_ALTER_LIVE_9255__=true;

const sb=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb||null;
const num=v=>Number(v||0);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let timer=null;

function ensureUI(){
 if(document.getElementById('rrDashAlterLive9255'))return document.getElementById('rrDashAlterLive9255');
 const style=document.createElement('style');
 style.id='rrDashAlterLive9255Style';
 style.textContent=`
 #rrDashAlterLive9255{margin-top:12px;padding:12px 14px;border:1px solid #6d5620;border-radius:14px;background:#19150d;display:flex;align-items:center;gap:10px;flex-wrap:wrap}
 #rrDashAlterLive9255 .rrdal-title{font-weight:950;color:#ffd56f}.rrdal-stat{display:inline-flex;gap:5px;align-items:center;padding:6px 8px;border:1px solid #4b4130;border-radius:999px;background:#11151c;font-size:11px;font-weight:850;color:#d9dee7}
 #rrDashAlterLive9255 .rrdal-stat b{color:#fff}.rrdal-time{margin-left:auto;color:#98a2b3;font-size:10px;font-weight:800}.rrdal-open{color:#9ec5ff;text-decoration:none;font-size:11px;font-weight:900}
 @media(max-width:520px){#rrDashAlterLive9255{align-items:flex-start}.rrdal-time{margin-left:0;width:100%}}
 `;
 document.head.appendChild(style);
 const box=document.createElement('section');
 box.id='rrDashAlterLive9255';
 box.innerHTML='<span class="rrdal-title">ALTER LIVE</span><span class="rrdal-stat">Loading…</span><a class="rrdal-open" href="real-universal-production-v770-v9059.html?mode=TEST&v=9255">Open UPM ›</a>';
 const hero=document.querySelector('.hero');
 if(hero?.parentNode)hero.insertAdjacentElement('afterend',box);
 else document.querySelector('.main')?.prepend(box);
 return box;
}

function goodIncluded(j){
 const flags=['good_included','is_good_included','good_qty_included','merged_to_good','reconciled_to_good','good_qty_posted','reentered_good','returned_to_good'];
 return flags.some(k=>j?.[k]===true||String(j?.[k]||'').toUpperCase()==='TRUE'||num(j?.[k])===1);
}

async function refresh(){
 const box=ensureUI(),client=sb();
 if(!box||!client)return;
 try{
  const {data,error}=await client.rpc('rr_upm_lot_card_due_alter_header_v9092',{p_department_code:null});
  if(error)throw error;
  const lots=(data?.lots||[]).filter(x=>num(x?.active_alter_qty)>0);
  let qty=0,journeys=0;
  for(const lot of lots){
   qty+=num(lot.active_alter_qty);
   journeys+=(lot.alter_journeys||[]).filter(j=>!goodIncluded(j)).length;
  }
  const stamp=new Date().toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'});
  box.innerHTML=`<span class="rrdal-title">ALTER LIVE</span><span class="rrdal-stat">Lots <b>${lots.length}</b></span><span class="rrdal-stat">Journeys <b>${journeys}</b></span><span class="rrdal-stat">Pending Good Qty <b>${qty}</b> PCS</span><a class="rrdal-open" href="real-universal-production-v770-v9059.html?mode=TEST&v=9255">Open UPM ›</a><span class="rrdal-time">Updated ${esc(stamp)}</span>`;
 }catch(e){
  box.innerHTML='<span class="rrdal-title">ALTER LIVE</span><span class="rrdal-stat">Live status unavailable</span><a class="rrdal-open" href="real-universal-production-v770-v9059.html?mode=TEST&v=9255">Open UPM ›</a>';
  console.warn('Dashboard ALTER live V9255:',e?.message||e);
 }
}

function start(){
 ensureUI();
 setTimeout(refresh,250);
 setTimeout(refresh,1200);
 clearInterval(timer);
 timer=setInterval(refresh,15000);
 document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh()});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();