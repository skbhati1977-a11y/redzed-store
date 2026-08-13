
(() => {
 async function searchLots(){try{const m=RF853.mode(),s=lotq.value.trim();let a=[];
 try{a=await RF853.rpc("rr_sale_universal_lot_search_v849",{p_search:s,p_limit:100,p_data_mode:m})}catch{a=await RF853.rows("rr_universal_sale_lot_v849",{limit:100})}
 RF853.table("lots",Array.isArray(a)?a:(a?.rows||[]),["lot_no","source_type","item_name","art_no","available_qty","sale_rate","data_mode"]);RF853.msg("msg","Universal lot result loaded.","ok")}catch(e){RF853.msg("msg",e.message,"error")}}
 async function boot(){try{const [b,r]=await Promise.all([RF853.rows("rr_live_commercial_binding_v849"),RF853.rows("rr_rm_stock_v849_2c6").catch(()=>[])]);
 RF853.table("bindings",b,["binding_code","target_object","target_signature","binding_status","execute_in_this_version","notes","updated_at"]);
 RF853.table("rm",r,["lot_no","item_name","qty","available_qty","purchase_rate","sale_rate","data_mode"])}catch(e){RF853.msg("msg",e.message,"error")}await searchLots()}
 searchBtn.onclick=searchLots;lotq.onkeydown=e=>{if(e.key==="Enter")searchLots()};dataMode.onchange=searchLots;boot();
})();
