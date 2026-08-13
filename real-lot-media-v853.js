
(() => {
 async function refresh(){try{const m=RF853.mode(),l=lot.value.trim();const eq={data_mode:m};if(l)eq.lot_no=l;
 const [a,b,c]=await Promise.all([RF853.rows("rr_lot_media_v808",{eq,order:"created_at"}),RF853.rows("rr_lot_media_notifications_v808",{eq:{data_mode:m},order:"created_at"}),RF853.rows("rr_lot_media_events_v808",{eq,order:"event_at"})]);
 RF853.table("media",a,["lot_no","media_role","source_seq","variant_no","status","selected_by_admin","is_published","storage_bucket","storage_path","created_at"]);
 RF853.table("notes",b,["lot_no","notification_type","ready_count","status","created_at","opened_at","actioned_at"]);
 RF853.table("events",c,["lot_no","event_type","actor_role","event_at","details"]);RF853.msg("msg",`${a.length} media rows loaded.`,"ok")}catch(e){RF853.msg("msg",e.message,"error")}}
 load.onclick=refresh;dataMode.onchange=refresh;refresh();
})();
