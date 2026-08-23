(()=>{
  'use strict';
  if(window.__RR_PACK_RRQ_WA_V9344__)return;
  window.__RR_PACK_RRQ_WA_V9344__=true;
  const MODE='TEST';
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String(document.getElementById('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const show=(t,cls='')=>{const m=document.getElementById('message');if(m){m.textContent=t;m.className='fg-msg '+cls}const x=document.getElementById('rrPicLocalMsg');if(x){x.textContent=t;x.className='fg-msg '+cls}};
  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}
  function phone(v){const d=String(v||'').replace(/\D/g,'');if(!d)return'';return d.length===10?'91'+d:d;}
  function usablePhone(p){return !!p && !/9876543210$/.test(p) && p.length>=11;}
  function waUrl(item){
    const p=phone(item?.mobile),t=String(item?.message_text||'').trim();
    if(!t)return'';
    return usablePhone(p)?`https://wa.me/${p}?text=${encodeURIComponent(t)}`:`https://wa.me/?text=${encodeURIComponent(t)}`;
  }
  async function openPending(l){
    for(let attempt=0;attempt<8;attempt++){
      await new Promise(r=>setTimeout(r,attempt?650:300));
      const q=await rpc('rr_pack_rrq_wa_pending_v9343',{p_lot_no:l,p_data_mode:MODE});
      const items=Array.isArray(q?.items)?q.items:[];
      const item=items[items.length-1];
      if(!item)continue;
      const url=waUrl(item);
      if(!url)throw Error('WhatsApp message missing');
      try{await rpc('rr_comm_mark_whatsapp_opened_v853',{p_message_id:item.message_id});}catch(_){/* open must continue */}
      const p=phone(item?.mobile),direct=usablePhone(p);
      show(direct?'Request save ho gayi · WhatsApp Admin chat open ho raha hai. Send manually press karein.':'Request save ho gayi · WhatsApp open ho raha hai. Admin/Super Admin chat select karke Send karein.','ok');
      const w=window.open(url,'_blank','noopener,noreferrer');
      if(!w)window.location.href=url;
      return;
    }
    show('Rate request save ho gayi, lekin WhatsApp message ready nahi mila. Refresh karke retry karein.','error');
  }
  document.addEventListener('click',e=>{
    const b=e.target?.closest?.('#rrRequestRate');
    if(!b)return;
    const l=lot();
    if(!l)return;
    setTimeout(()=>openPending(l).catch(err=>show('WhatsApp open: '+String(err?.message||err),'error')),40);
  },true);
})();