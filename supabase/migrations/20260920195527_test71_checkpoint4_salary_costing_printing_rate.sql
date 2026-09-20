-- TEST71 Checkpoint 4: canonical salary/costing, Printing and rate privacy.
-- This migration changes authority and calculation functions only. It does not
-- rewrite historical business rows or create a second workflow engine.

create or replace function public.rr_costing_user_scope_v760(
  p_department_code text default null
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_identity jsonb;
  v_role text;
  v_code text;
  v_departments text[];
  v_private boolean;
  v_rate_editor boolean;
  v_own_department boolean:=false;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  v_identity:=public.rr_upm_effective_identity_v200();
  v_role:=upper(coalesce(v_identity->>'resolved_role',v_identity->>'role_code','WORKER'));
  v_code:=public.rr_costing_canonical_department_v760(p_department_code);
  select coalesce(array_agg(upper(value)),'{}'::text[])
    into v_departments
  from jsonb_array_elements_text(coalesce(v_identity->'department_codes','[]'::jsonb));
  if coalesce(array_length(v_departments,1),0)=0 and nullif(v_identity->>'department_code','') is not null then
    v_departments:=array[upper(v_identity->>'department_code')];
  end if;
  v_private:=v_role in ('OWNER','SUPER_ADMIN');
  v_rate_editor:=v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER');
  if p_department_code is not null then
    v_own_department:=v_code=any(v_departments);
  end if;
  return jsonb_build_object(
    'role',lower(v_role),
    'effective_role',v_role,
    'is_owner',v_private,
    'can_view_private_cost',v_private,
    'full_rate_access',v_rate_editor,
    'own_department_access',v_own_department,
    'can_view_material',v_private,
    'can_edit_material',v_private,
    'can_edit_owner_margin',v_private,
    'can_edit_rate',v_rate_editor,
    'on_behalf',coalesce((v_identity->>'on_behalf')::boolean,false)
  );
end $$;

-- Canonical productive labor: physical Accept & Count -> Submit completion.
-- A row is classified once as SALARIED or PIECE_RATE, never both.
create or replace view public.rr_upm_department_labor_cost_v9160 as
with latest_pay as (
  select distinct on (b.worker_id,upper(coalesce(b.data_mode,'TEST')))
    b.worker_id,upper(coalesce(b.data_mode,'TEST')) data_mode,
    upper(coalesce(b.worker_category,'PIECE_RATE')) worker_category,
    coalesce(b.monthly_salary,0) monthly_salary,
    coalesce(b.normal_payable_minutes,0) normal_payable_minutes
  from public.rr_worker_payroll_board_v777_3 b
  where upper(coalesce(b.payroll_profile_status,'ACTIVE'))='ACTIVE'
  order by b.worker_id,upper(coalesce(b.data_mode,'TEST')),b.effective_from desc,b.configured_at desc nulls last
), latest_month_pay as (
  select distinct on (p.worker_id,upper(coalesce(p.data_mode,'TEST')))
    p.worker_id,upper(coalesce(p.data_mode,'TEST')) data_mode,p.per_minute_rate
  from public.rr_monthly_payroll_v779_1 p
  where coalesce(p.per_minute_rate,0)>0
  order by p.worker_id,upper(coalesce(p.data_mode,'TEST')),p.payroll_month desc,p.updated_at desc nulls last
), base as (
  select
    coalesce(pay.data_mode,'TEST') data_mode,
    a.canonical_lot_id,a.lot_no,
    public.rr_costing_canonical_department_v760(a.department_code) department_code,
    a.worker_id,a.id assignment_id,
    greatest(coalesce(r.confirmed_qty,0),0) good_qty,
    greatest(extract(epoch from (coalesce(a.completed_at,now())-r.confirmed_at))/60.0,0) active_minutes,
    coalesce(pay.worker_category,'PIECE_RATE') worker_category,
    coalesce(a.actual_rate,dr.actual_rate,0) actual_rate,
    coalesce(mp.per_minute_rate,
      case when pay.monthly_salary>0 and pay.normal_payable_minutes>0
        then pay.monthly_salary/(26*pay.normal_payable_minutes) else 0 end,0) salary_per_minute,
    s.session_id,s.status team_session_status,s.absorbed_salary,s.team_salary_per_min
  from public.rr_upm_work_assignments_v8 a
  join public.rr_upm_assignment_receipts_v9112 r
    on r.assignment_id=a.id and upper(coalesce(r.status,''))='CONFIRMED' and r.confirmed_at is not null
  left join latest_pay pay on pay.worker_id=a.worker_id
  left join latest_month_pay mp on mp.worker_id=a.worker_id and mp.data_mode=coalesce(pay.data_mode,'TEST')
  left join lateral (
    select x.actual_rate from public.rr_upm_department_rates_v2 x
    where x.canonical_lot_id=a.canonical_lot_id
      and public.rr_costing_canonical_department_v760(x.department_code)=public.rr_costing_canonical_department_v760(a.department_code)
      and x.actual_rate>0 order by x.updated_at desc limit 1
  ) dr on true
  left join lateral (
    select x.session_id,x.status,x.absorbed_salary,x.team_salary_per_min
    from public.rr_salaried_team_session_v299 x where x.assignment_id=a.id
    order by x.started_at desc limit 1
  ) s on true
  where upper(coalesce(a.status,''))<>'CANCELLED'
    and public.rr_costing_is_real_department_v760(a.department_code)
)
select data_mode,canonical_lot_id,lot_no,department_code,
  round(sum(case when worker_category='SALARIED' then
    coalesce(case when team_session_status='COMPLETED' then absorbed_salary end,
      active_minutes*coalesce(nullif(team_salary_per_min,0),salary_per_minute)) else 0 end),2) salaried_labor_cost,
  round(sum(case when worker_category<>'SALARIED' then good_qty*actual_rate else 0 end),2) piece_rate_labor_cost,
  count(*) filter(where worker_category<>'SALARIED' and actual_rate<=0 and good_qty>0) missing_piece_rate_rows,
  round(sum(active_minutes),2) total_active_minutes
from base group by data_mode,canonical_lot_id,lot_no,department_code;

create or replace function public.rr_costing_salary_allocation_v400(
  p_canonical_lot_id text,p_data_mode text default 'TEST'
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_lot record;v_start date;v_end date;v_rows jsonb:='[]'::jsonb;
  v_productive numeric:=0;v_piece numeric:=0;v_gap numeric:=0;v_staff numeric:=0;
begin
  select * into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
  if not found then raise exception 'Lot not found'; end if;
  v_start:=date_trunc('month',v_lot.created_at)::date;
  v_end:=(date_trunc('month',v_lot.created_at)+interval '1 month - 1 day')::date;

  with profiles as (
    select worker_id,public.rr_costing_canonical_department_v760(department_code) department_code,
      upper(coalesce(role_code,'')) role_code,monthly_salary
    from public.rr_salaried_profile_canonical_v294
    where upper(data_mode)=upper(p_data_mode) and effective_from<=v_end
      and(effective_to is null or effective_to>=v_start)
  ), month_labor as (
    select l.department_code,sum(l.salaried_labor_cost) productive_total
    from public.rr_upm_department_labor_cost_v9160 l
    join public.rr_upm_lot_registry x on x.canonical_lot_id=l.canonical_lot_id
    where upper(l.data_mode)=upper(p_data_mode) and x.created_at::date between v_start and v_end
    group by l.department_code
  ), dept_salary as (
    select department_code,sum(monthly_salary) salary_total from profiles
    where department_code not in ('FABRICATION','ADMIN','ACCOUNTS','SALES')
      and role_code not in ('LINE MAN','LINE_MAN','MANAGER','ADMIN','ACCOUNT','ACCOUNTS','SALESMAN','SALES')
    group by department_code
  ), qty as (
    select a.canonical_lot_id,public.rr_costing_canonical_department_v760(a.department_code) department_code,
      sum(greatest(coalesce(r.confirmed_qty,0),0)) qty
    from public.rr_upm_work_assignments_v8 a
    join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id=a.id and upper(coalesce(r.status,''))='CONFIRMED'
    join public.rr_upm_lot_registry x on x.canonical_lot_id=a.canonical_lot_id
    where x.created_at::date between v_start and v_end and upper(coalesce(a.status,''))<>'CANCELLED'
    group by a.canonical_lot_id,public.rr_costing_canonical_department_v760(a.department_code)
  ), alloc as (
    select s.department_code,s.salary_total,coalesce(m.productive_total,0) productive_month,
      greatest(s.salary_total-coalesce(m.productive_total,0),0) gap_pool,
      coalesce(sum(q.qty),0) month_qty,
      coalesce(sum(q.qty) filter(where q.canonical_lot_id=p_canonical_lot_id),0) lot_qty
    from dept_salary s left join month_labor m using(department_code) left join qty q using(department_code)
    group by s.department_code,s.salary_total,m.productive_total
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'department_code',department_code,'team_salary_month',round(salary_total,2),
      'productive_salary_month',round(productive_month,2),'department_lapse_pool',round(gap_pool,2),
      'lot_accepted_qty',lot_qty,'month_accepted_qty',month_qty,
      'department_lapse_lot',round(case when month_qty>0 then gap_pool*lot_qty/month_qty else 0 end,2)
    ) order by department_code),'[]'::jsonb),
    coalesce(sum(case when month_qty>0 then gap_pool*lot_qty/month_qty else 0 end),0)
  into v_rows,v_gap from alloc;

  select coalesce(sum(salaried_labor_cost),0),coalesce(sum(piece_rate_labor_cost),0)
    into v_productive,v_piece
  from public.rr_upm_department_labor_cost_v9160
  where canonical_lot_id=p_canonical_lot_id and upper(data_mode)=upper(p_data_mode);

  -- Staff salary is allocated only inside each lot's Cutting -> Packing window.
  with profiles as (
    select worker_id,upper(coalesce(role_code,'')) role_code,
      public.rr_costing_canonical_department_v760(department_code) department_code,monthly_salary
    from public.rr_salaried_profile_canonical_v294
    where upper(data_mode)=upper(p_data_mode) and effective_from<=v_end
      and(effective_to is null or effective_to>=v_start)
      and(public.rr_costing_canonical_department_v760(department_code) in ('FABRICATION','ADMIN','ACCOUNTS','SALES')
        or upper(coalesce(role_code,'')) in ('LINE MAN','LINE_MAN','MANAGER','ADMIN','ACCOUNT','ACCOUNTS','SALESMAN','SALES'))
  ), windows as (
    select l.canonical_lot_id,
      greatest(l.created_at,date_trunc('month',v_lot.created_at)) window_start,
      least(coalesce((select max(a.completed_at) from public.rr_upm_work_assignments_v8 a
        where a.canonical_lot_id=l.canonical_lot_id
          and public.rr_costing_canonical_department_v760(a.department_code)='PACKING'
          and a.completed_at is not null),now()),date_trunc('month',v_lot.created_at)+interval '1 month') window_end
    from public.rr_upm_lot_registry l where l.created_at::date between v_start and v_end
  ), wm as (
    select canonical_lot_id,greatest(extract(epoch from(window_end-window_start))/60.0,0) minutes from windows
  ), totals as (select sum(minutes) minutes from wm), per_worker as (
    select p.worker_id,p.role_code,p.department_code,p.monthly_salary,w.minutes,
      greatest(coalesce((public.rr_salary_scheduled_minutes_v313(p.worker_id,v_lot.created_at::date,p_data_mode)->>'scheduled_payable_minutes')::numeric,0),coalesce(t.minutes,0),1) denominator
    from profiles p cross join totals t join wm w on w.canonical_lot_id=p_canonical_lot_id
  )
  select coalesce(sum(monthly_salary*minutes/denominator),0) into v_staff from per_worker;

  return jsonb_build_object(
    'version','V400_ACCEPT_SUBMIT_SALARY_ALLOCATION','productive_salaried_lot',round(v_productive,2),
    'piece_rate_lot',round(v_piece,2),'department_lapse_lot',round(v_gap,2),
    'fabrication_staff_lot',round(v_staff,2),'department_breakdown',v_rows,
    'total_labor_lot',round(v_productive+v_piece+v_gap+v_staff,2),
    'rules',jsonb_build_array('ACCEPT_TO_SUBMIT','SALARIED_OR_PIECE_ONCE','LAPSE_SEPARATE','STAFF_CUTTING_TO_PACKING_ONLY')
  );
