(()=>{
  'use strict';
  if(window.__RR_PACK_RRQ_WA_V9343__)return;
  window.__RR_PACK_RRQ_WA_V9343__=true;
  const MODE='TEST';
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String(document.getElementById('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const show=(t,cls='')=>{const m=document.getElementById('message');if(m){m.textContent=t;m.className='fg-msg '+cls}const x=document.getElementById('rrPicLocalMsg');if(x){x.textContent=t;x.className='fg-msg '+cls}};
  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}
  async function sendPending(l){
    for(let attempt=0;attempt<8;attempt++){
      await new Promise(r=>setTimeout(r,attempt?650:350));
      const q=await rpc('rr_pack_rrq_wa_pending_v9343',{p_lot_no:l,p_data_mode:MODE});
      const ids=Array.isArray(q?.message_ids)?q.message_ids:[];
      if(!ids.length)continue;
      const c=db();
      const {data,error}=await c.functions.invoke('rr-wa-operational-send-v9343',{body:{message_ids:ids}});
      if(error)throw error;
      const sent=Number(data?.sent||0);
      const failed=(data?.results||[]).filter(x=>!x.ok);
      if(sent>0){show(`Request Admin/Super Admin ko bhej di gayi · WhatsApp ${sent} sent.`,'ok');return;}
      if(failed.length)throw Error(failed[0]?.error||failed[0]?.reason||'WhatsApp send failed');
      return;
    }
    show('Rate request save ho gayi, lekin WhatsApp queue nahi mili. Refresh karke retry karein.','error');
  }
  document.addEventListener('click',e=>{
    const b=e.target?.closest?.('#rrRequestRate');
    if(!b)return;
    const l=lot();
    if(!l)return;
    setTimeout(()=>sendPending(l).catch(err=>show('WhatsApp send: '+String(err?.message||err),'error')),50);
  },true);
})();