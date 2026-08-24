(()=>{
'use strict';
/* Permanent targeted guard: only Ready Packing Lots RPC gets timeout/retry. Other Supabase RPC calls remain untouched. */
window.__RR_PACK_SUBMIT_SYNC_9356__=true;
if(window.__RR_PACK_READY_RPC_FIX_9366__)return;
window.__RR_PACK_READY_RPC_FIX_9366__=true;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function timeout(p,ms){return Promise.race([p,new Promise((_,rej)=>setTimeout(()=>rej(new Error('Ready Lots request timeout')),ms))]);}
function install(){
  const c=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  if(!c?.rpc||c.__rrReadyOnly9366)return false;
  const orig=c.rpc.bind(c);
  c.rpc=function(name,args,options){
    if(name!=='rr_fg_ready_packing_cards_v788')return orig(name,args,options);
    return (async()=>{
      let last=null;
      for(let i=0;i<3;i++){
        try{
          const r=await timeout(orig(name,args,options),7000);
          if(!r?.error)return r;
          last=r.error;
        }catch(e){last=e;}
        if(i<2)await sleep(350*(i+1));
      }
      return {data:null,error:last||new Error('Ready Lots could not load')};
    })();
  };
  c.__rrReadyOnly9366=true;
  return true;
}
[0,50,150,400,900,1600].forEach(ms=>setTimeout(install,ms));
})();