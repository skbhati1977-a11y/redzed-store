(()=>{
'use strict';
/* Permanent Ready Packing Lots transport: direct REST only for rr_fg_ready_packing_cards_v788.
   Never falls back to a hanging Supabase rpc call. Session lookup, HTTP request and retries are all bounded. */
window.__RR_PACK_SUBMIT_SYNC_9356__=true;
if(window.__RR_PACK_READY_RPC_FIX_9368__)return;
window.__RR_PACK_READY_RPC_FIX_9368__=true;
const TARGET='rr_fg_ready_packing_cards_v788';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const bounded=(promise,ms,label)=>Promise.race([promise,new Promise((_,rej)=>setTimeout(()=>rej(new Error(label||'Request timeout')),ms))]);

async function readyRest(c,args){
  const sessionRes=await bounded(c.auth.getSession(),3500,'Login session timeout');
  if(sessionRes?.error)throw sessionRes.error;
  const session=sessionRes?.data?.session;
  const token=session?.access_token;
  if(!token)throw new Error('Login session required');
  const base=(typeof SUPABASE_URL!=='undefined'&&SUPABASE_URL)||c.supabaseUrl;
  const key=(typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_ANON_KEY)||c.supabaseKey;
  if(!base||!key)throw new Error('Supabase configuration unavailable');
  const ctl=new AbortController();
  const timer=setTimeout(()=>ctl.abort(),8000);
  try{
    const res=await fetch(`${base}/rest/v1/rpc/${TARGET}`,{
      method:'POST',
      headers:{'Content-Type':'application/json','apikey':key,'Authorization':`Bearer ${token}`},
      body:JSON.stringify(args||{}),
      signal:ctl.signal,
      cache:'no-store'
    });
    const raw=await res.text();
    let data=null;try{data=raw?JSON.parse(raw):null}catch(_){data=raw}
    if(!res.ok)throw new Error(data?.message||data?.hint||raw||`Ready Lots HTTP ${res.status}`);
    return data;
  }finally{clearTimeout(timer)}
}

function install(){
  const c=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  if(!c?.rpc||!c?.auth)return false;
  if(c.__rrReadyOnly9368)return true;
  const orig=c.rpc.bind(c);
  c.rpc=function(name,args,options){
    if(name!==TARGET)return orig(name,args,options);
    return (async()=>{
      let last=null;
      for(let i=0;i<3;i++){
        try{
          const data=await readyRest(c,args);
          return {data,error:null,status:200};
        }catch(e){
          last=e;
          console.warn(`Ready Lots direct attempt ${i+1} failed`,e);
          if(i<2)await sleep(450*(i+1));
        }
      }
      return {data:null,error:last||new Error('Ready Lots could not load')};
    })();
  };
  c.__rrReadyOnly9368=true;
  return true;
}

[0,25,75,150,300,600,1200,2400].forEach(ms=>setTimeout(install,ms));

/* If the app was already showing the initial loading placeholder when this bridge became active,
   trigger exactly one bounded reload attempt from the existing Refresh button. */
let kicked=false;
function kickIfStuck(){
  if(kicked||!install())return;
  const cards=document.getElementById('packLotCards');
  const btn=document.getElementById('refreshPackLots');
  if(!cards||!btn)return;
  if(/Ready lots load ho rahe hain/i.test(String(cards.textContent||''))){
    kicked=true;
    btn.click();
  }
}
[500,1200,2500,5000].forEach(ms=>setTimeout(kickIfStuck,ms));
})();