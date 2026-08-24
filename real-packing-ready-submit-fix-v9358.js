(()=>{
'use strict';
/* This module is the only submit-button authority. Disable the older submit-sync IIFE inside photo-first before that file loads. */
window.__RR_PACK_SUBMIT_SYNC_9356__=true;
if(window.__RR_PACK_READY_SUBMIT_FIX_9361__)return;window.__RR_PACK_READY_SUBMIT_FIX_9361__=true;
const MODE='TEST',$=id=>document.getElementById(id),db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function fetchish(e){return /failed to fetch|networkerror|functionsfetcherror|load failed/i.test(String(e?.message||e||''));}
function installRpcRetry(){const c=db();if(!c?.rpc||c.__rrPackRpcRetry9361)return false;const orig=c.rpc.bind(c);c.rpc=async function(name,args,options){let last;for(let i=0;i<3;i++){try{const r=await orig(name,args,options);if(!r?.error||!fetchish(r.error))return r;last=r.error;}catch(e){last=e;if(!fetchish(e))throw e;}if(i<2)await sleep(450*(i+1));}return {data:null,error:last||new Error('Network request failed after retry')};};c.__rrPackRpcRetry9361=true;return true;}
async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}
let syncing=false,lastState='';
function applyButton(b,state,title=''){const key=state+'|'+title;if(key===lastState)return;lastState=key;if(state==='SUBMITTED'){b.disabled=true;b.textContent='PACKING SUBMITTED';b.title='Packing already submitted. Duplicate submit blocked.';b.dataset.rrFinalGate='0';return;}b.textContent='SUBMIT PACKING';if(state==='READY'){b.disabled=false;b.title='';b.dataset.rrFinalGate='1';}else{b.disabled=true;b.title=title;b.dataset.rrFinalGate='0';}}
async function syncSubmit(){const b=$('submitPack'),l=lot();if(!b||!l||!document.querySelector('#packRows tr')||syncing)return;syncing=true;try{
 const [cards,rate,media,ai]=await Promise.all([
  rpc('rr_fg_ready_packing_cards_v788',{p_data_mode:MODE}),
  rpc('rr_pack_rate_status_v9340',{p_lot_no:l,p_data_mode:MODE}),
  rpc('rr_pack_media_summary_v9330',{p_lot_no:l,p_data_mode:MODE}),
  rpc('rr_pack_ai_list_v9340',{p_lot_no:l,p_data_mode:MODE})
 ]);
 const card=(cards||[]).find(x=>String(x.lot_no)===l),status=String(card?.assignment_status||'').toUpperCase();
 if(status==='SUBMITTED'){applyButton(b,'SUBMITTED');const m=$('message');if(m&&/Assigned accepted Packing Plan required/i.test(m.textContent||'')){m.textContent='Packing already submitted.';m.className='fg-msg ok';}return;}
 const photos=Number(media?.camera_count||0)===3,items=Array.isArray(ai?.items)?ai.items:[],finalStyles=[1,2,3].every(n=>items.some(x=>Number(x.style_no)===n&&x.is_final===true)),accepted=status==='ACCEPTED';
 if(accepted&&!!rate?.approved&&photos&&finalStyles){applyButton(b,'READY');return;}
 const miss=[];if(!accepted)miss.push('Accepted Packing Plan');if(!rate?.approved)miss.push('Final Rate');if(!photos)miss.push('3 Photos');if(!finalStyles)miss.push('Style 1/2/3 Final');applyButton(b,'LOCKED','Pending: '+miss.join(', '));
 }catch(e){console.warn('Packing submit gate sync',e)}finally{syncing=false;}}
function kick(){installRpcRetry();setTimeout(syncSubmit,100);}
[0,100,300,700,1400].forEach(ms=>setTimeout(kick,ms));document.addEventListener('click',()=>setTimeout(kick,160),true);document.addEventListener('change',()=>setTimeout(kick,160),true);new MutationObserver(()=>setTimeout(kick,70)).observe(document.documentElement,{childList:true,subtree:true});setInterval(()=>{installRpcRetry();syncSubmit()},1200);
})();