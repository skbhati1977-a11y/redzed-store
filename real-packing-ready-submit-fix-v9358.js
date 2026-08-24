(()=>{
'use strict';
/* Keep exactly one Ready Packing Lots bridge. If the proven manager bridge already owns the RPC,
   do not wrap it again. If it does not, install the same proven direct REST bridge here. */
window.__RR_PACK_SUBMIT_SYNC_9356__=true;
if(window.__RR_PACK_READY_RPC_FIX_9370__)return;
window.__RR_PACK_READY_RPC_FIX_9370__=true;
const TARGET='rr_fg_ready_packing_cards_v788';

function install(){
  const c=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  if(!c?.rpc||!c?.auth)return false;

  /* The older V9344 manager bridge is the previously proven working fix. Never wrap it again. */
  if(window.__RR_PACK_READY_REST_BRIDGE_9344__)return true;

  const originalRpc=c.rpc.bind(c);
  c.rpc=async function(name,args,options){
    if(name!==TARGET)return originalRpc(name,args,options);
    try{
      const sessionRes=await c.auth.getSession();
      const session=sessionRes?.data?.session;
      if(!session?.access_token)return originalRpc(name,args,options);
      const base=(typeof SUPABASE_URL!=='undefined'&&SUPABASE_URL)||c.supabaseUrl;
      const key=(typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_ANON_KEY)||c.supabaseKey;
      const ctl=new AbortController();
      const timer=setTimeout(()=>ctl.abort(),8000);
      const res=await fetch(`${base}/rest/v1/rpc/${TARGET}`,{
        method:'POST',
        headers:{'Content-Type':'application/json','apikey':key,'Authorization':`Bearer ${session.access_token}`},
        body:JSON.stringify(args||{}),signal:ctl.signal,cache:'no-store'
      });
      clearTimeout(timer);
      const raw=await res.text();
      let data=null;try{data=raw?JSON.parse(raw):null}catch(_){data=raw}
      if(!res.ok)return{data:null,error:{message:data?.message||raw||`HTTP ${res.status}`,status:res.status}};
      return{data,error:null,status:res.status};
    }catch(error){
      console.warn('Ready Lots REST bridge fallback',error);
      return originalRpc(name,args,options);
    }
  };
  window.__RR_PACK_READY_REST_BRIDGE_9344__=true;
  return true;
}

function kickIfStuck(){
  if(!install())return;
  const cards=document.getElementById('packLotCards');
  const msg=document.getElementById('message');
  const btn=document.getElementById('refreshPackLots');
  const stuck=/Ready lots load ho rahe hain/i.test(String(cards?.textContent||''))||/Press se Ready Lots fetch ho rahe hain/i.test(String(msg?.textContent||''));
  if(stuck&&btn&&!btn.disabled)btn.click();
}

install();
window.addEventListener('redzed:supabase-ready',install,{once:true});
[350,900,1800,3000].forEach(ms=>setTimeout(kickIfStuck,ms));
})();