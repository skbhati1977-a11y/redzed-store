-- REDZED Universal Production V732 (actual source integration)
-- Resolves: Product Master identity, exact current-department workers,
-- bucket-wise damage, and real Remake Issue -> Delivered -> Submit custody.
-- Run after the existing V726/V727 and V729 objects are installed.

begin;

create extension if not exists pgcrypto;

-- --------------------------------------------------------------------------
-- 1) Product Master -> Cutting identity resolver
-- --------------------------------------------------------------------------
create or replace function public.rr_upm_lot_identity_v731(p_canonical_lot_id text)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_reg public.rr_upm_lot_registry%rowtype;
  v_cut public.rr_cutting_lots_v3%rowtype;
  v_product_id uuid;
  v_art_no text;
  v_prints text;
  v_frames text;
  v_cb_no text;
  v_division text;
  v_has_product_link boolean:=false;
begin
  select * into v_reg
  from public.rr_upm_lot_registry
  where canonical_lot_id=p_canonical_lot_id
  limit 1;
  if not found then raise exception 'Lot not found in Universal Production registry.'; end if;

  select * into v_cut
  from public.rr_cutting_lots_v3 c
  where c.id::text=v_reg.source_id
     or upper(trim(c.lot_no))=upper(trim(v_reg.lot_no))
  order by case when c.id::text=v_reg.source_id then 0 else 1 end,
           c.created_at desc nulls last
  limit 1;
  if not found then raise exception 'Released Cutting Lot mapping not found for Lot %.',v_reg.lot_no; end if;

  select coalesce(nullif(trim(fp.cb_no),''),nullif(trim(u.cb_base_no),''),nullif(trim(u.cb_code),'')),
         coalesce(nullif(trim(u.cb_code),''),case when u.division_index is not null then 'D'||u.division_index end)
    into v_cb_no,v_division
  from public.rr_cb_units u
  left join public.rr_fabric_purchases fp on fp.id=coalesce(v_cut.cb_purchase_id,u.purchase_id)
  where u.id=v_cut.cb_unit_id;

  -- Product Master is the source of truth. The dynamic guards prevent installation
  -- from guessing a column that does not exist in a particular deployment.
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='rr_product_master' and column_name='id')
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='rr_product_master' and column_name='lot_no') then
    execute 'select id from public.rr_product_master where upper(trim(lot_no))=upper(trim($1)) order by updated_at desc nulls last, created_at desc nulls last limit 1'
      into v_product_id using v_reg.lot_no;
  end if;

  if v_product_id is not null then
    v_has_product_link:=true;

    if exists(select 1 from information_schema.columns where table_schema='public' and table_name='rr_product_master' and column_name='art_id') then
      execute 'select a.art_no from public.rr_product_master p join public.rr_art_master a on a.id=p.art_id where p.id=$1 limit 1'
        into v_art_no using v_product_id;
    end if;

    if exists(select 1 from information_schema.columns where table_schema='public' and table_name='rr_product_print_links' and column_name='product_id')
       and exists(select 1 from information_schema.columns where table_schema='public' and table_name='rr_product_print_links' and column_name='print_id') then
      execute $q$
        select string_agg(distinct pm.print_no, ', ' order by pm.print_no)
        from public.rr_product_print_links l
        join public.rr_print_master pm on pm.id=l.print_id
        where l.product_id=$1 and coalesce(pm.is_active,true)
      $q$ into v_prints using v_product_id;

      execute $q$
        select string_agg(distinct f.frame_no, ', ' order by f.frame_no)
        from public.rr_product_print_links l
        join public.rr_print_master pm on pm.id=l.print_id
        join public.rr_print_frames f on f.print_id=pm.id
        where l.product_id=$1
          and coalesce(pm.is_active,true)
          and upper(coalesce(f.frame_status,'ACTIVE')) not in ('RETIRED','CANCELLED')
      $q$ into v_frames using v_product_id;
    end if;
  end if;

  return jsonb_build_object(
    'lot_no',v_reg.lot_no,
    'cb_no',coalesce(v_cb_no,'MAPPING REQUIRED'),
    'division_code',coalesce(v_division,'MAPPING REQUIRED'),
    'art_no',coalesce(nullif(trim(v_art_no),''),'MAPPING REQUIRED'),
    'print_no',case when v_has_product_link then coalesce(nullif(trim(v_prints),''),'PRINT NOT APPLICABLE') else 'PRODUCT MASTER MAPPING REQUIRED' end,
    'frame_no',case when v_has_product_link then coalesce(nullif(trim(v_frames),''),'FRAME NOT APPLICABLE') else 'PRODUCT MASTER MAPPING REQUIRED' end,
    'item_name',v_reg.item_name,
    'product_id',v_product_id,
    'cutting_lot_id',v_cut.id,
    'identity_source','PRODUCT_MASTER_TO_CUTTING'
  );
