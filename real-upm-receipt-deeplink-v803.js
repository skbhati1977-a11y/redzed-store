(()=>{
  "use strict";
  const params=new URLSearchParams(location.search);
  const requested=String(params.get("rrAssignmentReceipt")||"").trim();
  if(!requested)return;
  const client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  if(!client||typeof client.rpc!=="function")return;

  // Exact assignment -> exact canonical receipt.
  // No receipts[0] reorder and no synthetic RECEIVE GOODS bell click.
  let opened=false,tries=0;

  const timer=setInterval(async()=>{
    if(opened||++tries>80){
      clearInterval(timer);
      return;
    }

    const bridge=window.RR&&window.RR.openExactAssignmentReceipt;
    if(typeof bridge!=="function") return;

    try{
      const result=await client.rpc("rr_upm_my_pending_receipts_v9112");
      if(result?.error) throw result.error;

      const batches=Array.isArray(result?.data?.rows)
        ? result.data.rows
        : Array.isArray(result?.data)
          ? result.data
          : [];

      const exact=batches.find(batch=>
        Array.isArray(batch?.colour_rows) &&
        batch.colour_rows.some(row=>
          String(row?.assignment_id||"")===requested
        )
      );

      if(!exact) return;

      opened=true;
      clearInterval(timer);
      bridge(exact);
    }catch(err){
      console.warn("Exact receipt deeplink",err);
    }
  },100);

})();
