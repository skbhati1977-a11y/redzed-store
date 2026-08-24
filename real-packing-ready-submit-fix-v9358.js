(()=>{
'use strict';
/* V9372 permanent Ready Packing Lots authority.
   This bridge deliberately overrides any older READY-only RPC wrapper.
   Non-ready RPCs keep their existing chain untouched. */
window.__RR_PACK_SUBMIT_SYNC_9356__=true;
if(window.__RR_PACK_READY_RPC_FIX_9372__)return;
window.__RR_PACK_READY_RPC_FIX_9372__=true;
const TARGET='rr_fg_ready_packing_cards_v788';
const bounded=(promise,ms,label)=>Promise.race([promise,new Promise((_,reject)=>setTimeout(()=>reject(new Error(label)),ms))]);

(function patchRoleAliases(){
  if(!window.RR?.requireRoles||window.RR.__fgRoleAlias9372)return;
  const original=window.RR.requireRoles.bind(window.RR);
  window.RR.requireRoles=async function(allowedRoles){
    const roles=[...(allowedRoles||[])];
    const add=r=>{if(!roles.includes(r))roles.push(r);};
    if(roles.includes('packing'))add('packing_operator');
    if(roles.includes('store'))add('store_operator');
    if(roles.includes('accounts'))add('account');
    return original(roles);
  };
  window.RR.__fgRoleAlias9372=true;
})();

function install(){
  const c=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  if(!c?.rpc||!c?.auth)return false;
  if(c.__rrReadyAuthority9372)return true;
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
          method:'POST',
          headers:{'Content-Type':'application/json','apikey':key,'Authorization':`Bearer ${token}`,'Cache-Control':'no-store'},
          body:JSON.stringify(args||{}),
          signal:ctl.signal,
          cache:'no-store',
          credentials:'omit'
        });
        const raw=await res.text();
        let data=null;try{data=raw?JSON.parse(raw):null}catch(_){data=raw}
        if(!res.ok)throw new Error(data?.message||data?.hint||raw||`Ready Lots HTTP ${res.status}`);
        if(!Array.isArray(data))throw new Error('Ready Lots response invalid');
        return{data,error:null,status:res.status,statusText:'OK'};
      }finally{clearTimeout(timer);}
    }catch(error){
      console.error('Ready Lots direct REST failed',error);
      return{data:null,error:{message:error?.name==='AbortError'?'Ready Packing Lots request timeout':(error?.message||'Ready Packing Lots failed')}};
    }
  };
  c.__rrReadyAuthority9372=true;
  window.__RR_PACK_READY_REST_BRIDGE_9344__=true;
  return true;
}

function kickIfStuck(){
  if(!install())return;
  const cards=document.getElementById('packLotCards');
  const message=document.getElementById('message');
  const btn=document.getElementById('refreshPackLots');
  const stuck=/Ready lots load ho rahe hain/i.test(String(cards?.textContent||''))||/Press se Ready Lots fetch ho rahe hain/i.test(String(message?.textContent||''));
  if(stuck&&btn&&!btn.disabled)btn.click();
}

install();
window.addEventListener('redzed:supabase-ready',install,{once:true});
[0,50,150,350,800].forEach(ms=>setTimeout(install,ms));
[500,1400,3000].forEach(ms=>setTimeout(kickIfStuck,ms));
})();