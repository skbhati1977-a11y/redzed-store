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

-- ============================================================================
-- V734: Good Qty visual model + mapped responsibility details in summary.
-- Identity V733 is intentionally preserved unchanged.
-- ============================================================================
begin;

create or replace function public.rr_upm_responsibility_summary_v734(
  p_canonical_lot_id text,p_department_code text
)
returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare v_department_name text;v_result jsonb;
begin
  select department_name into v_department_name
  from public.rr_upm_departments
  where upper(department_code)=upper(trim(p_department_code)) limit 1;

  with damage_by_row as(
    select upper(a.colour_code) colour_code,upper(a.size_code) size_code,
      coalesce(sum(a.qty) filter(where upper(coalesce(a.source_bucket,'PENDING'))='ALTER'),0)::numeric damage_alter,
      coalesce(sum(a.qty) filter(where upper(coalesce(a.source_bucket,'PENDING'))='REMAKE'),0)::numeric damage_remake
    from public.rr_upm_actions_v726 a
    where a.canonical_lot_id=p_canonical_lot_id
      and upper(a.department_code)=upper(trim(p_department_code))
      and a.action_type='DAMAGE'
    group by upper(a.colour_code),upper(a.size_code)
  ), flow_cards as(
    select 'ALTER_PENDING'::text pending_type,
      greatest(f.alter_qty-f.remake_issued_qty-coalesce(d.damage_alter,0),0)::numeric qty,
      f.cutting_master_id responsible_person_id,f.cutting_master_name responsible_name,
      coalesce(ua.worker_code,'') responsible_worker_code,'CUTTING_MASTER'::text responsible_role,
      upper(f.department_code) department_code,coalesce(v_department_name,upper(f.department_code)) department_name,
      f.colour_code,f.colour_name,f.size_code,f.lot_no,f.created_at
    from public.rr_upm_remake_flow_v729 f
    left join damage_by_row d on d.colour_code=upper(f.colour_code) and d.size_code=upper(f.size_code)
    left join public.rr_user_assignments_v2 ua on ua.user_id=f.cutting_master_id
    where f.canonical_lot_id=p_canonical_lot_id and upper(f.department_code)=upper(trim(p_department_code))

    union all
    select 'LINE_MAN_PENDING',greatest(f.remake_issued_qty-f.remake_delivered_qty,0),
      f.line_man_id,f.line_man_name,coalesce(ua.worker_code,''),'LINE_MAN',upper(f.department_code),
      coalesce(v_department_name,upper(f.department_code)),f.colour_code,f.colour_name,f.size_code,f.lot_no,f.updated_at
    from public.rr_upm_remake_flow_v729 f
    left join public.rr_user_assignments_v2 ua on ua.user_id=f.line_man_id
    where f.canonical_lot_id=p_canonical_lot_id and upper(f.department_code)=upper(trim(p_department_code))

    union all
    select 'WORKER_REMAKE_PENDING',greatest(f.remake_delivered_qty-f.remake_submitted_qty-coalesce(d.damage_remake,0),0),
      f.worker_id,f.worker_name,coalesce(fa.worker_code,''),'WORKER',upper(f.department_code),
      coalesce(v_department_name,upper(f.department_code)),f.colour_code,f.colour_name,f.size_code,f.lot_no,f.updated_at
    from public.rr_upm_remake_flow_v729 f
    left join damage_by_row d on d.colour_code=upper(f.colour_code) and d.size_code=upper(f.size_code)
    left join public.rr_upm_work_assignments_v8 fa on fa.id=f.assignment_id
    where f.canonical_lot_id=p_canonical_lot_id and upper(f.department_code)=upper(trim(p_department_code))
  ), damage_cards as(
    select 'DAMAGE'::text pending_type,sum(a.qty)::numeric qty,
      case upper(coalesce(a.source_bucket,'PENDING'))
        when 'ALTER' then max(f.cutting_master_id)
        when 'REMAKE' then max(case when f.remake_delivered_qty>0 then f.worker_id else f.line_man_id end)
        else max(a.worker_id) end responsible_person_id,
      case upper(coalesce(a.source_bucket,'PENDING'))
        when 'ALTER' then max(f.cutting_master_name)
        when 'REMAKE' then max(case when f.remake_delivered_qty>0 then f.worker_name else f.line_man_name end)
        else max(a.worker_name) end responsible_name,
      case upper(coalesce(a.source_bucket,'PENDING'))
        when 'ALTER' then coalesce(max(uc.worker_code),'')
        when 'REMAKE' then coalesce(max(case when f.remake_delivered_qty>0 then wa.worker_code else ul.worker_code end),'')
        else coalesce(max(a.worker_code),'') end responsible_worker_code,
      case upper(coalesce(a.source_bucket,'PENDING'))
        when 'ALTER' then 'CUTTING_MASTER'
        when 'REMAKE' then case when max(coalesce(f.remake_delivered_qty,0))>0 then 'WORKER' else 'LINE_MAN' end
        else 'WORKER' end responsible_role,
      upper(a.department_code) department_code,coalesce(v_department_name,upper(a.department_code)) department_name,
      a.colour_code,max(a.colour_name) colour_name,a.size_code,max(a.lot_no) lot_no,min(a.created_at) created_at
    from public.rr_upm_actions_v726 a
    left join public.rr_upm_remake_flow_v729 f on f.canonical_lot_id=a.canonical_lot_id
      and upper(f.department_code)=upper(a.department_code) and upper(f.colour_code)=upper(a.colour_code) and upper(f.size_code)=upper(a.size_code)
    left join public.rr_user_assignments_v2 uc on uc.user_id=f.cutting_master_id
    left join public.rr_user_assignments_v2 ul on ul.user_id=f.line_man_id
    left join public.rr_upm_work_assignments_v8 wa on wa.id=f.assignment_id
    where a.canonical_lot_id=p_canonical_lot_id
      and upper(a.department_code)=upper(trim(p_department_code)) and a.action_type='DAMAGE'
    group by upper(coalesce(a.source_bucket,'PENDING')),upper(a.department_code),a.colour_code,a.size_code
  ), cards as(
    select * from flow_cards where qty>0
    union all select * from damage_cards where qty>0
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'pending_type',pending_type,'qty',qty,'responsible_person_id',responsible_person_id,
    'responsible_name',coalesce(nullif(trim(responsible_name),''),'MAPPING REQUIRED'),
    'responsible_worker_code',nullif(trim(responsible_worker_code),''),
    'responsible_role',responsible_role,'department_code',department_code,'department_name',department_name,
    'colour_code',colour_code,'colour_name',colour_name,'size_code',size_code,'lot_no',lot_no,'created_at',created_at
  ) order by pending_type,colour_name,size_code),'[]'::jsonb) into v_result from cards;
  return v_result;