end $$;

create or replace function public.rr_upm_final_costing_private_v400(
  p_canonical_lot_id text,p_data_mode text default 'TEST'
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  l record;cut_qty numeric:=0;cloth jsonb;materials jsonb;box jsonb;salary jsonb;printing jsonb;
  cloth_pc numeric:=0;material_pc numeric:=0;other_pc numeric:=0;box_pc numeric:=0;
  labor_pc numeric:=0;fallback_pc numeric:=0;frame_pc numeric:=0;print_material_pc numeric:=0;
  base numeric:=0;margin numeric:=22;sale numeric:=0;missing jsonb:='[]'::jsonb;
begin
  select * into l from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
  if not found then raise exception 'Lot not found'; end if;
  select coalesce(sum(cutting_qty),0) into cut_qty from public.rr_upm_cut_size_rows_v726(l.lot_no);
  cloth:=public.rr_upm_cloth_cost_context_v9300(p_canonical_lot_id);
  materials:=public.rr_costing_materials_resolved_v292(p_canonical_lot_id,p_data_mode);
  box:=public.rr_costing_box_context_v296(l.lot_no);
  salary:=public.rr_costing_salary_allocation_v400(p_canonical_lot_id,p_data_mode);
  printing:=public.rr_printing_final_cost_resolver_v308(p_canonical_lot_id,p_data_mode);
  cloth_pc:=coalesce((cloth->>'regular_cost_per_pc')::numeric,0)+coalesce((cloth->>'matching_cost_per_pc')::numeric,0);
  select coalesce(sum(coalesce((x->>'cost_per_pc')::numeric,(x->>'total_cost')::numeric/nullif(cut_qty,0),0)),0)
    into material_pc from jsonb_array_elements(coalesce(materials->'rows','[]'::jsonb)) x
    where coalesce((x->>'impact')::boolean,false) and upper(coalesce(x->>'component',''))<>'PRINT_CHEMICAL';
  select coalesce(sum(total_cost),0)/nullif(cut_qty,0) into other_pc
    from public.rr_upm_costing_inputs_v9300 where canonical_lot_id=p_canonical_lot_id
      and upper(data_mode)=upper(p_data_mode) and input_type='OTHER_MFG_EXP';
  box_pc:=case when coalesce((box->>'impact')::boolean,false) then coalesce((box->>'value')::numeric,0) else 0 end;
  labor_pc:=coalesce((salary->>'total_labor_lot')::numeric,0)/nullif(cut_qty,0);
  select coalesce(sum(r.actual_rate),0) into fallback_pc from (
    select distinct on(public.rr_costing_canonical_department_v760(x.department_code))
      public.rr_costing_canonical_department_v760(x.department_code) dept,x.actual_rate
    from public.rr_upm_department_rates_v2 x
    where x.canonical_lot_id=p_canonical_lot_id and x.actual_rate>0
      and public.rr_costing_canonical_department_v760(x.department_code)<>'PRINTING'
      and not exists(
        select 1 from public.rr_upm_work_assignments_v8 a
        join public.rr_upm_assignment_receipts_v9112 rr on rr.assignment_id=a.id and upper(coalesce(rr.status,''))='CONFIRMED'
        where a.canonical_lot_id=p_canonical_lot_id
          and public.rr_costing_canonical_department_v760(a.department_code)=public.rr_costing_canonical_department_v760(x.department_code)
      )
    order by public.rr_costing_canonical_department_v760(x.department_code),x.updated_at desc
  ) r;
  if printing->>'state'='V308_ACTUAL' then
    frame_pc:=coalesce((printing->>'frame_recovery_per_lot_pc')::numeric,0);
    print_material_pc:=coalesce((printing->>'printing_material_per_lot_pc')::numeric,0);
  end if;
  select coalesce(numeric_value,22) into margin from public.rr_costing_universal_settings_v760 where setting_key='OWNER_MARGIN_FLAT_PER_PCS';
  base:=round(cloth_pc+material_pc+coalesce(other_pc,0)+box_pc+labor_pc+fallback_pc+frame_pc+print_material_pc,4);
  sale:=round(base+margin,2);
  if cut_qty<=0 then missing:=missing||jsonb_build_array('CUT_QTY'); end if;
  if coalesce(cloth->>'status','')<>'MAPPED' then missing:=missing||jsonb_build_array('MAIN_FABRIC'); end if;
  return jsonb_build_object(
    'ok',jsonb_array_length(missing)=0,'version','V400_CANONICAL_COSTING','canonical_lot_id',p_canonical_lot_id,
    'lot_no',l.lot_no,'cut_qty',cut_qty,'cloth',cloth,'materials_resolved',materials->'rows',
    'salary',salary,'printing',printing,'box',box,'missing',missing,
    'cloth_per_pc',round(cloth_pc,4),'material_resolved_per_pc',round(material_pc,4),
    'other_mfg_per_pc',round(coalesce(other_pc,0),4),'box_per_pc',round(box_pc,4),
    'department_process_per_pc',round(labor_pc+fallback_pc,4),
    'frame_recovery_per_pc',round(frame_pc,4),'printing_material_per_pc',round(print_material_pc,4),
    'base_cost_per_pc',base,'owner_margin_per_pc',margin,'final_sale_rate',sale,
    'costing_complete',jsonb_array_length(missing)=0,
    'authority_rule','ONE LABOR EVENT: SALARIED ACCEPT->SUBMIT OR PIECE RATE; LAPSE SEPARATE; STAFF CUTTING->PACKING'
  );
end $$;

create or replace function public.rr_upm_final_costing_v308(
  p_canonical_lot_id text,p_data_mode text default 'TEST'
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare full_ctx jsonb;scope jsonb;private_ok boolean;role text;public_ctx jsonb;
begin
  perform public.rr_fg_assert_user_v787();
  full_ctx:=public.rr_upm_final_costing_private_v400(p_canonical_lot_id,p_data_mode);
  scope:=public.rr_costing_user_scope_v760(null);private_ok:=coalesce((scope->>'can_view_private_cost')::boolean,false);
  role:=upper(coalesce(scope->>'effective_role','WORKER'));
  if private_ok then return full_ctx||jsonb_build_object('security','SUPER_ADMIN_PRIVATE'); end if;
  public_ctx:=jsonb_build_object('ok',full_ctx->'ok','version',full_ctx->'version',
    'canonical_lot_id',p_canonical_lot_id,'lot_no',full_ctx->'lot_no',
    'final_sale_rate',full_ctx->'final_sale_rate','costing_complete',full_ctx->'costing_complete',
    'missing',full_ctx->'missing','security','PRIVATE_COST_OMITTED','effective_role',role);
  return public_ctx;
end $$;

create or replace function public.rr_upm_costing_context_v9300(
  p_canonical_lot_id text,p_data_mode text default 'TEST'
) returns jsonb language sql stable security definer set search_path=public as $$
  select public.rr_upm_final_costing_v308(p_canonical_lot_id,p_data_mode)
$$;

create or replace function public.rr_pack_rate_context_v309(
  p_lot_no text,p_data_mode text default 'TEST'
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare cid text;f jsonb;qty numeric:=0;out jsonb;private_ok boolean;
begin
  perform public.rr_fg_assert_user_v787();
  select canonical_lot_id into cid from public.rr_upm_lot_registry where upper(trim(lot_no))=upper(trim(p_lot_no)) limit 1;
  if cid is null then return jsonb_build_object('ok',false,'costing_complete',false,'path','NONE','qty',0,'source_rate',0); end if;
  f:=public.rr_upm_final_costing_v308(cid,p_data_mode);
  select coalesce(sum(cutting_qty),0) into qty from public.rr_upm_cut_size_rows_v726(trim(p_lot_no));
  out:=jsonb_build_object('ok',coalesce((f->>'ok')::boolean,false),'costing_complete',coalesce((f->>'costing_complete')::boolean,false),
    'path','FINAL_COST_V400','canonical_lot_id',cid,'qty',qty,'calculated_sale_rate',f->'final_sale_rate',
    'source_rate',round(coalesce((f->>'final_sale_rate')::numeric,0),0),'approval_rounding','WHOLE_RUPEE',
    'authority_version',f->>'version','security',f->>'security');
  private_ok:=coalesce((public.rr_costing_user_scope_v760(null)->>'can_view_private_cost')::boolean,false);
  if private_ok then out:=out||jsonb_build_object('base_cost_per_pc',f->'base_cost_per_pc','owner_margin_per_pc',f->'owner_margin_per_pc',
    'printing',f->'printing','materials_resolved',f->'materials_resolved','salary',f->'salary'); end if;
  return out;
end $$;

create or replace function public.rr_pack_rate_context_universal_v9405(
  p_lot_no text,p_data_mode text default 'TEST'
) returns jsonb language sql stable security definer set search_path=public as $$
  select public.rr_pack_rate_context_v309(p_lot_no,p_data_mode)||jsonb_build_object('compat_entrypoint','V9405')
$$;

create or replace function public.rr_upm_costing_panel_v760(p_canonical_lot_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l record;scope jsonb;rates jsonb:='[]'::jsonb;out jsonb;private_ok boolean;rate_ok boolean;
begin
  select canonical_lot_id,lot_no,art_no,item_name into l from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
  if not found then raise exception 'Lot nahi mila.';end if;
  scope:=public.rr_costing_user_scope_v760(null);
  private_ok:=coalesce((scope->>'can_view_private_cost')::boolean,false);
  rate_ok:=coalesce((scope->>'can_edit_rate')::boolean,false);
  if rate_ok then
    select coalesce(jsonb_agg(jsonb_build_object('department_code',d.department_code,
      'department_name',public.rr_costing_department_display_v760(d.department_code),
      'actual_rate',d.actual_rate,'editable',true) order by d.department_code),'[]'::jsonb)
    into rates from (
      select distinct on(public.rr_costing_canonical_department_v760(x.department_code))
        public.rr_costing_canonical_department_v760(x.department_code) department_code,x.actual_rate
      from public.rr_upm_department_rates_v2 x where x.canonical_lot_id=p_canonical_lot_id
      order by public.rr_costing_canonical_department_v760(x.department_code),x.updated_at desc
    ) d;
  end if;
  out:=jsonb_build_object('ok',true,'version','V400_PRIVATE_COST_SCOPE','lot',to_jsonb(l),'scope',scope,'rates',rates);
  if private_ok then out:=out||jsonb_build_object('costing',public.rr_upm_final_costing_v308(p_canonical_lot_id,'TEST')); end if;
  return out;
end $$;

create or replace function public.rr_upm_set_department_rate_v760(
  p_canonical_lot_id text,p_department_code text,p_actual_rate numeric,p_request_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare l record;code text;scope jsonb;identity jsonb;actor_name text;old_rate numeric;row_rate record;request_row record;
begin
  if p_actual_rate is null or p_actual_rate<0 then raise exception 'Actual Rate zero ya usse zyada honi chahiye.';end if;
  select * into l from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
  if not found then raise exception 'Production Lot nahi mila.';end if;
  code:=public.rr_costing_canonical_department_v760(p_department_code);
  scope:=public.rr_costing_user_scope_v760(code);
  if not coalesce((scope->>'can_edit_rate')::boolean,false) then
    raise exception 'Only eligible Manager/Admin/Owner can fill Actual Rate.';
  end if;
  if p_request_id is not null then
    select * into request_row from public.rr_upm_rate_requests_v760
    where id=p_request_id and canonical_lot_id=p_canonical_lot_id and department_code=code
      and request_status in('PENDING','OPENED','RATE_FILLED') and expires_at>now() for update;
    if not found then raise exception 'Active canonical rate request not found.';end if;
  end if;
  identity:=public.rr_upm_effective_identity_v200();actor_name:=coalesce(identity->>'display_name',auth.uid()::text);
  select actual_rate into old_rate from public.rr_upm_department_rates_v2
    where canonical_lot_id=p_canonical_lot_id and public.rr_costing_canonical_department_v760(department_code)=code
    order by updated_at desc limit 1;
  delete from public.rr_upm_department_rates_v2 where canonical_lot_id=p_canonical_lot_id
    and public.rr_costing_canonical_department_v760(department_code)=code and department_code<>code;
  insert into public.rr_upm_department_rates_v2(canonical_lot_id,lot_no,department_code,actual_rate,
    filled_by,filled_by_name,updated_by,updated_by_name,updated_at)
  values(p_canonical_lot_id,l.lot_no,code,round(p_actual_rate,4),auth.uid(),actor_name,auth.uid(),actor_name,now())
  on conflict(canonical_lot_id,department_code) do update set actual_rate=excluded.actual_rate,
    updated_by=auth.uid(),updated_by_name=actor_name,updated_at=now()
  returning * into row_rate;
  insert into public.rr_upm_department_rate_log_v2(rate_id,old_rate,new_rate,changed_by_name)
    values(row_rate.id,old_rate,round(p_actual_rate,4),actor_name);
  update public.rr_upm_rate_requests_v760 set request_status='COMPLETED',filled_rate=round(p_actual_rate,4),
    filled_at=now(),filled_by=auth.uid(),filled_by_name=actor_name,completed_at=now(),archived_at=now()
  where canonical_lot_id=p_canonical_lot_id and department_code=code
    and request_status in('PENDING','OPENED','RATE_FILLED');
  return jsonb_build_object('ok',true,'version','V400_CANONICAL_RATE_AUTH','canonical_lot_id',p_canonical_lot_id,
    'lot_no',l.lot_no,'department_code',code,'department_name',public.rr_costing_department_display_v760(code),
    'actual_rate',row_rate.actual_rate,'rate_id',row_rate.id,'filled_by_name',actor_name);
end $$;

create or replace function public.rr_printing_actor_scope_v400(p_assignment_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare a record;i jsonb;r text;worker_ok boolean;privileged boolean;
begin
  select * into a from public.rr_upm_work_assignments_v8 where id=p_assignment_id;
  if not found or public.rr_costing_canonical_department_v760(a.department_code)<>'PRINTING' then raise exception 'Printing assignment not found.';end if;
  i:=public.rr_upm_effective_identity_v200();r:=upper(coalesce(i->>'resolved_role',i->>'role_code','WORKER'));
  privileged:=r in('OWNER','SUPER_ADMIN','ADMIN','MANAGER');
  worker_ok:=public.rr_canonical_worker_id_v264((i->>'worker_id')::uuid)=public.rr_canonical_worker_id_v264(a.worker_id);
  if not privileged and not worker_ok then raise exception 'Printing assignment permission denied.';end if;
  return jsonb_build_object('role',r,'private_cost',r in('OWNER','SUPER_ADMIN'),'worker_match',worker_ok,
    'identity',i,'canonical_lot_id',a.canonical_lot_id,'worker_id',a.worker_id);
end $$;

create or replace function public.rr_printing_design_context_v400(p_canonical_lot_id text,p_completed_qty numeric)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare l record;rows jsonb;cnt int:=0;complete int:=0;
begin
  select * into l from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
  if not found then raise exception 'Lot not found';end if;
  with requested as (
    select distinct trim(x) print_no from regexp_split_to_table(coalesce(l.print_no,l.metadata->>'print_no',''),'[,;/\n]+') x where trim(x)<>''
  ), mapped as (
    select r.print_no,m.id print_id,m.print_name,m.artwork_url,m.garment_preview_url,
      greatest(coalesce(m.design_colours,0),coalesce(m.colours,0),0) expected_frames,
      (select count(*) from public.rr_print_frames f join public.rr_print_frame_asset_v298 fa on fa.frame_no=f.frame_no
        where f.print_id=m.id and fa.lifecycle_status<>'SCRAPPED') mapped_frames,
      j.id print_job_id
    from requested r left join public.rr_print_master m on upper(trim(m.print_no))=upper(r.print_no) and coalesce(m.is_active,true)
    left join public.rr_upm_print_jobs j on j.canonical_lot_id=p_canonical_lot_id and upper(trim(j.print_no))=upper(r.print_no)
  )
  select coalesce(jsonb_agg(jsonb_build_object('print_no',print_no,'print_id',print_id,'print_name',print_name,
      'thumbnail_url',coalesce(garment_preview_url,artwork_url),'expected_frames',expected_frames,'mapped_frames',mapped_frames,
      'frame_state',case when print_id is null then 'DESIGN_MAPPING_MISSING' when expected_frames<=0 then 'FRAME_COUNT_MISSING'
        when mapped_frames<expected_frames then 'FRAME_MAPPING_INCOMPLETE' else 'READY' end,'print_job_id',print_job_id) order by print_no),'[]'::jsonb),
    count(*),count(*) filter(where print_id is not null and expected_frames>0 and mapped_frames>=expected_frames)
  into rows,cnt,complete from mapped;
  return jsonb_build_object('designs',rows,'design_count',cnt,'ready_count',complete,
    'state',case when cnt=0 then 'PRINT_DESIGN_MISSING' when complete=cnt then 'READY' else 'INCOMPLETE' end,
    'completed_qty',p_completed_qty);
end $$;

create or replace function public.rr_printing_submit_costing_context_v307(
  p_canonical_lot_id text,p_assignment_id uuid,p_completed_qty numeric,p_data_mode text default 'TEST'
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare scope jsonb;base jsonb;chem jsonb;designs jsonb;private_ok boolean;heads jsonb;
begin
  scope:=public.rr_printing_actor_scope_v400(p_assignment_id);
  if scope->>'canonical_lot_id'<>p_canonical_lot_id then raise exception 'Assignment / lot mismatch.';end if;
  base:=public.rr_printing_submit_costing_context_v305(p_canonical_lot_id,p_assignment_id,p_completed_qty,p_data_mode);
  chem:=public.rr_printing_chemical_context_v306(p_canonical_lot_id,p_data_mode);
  designs:=public.rr_printing_design_context_v400(p_canonical_lot_id,p_completed_qty);
  private_ok:=coalesce((scope->>'private_cost')::boolean,false);
  if private_ok then
    heads=jsonb_set(base->'heads','{chemical}',chem,true);
    heads=jsonb_set(heads,'{frame_recovery}',coalesce(heads->'frame_recovery','{}'::jsonb)||designs,true);
  else
    heads:=jsonb_build_object(
      'team_salary',jsonb_build_object('display',case when base#>>'{heads,team_salary,state}'='COMPLETED' then 'RECORDED' else 'AUTO' end,
        'state',base#>>'{heads,team_salary,state}','editable',false),
      'frame_recovery',jsonb_build_object('display','AUTO','state',designs->>'state','editable',false,'designs',designs->'designs','design_count',designs->'design_count'),
      'chemical',jsonb_build_object('qty_kg',chem->'qty_kg','unit','KG','display','AUTO','state',coalesce(chem#>>'{printing_material_pool,state}','PENDING'),'editable',true)
    );
  end if;
  return jsonb_build_object('version','V400_PRINTING_SUBMIT_PRIVATE','canonical_lot_id',p_canonical_lot_id,
    'assignment_id',p_assignment_id,'completed_qty',p_completed_qty,'heads',heads,'print_designs',designs->'designs',
    'editable_fields',jsonb_build_array('chemical_qty_kg'),'private_cost',private_ok,
    'rule','V204 HANDOVER; TEAM/FRAME/MATERIAL SERVER AUTO; ONLY CHEMICAL KG MANUAL');
end $$;

create or replace function public.rr_printing_finalize_costing_v307(
  p_canonical_lot_id text,p_assignment_id uuid,p_completed_qty numeric,p_chemical_kg numeric,p_data_mode text default 'TEST'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare scope jsonb;l record;d record;j record;preview jsonb;applied jsonb;frames jsonb:='[]'::jsonb;chem jsonb;ctx jsonb;private_ok boolean;
begin
  if coalesce(p_completed_qty,0)<=0 then raise exception 'Completed printed quantity required';end if;
  if p_chemical_kg is null or p_chemical_kg<0 then raise exception 'Chemical KG must be zero or greater';end if;
  scope:=public.rr_printing_actor_scope_v400(p_assignment_id);
  if scope->>'canonical_lot_id'<>p_canonical_lot_id then raise exception 'Assignment / lot mismatch.';end if;
  select * into l from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id for update;
  chem:=public.rr_printing_save_chemical_qty_v306(p_canonical_lot_id,p_chemical_kg,p_data_mode);
  for d in
    select distinct trim(x) print_no,m.id print_id,m.print_name
    from regexp_split_to_table(coalesce(l.print_no,l.metadata->>'print_no',''),'[,;/\n]+') x
    left join public.rr_print_master m on upper(trim(m.print_no))=upper(trim(x)) and coalesce(m.is_active,true)
    where trim(x)<>''
  loop
    if d.print_id is null then
      frames:=frames||jsonb_build_array(jsonb_build_object('print_no',d.print_no,'applied',false,'state','DESIGN_MAPPING_MISSING'));
      continue;
    end if;
    insert into public.rr_upm_print_jobs(canonical_lot_id,lot_no,print_no,print_id,print_name,status,planned_qty,completed_qty,updated_at)
    values(p_canonical_lot_id,l.lot_no,d.print_no,d.print_id,d.print_name,'IN_PROGRESS',p_completed_qty,p_completed_qty,now())
    on conflict(canonical_lot_id,print_no) do update set print_id=excluded.print_id,print_name=excluded.print_name,
      planned_qty=greatest(public.rr_upm_print_jobs.planned_qty,excluded.planned_qty),
      completed_qty=greatest(public.rr_upm_print_jobs.completed_qty,excluded.completed_qty),updated_at=now()
    returning * into j;
    preview:=public.rr_print_frame_recovery_preview_v303(j.id,p_completed_qty);
    if coalesce((preview->>'available')::boolean,false) then applied:=public.rr_print_apply_frame_recovery_v302(j.id,p_completed_qty);else applied:=preview;end if;
    frames:=frames||jsonb_build_array(jsonb_build_object('print_no',d.print_no,'print_job_id',j.id,'result',applied));
  end loop;
  ctx:=public.rr_printing_submit_costing_context_v307(p_canonical_lot_id,p_assignment_id,p_completed_qty,p_data_mode);
  private_ok:=coalesce((scope->>'private_cost')::boolean,false);
  if private_ok then return ctx||jsonb_build_object('chemical_save',chem,'frame_results',frames,'finalized',true);end if;
  return ctx||jsonb_build_object('chemical_saved',true,'frame_design_count',jsonb_array_length(frames),'finalized',true);
end $$;

create or replace function public.rr_salaried_team_finish_on_worker_submit_v322()
returns trigger language plpgsql security definer set search_path=public as $$
declare assignment_id uuid;completed_qty numeric;
begin
  if upper(coalesce(new.status,'')) not in('WAITING_LM','ESCALATED') then return new;end if;
  foreach assignment_id in array coalesce(new.assignment_ids,'{}'::uuid[]) loop
    select coalesce(r.confirmed_qty,a.inbound_qty,a.assigned_qty,0) into completed_qty
    from public.rr_upm_work_assignments_v8 a left join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id=a.id
    where a.id=assignment_id order by r.confirmed_at desc nulls last limit 1;
    perform public.rr_salaried_team_finish_if_applicable_v300(assignment_id,coalesce(completed_qty,0));
  end loop;
  return new;
end $$;

-- Client grants: exposed wrappers are authenticated only; raw payroll/cost sources stay server-internal.
revoke all on function public.rr_costing_salary_pool_v294(date,text) from public,anon,authenticated;
revoke all on function public.rr_costing_salary_department_drilldown_v297(date,text) from public,anon,authenticated;
revoke all on function public.rr_upm_final_costing_v295(text,text) from public,anon,authenticated;
revoke all on function public.rr_upm_final_costing_v296(text,text) from public,anon,authenticated;
revoke all on function public.rr_upm_final_costing_v297(text,text) from public,anon,authenticated;
revoke all on function public.rr_upm_final_costing_private_v400(text,text) from public,anon,authenticated;
revoke all on function public.rr_costing_salary_allocation_v400(text,text) from public,anon,authenticated;
revoke all on function public.rr_printing_actor_scope_v400(uuid) from public,anon,authenticated;
revoke all on function public.rr_printing_design_context_v400(text,numeric) from public,anon,authenticated;
revoke all on function public.rr_printing_submit_costing_context_v305(text,uuid,numeric,text) from public,anon,authenticated;
revoke all on function public.rr_printing_material_pool_rate_v306(date,text) from public,anon,authenticated;
revoke all on function public.rr_printing_chemical_context_v306(text,text) from public,anon,authenticated;
revoke all on function public.rr_printing_final_cost_resolver_v308(text,text) from public,anon,authenticated;
revoke all on function public.rr_print_frame_recovery_preview_v303(uuid,numeric) from public,anon,authenticated;
revoke all on function public.rr_print_apply_frame_recovery_v302(uuid,numeric) from public,anon,authenticated;
revoke all on table public.rr_salaried_profile_canonical_v294 from public,anon,authenticated;
revoke all on table public.rr_salaried_team_session_v299 from public,anon,authenticated;
revoke all on table public.rr_upm_department_labor_cost_v9160 from public,anon,authenticated;
revoke all on table public.rr_print_frame_job_recovery_v302 from public,anon,authenticated;

revoke all on function public.rr_costing_user_scope_v760(text) from public,anon;
revoke all on function public.rr_upm_final_costing_v308(text,text) from public,anon;
revoke all on function public.rr_upm_costing_context_v9300(text,text) from public,anon;
revoke all on function public.rr_pack_rate_context_v309(text,text) from public,anon;
revoke all on function public.rr_pack_rate_context_universal_v9405(text,text) from public,anon;
revoke all on function public.rr_upm_costing_panel_v760(text) from public,anon;
revoke all on function public.rr_upm_set_department_rate_v760(text,text,numeric,uuid) from public,anon;
revoke all on function public.rr_printing_submit_costing_context_v307(text,uuid,numeric,text) from public,anon;
revoke all on function public.rr_printing_finalize_costing_v307(text,uuid,numeric,numeric,text) from public,anon;

grant execute on function public.rr_costing_user_scope_v760(text) to authenticated;
grant execute on function public.rr_upm_final_costing_v308(text,text) to authenticated;
grant execute on function public.rr_upm_costing_context_v9300(text,text) to authenticated;
grant execute on function public.rr_pack_rate_context_v309(text,text) to authenticated;
grant execute on function public.rr_pack_rate_context_universal_v9405(text,text) to authenticated;
grant execute on function public.rr_upm_costing_panel_v760(text) to authenticated;
grant execute on function public.rr_upm_set_department_rate_v760(text,text,numeric,uuid) to authenticated;
grant execute on function public.rr_printing_submit_costing_context_v307(text,uuid,numeric,text) to authenticated;
grant execute on function public.rr_printing_finalize_costing_v307(text,uuid,numeric,numeric,text) to authenticated;

comment on function public.rr_upm_final_costing_v308(text,text) is
  'TEST71 CP4 canonical costing. Full cost/margin only for effective OWNER/SUPER_ADMIN; other roles receive final rate/status only.';
comment on function public.rr_printing_finalize_costing_v307(text,uuid,numeric,numeric,text) is
  'TEST71 CP4 canonical multi-design Printing costing finalization before existing V204 handover; idempotent frame recovery.';
