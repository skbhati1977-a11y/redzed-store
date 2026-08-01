-- ============================================================
-- REDZED UPM V760.2 — COSTING FORM CLEANUP
-- ============================================================
-- Fixes:
-- 1. OPEN_NEXT / OPEN FOR NEXT PROCESS pseudo-route is never a Cost Head.
-- 2. Pseudo departments are excluded from costing panel and cost totals.
-- 3. Keeps V760.1 refresh-record fix.
-- ============================================================

begin;

create or replace function public.rr_costing_is_real_department_v760(
  p_department text
)
returns boolean
language sql
immutable
as $$
  select public.rr_costing_normalize_key_v760(p_department)
    not in (
      '',
      'OPENNEXT',
      'OPENFORNEXTPROCESS',
      'NEXTPROCESS',
      'OPEN',
      'UNASSIGNED',
      'ROUTEGATE'
    )
$$;

create or replace function public.rr_upm_refresh_lot_costing_v760(
  p_canonical_lot_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_lot public.rr_upm_lot_registry%rowtype;
  v_row public.rr_upm_lot_costing_v760%rowtype;
  v_universal_margin numeric:=0;
  v_actual_total numeric:=0;
  v_standard_total numeric:=0;
  v_material numeric:=0;
  v_damage_loss numeric:=0;
  v_worker_claim numeric:=0;
  v_no_claim_loss numeric:=0;
  v_recovery numeric:=0;
  v_final_cost numeric:=0;
  v_sale numeric:=0;
  v_department_code text;
  v_actual_rate numeric;
  v_standard jsonb;
begin
  select *
  into v_lot
  from public.rr_upm_lot_registry
  where canonical_lot_id=p_canonical_lot_id
  limit 1;

  if not found then
    raise exception 'Lot nahi mila.';
  end if;

  select coalesce(numeric_value,0)
  into v_universal_margin
  from public.rr_costing_universal_settings_v760
  where setting_key='OWNER_MARGIN_FLAT_PER_PCS';

  insert into public.rr_upm_lot_costing_v760(
    canonical_lot_id,lot_no,art_no,item_name,
    owner_margin_flat,owner_margin_source,owner_margin_applied_at,
    created_by,updated_by
  )
  values(
    p_canonical_lot_id,v_lot.lot_no,v_lot.art_no,v_lot.item_name,
    v_universal_margin,'UNIVERSAL',now(),auth.uid(),auth.uid()
  )
  on conflict(canonical_lot_id) do nothing;

  select *
  into v_row
  from public.rr_upm_lot_costing_v760
  where canonical_lot_id=p_canonical_lot_id
  for update;

  v_material :=
    coalesce(v_row.regular_fabric_cost_per_piece,0)
    +coalesce(v_row.matching_cost_per_piece,0)
    +coalesce(v_row.other_material_cost_per_piece,0);

  for v_department_code in
    select distinct
      public.rr_costing_canonical_department_v760(a.department_code)
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and nullif(trim(a.department_code),'') is not null
      and public.rr_costing_is_real_department_v760(a.department_code)
  loop
    v_actual_rate:=null;

    select r.actual_rate
    into v_actual_rate
    from public.rr_upm_department_rates_v2 r
    where r.canonical_lot_id=p_canonical_lot_id
      and public.rr_costing_canonical_department_v760(r.department_code)
        =v_department_code
    order by r.updated_at desc
    limit 1;

    if coalesce(v_actual_rate,0)>0 then
      v_actual_total:=v_actual_total+v_actual_rate;
    else
      v_standard:=
        public.rr_costing_standard_rate_v760(
          v_lot.art_no,
          v_department_code
        );

      v_standard_total:=
        v_standard_total+
        coalesce((v_standard->>'standard_rate')::numeric,0);
    end if;
  end loop;

  select
    coalesce(sum(
      case
        when action_type in (
          'DAMAGE','DAMAGE_CLAIM','DAMAGE_REGISTER','ALTER_TO_DAMAGE'
        )
        then coalesce(gross_claim_amount,qty*actual_rate,0)
        else 0
      end
    ),0),
    coalesce(sum(
      case when action_type='DAMAGE_CLAIM'
        then coalesce(gross_claim_amount,qty*actual_rate,0)
        else 0 end
    ),0),
    coalesce(sum(
      case when action_type='DAMAGE_REGISTER'
        then coalesce(factory_loss_amount,qty*actual_rate,0)
        else 0 end
    ),0),
    coalesce(sum(
      case when action_type in ('CLAIM_RELAXATION','CLAIM_REVOKE')
        then abs(coalesce(qty*actual_rate,gross_claim_amount,0))
        else 0 end
    ),0)
  into v_damage_loss,v_worker_claim,v_no_claim_loss,v_recovery
  from public.rr_upm_actions_v726
  where canonical_lot_id=p_canonical_lot_id;

  v_final_cost:=round(v_material+v_actual_total+v_standard_total,4);

  if v_row.store_price_locked then
    v_sale:=coalesce(v_row.locked_sale_price,v_row.final_sale_price);
  else
    v_sale:=round(v_final_cost+v_row.owner_margin_flat,2);
  end if;

  update public.rr_upm_lot_costing_v760
  set
    material_total=v_material,
    process_actual_total=v_actual_total,
    process_standard_fallback_total=v_standard_total,
    base_cost_per_piece=v_final_cost,
    final_sale_price=v_sale,
    costing_status=
      case
        when costing_status in ('FINALIZED','DISPATCH_LOCKED','ARCHIVED')
          then costing_status
        when v_material>0 or v_actual_total>0 or v_standard_total>0
          then 'IN_PROGRESS'
        else 'DRAFT'
      end,
    updated_at=now(),
    updated_by=auth.uid()
  where canonical_lot_id=p_canonical_lot_id
  returning * into v_row;

  return jsonb_build_object(
    'ok',true,
    'version','V760_2_COSTING_FORM_CLEANUP',
    'costing',to_jsonb(v_row),
    'company_loss',jsonb_build_object(
      'gross_damage_loss',round(v_damage_loss,4),
      'worker_claim_booked',round(v_worker_claim,4),
      'no_claim_factory_loss',round(v_no_claim_loss,4),
      'recovery_or_relaxation',round(v_recovery,4),
      'net_company_loss',round(v_damage_loss-v_recovery,4),
      'rule','Har Damage costing level par Company Loss hai; recovery alag rahegi.'
    )
  );
end;
$function$;

create or replace function public.rr_upm_costing_panel_v760(
  p_canonical_lot_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_lot public.rr_upm_lot_registry%rowtype;
  v_scope jsonb;
  v_refresh jsonb;
  v_rates jsonb:='[]'::jsonb;
  d record;
  v_actual numeric;
  v_standard jsonb;
  v_visible boolean;
  v_editable boolean;
begin
  select *
  into v_lot
  from public.rr_upm_lot_registry
  where canonical_lot_id=p_canonical_lot_id
  limit 1;

  if not found then raise exception 'Lot nahi mila.'; end if;

  v_refresh:=public.rr_upm_refresh_lot_costing_v760(p_canonical_lot_id);

  for d in
    select distinct code
    from (
      select
        public.rr_costing_canonical_department_v760(department_code) as code
      from public.rr_upm_departments
      where is_active
        and coalesce(rate_enabled,true)
        and public.rr_costing_is_real_department_v760(department_code)

      union

      select
        public.rr_costing_canonical_department_v760(department_code)
      from public.rr_upm_work_assignments_v8
      where canonical_lot_id=p_canonical_lot_id
        and public.rr_costing_is_real_department_v760(department_code)
    ) q
    where public.rr_costing_is_real_department_v760(code)
  loop
    v_scope:=public.rr_costing_user_scope_v760(d.code);

    v_visible:=
      coalesce((v_scope->>'full_rate_access')::boolean,false)
      or coalesce((v_scope->>'own_department_access')::boolean,false)
      or exists(
        select 1
        from public.rr_upm_rate_requests_v760 q
        where q.canonical_lot_id=p_canonical_lot_id
          and q.department_code=d.code
          and q.requested_by=auth.uid()
          and q.request_status in ('PENDING','OPENED','RATE_FILLED')
      );

    if not v_visible then continue; end if;

    select actual_rate
    into v_actual
    from public.rr_upm_department_rates_v2
    where canonical_lot_id=p_canonical_lot_id
      and public.rr_costing_canonical_department_v760(department_code)=d.code
    order by updated_at desc
    limit 1;

    v_standard:=public.rr_costing_standard_rate_v760(v_lot.art_no,d.code);

    v_editable:=
      coalesce((v_scope->>'can_edit_rate')::boolean,false)
      or exists(
        select 1
        from public.rr_upm_rate_requests_v760 q
        where q.canonical_lot_id=p_canonical_lot_id
          and q.department_code=d.code
          and q.requested_by=auth.uid()
          and q.request_status in ('PENDING','OPENED')
          and q.expires_at>now()
      );

    v_rates:=v_rates||jsonb_build_array(
      jsonb_build_object(
        'department_code',d.code,
        'department_name',public.rr_costing_department_display_v760(d.code),
        'actual_rate',v_actual,
        'standard_rate',coalesce((v_standard->>'standard_rate')::numeric,0),
        'standard_source',v_standard->>'source',
        'rate_used',
          case when coalesce(v_actual,0)>0 then v_actual
            else coalesce((v_standard->>'standard_rate')::numeric,0) end,
        'rate_source',
          case
            when coalesce(v_actual,0)>0 then 'ACTUAL'
            when coalesce((v_standard->>'standard_rate')::numeric,0)>0
              then 'STANDARD_FALLBACK'
            else 'MISSING'
          end,
        'editable',v_editable
      )
    );
  end loop;

  return jsonb_build_object(
    'ok',true,
    'version','V760_2_COSTING_FORM_CLEANUP',
    'lot',jsonb_build_object(
      'canonical_lot_id',v_lot.canonical_lot_id,
      'lot_no',v_lot.lot_no,
      'art_no',v_lot.art_no,
      'item_name',v_lot.item_name
    ),
    'scope',public.rr_costing_user_scope_v760(null),
    'rates',v_rates,
    'costing',v_refresh->'costing',
    'company_loss',v_refresh->'company_loss'
  );
end;
$function$;

grant execute on function public.rr_costing_is_real_department_v760(text)
  to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V760_2_COSTING_FORM_CLEANUP',
  'open_next_removed',true,
  'pseudo_routes_excluded_from_total',true
) as rr_upm_v760_2_result;
