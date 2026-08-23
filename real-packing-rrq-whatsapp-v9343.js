(()=>{
  'use strict';
  if(window.__RR_PACK_RRQ_WA_V9356__)return;
  window.__RR_PACK_RRQ_WA_V9356__=true;

  const MODE='TEST';
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String(document.getElementById('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const show=(t,cls='')=>{const m=document.getElementById('message');if(m){m.textContent=t;m.className='fg-msg '+cls}const x=document.getElementById('rrPicLocalMsg');if(x){x.textContent=t;x.className='fg-msg '+cls}};
  const sleep=ms=>new Promise(r=>setTimeout(r,ms));
  const transient=e=>/abort|aborted|AbortError|Failed to fetch|FunctionsFetchError|NetworkError/i.test(String(e?.name||'')+' '+String(e?.message||e||''));
  const providerUnavailable=e=>/133010|Account not registered|not registered|SIMULATED/i.test(String(e?.message||e||''));

  let lastOpenPayload=[];

  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}

  async function invokeWA(ids){
    if(!ids?.length)return{sent:0,results:[]};
    const c=db();let lastErr=null;
    for(let i=0;i<3;i++){
      try{
        const {data,error}=await c.functions.invoke('rr-wa-operational-send-v9343',{body:{message_ids:ids}});
        if(error)throw error;
        return data||{};
      }catch(e){lastErr=e;if(!transient(e))throw e;await sleep(700*(i+1));}
    }
    throw lastErr||Error('WhatsApp send failed');
  }

  function waHref(item){
    const mobile=String(item?.mobile||'').replace(/\D/g,'');
    if(!mobile)return'';
    return `https://wa.me/${mobile}?text=${encodeURIComponent(String(item?.message_text||''))}`;
  }

  function renderFallback(items,reason){
    const clean=(items||[]).filter(x=>waHref(x));
    lastOpenPayload=clean;
    const host=document.getElementById('rrPicLocalMsg')||document.getElementById('message');
    if(!host){show('Rate request saved. WhatsApp provider unavailable.','error');return;}
    host.className='fg-msg error';
    host.innerHTML='';
    const text=document.createElement('span');
    text.textContent=providerUnavailable(reason)?'Rate request saved. WhatsApp Business provider registered nahi hai — prepared message manually open karein.':'Rate request saved. Automatic WhatsApp send nahi hua — prepared message open karke send karein.';
    host.appendChild(text);
    clean.forEach((item,i)=>{
      const a=document.createElement('a');
      a.className='fg-btn primary';
      a.style.marginLeft='8px';
      a.target='_blank';a.rel='noopener';a.href=waHref(item);
      a.textContent=`OPEN WHATSAPP${clean.length>1?' '+(i+1):''}`;
      host.appendChild(a);
    });
  }

  async function deliverPayload(payload){
    const ids=[...new Set((payload?.whatsapp_message_ids||[]).filter(Boolean))];
    const open=Array.isArray(payload?.whatsapp_open)?payload.whatsapp_open:[];
    if(open.length)lastOpenPayload=open;
    if(!ids.length){if(open.length)renderFallback(open,Error('No sendable message ids'));return;}
    try{
      const data=await invokeWA(ids),sent=Number(data?.sent||0),failed=(data?.results||[]).filter(x=>!x.ok);
      if(sent>0){show(`Request saved · WhatsApp ${sent} sent.`,'ok');return;}
      const err=Error(failed[0]?.error||failed[0]?.reason||'WhatsApp send failed');
      if(open.length){renderFallback(open,err);return;}
      throw err;
    }catch(e){
      if(open.length){renderFallback(open,e);return;}
      throw e;
    }
  }

  function installRpcBridge(){
    const c=db();
    if(!c?.rpc||c.__rrRrqWaBridge9356)return false;
    const original=c.rpc.bind(c);
    c.rpc=async function(name,args,options){
      const res=await original(name,args,options);
      if(name==='rr_pack_request_rate_v9340'&&!res?.error&&res?.data){
        setTimeout(()=>deliverPayload(res.data).catch(e=>show('WhatsApp send: '+String(e?.message||e),'error')),0);
      }
      return res;
    };
    c.__rrRrqWaBridge9356=true;
    return true;
  }

  async function retryFromPending(l){
    if(!l)return;
    try{
      const q=await rpc('rr_pack_rrq_wa_pending_v9343',{p_lot_no:l,p_data_mode:MODE});
      const items=Array.isArray(q?.items)?q.items:[];
      const ids=[...new Set(items.map(x=>x?.message_id).filter(Boolean))];
      if(!ids.length){
        if(lastOpenPayload.length)renderFallback(lastOpenPayload,Error('Provider retry unavailable'));
        return;
      }
      const data=await invokeWA(ids),sent=Number(data?.sent||0),failed=(data?.results||[]).filter(x=>!x.ok);
      if(sent>0){show(`WhatsApp ${sent} sent.`,'ok');return;}
      throw Error(failed[0]?.error||failed[0]?.reason||'WhatsApp send failed');
    }catch(e){
      if(lastOpenPayload.length){renderFallback(lastOpenPayload,e);return;}
      show('WhatsApp send: '+String(e?.message||e),'error');
    }
  }

  document.addEventListener('click',e=>{
    if(!e.target?.closest?.('#rrRateRefresh'))return;
    setTimeout(()=>retryFromPending(lot()),250);
  },true);

  [0,150,400,900,1600].forEach(ms=>setTimeout(installRpcBridge,ms));
})();
