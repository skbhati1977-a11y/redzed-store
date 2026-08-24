(()=>{
'use strict';
if(window.__RR_PACK_SUBMIT_GATE_V9356__)return;window.__RR_PACK_SUBMIT_GATE_V9356__=true;
const MODE='TEST',$=id=>document.getElementById(id),db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
let syncing=false,lastKey='';
async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data}
function algoReady(){return !!document.querySelector('#packRows tr')}
function finalsReady(items){return [1,2,3].every(n=>(items||[]).some(x=>Number(x.style_no)===n&&x.is_final===true))}
async function sync(){if(syncing)return;const l=lot(),btn=$('submitPack');if(!l||!btn||!algoReady())return;syncing=true;try{const [rate,media,ai]=await Promise.all([rpc('rr_pack_rate_status_v9340',{p_lot_no:l,p_data_mode:MODE}),rpc('rr_pack_media_summary_v9330',{p_lot_no:l,p_data_mode:MODE}),rpc('rr_pack_ai_list_v9340',{p_lot_no:l,p_data_mode:MODE})]);const photoCount=Math.min(3,Number(media?.camera_count||0));const allFinal=finalsReady(ai?.items||[]);const ready=!!rate?.approved&&photoCount===3&&allFinal&&algoReady();btn.disabled=!ready;btn.title=ready?'':!rate?.approved?'Final rate approval pending':photoCount!==3?`Final garment photos ${photoCount}/3`:!allFinal?'Style 1, 2, 3 final selection pending':'Packing algorithm required';btn.dataset.rrCatalogReady=ready?'1':'0';}catch(e){console.warn('Packing submit gate sync failed',e)}finally{syncing=false}}
function schedule(){setTimeout(sync,80);setTimeout(sync,350);setTimeout(sync,900)}
document.addEventListener('click',e=>{if(e.target?.closest?.('[data-final],#rrRateRefresh,#rrPicRefresh,#rrUploadPics,#runPackAlgo'))schedule()},true);
document.addEventListener('change',e=>{if(e.target?.matches?.('#rrCameraPics,#rrGalleryPics,[data-ai-upload]'))schedule()},true);
new MutationObserver(()=>{const k=lot()+'|'+document.querySelectorAll('#packRows tr').length+'|'+document.querySelectorAll('.rr-style .fg-chip').length;if(k!==lastKey){lastKey=k;schedule()}}).observe(document.documentElement,{childList:true,subtree:true});
setInterval(sync,1500);[250,700,1400,2600].forEach(ms=>setTimeout(sync,ms));
})();