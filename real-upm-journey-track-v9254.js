(()=>{
'use strict';
if(window.__RR_UPM_JOURNEY_9255__)return;
window.__RR_UPM_JOURNEY_9255__=true;

const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const up=v=>String(v||'').trim().toUpperCase();
const num=v=>Number(v||0);
const frameEl=()=>{try{return window.frameElement}catch(_){return null}};
const sb=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb||null;
const retainedByLot=new Map();

const canonicalDept=v=>{
 const x=up(v).replace(/[^A-Z0-9]+/g,'');
 const m={KR:'STITCHING',KARIGAR:'STITCHING',STITCH:'STITCHING',STITCHING:'STITCHING',OV:'OVERLOCK',OVERLOCKING:'OVERLOCK',OVERLOCK:'OVERLOCK',FLD:'FOLDING',FOLD:'FOLDING',FLATLOCK:'FOLDING',FOLDING:'FOLDING',KAJ:'KAAJ',KAAJ:'KAAJ',BTN:'BUTTON',BUTTON:'BUTTON',KAAJBUTTON:'KAAJ_BUTTON',TEAK:'TEAK_TANKI',TANKI:'TEAK_TANKI',TEAKTANKI:'TEAK_TANKI',THCUT:'THREAD_CUT',THREADCUT:'THREAD_CUT',THREADCUTTING:'THREAD_CUT',CHECK:'QC',CHECKING:'QC',QUALITYCHECK:'QC',QC:'QC',PRESSFINISHING:'PRESS',FINISHING:'PRESS',PRESS:'PRESS',PACK:'PACKING',PACKING:'PACKING',DISPATCH:'DESPATCH',DESPATCH:'DESPATCH',PRINT:'PRINTING',PRINTER:'PRINTING',PRINTING:'PRINTING',ID:'METAL_ID',METAL:'METAL_ID',METALID:'METAL_ID',STICKER:'STICKER',CUT:'CUTTING',CUTTING:'CUTTING'};
 return m[x]||up(v)||null;
};
function dept(){
 const q=new URLSearchParams(location.search);
 return canonicalDept(q.get('dept')||frameEl()?.dataset?.upmDept||document.body?.dataset?.department||'');
}
function injectStyle(){
 if(document.getElementById('rrJourney9255Style'))return;
 const s=document.createElement('style');s.id='rrJourney9255Style';s.textContent=`
 .rr-j9255{margin:7px 0 2px;padding:8px 9px;border:1px solid #3b4655;border-radius:11px;background:#0d1219;display:grid;gap:5px}
 .rr-j9255-top{display:flex;gap:6px;align-items:center;flex-wrap:wrap}.rr-j9255-badge{display:inline-flex;align-items:center;border:1px solid #9b7a16;border-radius:999px;padding:4px 7px;color:#ffe067;font-size:10px;font-weight:950}
 .rr-j9255-stage{color:#9ec5ff;font-size:10px;font-weight:900}.rr-j9255-line{font-size:11px;line-height:1.5;font-weight:850;color:#d8dee8;overflow-wrap:anywhere}.rr-j9255-line b{color:#fff}.rr-j9255-age{color:#ffc857}.rr-j9255-from{color:#cbd5e1}.rr-j9255-owner{color:#7ee7b8}
 .rr-j9255-host{margin-top:6px}.rr-j9255-zero{color:#7f8998}
 @media(max-width:560px){.rr-j9255{padding:7px}.rr-j9255-line{font-size:10.5px}}
 `;document.head.appendChild(s);
}
function ageText(j){
 const direct=j.age_label||j.age_text||j.elapsed_label||j.elapsed_text;
 if(direct)return String(direct);
 const raw=j.started_at||j.journey_started_at||j.alter_created_at||j.created_at||j.opened_at||j.received_at;
 if(!raw)return '';
 const t=new Date(raw).getTime();if(!Number.isFinite(t))return '';
 let mins=Math.max(0,Math.floor((Date.now()-t)/60000));
 const d=Math.floor(mins/1440);mins-=d*1440;const h=Math.floor(mins/60);const m=mins%60;
 return [d?`${d}d`:'',h?`${h}h`:'',`${m}m`].filter(Boolean).join(' ');
}
function person(j,kind){
 const keys=kind==='from'
  ?['from_name','source_name','sender_name','from_worker_name','created_by_name','worker_name','origin_name']
  :['owner_name','responsible_name','receiver_name','current_owner_name','line_man_name','assigned_to_name'];
 for(const k of keys)if(String(j?.[k]||'').trim())return String(j[k]).trim();
 return kind==='owner'?'Owner pending':'Unknown';
}
function parseSizes(j){
 const out=[];
 const push=(s,q)=>{s=up(s);if(!s)return;out.push({size:s,qty:num(q)})};
 const raw=j?.size_breakup??j?.sizes??j?.qty_by_size??j?.size_qty??j?.size_breakdown;
 let x=raw;if(typeof x==='string'){try{x=JSON.parse(x)}catch(_){x=null}}
 if(Array.isArray(x))x.forEach(r=>push(r?.size_code??r?.size??r?.code,r?.qty??r?.quantity??r?.alter_qty));
 else if(x&&typeof x==='object')Object.entries(x).forEach(([s,q])=>push(s,q));
 if(!out.length&&j?.size_code)push(j.size_code,j.qty);
 return out;
}
function goodIncluded(j){
 const flags=['good_included','is_good_included','good_qty_included','merged_to_good','reconciled_to_good','good_qty_posted','reentered_good','returned_to_good'];
 return flags.some(k=>j?.[k]===true||up(j?.[k])==='TRUE'||num(j?.[k])===1);
}
function journeyKey(j){
 return String(j?.journey_id||j?.alter_journey_id||[
  j?.journey_code||'ALTER',j?.colour_code||'',person(j,'from'),person(j,'owner'),j?.started_at||j?.created_at||''
 ].join('|'));
}
function activeRowsForLot(row){
 const lot=up(row?.lot_no);const incoming=(row?.alter_journeys||[]).filter(j=>!goodIncluded(j));
 const activeQty=num(row?.active_alter_qty);
 if(activeQty<=0){retainedByLot.delete(lot);return []}
 const map=new Map((retainedByLot.get(lot)||[]).map(j=>[journeyKey(j),j]));
 for(const j of incoming)map.set(journeyKey(j),j);
 const rows=[...map.values()].filter(j=>!goodIncluded(j));
 retainedByLot.set(lot,rows);
 return rows;
}
function sizeOrder(a){const m={XS:1,S:2,M:3,L:4,XL:5,XXL:6,'2XL':6,'3XL':7,'4XL':8,'5XL':9};return m[a]||99}
function lotSizeUniverse(row,rows){
 const set=new Set();
 const harvest=x=>parseSizes(x).forEach(s=>set.add(s.size));
 (rows||[]).forEach(harvest);
 harvest({size_breakup:row?.size_breakup??row?.sizes??row?.qty_by_size??row?.size_qty??row?.size_breakdown});
 return [...set].sort((a,b)=>sizeOrder(a)-sizeOrder(b)||a.localeCompare(b));
}
function groupJourneys(rows,sizeUniverse){
 const map=new Map();
 for(const j of rows||[]){
  const key=[journeyKey(j),person(j,'from'),person(j,'owner'),j.stage||j.stage_label||'',j.colour_code||''].join('|');
  if(!map.has(key))map.set(key,{base:j,sizes:new Map(sizeUniverse.map(s=>[s,0]))});
  const g=map.get(key);
  for(const s of parseSizes(j))g.sizes.set(s.size,(g.sizes.get(s.size)||0)+num(s.qty));
 }
 return [...map.values()].map(g=>({j:g.base,sizes:[...g.sizes.entries()].map(([size,qty])=>({size,qty}))}));
}
function renderJourney(g){
 const j=g.j;const sizes=[...g.sizes].sort((a,b)=>sizeOrder(a.size)-sizeOrder(b.size)||a.size.localeCompare(b.size));
 const sizeText=sizes.length?sizes.map(x=>`<span class="${num(x.qty)===0?'rr-j9255-zero':''}">${esc(x.size)} ${num(x.qty)}</span>`).join(' · '):`${num(j.qty)} PCS`;
 const from=person(j,'from'),owner=person(j,'owner'),age=ageText(j),stage=j.stage_label||j.stage||'';
 return `<div class="rr-j9255"><div class="rr-j9255-top"><span class="rr-j9255-badge">${esc(j.journey_code||'ALTER')}</span>${stage?`<span class="rr-j9255-stage">${esc(stage)}</span>`:''}</div><div class="rr-j9255-line"><b>${sizeText}</b> · <span class="rr-j9255-from">From ${esc(from)}</span> · <span class="rr-j9255-owner">Owner ${esc(owner)}</span>${age?` · <span class="rr-j9255-age">Age ${esc(age)}</span>`:''}</div></div>`;
}
function lotNoFromCard(card){
 const el=card.querySelector?.('.lot-no,[data-lot-no],.cm-lot-number,.lot-number,[class*="lot-no"]');
 return up(el?.dataset?.lotNo||el?.textContent||card.dataset?.lotNo||card.dataset?.lot||'').replace(/^LOT\s*[:#-]?\s*/,'').trim();
}
function cardCandidates(){
 const selectors=['.lot-card','[data-lot-no]','.cm-card','.fg-card','.packing-card','.work-card'];
 const seen=new Set(),out=[];
 for(const sel of selectors)document.querySelectorAll(sel).forEach(x=>{if(!seen.has(x)){seen.add(x);out.push(x)}});
 return out;
}
function decorate(payload){
 const byLot=new Map((payload?.lots||[]).map(x=>[up(x.lot_no),x]));
 for(const card of cardCandidates()){
  const lot=lotNoFromCard(card),row=byLot.get(lot);card.querySelectorAll(':scope > .rr-j9254-host,:scope > .rr-j9255-host').forEach(x=>x.remove());
  if(!row)continue;
  const rows=activeRowsForLot(row);if(!rows.length)continue;
  const universe=lotSizeUniverse(row,rows);
  const host=document.createElement('div');host.className='rr-j9255-host';host.innerHTML=groupJourneys(rows,universe).map(renderJourney).join('');
  const anchor=card.querySelector('.lot-head,.cm-lot-box,.card-head,.fg-card-head')||card.firstElementChild;
  if(anchor?.insertAdjacentElement)anchor.insertAdjacentElement('afterend',host);else card.prepend(host);
 }
}
let timer=null,observer=null,lastSig='';
async function refresh(){
 const c=sb(),d=dept();if(!c||!d)return;
 try{
  const {data,error}=await c.rpc('rr_upm_lot_card_due_alter_header_v9092',{p_department_code:d});
  if(error)throw error;
  const sig=JSON.stringify((data?.lots||[]).map(x=>[x.lot_no,x.active_alter_qty,(x.alter_journeys||[]).map(j=>[journeyKey(j),j.size_code,j.qty,person(j,'from'),person(j,'owner'),j.stage,j.started_at,j.created_at,j.good_included,j.good_qty_included])]));
  if(sig!==lastSig)lastSig=sig;
  decorate(data||{});
 }catch(e){console.warn('UPM journey tracker V9255:',e?.message||e)}
}
function start(){
 injectStyle();refresh();clearInterval(timer);timer=setInterval(refresh,15000);
 observer?.disconnect?.();observer=new MutationObserver(()=>{clearTimeout(observer._t);observer._t=setTimeout(refresh,120)});observer.observe(document.body,{childList:true,subtree:true});
 document.addEventListener('click',e=>{if(e.target.closest?.('#refresh,[id*="refresh" i],[class*="refresh" i]'))setTimeout(refresh,350)},true);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();