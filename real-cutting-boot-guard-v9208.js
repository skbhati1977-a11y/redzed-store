/* REDZED Cutting startup guard v9209 */
(()=>{
'use strict';
if(window.__RR_CUTTING_BOOT_GUARD_9209__)return;
window.__RR_CUTTING_BOOT_GUARD_9209__=true;
const client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
if(!client||typeof client.rpc!=='function')return;
const originalRpc=client.rpc.bind(client);
const bootStarted=Date.now();
client.rpc=function(name,args,options){
  const key=String(name||'');
  if(key==='rr_current_role' && Date.now()-bootStarted<10000){
    return Promise.resolve({data:null,error:null,rr_startup_bypass:true});
  }
  if(key==='rr_recover_lot_matching_v2' && Date.now()-bootStarted<10000){
    try{void originalRpc(name,args,options)}catch(_){}
    return Promise.resolve({data:null,error:null,rr_startup_bypass:true});
  }
  return originalRpc(name,args,options);
};
client.__rrBootRpc9208=true;
client.__rrCuttingRpc9204=true;
})();