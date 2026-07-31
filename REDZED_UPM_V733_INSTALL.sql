begin;
create or replace function public.rr_upm_lot_identity_v733(p_canonical_lot_id text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_reg public.rr_upm_lot_registry%rowtype;v_cut public.rr_cutting_lots_v3%rowtype;v_cb_no text;v_division text;v_art text;v_print text;v_frames text;
begin
 select * into v_reg from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
 if not found then raise exception 'Lot not found in Universal Production registry.'; end if;
 select * into v_cut from public.rr_cutting_lots_v3 c where c.id::text=v_reg.source_id or upper(trim(c.lot_no))=upper(trim(v_reg.lot_no)) order by case when c.id::text=v_reg.source_id then 0 else 1 end,c.created_at desc nulls last limit 1;
 if not found then raise exception 'Released Cutting Lot mapping not found for Lot %.',v_reg.lot_no; end if;
 select coalesce(nullif(trim(fp.cb_no),''),nullif(trim(u.cb_base_no),''),nullif(trim(u.cb_code),'')),coalesce(nullif(trim(u.cb_code),''),case when u.division_index is not null then 'D'||u.division_index end)
 into v_cb_no,v_division from public.rr_cb_units u left join public.rr_fabric_purchases fp on fp.id=coalesce(v_cut.cb_purchase_id,u.purchase_id) where u.id=v_cut.cb_unit_id;
 v_art:=coalesce(nullif(trim(v_cut.art_no),''),nullif(trim(v_reg.art_no),''));
 v_print:=coalesce(nullif(trim(v_cut.print_no),''),nullif(trim(v_reg.metadata->>'print_no'),''));
 if v_print is not null then
  select string_agg(distinct f.frame_no, ', ' order by f.frame_no) into v_frames
  from regexp_split_to_table(v_print,'\s*,\s*') z join public.rr_print_master pm on upper(trim(pm.print_no))=upper(trim(z))
  left join public.rr_print_frames f on f.print_id=pm.id and upper(coalesce(f.frame_status,'ACTIVE')) not in ('RETIRED','CANCELLED');
 end if;
 return jsonb_build_object('lot_no',v_reg.lot_no,'cb_no',coalesce(v_cb_no,'MAPPING REQUIRED'),'division_code',coalesce(v_division,'MAPPING REQUIRED'),'art_no',coalesce(v_art,'MAPPING REQUIRED'),'print_no',coalesce(v_print,'MAPPING REQUIRED'),'frame_no',coalesce(nullif(trim(v_frames),''),case when v_print is null then 'MAPPING REQUIRED' else 'FRAME MAPPING REQUIRED' end),'item_name',v_reg.item_name,'cutting_lot_id',v_cut.id,'identity_source','CUTTING_RELEASE_SNAPSHOT');
end $$;
grant execute on function public.rr_upm_lot_identity_v733(text) to authenticated;

create or replace function public.rr_upm_action_balance_v733(p_canonical_lot_id text,p_department_code text,p_colour_id uuid,p_colour_code text,p_size_code text)
returns table(inbound_qty numeric,direct_good_qty numeric,alter_registered_qty numeric,remake_issued_qty numeric,remake_completed_qty numeric,damage_pending_qty numeric,damage_alter_qty numeric,damage_remake_qty numeric,damage_total_qty numeric,pending_qty numeric,alter_open_qty numeric,line_man_pending_qty numeric,worker_remake_pending_qty numeric,remake_open_qty numeric,good_total_qty numeric,outbound_qty numeric,submit_ready_qty numeric)
language sql stable security definer set search_path=public as $$
with b as(select * from public.rr_upm_action_balance_v731(p_canonical_lot_id,p_department_code,p_colour_id,p_colour_code,p_size_code)),f as(select count(*)::integer flow_rows from public.rr_upm_remake_flow_v729 x where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(trim(p_department_code)) and upper(x.size_code)=upper(trim(p_size_code)) and ((p_colour_id is not null and x.colour_id=p_colour_id) or (p_colour_id is null and upper(x.colour_code)=upper(trim(p_colour_code)))))
select b.inbound_qty,b.direct_good_qty,b.alter_registered_qty,b.remake_issued_qty,b.remake_completed_qty,b.damage_pending_qty,b.damage_alter_qty,b.damage_remake_qty,b.damage_total_qty,b.pending_qty,b.alter_open_qty,case when f.flow_rows>0 then b.line_man_pending_qty else 0 end,case when f.flow_rows>0 then b.worker_remake_pending_qty else greatest(b.remake_issued_qty-b.remake_completed_qty-b.damage_remake_qty,0) end,case when f.flow_rows>0 then b.worker_remake_pending_qty else greatest(b.remake_issued_qty-b.remake_completed_qty-b.damage_remake_qty,0) end,b.good_total_qty,b.outbound_qty,b.submit_ready_qty from b cross join f;
$$;
grant execute on function public.rr_upm_action_balance_v733(text,text,uuid,text,text) to authenticated;

create or replace function public.rr_upm_universal_form_v733(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_base jsonb;v_identity jsonb;v_rows jsonb:='[]'::jsonb;v_row jsonb;v_bal record;v_summary jsonb;
begin
 v_base:=public.rr_upm_universal_form_v731(p_canonical_lot_id,p_department_code);v_identity:=public.rr_upm_lot_identity_v733(p_canonical_lot_id);
 for v_row in select value from jsonb_array_elements(coalesce(v_base->'rows','[]'::jsonb)) loop
  select * into v_bal from public.rr_upm_action_balance_v733(p_canonical_lot_id,p_department_code,nullif(v_row->>'colour_id','')::uuid,v_row->>'colour_code',v_row->>'size_code');
  v_row:=v_row||jsonb_build_object('line_man_pending_qty',v_bal.line_man_pending_qty,'worker_remake_pending_qty',v_bal.worker_remake_pending_qty,'remake_open_qty',v_bal.remake_open_qty,'remake_qty',v_bal.remake_open_qty);v_rows:=v_rows||jsonb_build_array(v_row);
 end loop;
 select jsonb_build_object('assigned',coalesce(sum((r->>'assigned_qty')::numeric),0),'inbound',coalesce(sum((r->>'inbound_qty')::numeric),0),'good',coalesce(sum((r->>'good_qty')::numeric),0),'alter',coalesce(sum((r->>'alter_open_qty')::numeric),0),'line_man_pending',coalesce(sum((r->>'line_man_pending_qty')::numeric),0),'remake',coalesce(sum((r->>'worker_remake_pending_qty')::numeric),0),'damage',coalesce(sum((r->>'damage_qty')::numeric),0),'pending',coalesce(sum((r->>'pending_qty')::numeric),0),'ready_to_submit',coalesce(sum((r->>'submit_ready_qty')::numeric),0),'outbound',coalesce(sum((r->>'outbound_qty')::numeric),0)) into v_summary from jsonb_array_elements(v_rows) r;
 return v_base||jsonb_build_object('lot',(coalesce(v_base->'lot','{}'::jsonb)||v_identity),'rows',v_rows,'summary',v_summary,'balance_version','V733_LEGACY_SAFE','identity_version','CUTTING_RELEASE_SNAPSHOT');
end $$;
grant execute on function public.rr_upm_universal_form_v733(text,text) to authenticated;

create or replace function public.rr_upm_debug_lot_flow_v733(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_context jsonb;v_identity jsonb;v_issues jsonb:='[]'::jsonb;v_workers integer;
begin
 v_identity:=public.rr_upm_lot_identity_v733(p_canonical_lot_id);v_context:=public.rr_upm_universal_form_v733(p_canonical_lot_id,p_department_code);select count(*) into v_workers from public.rr_upm_worker_list_v731(p_department_code);
 if v_identity->>'cb_no'='MAPPING REQUIRED' then v_issues:=v_issues||jsonb_build_array('CB mapping missing in released Cutting Lot'); end if;if v_identity->>'art_no'='MAPPING REQUIRED' then v_issues:=v_issues||jsonb_build_array('Art No missing in released Cutting Lot'); end if;if v_identity->>'print_no'='MAPPING REQUIRED' then v_issues:=v_issues||jsonb_build_array('Print No missing in released Cutting Lot/metadata snapshot'); end if;if v_workers=0 then v_issues:=v_issues||jsonb_build_array('No exact current-department worker is available'); end if;
 return jsonb_build_object('ok',jsonb_array_length(v_issues)=0,'issues',v_issues,'identity',v_identity,'department_code',upper(p_department_code),'exact_department_workers',v_workers,'context',v_context,'versions',jsonb_build_object('universal_form','V733','balance','V733_LEGACY_SAFE','identity','CUTTING_RELEASE_SNAPSHOT'));
end $$;
grant execute on function public.rr_upm_debug_lot_flow_v733(text,text) to authenticated;
commit;
