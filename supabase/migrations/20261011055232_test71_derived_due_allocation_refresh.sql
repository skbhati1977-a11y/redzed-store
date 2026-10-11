-- Rebuild only calculated, unconfirmed Art-combo allocations before changing
-- their calculated quantity. The immutable purchase-entry trigger remains intact.
DO $patch$
DECLARE d text; old_deactivate text;new_deactivate text;old_refresh text;new_refresh text;
BEGIN
 SELECT pg_get_functiondef('public.rr_cb_refresh_derived_requirements_core_v1(uuid)'::regprocedure) INTO d;
 IF position('TEST71_DERIVED_DUE_ALLOCATION_REFRESH' IN d)>0 THEN RETURN;END IF;
 old_deactivate:=$old$  update public.rr_cb_purchase_entries e
  set requirement_state='NOT REQUIRED',quantity=0,updated_at=now()$old$;
 new_deactivate:=$new$  -- TEST71_DERIVED_DUE_ALLOCATION_REFRESH
  delete from public.rr_cb_material_allocations a
  using public.rr_cb_purchase_entries e
  where a.purchase_entry_id=e.id and e.cb_id=p_cb_id
    and e.entry_notes='AUTO ART COMBO MATERIAL' and e.requirement_state='DUE'
    and not exists(
      select 1 from public.rr_cb_derived_requirement_v1 r
      where r.cb_id=p_cb_id and r.active and r.requirement_type='MATERIAL'
        and r.source_id=e.material_category_id and r.required_qty>0
    );

  update public.rr_cb_purchase_entries e
  set requirement_state='NOT REQUIRED',quantity=0,updated_at=now()$new$;
 old_refresh:=$old$    else
      update public.rr_cb_purchase_entries
      set quantity=case when entry_notes='AUTO ART COMBO MATERIAL' and requirement_state<>'CONFIRMED' then total_qty else quantity end,$old$;
 new_refresh:=$new$    else
      delete from public.rr_cb_material_allocations a
      using public.rr_cb_purchase_entries e
      where a.purchase_entry_id=e.id and e.id=entry_id
        and e.entry_notes='AUTO ART COMBO MATERIAL' and e.requirement_state<>'CONFIRMED';
      update public.rr_cb_purchase_entries
      set quantity=case when entry_notes='AUTO ART COMBO MATERIAL' and requirement_state<>'CONFIRMED' then total_qty else quantity end,$new$;
 IF position(old_deactivate IN d)=0 OR position(old_refresh IN d)=0 THEN
  RAISE EXCEPTION 'Derived-requirement function changed; refusing an ambiguous patch';
 END IF;
 d:=replace(replace(d,old_deactivate,new_deactivate),old_refresh,new_refresh);
 EXECUTE d;
END;$patch$;
