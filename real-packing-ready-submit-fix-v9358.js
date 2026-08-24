(()=>{
'use strict';
/* V9367 permanent Ready Lots fix. Restores the previously proven direct REST bridge for ONLY rr_fg_ready_packing_cards_v788. */
window.__RR_PACK_SUBMIT_SYNC_9356__=true;
if(window.__RR_PACK_READY_REST_BRIDGE_9367__)return;
window.__RR_PACK_READY_REST_BRIDGE_9367__=true;

const text=x=>String(x?.textContent||'').replace(/\s+/g,' ').trim();
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const withTimeout=(p,ms,label)=>Promise.race([p,new Promise((_,rej)=>setTimeout(()=>rej(new Error(label||'Timeout')),ms))]);

function db(){return window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;}
function baseAndKey(c){
  const base=String(window.RF_SUPABASE_URL||window.SUPABASE_URL||c?.supabaseUrl||'').replace(/\/$/,'');
  const key=String(window.RF_SUPABASE_ANON_KEY||window.SUPABASE_ANON_KEY||c?.supabaseKey||'');
  return{base,key};
}

async function readyRest(args={}){
  const c=db();if(!c?.auth)throw Error('Supabase client unavailable');
  const {base,key}=baseAndKey(c);if(!base||!key)throw Error('Supabase config unavailable');
  let token=key;
  try{
    const s=await withTimeout(c.auth.getSession(),3500,'Login session timeout');
    token=s?.data?.session?.access_token||key;
  }catch(e){console.warn('Ready Lots session fallback',e);}

  let last=null;
  for(let attempt=1;attempt<=3;attempt++){
    const ctl=new AbortController();
    const timer=setTimeout(()=>ctl.abort(),8000);
    try{
      const res=await fetch(`${base}/rest/v1/rpc/rr_fg_ready_packing_cards_v788`,{
        method:'POST',
        headers:{'Content-Type':'application/json','apikey':key,'Authorization':`Bearer ${token}`},
        body:JSON.stringify({p_data_mode:args?.p_data_mode||'TEST'}),
        signal:ctl.signal,
        cache:'no-store'
      });
      const raw=await res.text();
      let data=null;try{data=raw?JSON.parse(raw):null}catch(_){data=raw}
      if(!res.ok)throw Error(data?.message||data?.error||raw||`Ready Lots HTTP ${res.status}`);
      return data;
    }catch(e){
      last=e;
      if(attempt<3)await sleep(300*attempt);
    }finally{clearTimeout(timer);}
  }
  throw(last||new Error('Ready Lots could not load'));
}

function install(){
  const c=db();if(!c?.rpc)return false;
  if(c.__rrReadyRestBridge9367)return true;
  const originalRpc=c.rpc.bind(c);
  c.rpc=async function(name,args,options){
    if(name!=='rr_fg_ready_packing_cards_v788')return originalRpc(name,args,options);
    try{return{data:await readyRest(args),error:null,status:200};}
    catch(error){return{data:null,error:{message:error?.name==='AbortError'?'Ready Lots server timeout. Refresh karein.':String(error?.message||error)},status:0};}
  };
  c.__rrReadyRestBridge9367=true;
  return true;
}

function retryIfStuck(){
  if(!install())return;
  const cards=document.getElementById('packLotCards'),msg=document.getElementById('message');
  const stuck=/Ready lots load ho rahe hain/i.test(text(cards))||/Press se Ready Lots fetch ho rahe hain/i.test(text(msg));
  if(!stuck)return;
  const b=document.getElementById('refreshPackLots');
  if(b&&!b.disabled)b.click();
}

[0,40,100,220,450,900,1500].forEach(ms=>setTimeout(install,ms));
document.addEventListener('DOMContentLoaded',()=>{
  install();
  [450,1200,2600,5200].forEach(ms=>setTimeout(retryIfStuck,ms));
},{once:true});
})();