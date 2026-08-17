(()=>{
'use strict';
if(window.__RR_CUTTING_RUNTIME_9193__)return;window.__RR_CUTTING_RUNTIME_9193__=true;
/* Never let legacy loading guards replace a valid Cutting render. */
window.__RR_CUTTING_LOAD_GUARD_9191__=true;
window.__RR_CUTTING_LOADING_GUARD_9191__=true;
const client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
if(!client||typeof client.rpc!=='function')return;
const originalRpc=client.rpc.bind(client);
const RPC_TIMEOUTS=new Map([
 ['rr_current_role',1200],
 ['rr_recover_lot_matching_v2',1800],
 ['rr_get_matching_cloth_stock_v2',3500],
 ['rr_get_matching_cloth_stock_v1',3500],
 ['rr_get_mc1_lot_matchings_v2',3500],
 ['rr_list_multi_lots_v3',3500]
]);
client.rpc=function(name,args,options){
 const request=originalRpc(name,args,options);
 const ms=RPC_TIMEOUTS.get(String(name||''));
 if(!ms)return request;
 return Promise.race([
   Promise.resolve(request),
   new Promise(resolve=>setTimeout(()=>resolve({data:null,error:{message:`${name} timed out after ${ms}ms`,code:'RR_NONBLOCKING_TIMEOUT'}}),ms))
 ]);
};
/* Cost settings are non-essential for gallery render; do not let that read hold the page. */
if(typeof client.from==='function'){
 const originalFrom=client.from.bind(client);
 client.from=function(table){
   const builder=originalFrom(table);
   if(String(table)!=='rr_cutting_cost_settings_v3')return builder;
   return new Proxy(builder,{get(target,prop,receiver){
     const value=Reflect.get(target,prop,receiver);
     if(typeof value!=='function')return value;
     return function(...args){
       const result=value.apply(target,args);
       if(!result||typeof result!=='object'||typeof result.then!=='function')return result;
       return new Proxy(result,{get(t,p,r){
         if(p==='then')return (ok,bad)=>Promise.race([
           new Promise((resolve,reject)=>t.then(resolve,reject)),
           new Promise(resolve=>setTimeout(()=>resolve({data:null,error:{message:'Cutting cost settings timed out',code:'RR_OPTIONAL_TIMEOUT'}}),2200))
         ]).then(ok,bad);
         const v=Reflect.get(t,p,r);
         if(typeof v==='function')return (...a)=>v.apply(t,a);
         return v;
       }});
     };
   }});
 }
}
/* If core populated state but a late UI mutation left the gallery busy, render once. */
function reconcile(){
 const api=window.RRCuttingMasterPM,g=document.getElementById('divisionGallery');
 if(!api||!g)return;
 try{
   const st=api.state?.()||{};
   if(Array.isArray(st.galleryRows)&&st.galleryRows.length>0&&g.getAttribute('aria-busy')==='true')api.renderGallery?.();
 }catch(e){console.warn('Cutting v9193 reconcile',e)}
}
window.addEventListener('load',()=>{setTimeout(reconcile,1200);setTimeout(reconcile,3500)},{once:true});
})();