end $$;

grant execute on function public.rr_upm_lot_identity_v731(text) to authenticated;

-- Freeze Product Master identity into Cutting/UPM snapshots without inventing values.
create or replace function public.rr_upm_sync_product_identity_v731(p_canonical_lot_id text)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare v_identity jsonb;v_cut_id uuid;v_print text;v_art text;
begin
  v_identity:=public.rr_upm_lot_identity_v731(p_canonical_lot_id);
  v_cut_id:=nullif(v_identity->>'cutting_lot_id','')::uuid;
  v_art:=nullif(v_identity->>'art_no','MAPPING REQUIRED');
  v_print:=nullif(v_identity->>'print_no','PRODUCT MASTER MAPPING REQUIRED');
  if v_art is null then raise exception 'Product Master Art mapping is required before Cutting identity can be frozen.'; end if;
  if v_print='PRINT NOT APPLICABLE' then v_print:=null; end if;

  update public.rr_cutting_lots_v3
     set art_no=v_art,print_no=v_print
   where id=v_cut_id;

  update public.rr_upm_lot_registry
     set art_no=v_art,
         metadata=jsonb_set(jsonb_set(coalesce(metadata,'{}'::jsonb),'{print_no}',to_jsonb(v_print),true),'{identity_source}',to_jsonb('PRODUCT_MASTER_TO_CUTTING'::text),true),
         updated_at=now()
   where canonical_lot_id=p_canonical_lot_id;

  delete from public.rr_upm_print_jobs where canonical_lot_id=p_canonical_lot_id;
  if v_print is not null then
    insert into public.rr_upm_print_jobs(canonical_lot_id,lot_no,print_no,print_id,print_name,status,planned_qty,updated_at)
    select p_canonical_lot_id,r.lot_no,pm.print_no,pm.id,pm.print_name,'PENDING',r.total_qty,now()
    from public.rr_upm_lot_registry r
    join lateral regexp_split_to_table(v_print,'\s*,\s*') z on true
    join public.rr_print_master pm on upper(trim(pm.print_no))=upper(trim(z))
    where r.canonical_lot_id=p_canonical_lot_id
    on conflict(canonical_lot_id,print_no) do update
      set print_id=excluded.print_id,print_name=excluded.print_name,planned_qty=excluded.planned_qty,updated_at=now();
  end if;
  return public.rr_upm_lot_identity_v731(p_canonical_lot_id);
end $$;

grant execute on function public.rr_upm_sync_product_identity_v731(text) to authenticated;

-- --------------------------------------------------------------------------
-- 2) Worker list isolated to the exact department currently being assigned
-- --------------------------------------------------------------------------
create or replace function public.rr_upm_worker_list_v731(p_department_code text)
returns table(
  worker_id uuid,worker_code text,worker_name text,role_code text,
  department_code text,linked_auth_user_id uuid,is_active boolean,
  access_status text,source text
)
language sql stable security definer set search_path=public
as $$
  select w.worker_id,w.worker_code,w.worker_name,w.role_code,w.department_code,
         w.linked_auth_user_id,w.is_active,w.access_status,w.source
  from public.rr_upm_worker_list_v8_3(p_department_code) w
  where upper(trim(w.department_code))=upper(trim(p_department_code))
    and coalesce(w.is_active,false)
    and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'
  order by w.worker_name,w.worker_code;
$$;

