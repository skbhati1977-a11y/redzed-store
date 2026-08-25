(()=>{
  'use strict';
  if(window.__RR_PACK_RRQ_SEND_BRIDGE_V9356__)return;
  window.__RR_PACK_RRQ_SEND_BRIDGE_V9356__=true;
  const MODE='TEST';
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const $=id=>document.getElementById(id);
  const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const sleep=ms=>new Promise(r=>setTimeout(r,ms));
  const clean=e=>{
    const raw=String(e?.message||e?.context?.msg||e?.details||e||'');
    if(/user aborted|abort|aborted|AbortError/i.test(raw))return 'Request saved. WhatsApp status retry ho raha hai; Refresh se bhi retry ho jayega.';
    if(/133010|Account not registered|OAuthException/i.test(raw))return 'WhatsApp sender account registration issue. Message approved format me queue me saved hai; sender account reconnect/register karna hoga.';
    if(/FunctionsFetchError|Failed to fetch|NetworkError|Failed to send/i.test(raw))return 'WhatsApp sender network retry pending. Refresh se retry karein.';
    return raw||'WhatsApp send status unavailable.';
  };
  const show=(t,cls='')=>['message','rrPicLocalMsg'].forEach(id=>{const n=$(id);if(n){n.textContent=t;n.className='fg-msg '+cls;}});
  const sanitize=()=>['message','rrPicLocalMsg'].forEach(id=>{const n=$(id);if(!n)return;const t=n.textContent||'';if(/The user aborted a request/i.test(t))show(clean(t),'error');if(/Account not registered|133010|OAuthException/i.test(t))show(clean(t),'error');});
  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}
  async function send(ids){const c=db();if(!c?.functions)throw Error('Supabase functions unavailable');const {data,error}=await c.functions.invoke('rr-wa-operational-send-v9343',{body:{message_ids:ids}});if(error)throw error;return data||{};}
  let running=false;
  async function retry(){
    const l=lot();if(!l||running)return;running=true;
    try{
      for(let i=0;i<5;i++){
        await sleep(i?900:350);
        const q=await rpc('rr_pack_rrq_wa_pending_v9343',{p_lot_no:l,p_data_mode:MODE});
        const items=Array.isArray(q?.items)?q.items:[];
        const ids=[...new Set(items.map(x=>x?.message_id).filter(Boolean))];
        if(!ids.length){if(i>0)show('Rate request saved. WhatsApp queue clear hai.','ok');return;}
        const data=await send(ids);
        const sent=Number(data?.sent||0);
        if(sent>0){show('WhatsApp message approved format me sent.','ok');return;}
        const failed=(data?.results||[]).filter(x=>!x.ok);
        if(failed.length)throw Error(failed[0]?.error||failed[0]?.reason||'WhatsApp send failed');
      }
      show('Rate request saved. WhatsApp retry pending; Refresh se retry karein.','error');
    }catch(e){show(clean(e),'error')}finally{running=false;sanitize();}
  }
  document.addEventListener('click',e=>{if(e.target?.closest?.('#rrRequestRate,#rrRateRefresh'))setTimeout(retry,650);},true);
  new MutationObserver(sanitize).observe(document.documentElement,{childList:true,subtree:true,characterData:true});
  setInterval(sanitize,1200);
})();