/* Add after the current Cutting Master JS. Call RR_UPM.registerReleasedLot(lot, breakupRows) after successful lot release. */
window.RR_UPM={
 async registerReleasedLot(lot,breakups=[]){
  const sb=window.supabaseClient||window.sb;if(!sb)throw new Error('Supabase unavailable');
  const sourceId=String(lot.id||lot.production_lot_id||lot.cutting_lot_id||lot.lot_id||'');
  const lotNo=String(lot.lot_no||lot.lot_number||lotNo||sourceId);
  const canonical=`${lot.lot_source||'rr_cutting_lots_v3'}:${sourceId||lotNo}`;
  const map=new Map();for(const r of breakups||[]){const code=String(r.colour_code||r.color_code||r.colour||r.color||'GENERAL');const old=map.get(code)||{colour_code:code,colour_name:r.colour_name||r.color_name||code,qty:0};old.qty+=Number(r.qty||r.quantity||r.pcs||r.total_qty||0);map.set(code,old)}
  const total=Number(lot.total_qty||lot.total_pcs||lot.qty||[...map.values()].reduce((s,x)=>s+x.qty,0));
  const {data,error}=await sb.rpc('rr_upm_register_lot_v1',{p_canonical_lot_id:canonical,p_lot_no:lotNo,p_source_table:lot.lot_source||'rr_cutting_lots_v3',p_source_id:sourceId||null,p_art_no:lot.art_no||null,p_item_name:lot.item_name||lot.product_name||null,p_total_qty:total,p_colours:[...map.values()],p_metadata:{legacy_lot:lot,bridge_version:'72040'}});if(error)throw error;return data;
 }
};