grant execute on function public.rr_upm_worker_list_v731(text) to authenticated;

-- --------------------------------------------------------------------------
-- 3) Correct balance: damage is subtracted only from its own source bucket
-- --------------------------------------------------------------------------
create or replace function public.rr_upm_action_balance_v731(
  p_canonical_lot_id text,p_department_code text,p_colour_id uuid,p_colour_code text,p_size_code text
)
returns table(
  inbound_qty numeric,direct_good_qty numeric,alter_registered_qty numeric,
  remake_issued_qty numeric,remake_completed_qty numeric,
  damage_pending_qty numeric,damage_alter_qty numeric,damage_remake_qty numeric,
  damage_total_qty numeric,pending_qty numeric,alter_open_qty numeric,
  line_man_pending_qty numeric,worker_remake_pending_qty numeric,remake_open_qty numeric,
  good_total_qty numeric,outbound_qty numeric,submit_ready_qty numeric
)
language sql stable security definer set search_path=public
as $$
with inbound as(
  select coalesce(i.inbound_qty,0)::numeric inbound_qty
  from public.rr_upm_department_inbound_v727(p_canonical_lot_id,p_department_code,p_colour_id,p_colour_code,p_size_code) i
), act as(
  select
    coalesce(sum(qty) filter(where action_type='GOOD'),0)::numeric direct_good,
    coalesce(sum(qty) filter(where action_type='ALTER'),0)::numeric alter_fill,
    coalesce(sum(qty) filter(where action_type='REMAKE_ISSUE'),0)::numeric remake_issue,
    coalesce(sum(qty) filter(where action_type='REMAKE_COMPLETE'),0)::numeric remake_submit,
    coalesce(sum(qty) filter(where action_type='DAMAGE' and upper(coalesce(source_bucket,'PENDING'))='PENDING'),0)::numeric dmg_pending,
    coalesce(sum(qty) filter(where action_type='DAMAGE' and upper(coalesce(source_bucket,'PENDING'))='ALTER'),0)::numeric dmg_alter,
    coalesce(sum(qty) filter(where action_type='DAMAGE' and upper(coalesce(source_bucket,'PENDING'))='REMAKE'),0)::numeric dmg_remake
  from public.rr_upm_actions_v726 a
  where a.canonical_lot_id=p_canonical_lot_id
    and upper(a.department_code)=upper(trim(p_department_code))
    and upper(a.size_code)=upper(trim(p_size_code))
    and ((p_colour_id is not null and a.colour_id=p_colour_id)
      or (p_colour_id is null and upper(a.colour_code)=upper(trim(p_colour_code))))
), flow as(
  select
    coalesce(sum(remake_delivered_qty),0)::numeric delivered,
    coalesce(sum(remake_submitted_qty),0)::numeric submitted,
    count(*)::integer flow_rows
  from public.rr_upm_remake_flow_v729 f
  where f.canonical_lot_id=p_canonical_lot_id
    and upper(f.department_code)=upper(trim(p_department_code))
    and upper(f.size_code)=upper(trim(p_size_code))
    and ((p_colour_id is not null and f.colour_id=p_colour_id)
      or (p_colour_id is null and upper(f.colour_code)=upper(trim(p_colour_code))))
), handed as(
  select coalesce(sum(qty),0)::numeric outbound
  from public.rr_upm_department_handoffs_v727 h
  where h.canonical_lot_id=p_canonical_lot_id
    and upper(h.from_department_code)=upper(trim(p_department_code))
    and upper(h.size_code)=upper(trim(p_size_code))
    and ((p_colour_id is not null and h.colour_id=p_colour_id)
      or (p_colour_id is null and upper(h.colour_code)=upper(trim(p_colour_code))))
), calc as(
  select i.inbound_qty,a.*,f.*,h.outbound,
    greatest(i.inbound_qty-a.direct_good-a.alter_fill-a.dmg_pending,0)::numeric p_pending,
    greatest(a.alter_fill-a.remake_issue-a.dmg_alter,0)::numeric p_alter,
    greatest(a.remake_issue-f.delivered,0)::numeric p_line_man,
    case when f.flow_rows>0
      then greatest(f.delivered-f.submitted-a.dmg_remake,0)
      else greatest(a.remake_issue-a.remake_submit-a.dmg_remake,0)
    end::numeric p_worker_remake,
    (a.direct_good+a.remake_submit)::numeric p_good
  from inbound i cross join act a cross join flow f cross join handed h
)
select inbound_qty,direct_good,alter_fill,remake_issue,remake_submit,
       dmg_pending,dmg_alter,dmg_remake,(dmg_pending+dmg_alter+dmg_remake),
       p_pending,p_alter,p_line_man,p_worker_remake,p_worker_remake,p_good,outbound,
       greatest(p_good-outbound,0)::numeric
