create or replace function public.rr_pm_save_decision_bundle_v804(
  p_cb_unit_id uuid,
  p_art_id uuid,
  p_print_mode text default 'NA',
  p_print_ids uuid[] default '{}'::uuid[],
  p_sticker_mode text default 'NA',
  p_sticker_master_ids uuid[] default '{}'::uuid[],
  p_metal_id_mode text default 'NA',
  p_metal_id_master_ids uuid[] default '{}'::uuid[],
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path=public
set statement_timeout='30s'
as $$
declare
  v_sticker_instruction_ids uuid[]:='{}'::uuid[];
  v_metal_instruction_ids uuid[]:='{}'::uuid[];
  v_id uuid;
  v_result jsonb;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  i integer:=0;
begin
  if not public.rr_is_owner_or_admin() then raise exception 'Owner/Admin permission required.'; end if;
  if p_cb_unit_id is null then raise exception 'CB/D required.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('RR_ART_DECISION:'||p_cb_unit_id::text,611));
  if exists(select 1 from public.rr_cutting_lots_v3 where cb_unit_id=p_cb_unit_id)
     or exists(select 1 from public.rr_production_lots where cb_unit_id=p_cb_unit_id) then
    raise exception 'CB Set Art Combo is locked after Cutting Lot release.';
  end if;
  if v_mode not in ('TEST','REAL') then raise exception 'Data Mode must be TEST or REAL.'; end if;
  if upper(trim(coalesce(p_sticker_mode,'NA')))='SELECTED' then
    foreach v_id in array coalesce(p_sticker_master_ids,'{}'::uuid[]) loop
      i:=i+1;
      v_sticker_instruction_ids:=array_append(v_sticker_instruction_ids,public.rr_sticker_instruction_for_master_v804(p_art_id,v_id,i));
    end loop;
  end if;
  i:=0;
  if upper(trim(coalesce(p_metal_id_mode,'NA')))='SELECTED' then
    foreach v_id in array coalesce(p_metal_id_master_ids,'{}'::uuid[]) loop
      i:=i+1;
      v_metal_instruction_ids:=array_append(v_metal_instruction_ids,public.rr_metal_id_instruction_for_master_v804(p_art_id,v_id,i));
    end loop;
  end if;
  v_result:=public.rr_pm_save_decision_bundle_v802_2(
    p_cb_unit_id,p_art_id,p_print_mode,p_print_ids,
    p_sticker_mode,v_sticker_instruction_ids,
    p_metal_id_mode,v_metal_instruction_ids
  );
  perform public.rr_cb_reconcile_department_states_v618();
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'sticker_master_ids',coalesce(p_sticker_master_ids,'{}'::uuid[]),
    'metal_id_master_ids',coalesce(p_metal_id_master_ids,'{}'::uuid[]),
    'data_mode',v_mode,'combo_authority','CB_SET','locked_after_lot',true
  );
end
$$;
revoke all on function public.rr_pm_save_decision_bundle_v804(uuid,uuid,text,uuid[],text,uuid[],text,uuid[],text) from public,anon;
grant execute on function public.rr_pm_save_decision_bundle_v804(uuid,uuid,text,uuid[],text,uuid[],text,uuid[],text) to authenticated;
