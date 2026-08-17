(()=>{
'use strict';
const q=new URLSearchParams(location.search),raw=String(q.get('dept')||'').trim().toUpperCase();
const dept=raw==='ID'?'METAL_ID':raw,mode=String(q.get('mode')||'TEST').trim().toUpperCase();
if(!['STICKER','METAL_ID'].includes(dept))return;
const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const style=document.createElement('style');
style.textContent=`
#rr9171AssignGrid .rr9171-card{position:relative;overflow:hidden;transition:.15s ease}
#rr9171AssignGrid .rr9171-card.rr-accessory-full{background:#0f3556!important;border-color:#2877b4!important}
#rr9171AssignGrid .rr9171-card.rr-accessory-partial{padding-right:86px!important;border-color:#8a6b2b!important;background:#0f3556!important}
#rr9171AssignGrid .rr9171-card.rr-accessory-partial::after{content:"PARTIAL\A" attr(data-open-colours);white-space:pre-wrap;position:absolute;right:0;top:0;bottom:0;width:78px;background:#ffc857;color:#17120a;display:flex;align-items:center;justify-content:center;text-align:center;padding:8px 5px;font-size:10px;line-height:1.35;font-weight:950;letter-spacing:.02em;border-left:1px solid #e0a91f}
@media(max-width:520px){#rr9171AssignGrid .rr9171-card.rr-accessory-partial{padding-right:76px!important}#rr9171AssignGrid .rr9171-card.rr-accessory-partial::after{width:69px;font-size:9px}}
`;
document.head.appendChild(style);
let busy=false,last=null;
async function load(){if(busy)return;const c=db();if(!c)return;busy=true;try{const {data,error}=await c.rpc('rr_upm_accessory_due_card_v9172',{p_department_code:dept,p_data_mode:mode});if(error)throw error;last=data;decorate()}catch(e){console.warn('Accessory partial visual v9172',e)}finally{busy=false}}
function decorate(){if(!last)return;const map=new Map((last.lots||[]).map(l=>[String(l.canonical_lot_id),l]));document.querySelectorAll('#rr9171AssignGrid .rr9171-card[data-canonical]').forEach(card=>{const l=map.get(String(card.dataset.canonical));card.classList.remove('rr-accessory-full','rr-accessory-partial');card.removeAttribute('data-open-colours');if(!l)return;const state=String(l.availability_state||'').toUpperCase();const cols=(l.available_colour_codes||[]).map(String);if(state==='PARTIAL'){card.classList.add('rr-accessory-partial');card.dataset.openColours=cols.join(' · ')||'OPEN';}else if(state==='FULL'){card.classList.add('rr-accessory-full');}})}
const obs=new MutationObserver(()=>requestAnimationFrame(decorate));
function boot(){const host=document.getElementById('rr9171Host')||document.body;obs.observe(host,{childList:true,subtree:true});load();setInterval(load,8000)}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();