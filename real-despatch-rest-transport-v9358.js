(()=>{
'use strict';
if(window.__RR_DESPATCH_REST_9358__)return;
window.__RR_DESPATCH_REST_9358__=true;
const c=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
if(!c?.rpc||!c?.auth)return;
const targets=new Set(['rr_fg_despatch_ready_lots_v9356','rr_fg_receive_pending_v9356','rr_fg_create_despatch_lot_v9356','rr_fg_receive_accept_v9356']);
const original=c.rpc.bind(c);
const timeout=(p,ms,label)=>Promise.race([p,new Promise((_,rej)=>setTimeout(()=>rej(new Error(label)),ms))]);
c.rpc=async function(name,args,options){
  if(!targets.has(name))return original(name,args,options);
  try{
    const s=await timeout(c.auth.getSession(),2500,'Login session timeout');
    if(s?.error)throw s.error;
    const token=s?.data?.session?.access_token;
    if(!token)throw new Error('Login session required');
    const ctl=new AbortController();
    const timer=setTimeout(()=>ctl.abort(),8000);
    try{
      const res=await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`,{
        method:'POST',
        headers:{'Content-Type':'application/json','apikey':SUPABASE_ANON_KEY,'Authorization':`Bearer ${token}`,'Cache-Control':'no-store'},
        body:JSON.stringify(args||{}),
        signal:ctl.signal,
        cache:'no-store',
        credentials:'omit'
      });
      const raw=await res.text();
      let data=null;
      try{data=raw?JSON.parse(raw):null}catch(_){data=raw}
      if(!res.ok)return{data:null,error:{message:data?.message||data?.hint||raw||`HTTP ${res.status}`}};
      return{data,error:null,status:res.status,statusText:'OK'};
    }finally{clearTimeout(timer)}
  }catch(e){
    const m=e?.name==='AbortError'?'Despatch request timeout':(e?.message||String(e));
    return{data:null,error:{message:m}};
  }
};
})();