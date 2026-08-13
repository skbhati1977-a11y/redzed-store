
(() => {
 let cache={print:[],sticker:[],metal:[],cut:[]};
 const filter=a=>{const q=search.value.trim().toLowerCase();return !q?a:a.filter(x=>JSON.stringify(x).toLowerCase().includes(q))}
 function render(){RF853.table("print",filter(cache.print),["lot_no","print_no","print_name","live_cut_qty","required_qty","completed_qty","damage_qty","due_qty","due_status"]);
 RF853.table("sticker",filter(cache.sticker),["lot_no","sticker_no","sticker_name","live_cut_qty","required_qty","completed_qty","damage_qty","due_qty","due_status"]);
 RF853.table("metal",filter(cache.metal),["lot_no","metal_id_no","metal_id_name","live_cut_qty","required_qty","completed_qty","damage_qty","due_qty","due_status"]);
 RF853.table("cut",filter(cache.cut),["lot_no","live_cut_qty","live_qty_source","verified_cut_qty","verified_original_cut_qty","mapped_cut_qty","cutting_qty"]);
 mPrint.textContent=cache.print.reduce((s,x)=>s+Number(x.due_qty||0),0);mSticker.textContent=cache.sticker.reduce((s,x)=>s+Number(x.due_qty||0),0);mMetal.textContent=cache.metal.reduce((s,x)=>s+Number(x.due_qty||0),0);mCut.textContent=cache.cut.length}
 async function load(){try{RF853.msg("msg","Loading…");const mode=RF853.mode();const opt=mode?{eq:{data_mode:mode}}:{};const get=async(n)=>{try{return await RF853.rows(n,opt)}catch{return await RF853.rows(n)}};
 [cache.print,cache.sticker,cache.metal,cache.cut]=await Promise.all([get("rr_print_due_activation_v839"),get("rr_sticker_due_activation_v839"),get("rr_metal_id_due_activation_v839"),get("rr_cut_qty_source_audit_v839")]);render();RF853.msg("msg","Live due views loaded.","ok")}catch(e){RF853.msg("msg",e.message,"error")}}
 refresh.onclick=load;search.oninput=render;dataMode.onchange=load;load();
})();
