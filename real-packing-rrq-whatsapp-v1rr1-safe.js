(()=>{
  'use strict';
  if(window.__RR_PACK_RRQ_WA_SAFE_1RR1__)return;
  window.__RR_PACK_RRQ_WA_SAFE_1RR1__=true;
  const MODE='TEST';
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String(document.getElementById('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const show=(t,cls='')=>{const m=document.getElementById('message');if(m){m.textContent=t;m.className='fg-msg '+cls}const x=document.getElementById('rrPicLocalMsg');if(x){x.textContent=t;x.className='fg-msg '+cls}};
  const inflight=new Map(), done=new Set();
  const sleep=ms=>new Promise(r=>setTimeout(r,ms));
  const text=e=>String(e?.message||e?.error?.message||e?.details||e?.hint||e||'');
  const transient=e=>/abort|aborted|AbortError|Failed to fetch|FunctionsFetchError|NetworkError/i.test(String(e?.name||'')+' '+text(e));
  const waAccountIssue=e=>/133010|Account not registered|OAuthException/i.test(text(e));
  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}
  async function invokeWA(ids){
    const c=db();let lastErr=null;
    for(let i=0;i<3;i++){
      try{const {data,error}=await c.functions.invoke('rr-wa-operational-send-v9343',{body:{message_ids:ids}});if(error)throw error;return data||{};}
      catch(e){lastErr=e;if(waAccountIssue(e))return {sent:0,wa_account_issue:true,results:[{ok:false,error:text(e)}]};if(!transient(e))throw e;await sleep(650*(i+1));}
    }
    throw lastErr||Error('WhatsApp send failed');
  }
  async function sendPending(l){
    if(!l||done.has(l))return;
    if(inflight.has(l))return inflight.get(l);
    const task=(async()=>{try{
      for(let attempt=0;attempt<8;attempt++){
        await sleep(attempt?700:450);
        let q;try{q=await rpc('rr_pack_rrq_wa_pending_v9343',{p_lot_no:l,p_data_mode:MODE})}catch(e){if(transient(e))continue;throw e}
        const items=Array.isArray(q?.items)?q.items:[];
        const ids=[...new Set(items.map(x=>x?.message_id).filter(Boolean))];
        if(!ids.length)continue;
        const data=await invokeWA(ids);
        const sent=Number(data?.sent||0);
        const failed=(data?.results||[]).filter(x=>!x.ok);
        if(sent>0){done.add(l);show(`Request messages ready · WhatsApp ${sent} sent.`,'ok');return;}
        if(data?.wa_account_issue||failed.some(waAccountIssue)){
          done.add(l);
          show('Rate request saved. WhatsApp account registration issue logged; packing flow unlocked.','ok');
          return;
        }
        if(failed.length)throw Error(failed[0]?.error||failed[0]?.reason||'WhatsApp send failed');
        return;
      }
      show('Rate request saved. WhatsApp queue pending; Refresh se retry ho jayega.','ok');
    }catch(e){
      if(waAccountIssue(e)){done.add(l);show('Rate request saved. WhatsApp account registration issue logged; packing flow unlocked.','ok');return;}
      show('WhatsApp send pending: '+text(e),'error');
    }finally{inflight.delete(l)}})();
    inflight.set(l,task);return task;
  }
  document.addEventListener('click',e=>{const b=e.target?.closest?.('#rrRequestRate');if(!b)return;const l=lot();if(!l)return;done.delete(l);setTimeout(()=>sendPending(l),250);},true);
  document.addEventListener('click',e=>{if(!e.target?.closest?.('#rrRateRefresh'))return;const l=lot();if(!l)return;done.delete(l);setTimeout(()=>sendPending(l),300);},true);
})();
