create or replace function public.rr_cb_material_mapping_sync_v5(p_cb_id uuid,p_materials jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  m jsonb; e uuid; u record; wanted int[]; allowed uuid[]; n int:=0; dup record; set_cat uuid; set_code text;
begin
  perform public.rr_cb_department_assert_authority_v600();
  if p_cb_id is null then raise exception 'CB required.'; end if;
  select category_id,count(*) into dup
  from (select nullif(x.value->>'category_id','')::uuid category_id from jsonb_array_elements(coalesce(p_materials,'[]'::jsonb)) x) z
  where category_id is not null group by category_id having count(*)>1 limit 1;
  if dup.category_id is not null then raise exception 'This Material is already added in another Material card. Use the existing Material card.'; end if;

  for m in select value from jsonb_array_elements(coalesce(p_materials,'[]'::jsonb)) loop
    e:=nullif(m->>'id','')::uuid;
    if e is null then select id into e from public.rr_cb_purchase_entries where cb_id=p_cb_id and client_key=nullif(m->>'client_key','')::uuid limit 1; end if;
    if e is null then continue; end if;
    wanted:=coalesce(array(select jsonb_array_elements_text(coalesce(m->'selected_sets','[]'::jsonb))::int),'{}');
    allowed:=coalesce(array(select jsonb_array_elements_text(coalesce(m->'allowed_art_category_ids','[]'::jsonb))::uuid),'{}');

    update public.rr_cb_purchase_entries set allowed_art_category_ids=allowed,allocation_scope='selected' where id=e and cb_id=p_cb_id;
    delete from public.rr_cb_material_allocations where purchase_entry_id=e;
    delete from public.rr_cb_material_usage_v1 where purchase_entry_id=e;

    for u in
      select cu.id,cu.division_index,coalesce(sr.art_category_id,cu.garment_category_id) as effective_category_id
      from public.rr_cb_units cu
      left join public.rr_cb_set_requirement_v1 sr on sr.cb_unit_id=cu.id
      where cu.purchase_id=p_cb_id and coalesce(cu.is_final,true) and cu.division_index=any(wanted)
    loop
      set_cat:=u.effective_category_id;
      select lower(category_code) into set_code from public.rr_art_categories where id=set_cat;
      if set_code='self-collar' then raise exception 'S% Self Collar is Direct Material N/A. Additional Material cannot be linked.',u.division_index; end if;
      if cardinality(allowed)>0 and set_cat is not null and not (set_cat=any(allowed)) then
        raise exception 'S% Category is outside this Material allowed categories.',u.division_index;
      end if;
      insert into public.rr_cb_material_allocations(purchase_entry_id,division_id,material_category_id,allowed_art_category_ids)
      select e,u.id,p.material_category_id,allowed from public.rr_cb_purchase_entries p where p.id=e;
      n:=n+1;
    end loop;
  end loop;

  return jsonb_build_object('ok',true,'allocation_count',n,'usage_mapping','RETIRED_CANONICAL_CB_CONSTRUCTION','self_collar_direct_guard',true);
end $$;

revoke all on function public.rr_cb_material_mapping_sync_v5(uuid,jsonb) from public,anon;
grant execute on function public.rr_cb_material_mapping_sync_v5(uuid,jsonb) to authenticated;
