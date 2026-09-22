-- TEST71 V620: include canonical material allocations in the exact-marker
-- V619 fixture cleanup. No business record is named or patched.
begin;

do $patch$
declare
  d text;
  anchor text := $old$    delete from public.rr_cb_department_audit_v600 where cb_id=v_cb;
    delete from public.rr_cb_purchase_rolls where division_id=any(coalesce(v_units,'{}'::uuid[]));$old$;
  replacement text := $new$    delete from public.rr_cb_department_audit_v600 where cb_id=v_cb;
    delete from public.rr_cb_material_allocations
    where division_id=any(coalesce(v_units,'{}'::uuid[]))
      or purchase_entry_id in(select id from public.rr_cb_purchase_entries where cb_id=v_cb);
    delete from public.rr_cb_purchase_rolls where division_id=any(coalesce(v_units,'{}'::uuid[]));$new$;
begin
  select replace(pg_get_functiondef(
    'public.rr_test_cb_ui_fixture_v619(text,uuid)'::regprocedure
  ),chr(13),'') into d;
  if position('delete from public.rr_cb_material_allocations' in d)>0 then return; end if;
  if position(anchor in d)=0 then
    raise exception 'V620 refused: V619 cleanup signature changed';
  end if;
  execute replace(d,anchor,replacement);
end
$patch$;

notify pgrst,'reload schema';
commit;
