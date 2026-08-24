(()=>{
'use strict';
if(window.__RR_PACK_SUBMIT_STATUS_9359__)return;window.__RR_PACK_SUBMIT_STATUS_9359__=true;
const MODE='TEST',$=id=>document.getElementById(id),db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
const algoReady=()=>!!document.querySelector('#packRows tr');
let busy=false,bypass=false,cache={lot:'',status:'',ready:false,title:'Checking packing submit gate…'};
async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data}
function all3Final(items){return [1,2,3].every(n=>(items||[]).some(x=>Number(x.style_no)===n&&x.is_final===true))}
function apply(){const b=$('submitPack'),l=lot();if(!b||!l||cache.lot!==l)return;const submitted=cache.status==='SUBMITTED';b.textContent=submitted?'PACKING SUBMITTED':'SUBMIT PACKING';b.disabled=submitted||!cache.ready;b.title=submitted?'Packing already submitted. Duplicate submit blocked.':cache.title;}
async function inspect(){const l=lot();if(!l)return null;const [cards,rate,media,ai]=await Promise.all([
  rpc('rr_fg_ready_packing_cards_v788',{p_data_mode:MODE}),
  rpc('rr_pack_rate_status_v9340',{p_lot_no:l,p_data_mode:MODE}),
  rpc('rr_pack_media_summary_v9330',{p_lot_no:l,p_data_mode:MODE}),
  rpc('rr_pack_ai_list_v9340',{p_lot_no:l,p_data_mode:MODE})
]);
const x=(cards||[]).find(v=>String(v.lot_no)===l),status=String(x?.assignment_status||'').toUpperCase(),photos=Math.min(3,Number(media?.camera_count||0)),finals=all3Final(ai?.items||[]),accepted=status==='ACCEPTED',submitted=status==='SUBMITTED',algo=algoReady();
let title='';if(submitted)title='Packing already submitted. Duplicate submit blocked.';else if(!accepted)title='Accepted Packing Plan required';else if(!algo)title='Packing algorithm required';else if(photos!==3)title=`Final garment photos ${photos}/3`;else if(!rate?.approved)title='Final rate approval pending';else if(!finals)title='AI Style 1, Style 2, Style 3 FINAL required';
const ready=accepted&&algo&&photos===3&&!!rate?.approved&&finals;
cache={lot:l,status,ready,title};apply();return cache;
}
async function sync(){if(busy)return;busy=true;try{await inspect()}catch(e){console.warn('packing submit bridge',e)}finally{busy=false}}
document.addEventListener('click',async e=>{
  const b=e.target?.closest?.('#submitPack');if(!b||bypass)return;
  e.preventDefault();e.stopImmediatePropagation();
  try{
    const s=await inspect();
    if(!s?.ready){const m=$('message');if(m){m.textContent=s?.title||'Packing submit gate incomplete.';m.className='fg-msg error';}return;}
    const old=b.onclick;if(typeof old!=='function')throw Error('Original Packing Submit handler unavailable.');
    bypass=true;try{await old.call(b,e)}finally{bypass=false;setTimeout(sync,120)}
  }catch(err){const m=$('message');if(m){m.textContent=String(err?.message||err);m.className='fg-msg error';}}
},true);
new MutationObserver(()=>{apply();setTimeout(sync,100)}).observe(document.documentElement,{childList:true,subtree:true});
setInterval(sync,900);[250,700,1400].forEach(ms=>setTimeout(sync,ms));
})();