-- TEST70 V166: canonical Packing rate costing + suggestion/approval mirror.

create or replace function public.rr_pack_rate_context_universal_v9405(
  p_lot_no text,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_lot text:=trim(p_lot_no);
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));
  v_canonical text;
  v_old jsonb;
  v_cloth jsonb;
  v_qty numeric:=0;
  v_source numeric:=0;
  v_base numeric:=0;
  v_margin numeric:=0;
  v_sale numeric:=0;
  v_material_pc numeric:=0;
  v_process_pc numeric:=0;
  v_other_pc numeric:=0;
  v_complete boolean:=false;
  v_missing jsonb:='[]'::jsonb;
begin
  perform public.rr_fg_assert_user_v787();

  select canonical_lot_id into v_canonical
  from public.rr_upm_lot_registry
  where upper(trim(lot_no))=upper(v_lot)
  limit 1;

  if v_canonical is not null then
    begin
      v_old:=public.rr_upm_costing_context_v9300(v_canonical,v_mode);
      v_qty:=coalesce((v_old->>'cut_qty')::numeric,0);
      v_cloth:=coalesce(v_old->'cloth','{}'::jsonb);
      v_material_pc:=round(coalesce((v_old->>'material_total')::numeric,0)/nullif(v_qty,0),4);
      v_process_pc:=coalesce((v_old->>'process_total')::numeric,0);
      v_other_pc:=round(coalesce((v_old->>'other_mfg_total')::numeric,0)/nullif(v_qty,0),4);
      v_margin:=coalesce((v_old->>'owner_margin_per_pc')::numeric,22);
      v_base:=round(v_material_pc+v_process_pc+v_other_pc,4);
      v_sale:=round(v_base+v_margin,2);
      v_complete:=coalesce(v_cloth->>'status','')='MAPPED';
      if coalesce(v_cloth->>'status','')<>'MAPPED' then
        v_missing:=v_missing||jsonb_build_array('REGULAR_CLOTH');
      end if;
    exception when others then
      v_qty:=0;
      v_complete:=false;
      v_missing:=v_missing||jsonb_build_array('COSTING_CONTEXT');
    end;
    if v_qty<=0 then
      select coalesce(max(ready_qty),0) into v_qty
      from public.rr_fg_packing_assignments_v788
      where data_mode=v_mode and upper(trim(lot_no))=upper(v_lot);
    end if;
    if v_sale>0 and v_qty>0 then
      return jsonb_build_object(
        'ok',v_complete,'costing_complete',v_complete,'missing',v_missing,
        'path','UPM_COSTING_CORRECTED_V166','canonical_lot_id',v_canonical,'qty',v_qty,
        'material_cost_per_pc',round(v_material_pc,2),'process_cost_per_pc',round(v_process_pc,2),
        'other_mfg_cost_per_pc',round(v_other_pc,2),'base_cost_per_pc',round(v_base,2),
        'owner_margin_per_pc',round(v_margin,2),
        'calculated_sale_rate',round(v_sale,2),'source_rate',round(v_sale,0),
        'approval_rounding','WHOLE_RUPEE','cloth',v_cloth,
        'department_rates',coalesce(v_old->'department_rates','[]'::jsonb),
        'inputs',coalesce(v_old->'inputs','[]'::jsonb)
      );
    end if;
  end if;

  select coalesce(nullif(base_sale_rate,0),nullif(final_sale_rate,0)),qty_snapshot,canonical_lot_id
  into v_source,v_qty,v_canonical
  from public.rrq_lot_rates_v9300
  where data_mode=v_mode and upper(trim(lot_no))=upper(v_lot)
    and qty_snapshot>0 and coalesce(nullif(base_sale_rate,0),nullif(final_sale_rate,0))>0
  order by updated_at desc nulls last limit 1;
  if coalesce(v_source,0)>0 and coalesce(v_qty,0)>0 then
    return jsonb_build_object('ok',true,'path','RRQ','canonical_lot_id',v_canonical,'qty',v_qty,
      'base_cost_per_pc',null,'owner_margin_per_pc',null,'calculated_sale_rate',v_source,
      'source_rate',round(v_source,0),'approval_rounding','WHOLE_RUPEE');
  end if;

  select source_rate,qty_snapshot into v_source,v_qty
  from public.rr_pack_rate_approval_v9340
  where data_mode=v_mode and upper(trim(lot_no))=upper(v_lot) and source_rate>0 and qty_snapshot>0
  order by updated_at desc nulls last limit 1;
  if coalesce(v_source,0)>0 and coalesce(v_qty,0)>0 then
    return jsonb_build_object('ok',true,'path','APPROVAL_HISTORY','canonical_lot_id',v_canonical,'qty',v_qty,
      'base_cost_per_pc',null,'owner_margin_per_pc',null,'calculated_sale_rate',v_source,
      'source_rate',round(v_source,0),'approval_rounding','WHOLE_RUPEE');
  end if;
  return jsonb_build_object('ok',false,'path','NONE','canonical_lot_id',v_canonical,'qty',0,'source_rate',0);
