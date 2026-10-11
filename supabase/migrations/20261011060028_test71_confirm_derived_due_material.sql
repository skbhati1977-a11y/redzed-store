-- Authorized DUE completion rebuilds provisional allocations atomically.
-- Confirmed purchases retain the existing immutable quantity/rate trigger.
DO $patch$
DECLARE d text;old_update text;new_update text;
BEGIN
 SELECT pg_get_functiondef('public.rr_cb_department_save_v600(uuid,uuid,boolean,jsonb)'::regprocedure) INTO d;
 IF position('TEST71_DUE_CONFIRM_ALLOCATION_REFRESH' IN d)>0 THEN RETURN;END IF;
 old_update:=$old$    else
      update public.rr_cb_purchase_entries set
        vendor_name=nullif(trim(entry_row->>'vendor'),''),$old$;
 new_update:=$new$    else
      -- TEST71_DUE_CONFIRM_ALLOCATION_REFRESH
      delete from public.rr_cb_material_allocations a
      using public.rr_cb_purchase_entries e
      where a.purchase_entry_id=e.id and e.id=entry_id and e.cb_id=cb
        and e.requirement_state='DUE';
      update public.rr_cb_purchase_entries set
        vendor_name=nullif(trim(entry_row->>'vendor'),''),$new$;
 IF (length(d)-length(replace(d,old_update,'')))/length(old_update)<>1 THEN
  RAISE EXCEPTION 'CB save function changed; refusing an ambiguous patch';
 END IF;
 EXECUTE replace(d,old_update,new_update);
END;$patch$;
