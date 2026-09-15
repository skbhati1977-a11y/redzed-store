-- TEST70 V168: keep the App costing snapshot mirrored to canonical material sources.
create or replace function public.rr_upm_mirror_material_cost_v168()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_cloth jsonb;v_cut numeric:=0;v_accessory_total numeric:=0;v_mode text:='TEST';
begin
 v_cloth:=public.rr_upm_cloth_cost_context_v9300(new.canonical_lot_id);
 select coalesce(sum(cutting_qty),0)into v_cut from public.rr_upm_cut_size_rows_v726(new.lot_no);
 select coalesce(sum(total_cost),0)into v_accessory_total from public.rr_upm_costing_inputs_v9300
 where canonical_lot_id=new.canonical_lot_id and data_mode=v_mode and input_type<>'OTHER_MFG_EXP';
 new.regular_fabric_cost_per_piece:=coalesce((v_cloth->>'regular_cost_per_pc')::numeric,0);
 new.matching_cost_per_piece:=coalesce((v_cloth->>'matching_cost_per_pc')::numeric,0);
 new.other_material_cost_per_piece:=round(v_accessory_total/nullif(v_cut,0),4);
 new.material_cost_status:=case when coalesce(v_cloth->>'status','')='MAPPED'then'ACTUAL'else'MISSING'end;
 return new;
end $$;
drop trigger if exists rr_upm_mirror_material_cost_v168 on public.rr_upm_lot_costing_v760;
create trigger rr_upm_mirror_material_cost_v168 before insert or update on public.rr_upm_lot_costing_v760
for each row execute function public.rr_upm_mirror_material_cost_v168();
update public.rr_upm_lot_costing_v760 set updated_at=updated_at;
do $$declare x record;begin for x in select canonical_lot_id from public.rr_upm_lot_costing_v760 loop perform public.rr_upm_refresh_lot_costing_v760(x.canonical_lot_id);end loop;end $$;
revoke all on function public.rr_upm_mirror_material_cost_v168()from public,anon,authenticated;
comment on function public.rr_upm_mirror_material_cost_v168()is 'Mirrors canonical fabric, matching and accessory per-piece costs into the shared App/Real Chat V760 snapshot.';