end;
$$;

create or replace function public.rr_pack_rate_status_v9340(p_lot_no text,p_data_mode text default 'TEST')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare r record; v_art text;
begin
  perform public.rr_fg_assert_user_v787();
  select * into r from public.rr_pack_rate_approval_v9340
  where data_mode=upper(p_data_mode) and lot_no=trim(p_lot_no);
  if not found then
    return jsonb_build_object('lot_no',trim(p_lot_no),'status','NOT_REQUESTED','approved',false,'art_code',null);
  end if;
  if r.status='APPROVED' then v_art:=public.rr_pack_art_code_v9340(r.final_rate); end if;
  return jsonb_build_object(
    'lot_no',r.lot_no,'status',r.status,'approved',r.status='APPROVED','art_code',v_art,
    'source_rate',r.source_rate,'suggested_rate',r.suggested_rate,
    'sales_suggested_rate',r.sales_suggested_rate,'admin_suggested_rate',r.admin_suggested_rate,
    'final_rate',r.final_rate,'qty',r.qty_snapshot,
    'requested_at',r.requested_at,'suggested_at',r.suggested_at,'approved_at',r.approved_at
  );
end;
$$;

create or replace function public.rr_pack_rate_suggest_v9340(
  p_lot_no text,p_suggested_rate numeric,p_data_mode text default 'TEST'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text:=lower(coalesce(public.rr_current_role(),'')); v_kind text;
begin
  if v_role not in ('owner','accounts','sales') then raise exception 'Sales/Admin/Super Admin access required'; end if;
  if p_suggested_rate is null or p_suggested_rate<=0 or p_suggested_rate<>round(p_suggested_rate,0) then
    raise exception 'Suggested rate must be whole rupee';
  end if;
  v_kind:=case when v_role='sales' then 'SALES' else 'ADMIN' end;
  update public.rr_pack_rate_approval_v9340 set
    sales_suggested_rate=case when v_kind='SALES' then p_suggested_rate else sales_suggested_rate end,
    sales_suggested_by=case when v_kind='SALES' then auth.uid() else sales_suggested_by end,
    sales_suggested_at=case when v_kind='SALES' then now() else sales_suggested_at end,
    admin_suggested_rate=case when v_kind='ADMIN' then p_suggested_rate else admin_suggested_rate end,
    admin_suggested_by=case when v_kind='ADMIN' then auth.uid() else admin_suggested_by end,
    admin_suggested_at=case when v_kind='ADMIN' then now() else admin_suggested_at end,
    suggested_rate=p_suggested_rate,suggested_by=auth.uid(),suggested_at=now(),status='SUGGESTED',updated_at=now()
  where data_mode=upper(p_data_mode) and lot_no=trim(p_lot_no) and status<>'APPROVED';
  if not found then raise exception 'Rate request not found or already approved'; end if;
  return jsonb_build_object('ok',true,'suggestion_type',v_kind,'suggested_rate',p_suggested_rate);
end;
$$;

-- Repair only complete, still-open UPM requests; approved audit history is immutable.
update public.rr_pack_rate_approval_v9340 r
set source_rate=round(c.final_sale_price,0),updated_at=now()
from public.rr_upm_lot_registry l
join public.rr_upm_lot_costing_v760 c on c.canonical_lot_id=l.canonical_lot_id
where upper(trim(r.lot_no))=upper(trim(l.lot_no))
  and r.status<>'APPROVED' and coalesce(c.final_sale_price,0)>0
  and coalesce(c.regular_fabric_cost_per_piece,0)>0
  and r.source_rate is distinct from round(c.final_sale_price,0);

revoke all on function public.rr_pack_rate_context_universal_v9405(text,text) from public,anon;
revoke all on function public.rr_pack_rate_status_v9340(text,text) from public,anon;
revoke all on function public.rr_pack_rate_suggest_v9340(text,numeric,text) from public,anon;
grant execute on function public.rr_pack_rate_context_universal_v9405(text,text) to authenticated;
grant execute on function public.rr_pack_rate_status_v9340(text,text) to authenticated;
grant execute on function public.rr_pack_rate_suggest_v9340(text,numeric,text) to authenticated;

comment on function public.rr_pack_rate_context_universal_v9405(text,text) is
  'V166: canonical V760 base cost + owner margin drives Packing mapped sale suggestion.';
