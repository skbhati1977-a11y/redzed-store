(()=>{
'use strict';
/* V9373 permanent Ready Packing Lots authority.
   Install must happen AFTER config creates supabaseClient, but BEFORE app boot.
   Keep all non-ready RPCs untouched. */
window.__RR_PACK_SUBMIT_SYNC_9356__=true;
if(window.__RR_PACK_READY_RPC_FIX_9373__)return;
window.__RR_PACK_READY_RPC_FIX_9373__=true;
const TARGET='rr_fg_ready_packing_cards_v788';
const bounded=(promise,ms,label)=>Promise.race([promise,new Promise((_,reject)=>setTimeout(()=>reject(new Error(label)),ms))]);

function patchRoleAliases(){
  if(!window.RR?.requireRoles||window.RR.__fgRoleAlias9373)return false;
  const original=window.RR.requireRoles.bind(window.RR);
  window.RR.requireRoles=async function(allowedRoles){
    const roles=[...(allowedRoles||[])];
    const add=r=>{if(!roles.includes(r))roles.push(r);};
    if(roles.includes('packing'))add('packing_operator');
    if(roles.includes('store'))add('store_operator');
    if(roles.includes('accounts'))add('account');
    return original(roles);
  };
  window.RR.__fgRoleAlias9373=true;
  return true;
}

function install(){
  patchRoleAliases();
  const c=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  if(!c?.rpc||!c?.auth)return false;
  if(c.__rrReadyAuthority9373)return true;
  const previousRpc=c.rpc.bind(c);
  c.rpc=async function(name,args,options){
    if(name!==TARGET)return previousRpc(name,args,options);
    try{
      const sessionRes=await bounded(c.auth.getSession(),2500,'Ready Lots login session timeout');
      if(sessionRes?.error)throw sessionRes.error;
      const token=sessionRes?.data?.session?.access_token;
      if(!token)throw new Error('Login session required for Ready Packing Lots');
      const base=String((typeof SUPABASE_URL!=='undefined'&&SUPABASE_URL)||c.supabaseUrl||'').replace(/\/$/,'');
      const key=String((typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_ANON_KEY)||c.supabaseKey||'');
      if(!base||!key)throw new Error('Supabase configuration unavailable');
      const ctl=new AbortController();
      const timer=setTimeout(()=>ctl.abort(),7000);
      try{
        const res=await fetch(`${base}/rest/v1/rpc/${TARGET}`,{
          method:'POST',headers:{'Content-Type':'application/json','apikey':key,'Authorization':`Bearer ${token}`,'Cache-Control':'no-store'},
          body:JSON.stringify(args||{}),signal:ctl.signal,cache:'no-store',credentials:'omit'
        });
        const raw=await res.text(); let data=null;
        try{data=raw?JSON.parse(raw):null}catch(_){data=raw}
        if(!res.ok)throw new Error(data?.message||data?.hint||raw||`Ready Lots HTTP ${res.status}`);
        if(!Array.isArray(data))throw new Error('Ready Lots response invalid');
        return{data,error:null,status:res.status,statusText:'OK'};
      }finally{clearTimeout(timer);}
    }catch(error){
      console.error('Ready Lots direct REST failed',error);
      return{data:null,error:{message:error?.name==='AbortError'?'Ready Packing Lots request timeout':(error?.message||'Ready Packing Lots failed')}};
    }
  };
  c.__rrReadyAuthority9373=true;
  window.__RR_PACK_READY_REST_BRIDGE_9344__=true;
  return true;
}

/* Config/common are before this script. Wait synchronously via short polling;
   app JS is loaded after us, so first successful install owns the RPC before boot. */
let tries=0;
const waiter=setInterval(()=>{
  tries++;
  if(install()||tries>=100)clearInterval(waiter);
},25);
install();
window.addEventListener('redzed:supabase-ready',install);

function recoverVisibleStuck(){
  if(!install())return;
  const cards=document.getElementById('packLotCards');
  const message=document.getElementById('message');
  const btn=document.getElementById('refreshPackLots');
  const stuck=/Ready lots load ho rahe hain/i.test(String(cards?.textContent||''))||/Press se Ready Lots fetch ho rahe hain/i.test(String(message?.textContent||''));
  if(stuck&&btn&&!btn.disabled)btn.click();
}
[750,1800,3500,6000].forEach(ms=>setTimeout(recoverVisibleStuck,ms));
})();