from calc;
$$;

grant execute on function public.rr_upm_action_balance_v731(text,text,uuid,text,text) to authenticated;

-- --------------------------------------------------------------------------
-- 4) Bucket-wise damage RPC. It validates against V731 balances, not total damage.
-- --------------------------------------------------------------------------
create or replace function public.rr_upm_save_damage_v731(
  p_canonical_lot_id text,p_department_code text,p_rows jsonb,
  p_rate numeric default 0,p_remarks text default null
)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare r jsonb;v_qty numeric;v_bucket text;v_bal record;v_assign public.rr_upm_work_assignments_v8%rowtype;
        v_lot public.rr_upm_lot_registry%rowtype;v_actor text;v_count integer:=0;v_available numeric;
begin
  if not public.rr_upm_action_permission_v727('DAMAGE',p_department_code) then raise exception 'Damage permission denied.'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Enter at least one Damage row.'; end if;
  select * into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
  if not found then raise exception 'Lot is not registered.'; end if;
  v_actor:=coalesce(public.rr_up_user_context_v2()->>'display_name',auth.uid()::text);

  for r in select value from jsonb_array_elements(p_rows) loop
    v_qty:=coalesce(nullif(r->>'qty','')::numeric,0);
    if v_qty<=0 then continue; end if;
    v_bucket:=upper(trim(coalesce(r->>'source_bucket','PENDING')));
    if v_bucket not in('PENDING','ALTER','REMAKE') then raise exception 'Invalid Damage source bucket %.',v_bucket; end if;

    select * into v_assign from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and upper(a.department_code)=upper(p_department_code)
      and a.status in('ASSIGNED','IN_PROGRESS')
      and ((nullif(r->>'colour_id','') is not null and a.colour_id=nullif(r->>'colour_id','')::uuid)
        or upper(a.colour_code)=upper(r->>'colour_code'))
    order by a.assigned_at desc limit 1;
    if v_assign.id is null then raise exception 'Active assignment not found for %.',r->>'colour_code'; end if;

    select * into v_bal from public.rr_upm_action_balance_v731(
      p_canonical_lot_id,p_department_code,nullif(r->>'colour_id','')::uuid,r->>'colour_code',r->>'size_code');
    v_available:=case v_bucket when 'PENDING' then v_bal.pending_qty when 'ALTER' then v_bal.alter_open_qty else v_bal.worker_remake_pending_qty end;
    if v_qty>coalesce(v_available,0) then raise exception '% / %: Damage % exceeds % balance %.',r->>'colour_code',r->>'size_code',v_qty,v_bucket,v_available; end if;

    insert into public.rr_upm_actions_v726(
      request_id,canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,size_code,
      assignment_id,worker_id,worker_name,worker_code,action_type,source_bucket,qty,actual_rate,remarks,actor_name)
    values(gen_random_uuid(),p_canonical_lot_id,v_lot.lot_no,upper(p_department_code),nullif(r->>'colour_id','')::uuid,
      upper(r->>'colour_code'),coalesce(nullif(trim(r->>'colour_name'),''),v_assign.colour_name),upper(r->>'size_code'),
      v_assign.id,v_assign.worker_id,v_assign.worker_name_snapshot,v_assign.worker_code,'DAMAGE',v_bucket,v_qty,
      coalesce(v_assign.actual_rate,p_rate,0),coalesce(p_remarks,'Bucket-wise Damage'),v_actor);

    insert into public.rr_upm_entries(canonical_lot_id,lot_no,department_code,colour_code,size_code,entry_type,qty,rate,remarks,operator_name)
    values(p_canonical_lot_id,v_lot.lot_no,upper(p_department_code),upper(r->>'colour_code'),upper(r->>'size_code'),'REJECT',v_qty,
      coalesce(v_assign.actual_rate,p_rate,0),concat_ws(' · ',p_remarks,'Source '||v_bucket),v_actor);
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('ok',true,'damage_rows_saved',v_count);
end $$;

