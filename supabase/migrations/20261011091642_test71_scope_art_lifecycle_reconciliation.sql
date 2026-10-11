-- Narrow the existing TEST Art batch's legacy lifecycle reconciliation to its
-- authoritative purchase and related Cutting lots. Unscoped calls, including
-- REAL writes, retain their existing behavior. No gates or triggers are disabled.
do $patch$
declare d text; anchor text; replacement text;
begin
  select pg_get_functiondef('public.rr_real_chat_reconcile_dynamic_lifecycle_v101()'::regprocedure) into d;
  if position('redzed.cb_lifecycle_purchase_test71' in d)=0 then
    anchor := $old$and b.source_record_id ~* '^[0-9a-f-]{36}$';$old$;
    if (length(d)-length(replace(d,anchor,'')))/length(anchor)<>2 then
      raise exception 'Expected two dynamic lifecycle update predicates';
    end if;
    replacement := $new$and b.source_record_id ~* '^[0-9a-f-]{36}$'
  and (
    nullif(current_setting('redzed.cb_lifecycle_purchase_test71',true),'') is null
    or (b.data_mode='TEST' and (
      (b.source_module='CB_PURCHASE' and b.source_record_id=current_setting('redzed.cb_lifecycle_purchase_test71',true))
      or (b.source_module='CUTTING' and exists (
        select 1 from public.rr_upm_lot_registry scoped_lot
        join public.rr_cutting_lots_v3 scoped_cutting
          on scoped_lot.canonical_lot_id='rr_cutting_lots_v3:'||scoped_cutting.id::text
        where scoped_lot.id::text=b.source_record_id
          and scoped_cutting.cb_purchase_id::text=current_setting('redzed.cb_lifecycle_purchase_test71',true)
      ))
    ))
  );$new$;
    execute replace(d,anchor,replacement);
  end if;

  select pg_get_functiondef('public.rr_pm_save_decision_bundle_v804(uuid,uuid,text,uuid[],text,uuid[],text,uuid[],text)'::regprocedure) into d;
  if position('redzed.cb_lifecycle_purchase_test71' in d)=0 then
    anchor := '  batch_test boolean:=false;';
    if position(anchor in d)=0 then raise exception 'Expected TEST Art batch declaration'; end if;
    d:=replace(d,anchor,anchor||E'\n  lifecycle_scope_old text:=coalesce(current_setting(''redzed.cb_lifecycle_purchase_test71'',true),'''');');
    anchor := $callold$    if batch_old<>'on' and art_batch_old<>'on' then
      perform public.rr_real_chat_reconcile_dynamic_lifecycle_v101();$callold$;
    if position(anchor in d)=0 then raise exception 'Expected TEST-only lifecycle batch call'; end if;
    replacement := $callnew$    if batch_old<>'on' and art_batch_old<>'on' then
      perform set_config('redzed.cb_lifecycle_purchase_test71',coalesce(v_cb_id::text,''),true);
      perform public.rr_real_chat_reconcile_dynamic_lifecycle_v101();
      perform set_config('redzed.cb_lifecycle_purchase_test71',lifecycle_scope_old,true);$callnew$;
    execute replace(d,anchor,replacement);
  end if;
end $patch$;
