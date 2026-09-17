(()=>{
  "use strict";
  const params=new URLSearchParams(location.search);
  const requested=String(params.get("rrAssignmentReceipt")||"").trim();
  if(!requested)return;
  const client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  if(!client||typeof client.rpc!=="function")return;

  // V796 renders the canonical V802 receipt UI from rr_upm_my_pending_receipts_v9112.
  // Keep that engine untouched; only pin the deeplinked assignment's batch to row 0,
  // because the existing RECEIVE GOODS bell opens receipts[0].
  const originalRpc=client.rpc.bind(client);
  client.rpc=function(name,args,options){
    const out=originalRpc(name,args,options);
    if(name!=="rr_upm_my_pending_receipts_v9112"||!out||typeof out.then!=="function")return out;
    return out.then(result=>{
      const rows=Array.isArray(result?.data?.rows)?result.data.rows:null;
      if(!rows)return result;
      const index=rows.findIndex(batch=>Array.isArray(batch?.colour_rows)&&batch.colour_rows.some(row=>String(row?.assignment_id||"")===requested));
      if(index>0){const target=rows.splice(index,1)[0];rows.unshift(target);}
      return result;
    });
  };

  let opened=false,tries=0;
  const timer=setInterval(()=>{
    if(opened||++tries>80){clearInterval(timer);return;}
    const bell=document.getElementById("rf794ReceiptBell");
    if(!bell)return;
    opened=true;
    clearInterval(timer);
    bell.click();
  },100);
})();