grant execute on function public.rr_upm_save_damage_v731(text,text,jsonb,numeric,text) to authenticated;

-- --------------------------------------------------------------------------
-- 5) V731 wrappers for real custody stages and dynamic mapping checks
-- --------------------------------------------------------------------------
create or replace function public.rr_upm_alter_fill_v731(
  p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_evidence_urls jsonb,
  p_physical_submitted boolean,p_remarks text default null
)
returns jsonb language plpgsql security definer set search_path=public
as $$
begin
  return public.rr_upm_alter_fill_v729(p_canonical_lot_id,p_department_code,p_rows,p_evidence_urls,p_physical_submitted,p_remarks);
end $$;

create or replace function public.rr_upm_remake_stage_v731(
  p_stage text,p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_remarks text default null
)
returns jsonb language plpgsql security definer set search_path=public
as $$
begin
  return public.rr_upm_remake_stage_v729(p_stage,p_canonical_lot_id,p_department_code,p_rows,p_remarks);
end $$;

grant execute on function public.rr_upm_alter_fill_v731(text,text,jsonb,jsonb,boolean,text) to authenticated;
grant execute on function public.rr_upm_remake_stage_v731(text,text,text,jsonb,text) to authenticated;

-- --------------------------------------------------------------------------
-- 6) Universal form V731: preserve proven V726 assignment/submit logic,
-- replace identity, workers and all balances with corrected V731 values.
-- --------------------------------------------------------------------------
create or replace function public.rr_upm_universal_form_v731(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql stable security definer set search_path=public
as $$
declare
  v_base jsonb;v_identity jsonb;v_workers jsonb;v_rows jsonb:='[]'::jsonb;v_row jsonb;v_bal record;
  v_summary jsonb;v_flow record;
begin
  v_base:=public.rr_upm_universal_form_v726(p_canonical_lot_id,p_department_code);
  v_identity:=public.rr_upm_lot_identity_v731(p_canonical_lot_id);

  select coalesce(jsonb_agg(to_jsonb(w) order by w.worker_name),'[]'::jsonb)
    into v_workers from public.rr_upm_worker_list_v731(p_department_code) w;

  for v_row in select value from jsonb_array_elements(coalesce(v_base->'rows','[]'::jsonb)) loop
    select * into v_bal from public.rr_upm_action_balance_v731(
      p_canonical_lot_id,p_department_code,nullif(v_row->>'colour_id','')::uuid,v_row->>'colour_code',v_row->>'size_code');

    v_row:=v_row || jsonb_build_object(
      'inbound_qty',v_bal.inbound_qty,
      'direct_good_qty',v_bal.direct_good_qty,
      'good_qty',v_bal.good_total_qty,
      'alter_registered_qty',v_bal.alter_registered_qty,
      'alter_open_qty',v_bal.alter_open_qty,
      'alter_qty',v_bal.alter_open_qty,
      'remake_issued_qty',v_bal.remake_issued_qty,
      'remake_completed_qty',v_bal.remake_completed_qty,
      'line_man_pending_qty',v_bal.line_man_pending_qty,
      'worker_remake_pending_qty',v_bal.worker_remake_pending_qty,
      'remake_open_qty',v_bal.worker_remake_pending_qty,
      'remake_qty',v_bal.worker_remake_pending_qty,
      'damage_pending_qty',v_bal.damage_pending_qty,
      'damage_alter_qty',v_bal.damage_alter_qty,
      'damage_remake_qty',v_bal.damage_remake_qty,
      'damage_qty',v_bal.damage_total_qty,
      'pending_qty',v_bal.pending_qty,
      'outbound_qty',v_bal.outbound_qty,
      'submit_ready_qty',v_bal.submit_ready_qty,
      'status',case
        when coalesce((v_row->>'assignment_id')::text,'')='' and v_bal.inbound_qty<=0 then 'WAITING PREVIOUS SUBMIT'
        when coalesce((v_row->>'assignment_id')::text,'')='' then 'OPEN FOR ASSIGNMENT'
        when v_bal.pending_qty=0 and v_bal.alter_open_qty=0 and v_bal.line_man_pending_qty=0 and v_bal.worker_remake_pending_qty=0 and v_bal.submit_ready_qty=0 then 'SUBMITTED'
        else 'RUNNING' end
    );
    v_rows:=v_rows||jsonb_build_array(v_row);
  end loop;

  select jsonb_build_object(
    'assigned',coalesce(sum((r->>'assigned_qty')::numeric),0),
    'inbound',coalesce(sum((r->>'inbound_qty')::numeric),0),
    'good',coalesce(sum((r->>'good_qty')::numeric),0),
    'alter',coalesce(sum((r->>'alter_open_qty')::numeric),0),
    'line_man_pending',coalesce(sum((r->>'line_man_pending_qty')::numeric),0),
    'remake',coalesce(sum((r->>'worker_remake_pending_qty')::numeric),0),
    'damage',coalesce(sum((r->>'damage_qty')::numeric),0),
    'pending',coalesce(sum((r->>'pending_qty')::numeric),0),
    'ready_to_submit',coalesce(sum((r->>'submit_ready_qty')::numeric),0),
    'outbound',coalesce(sum((r->>'outbound_qty')::numeric),0)
  ) into v_summary from jsonb_array_elements(v_rows) r;

  return v_base
    || jsonb_build_object(
      'lot',(coalesce(v_base->'lot','{}'::jsonb)||v_identity),
      'workers',v_workers,
      'rows',v_rows,
      'summary',v_summary,
      'balance_version','732_BUCKET_SAFE',
      'identity_version','PRODUCT_MASTER_TO_CUTTING',
      'remake_flow','ALTER_FILL_TO_ISSUE_TO_DELIVERED_TO_SUBMIT'
    );
end $$;

grant execute on function public.rr_upm_universal_form_v731(text,text) to authenticated;

-- Debug uses the same data that the V731 screen renders.
create or replace function public.rr_upm_debug_lot_flow_v731(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql stable security definer set search_path=public
as $$
declare v_context jsonb;v_identity jsonb;v_issues jsonb:='[]'::jsonb;v_workers integer;v_mapping integer;
begin
  v_identity:=public.rr_upm_lot_identity_v731(p_canonical_lot_id);
  v_context:=public.rr_upm_universal_form_v731(p_canonical_lot_id,p_department_code);
  select count(*) into v_workers from public.rr_upm_worker_list_v731(p_department_code);
  select count(*) into v_mapping from public.rr_upm_remake_flow_v729
   where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(p_department_code);
  if v_identity->>'cb_no'='MAPPING REQUIRED' then v_issues:=v_issues||jsonb_build_array('CB mapping missing from Cutting cb_purchase_id/cb_unit_id'); end if;
  if v_identity->>'art_no'='MAPPING REQUIRED' then v_issues:=v_issues||jsonb_build_array('Art mapping missing in Product Master'); end if;
  if v_identity->>'print_no'='PRODUCT MASTER MAPPING REQUIRED' then v_issues:=v_issues||jsonb_build_array('Print mapping missing in Product Master'); end if;
  if v_workers=0 then v_issues:=v_issues||jsonb_build_array('No exact current-department worker is available'); end if;
  return jsonb_build_object('ok',jsonb_array_length(v_issues)=0,'issues',v_issues,'identity',v_identity,
    'department_code',upper(p_department_code),'exact_department_workers',v_workers,'remake_flow_rows',v_mapping,
    'context',v_context,'versions',jsonb_build_object('universal_form','V732','balance','V732_BUCKET_SAFE','identity','PRODUCT_MASTER_TO_CUTTING'));
end $$;

grant execute on function public.rr_upm_debug_lot_flow_v731(text,text) to authenticated;

commit;