end $$;

grant execute on function public.rr_upm_responsibility_summary_v734(text,text) to authenticated;

create or replace function public.rr_upm_universal_form_v734(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql stable security definer set search_path=public
as $$
declare v_base jsonb;v_rows jsonb:='[]'::jsonb;v_row jsonb;v_main numeric;v_good numeric;v_summary jsonb;v_responsibility jsonb;
begin
  v_base:=public.rr_upm_universal_form_v733(p_canonical_lot_id,p_department_code);
  for v_row in select value from jsonb_array_elements(coalesce(v_base->'rows','[]'::jsonb)) loop
    v_main:=coalesce((v_row->>'cutting_qty')::numeric,0);
    v_good:=greatest(v_main
      -coalesce((v_row->>'alter_open_qty')::numeric,0)
      -coalesce((v_row->>'line_man_pending_qty')::numeric,0)
      -coalesce((v_row->>'worker_remake_pending_qty')::numeric,0)
      -coalesce((v_row->>'damage_qty')::numeric,0),0);
    v_row:=v_row||jsonb_build_object('main_qty',v_main,'good_qty',v_good,'good_qty_model','MAIN_MINUS_OPEN_EXCEPTION_BUCKETS');
    v_rows:=v_rows||jsonb_build_array(v_row);
  end loop;
  select jsonb_build_object(
    'main',coalesce(sum((r->>'main_qty')::numeric),0),
    'good',coalesce(sum((r->>'good_qty')::numeric),0),
    'alter',coalesce(sum((r->>'alter_open_qty')::numeric),0),
    'line_man_pending',coalesce(sum((r->>'line_man_pending_qty')::numeric),0),
    'remake',coalesce(sum((r->>'worker_remake_pending_qty')::numeric),0),
    'damage',coalesce(sum((r->>'damage_qty')::numeric),0)
  ) into v_summary from jsonb_array_elements(v_rows) r;
  v_responsibility:=public.rr_upm_responsibility_summary_v734(p_canonical_lot_id,p_department_code);
  return v_base||jsonb_build_object('rows',v_rows,'summary',v_summary,'responsibility_summary',v_responsibility,
    'display_model','GOOD_QTY_BASE','balance_equation','MAIN = GOOD + ALTER + LINE_MAN + WORKER_REMAKE + DAMAGE','version','V734');
end $$;

grant execute on function public.rr_upm_universal_form_v734(text,text) to authenticated;

create or replace function public.rr_upm_debug_lot_flow_v734(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql stable security definer set search_path=public
as $$
declare v_context jsonb;v_identity jsonb;
begin
  v_context:=public.rr_upm_universal_form_v734(p_canonical_lot_id,p_department_code);
  v_identity:=public.rr_upm_lot_identity_v733(p_canonical_lot_id);
  return jsonb_build_object('ok',true,'issues','[]'::jsonb,'identity',v_identity,'context',v_context,
    'department_code',upper(p_department_code),'versions',jsonb_build_object('universal_form','V734','identity','V733_CUTTING_RELEASE_SNAPSHOT','display','GOOD_QTY_BASE','responsibility','MAPPED_SNAPSHOT'));
end $$;

grant execute on function public.rr_upm_debug_lot_flow_v734(text,text) to authenticated;
commit;
