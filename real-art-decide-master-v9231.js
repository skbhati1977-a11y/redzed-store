(()=>{
"use strict";
if(window.__RR_ART_DECISION_RETIRED_TO_CB__)return;
window.__RR_ART_DECISION_RETIRED_TO_CB__=true;

const params=new URLSearchParams(location.search);
const cbId=String(params.get("cb_id")||"").trim();
const cbNo=String(params.get("cb_no")||"").trim();
const unitId=String(params.get("cb_unit_id")||"").trim();

function goByCbId(id){
  location.replace("real-cb-new-v9130-fix2.html?cb_id="+encodeURIComponent(id)+"&from=ART_DECISION_RETIRED#setDecisionCard");
}
function goByCbNo(no){
  location.replace("real-cb-new-v9130-loader.html?cb_no="+encodeURIComponent(no)+"&from=ART_DECISION_RETIRED#setDecisionCard");
}
function getClient(){
  try{if(window.supabaseClient?.from)return window.supabaseClient}catch(_){}
  try{if(typeof supabaseClient!=="undefined"&&supabaseClient?.from)return supabaseClient}catch(_){}
  return [window.supabaseDb,window.redzedSupabase,window.sb].find(x=>x?.from)||null;
}
async function waitForClient(){
  const started=Date.now();
  while(Date.now()-started<8000){
    const client=getClient();
    if(client)return client;
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  return null;
}
async function boot(){
  if(cbId)return goByCbId(cbId);
  if(cbNo)return goByCbNo(cbNo);
  if(unitId){
    try{
      const client=await waitForClient();
      if(client){
        const r=await client.from("rr_cb_units").select("purchase_id").eq("id",unitId).maybeSingle();
        if(!r.error&&r.data?.purchase_id)return goByCbId(r.data.purchase_id);
      }
    }catch(error){console.warn("Retired Art Decision redirect",error)}
  }
  location.replace("test70-cb-purchase-real-chat-pilot.html?from=ART_DECISION_RETIRED");
}
boot();
})();
