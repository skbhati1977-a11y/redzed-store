(()=>{
'use strict';
if(window.__RR_PACK_SUBMIT_STATUS_9359__)return;window.__RR_PACK_SUBMIT_STATUS_9359__=true;
const $=id=>document.getElementById(id),db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
let busy=false,last='';
async function rpc(name,args={}){const c=db();if(!c?.rpc)return null;const {data,error}=await c.rpc(name,args);if(error)throw error;return data}
async function sync(){const l=lot(),b=$('submitPack');if(!l||!b||busy)return;busy=true;try{const cards=await rpc('rr_fg_ready_packing_cards_v788',{p_data_mode:'TEST'});const x=(cards||[]).find(v=>String(v.lot_no)===l);if(!x)return;const st=String(x.assignment_status||'').toUpperCase();if(st==='SUBMITTED'){b.disabled=true;b.textContent='PACKING SUBMITTED';b.title='Packing already submitted. Duplicate submit blocked.';if(last!==l+'|SUBMITTED'){last=l+'|SUBMITTED';const m=$('message');if(m&&/Assigned accepted Packing Plan required/i.test(m.textContent||'')){m.textContent='Packing already submitted. Duplicate submit blocked.';m.className='fg-msg ok';}}}else{if(b.textContent==='PACKING SUBMITTED')b.textContent='SUBMIT PACKING';}}
catch(e){console.warn('packing submit status sync',e)}finally{busy=false}}
setInterval(sync,700);document.addEventListener('click',()=>setTimeout(sync,120),true);new MutationObserver(()=>setTimeout(sync,80)).observe(document.documentElement,{childList:true,subtree:true});[300,800,1500].forEach(ms=>setTimeout(sync,ms));
})();