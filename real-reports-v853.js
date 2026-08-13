
(() => {
 async function go(){try{RF853.msg("msg","Analyzing…");let x;
 try{x=await RF853.rpc("rr_report_search_bridge_v807",{p_query:query.value.trim(),p_date_from:from.value||null,p_date_to:to.value||null,p_data_mode:RF853.mode()})}
 catch{ x=await RF853.rpc("rr_report_bootstrap_v807",{p_data_mode:RF853.mode()})}
 const arr=Array.isArray(x)?x:(x?.results||x?.templates||[x]);RF853.table("result",arr);RF853.msg("msg","Report result ready.","ok")}catch(e){RF853.msg("msg",e.message,"error")}}
 run.onclick=go;query.onkeydown=e=>{if(e.key==="Enter")go()};
})();
