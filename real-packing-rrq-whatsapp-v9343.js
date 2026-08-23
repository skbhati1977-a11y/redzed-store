(()=>{
  'use strict';
  if(window.__RR_PACK_RRQ_WA_V9343__)return;
  window.__RR_PACK_RRQ_WA_V9343__=true;
  const MODE='TEST';
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String(document.getElementById('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const show=(t,cls='')=>{const m=document.getElementById('message');if(m){m.textContent=t;m.className='fg-msg '+cls}const x=document.getElementById('rrPicLocalMsg');if(x){x.textContent=t;x.className='fg-msg '+cls}};
  const inflight=new Map(),done=new Set();
  const sleep=ms=>new Promise(r=>setTimeout(r,ms));
  const abortish=e=>/abort|aborted|AbortError|The user aborted a request/i.test(String(e?.name||'')+' '+String(e?.message||e||''));

  async function rpc(name,args={}){
    const c=db();if(!c?.auth)throw Error('Supabase client unavailable');
    const {data:sess,error:se}=await c.auth.getSession();if(se)throw se;
    const token=sess?.session?.access_token;if(!token)throw Error('Login session required');
    const base=(typeof SUPABASE_URL!=='undefined'&&SUPABASE_URL)||c.supabaseUrl;
    const key=(typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_ANON_KEY)||c.supabaseKey;
    const res=await fetch(`${base}/rest/v1/rpc/${encodeURIComponent(name)}`,{method:'POST',headers:{'Content-Type':'application/json','apikey':key,'Authorization':`Bearer ${token}`},body:JSON.stringify(args||{}),cache:'no-store'});
    const raw=await res.text();let data=null;try{data=raw?JSON.parse(raw):null}catch(_){data=raw}
    if(!res.ok)throw Error(data?.message||data?.hint||raw||`HTTP ${res.status}`);
    return data;
  }

  async function invokeWA(ids){
    const c=db();let lastErr=null;
    for(let i=0;i<3;i++){
      try{
        const {data,error}=await c.functions.invoke('rr-wa-operational-send-v9343',{body:{message_ids:ids}});
        if(error)throw error;
        return data||{};
      }catch(e){lastErr=e;if(!abortish(e))throw e;await sleep(700*(i+1));}
    }
    throw lastErr||Error('WhatsApp send failed');
  }

  async function sendPending(l){
    if(!l||done.has(l))return;
    if(inflight.has(l))return inflight.get(l);
    const task=(async()=>{
      try{
        for(let attempt=0;attempt<8;attempt++){
          await sleep(attempt?700:500);
          let q;
          try{q=await rpc('rr_pack_rrq_wa_pending_v9343',{p_lot_no:l,p_data_mode:MODE})}
          catch(e){if(abortish(e)){continue}throw e}
          const items=Array.isArray(q?.items)?q.items:[];
          const ids=[...new Set(items.map(x=>x?.message_id).filter(Boolean))];
          if(!ids.length)continue;
          let data;
          try{data=await invokeWA(ids)}catch(e){if(abortish(e))continue;throw e}
          const sent=Number(data?.sent||0);
          const failed=(data?.results||[]).filter(x=>!x.ok);
          if(sent>0){done.add(l);show(`Request messages ready · WhatsApp ${sent} sent.`,'ok');return;}
          if(failed.length)throw Error(failed[0]?.error||failed[0]?.reason||'WhatsApp send failed');
          return;
        }
        show('Rate request save ho gayi. WhatsApp queue abhi ready nahi hai; Refresh par retry hoga.','error');
      }finally{inflight.delete(l)}
    })();
    inflight.set(l,task);return task;
  }

  document.addEventListener('click',e=>{
    const b=e.target?.closest?.('#rrRequestRate');if(!b)return;
    const l=lot();if(!l)return;
    setTimeout(()=>sendPending(l).catch(err=>{if(!abortish(err))show('WhatsApp send: '+String(err?.message||err),'error')}),250);
  },true);

  document.addEventListener('click',e=>{
    if(!e.target?.closest?.('#rrRateRefresh'))return;
    const l=lot();if(!l)return;
    done.delete(l);setTimeout(()=>sendPending(l).catch(err=>{if(!abortish(err))show('WhatsApp send: '+String(err?.message||err),'error')}),300);
  },true);
})();