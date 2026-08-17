/* REDZED Cutting startup guard v9208 */
(()=>{
'use strict';
if(window.__RR_CUTTING_BOOT_GUARD_9208__)return;
window.__RR_CUTTING_BOOT_GUARD_9208__=true;
const client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
if(!client)return;
function timeoutEmpty(label,ms){return {data:[],error:null,rr_timeout:true,rr_timeout_label:label,rr_timeout_ms:ms}}
function race(request,ms,label){return Promise.race([Promise.resolve(request),new Promise(resolve=>setTimeout(()=>resolve(timeoutEmpty(label,ms)),ms))])}
if(typeof client.rpc==='function'&&!client.__rrBootRpc9208){
  const originalRpc=client.rpc.bind(client);
  client.rpc=function(name,args,options){
    const key=String(name||'');
    if(key==='rr_current_role')return race(originalRpc(name,args,options),1200,key);
    if(key==='rr_recover_lot_matching_v2')return race(originalRpc(name,args,options),1800,key);
    return originalRpc(name,args,options);
  };
  client.__rrBootRpc9208=true;
}
})();