(()=>{
  'use strict';
  if(window.__RR_PACK_RRQ_WA_OPEN_V9356__)return;
  window.__RR_PACK_RRQ_WA_OPEN_V9356__=true;
  const MODE='TEST';
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String(document.getElementById('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const show=(t,cls='')=>{const m=document.getElementById('message');if(m){m.textContent=t;m.className='fg-msg '+cls}const x=document.getElementById('rrPicLocalMsg');if(x){x.textContent=t;x.className='fg-msg '+cls}};
  const inflight=new Map();
  const sleep=ms=>new Promise(r=>setTimeout(r,ms));
  const transient=e=>/abort|aborted|AbortError|Failed to fetch|FunctionsFetchError|NetworkError/i.test(String(e?.name||'')+' '+String(e?.message||e||''));
  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}
  function openWA(item){
    const phone=String(item?.mobile||'').replace(/[^0-9]/g,'');
    const text=String(item?.message_text||'').trim();
    if(!phone)throw Error('WhatsApp mobile missing');
    if(!text)throw Error('WhatsApp message missing');
    const url='https://wa.me/'+phone+'?text='+encodeURIComponent(text);
    show('WhatsApp app open ho raha hai. Chat khulne par Send dabayein.','ok');
    setTimeout(()=>{location.href=url;},120);
  }
  async function openPending(l){
    if(!l)return;
    if(inflight.has(l))return inflight.get(l);
    const task=(async()=>{try{
      for(let attempt=0;attempt<10;attempt++){
        await sleep(attempt?650:350);
        let q;
        try{q=await rpc('rr_pack_rrq_wa_pending_v9343',{p_lot_no:l,p_data_mode:MODE});}
        catch(e){if(transient(e))continue;throw e;}
        const items=Array.isArray(q?.items)?q.items:[];
        if(!items.length)continue;
        const owner=items.find(x=>String(x?.recipient_role||'').toLowerCase()==='owner')||items.find(x=>String(x?.mobile||'').includes('9654401954'))||items[0];
        openWA(owner);
        return;
      }
      show('Rate request saved, lekin active WhatsApp link nahi mila. Refresh dabakar phir try karein.','error');
    }finally{inflight.delete(l);}})();
    inflight.set(l,task);return task;
  }
  document.addEventListener('click',e=>{
    if(!e.target?.closest?.('#rrRequestRate,#rrRateRefresh'))return;
    const l=lot();if(!l)return;
    setTimeout(()=>openPending(l).catch(err=>show('WhatsApp open: '+String(err?.message||err),'error')),250);
  },true);
})();