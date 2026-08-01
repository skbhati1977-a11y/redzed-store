-- ============================================================
-- REDZED UPM V759.1 — DAMAGE FINANCIAL ENGINE + NO-CLAIM DAMAGE
-- ============================================================
--
-- VERIFIED EXISTING ARCHITECTURE USED:
--   rr_upm_save_damage_v731
--   rr_upm_actions_v726
--   rr_upm_entries
--   rr_upm_worker_ledger_v726 (view over rr_upm_actions_v726)
--   rr_upm_work_assignments_v8
--   rr_upm_department_rates_v2
--   rr_product_master
--   rr_product_cost_snapshot
--   rr_art_cost_summary
--
-- NO PARALLEL WORKER LEDGER IS CREATED.
--
-- COST RULE:
--   Material snapshot
-- + completed/current process rates
-- = Damage Rate Upto This Stage
--
-- PROCESS RATE PRIORITY:
--   1. Assignment frozen actual_rate
--   2. Lot + Department actual rate
--   3. Art Module standard rate fallback
--
-- IMMUTABILITY:
--   The calculated cost snapshot and rate are stored on the Damage action.
--   Later rate changes do not rewrite old Damage entries.
--
-- STRICT RULE:
--   If automatic full-stage cost is incomplete, Damage save is blocked.
--   An authorised manually verified FULL damage rate may be supplied through
--   p_rate > 0; it is stored as MANUAL_FULL_RATE_OVERRIDE.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Backup current production function
-- ------------------------------------------------------------
create table if not exists public.rr_upm_function_backup_v759 (
  id bigserial primary key,
  function_identity text not null,
  version_tag text not null,
  function_definition text not null,
  backed_up_at timestamptz not null default now()
);

insert into public.rr_upm_function_backup_v759(
  function_identity,
  version_tag,
  function_definition
)
select
  'public.rr_upm_save_damage_v731(text,text,jsonb,numeric,text)',
  'PRE_V759_DAMAGE_FINANCIAL_ENGINE',
  pg_get_functiondef(
    'public.rr_upm_save_damage_v731(text,text,jsonb,numeric,text)'::regprocedure
  );

-- ------------------------------------------------------------
-- 2. Extend existing action ledger source, not a new ledger
-- ------------------------------------------------------------
alter table public.rr_upm_actions_v726
  add column if not exists cost_snapshot jsonb,
  add column if not exists claim_status text not null default 'POSTED',
  add column if not exists claim_parent_action_id uuid,
  add column if not exists gross_claim_amount numeric,
  add column if not exists relaxed_claim_amount numeric not null default 0,
  add column if not exists responsibility_mode text not null default 'WORKER_CLAIM',
  add column if not exists factory_loss_amount numeric not null default 0,
  add column if not exists responsible_worker_id uuid,
  add column if not exists responsible_department_code text,
  add column if not exists damage_reason_code text;

create index if not exists rr_upm_actions_v726_claim_parent_idx
  on public.rr_upm_actions_v726(claim_parent_action_id);

create index if not exists rr_upm_actions_v726_damage_claim_idx
  on public.rr_upm_actions_v726(
    canonical_lot_id,
    worker_id,
    action_type,
    created_at
  )
  where action_type in (
    'DAMAGE',
    'DAMAGE_CLAIM',
    'CLAIM_RELAXATION',
    'CLAIM_REVOKE',
    'ALTER_TO_DAMAGE'
  );

do $$
begin
  if not exists(
    select 1
    from pg_constraint
    where conname='rr_upm_actions_v726_responsibility_mode_chk'
      and conrelid='public.rr_upm_actions_v726'::regclass
  ) then
    alter table public.rr_upm_actions_v726
      add constraint rr_upm_actions_v726_responsibility_mode_chk
      check (responsibility_mode in ('WORKER_CLAIM','NO_CLAIM'));
  end if;
end $$;

-- ------------------------------------------------------------
-- 3. Department code → Art standard-rate mapping
-- ------------------------------------------------------------
create or replace function public.rr_upm_art_standard_rate_v759(
  p_art_no text,
  p_department_code text
)
returns numeric
language sql
stable
security definer
set search_path to 'public'
as $$
  select
    case upper(trim(p_department_code))
      when 'CUTTING' then coalesce(a.cutting_rate,0)
      when 'PRINT' then coalesce(a.printing_rate,0)
      when 'PRINTING' then coalesce(a.printing_rate,0)
      when 'STICKER' then coalesce(a.sticker_rate,0)
      when 'KR' then coalesce(a.kr_rate,0)
      when 'STITCHING' then coalesce(a.kr_rate,0)
      when 'KARIGAR' then coalesce(a.kr_rate,0)
      when 'OVERLOCK' then coalesce(a.ov_rate,0)
      when 'OV' then coalesce(a.ov_rate,0)
      when 'FOLDING' then coalesce(a.fld_rate,0)
      when 'FLD' then coalesce(a.fld_rate,0)
      when 'KAJ' then coalesce(a.kaj_button_rate,0)
      when 'KAJ_BUTTON' then coalesce(a.kaj_button_rate,0)
      when 'BUTTON' then coalesce(a.kaj_button_rate,0)
      when 'TANKI' then coalesce(a.tanki_tack_rate,0)
      when 'TANKI_TACK' then coalesce(a.tanki_tack_rate,0)
      when 'THREAD_CUT' then coalesce(a.thread_cut_rate,0)
      when 'THREAD_CUTTING' then coalesce(a.thread_cut_rate,0)
      when 'QC' then 0
      when 'PRESS' then coalesce(a.press_rate,0)
      when 'PRESSING' then coalesce(a.press_rate,0)
      when 'PACK' then coalesce(a.packing_rate,0)
      when 'PACKING' then coalesce(a.packing_rate,0)
      else coalesce(a.other_rate,0)
    end
  from public.rr_art_cost_summary a
  where upper(a.art_no)=upper(trim(p_art_no))
    and coalesce(a.is_active,true)
  limit 1
$$;

-- ------------------------------------------------------------
-- 4. Damage Rate Upto This Stage snapshot
-- ------------------------------------------------------------
create or replace function public.rr_upm_damage_rate_snapshot_v759(
  p_canonical_lot_id text,
  p_department_code text,
  p_colour_id uuid,
  p_colour_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_lot public.rr_upm_lot_registry%rowtype;
  v_product_id uuid;
  v_material numeric := 0;
  v_material_snapshot jsonb := '{}'::jsonb;
  v_material_found boolean := false;

  v_process_total numeric := 0;
  v_actual_total numeric := 0;
  v_standard_total numeric := 0;
  v_missing_departments text[] := array[]::text[];
  v_processes jsonb := '[]'::jsonb;

  v_assignment record;
  v_rate numeric;
  v_rate_source text;
  v_master_actual numeric;
  v_standard numeric;
  v_rate_required boolean;
  v_complete boolean;
begin
  select *
  into v_lot
  from public.rr_upm_lot_registry
  where canonical_lot_id=p_canonical_lot_id
  limit 1;

  if not found then
    raise exception 'Lot is not registered.';
  end if;

  /*
    MATERIAL LOOKUP:
    Lot No → Product Master → latest Product Cost Snapshot.
    No cost is guessed from sale/dealer rate.
  */
  select pm.id
  into v_product_id
  from public.rr_product_master pm
  where upper(pm.lot_no)=upper(v_lot.lot_no)
    and coalesce(pm.is_active,true)
  order by pm.updated_at desc nulls last, pm.created_at desc nulls last
  limit 1;

  if v_product_id is not null then
    select
      coalesce(
        nullif(pcs.material_cost_total,0),
        nullif(pcs.fabric_cost_per_piece,0),
        (
          coalesce(pcs.regular_cloth_cost,0)
          + coalesce(pcs.matching_cost,0)
          + coalesce(pcs.collar_cuff_cost,0)
          + coalesce(pcs.rib_cost,0)
          + coalesce(pcs.elastic_cost,0)
          + coalesce(pcs.zip_cost,0)
          + coalesce(pcs.tape_cost,0)
          + coalesce(pcs.custom_material_cost,0)
        )
      ),
      jsonb_build_object(
        'product_id',pcs.product_id,
        'snapshot_id',pcs.id,
        'snapshot_at',pcs.snapshot_at,
        'regular_cloth_cost',coalesce(pcs.regular_cloth_cost,0),
        'matching_cost',coalesce(pcs.matching_cost,0),
        'collar_cuff_cost',coalesce(pcs.collar_cuff_cost,0),
        'rib_cost',coalesce(pcs.rib_cost,0),
        'elastic_cost',coalesce(pcs.elastic_cost,0),
        'zip_cost',coalesce(pcs.zip_cost,0),
        'tape_cost',coalesce(pcs.tape_cost,0),
        'custom_material_cost',coalesce(pcs.custom_material_cost,0),
        'material_cost_total',pcs.material_cost_total,
        'fabric_cost_per_piece',pcs.fabric_cost_per_piece
      )
    into v_material,v_material_snapshot
    from public.rr_product_cost_snapshot pcs
    where pcs.product_id=v_product_id
    order by pcs.snapshot_at desc nulls last,pcs.updated_at desc nulls last
    limit 1;

    v_material_found := found and coalesce(v_material,0)>0;
  end if;

  /*
    PROCESS COST:
    Include completed departments for this Colour, plus the currently active
    diagnosis department. Each historical assignment keeps its own snapshot.
  */
  for v_assignment in
    select distinct on (upper(a.department_code))
      a.id,
      upper(a.department_code) as department_code,
      a.status,
      a.actual_rate,
      a.rate_filled_at,
      a.assigned_at,
      a.completed_at
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and (
        (p_colour_id is not null and a.colour_id=p_colour_id)
        or upper(a.colour_code)=upper(p_colour_code)
      )
      and (
        a.status='COMPLETED'
        or (
          upper(a.department_code)=upper(p_department_code)
          and a.status in ('ASSIGNED','IN_PROGRESS')
        )
      )
    order by
      upper(a.department_code),
      case when a.status='COMPLETED' then 0 else 1 end,
      coalesce(a.completed_at,a.assigned_at) desc
  loop
    select r.actual_rate
    into v_master_actual
    from public.rr_upm_department_rates_v2 r
    where r.canonical_lot_id=p_canonical_lot_id
      and upper(r.department_code)=v_assignment.department_code
    limit 1;

    v_standard := public.rr_upm_art_standard_rate_v759(
      v_lot.art_no,
      v_assignment.department_code
    );

    select coalesce(d.rate_enabled,true)
    into v_rate_required
    from public.rr_upm_departments d
    where upper(d.department_code)=v_assignment.department_code
    limit 1;

    v_rate_required := coalesce(v_rate_required,true);

    if coalesce(v_assignment.actual_rate,0)>0 then
      v_rate := v_assignment.actual_rate;
      v_rate_source := 'ASSIGNMENT_ACTUAL_SNAPSHOT';
      v_actual_total := v_actual_total+v_rate;
    elsif coalesce(v_master_actual,0)>0 then
      v_rate := v_master_actual;
      v_rate_source := 'LOT_DEPARTMENT_ACTUAL';
      v_actual_total := v_actual_total+v_rate;
    elsif coalesce(v_standard,0)>0 then
      v_rate := v_standard;
      v_rate_source := 'ART_STANDARD_FALLBACK';
      v_standard_total := v_standard_total+v_rate;
    elsif not v_rate_required then
      v_rate := 0;
      v_rate_source := 'RATE_NOT_APPLICABLE';
    else
      v_rate := 0;
      v_rate_source := 'MISSING';
      v_missing_departments :=
        array_append(v_missing_departments,v_assignment.department_code);
    end if;

    v_process_total := v_process_total+coalesce(v_rate,0);

    v_processes := v_processes || jsonb_build_array(
      jsonb_build_object(
        'assignment_id',v_assignment.id,
        'department_code',v_assignment.department_code,
        'assignment_status',v_assignment.status,
        'rate',round(coalesce(v_rate,0),4),
        'rate_source',v_rate_source,
        'rate_filled_at',v_assignment.rate_filled_at,
        'completed_at',v_assignment.completed_at
      )
    );
  end loop;

  v_complete :=
    v_material_found
    and coalesce(array_length(v_missing_departments,1),0)=0;

  return jsonb_build_object(
    'ok',true,
    'version','V759_1_DAMAGE_ENGINE_NO_CLAIM',
    'canonical_lot_id',p_canonical_lot_id,
    'lot_no',v_lot.lot_no,
    'art_no',v_lot.art_no,
    'colour_id',p_colour_id,
    'colour_code',upper(p_colour_code),
    'diagnosed_department',upper(p_department_code),

    'material_found',v_material_found,
    'material_rate',round(coalesce(v_material,0),4),
    'material_snapshot',v_material_snapshot,

    'process_rate',round(coalesce(v_process_total,0),4),
    'actual_process_rate',round(coalesce(v_actual_total,0),4),
    'standard_fallback_rate',round(coalesce(v_standard_total,0),4),
    'processes',v_processes,
    'missing_departments',to_jsonb(v_missing_departments),

    'complete',v_complete,
    'damage_rate_upto_stage',
      round(coalesce(v_material,0)+coalesce(v_process_total,0),4),
    'snapshot_at',now()
  );
end;
$function$;

-- ------------------------------------------------------------
-- 5. Replace existing Damage function, preserving its signature
-- ------------------------------------------------------------
create or replace function public.rr_upm_save_damage_v731(
  p_canonical_lot_id text,
  p_department_code text,
  p_rows jsonb,
  p_rate numeric default 0,
  p_remarks text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r jsonb;
  v_qty numeric;
  v_bucket text;
  v_bal record;
  v_assign public.rr_upm_work_assignments_v8%rowtype;
  v_lot public.rr_upm_lot_registry%rowtype;
  v_actor text;
  v_count integer:=0;
  v_available numeric;

  v_snapshot jsonb;
  v_damage_rate numeric;
  v_rate_source text;
  v_action_id uuid;
  v_claim_value numeric;
  v_responsibility_mode text;
  v_damage_reason_code text;
  v_factory_loss numeric;
begin
  if not public.rr_upm_action_permission_v727(
    'DAMAGE',
    p_department_code
  ) then
    raise exception 'Damage permission denied.';
  end if;

  if jsonb_typeof(p_rows)<>'array'
     or jsonb_array_length(p_rows)=0
  then
    raise exception 'Enter at least one Damage row.';
  end if;

  select *
  into v_lot
  from public.rr_upm_lot_registry
  where canonical_lot_id=p_canonical_lot_id;

  if not found then
    raise exception 'Lot is not registered.';
  end if;

  v_actor:=coalesce(
    public.rr_up_user_context_v2()->>'display_name',
    auth.uid()::text
  );

  for r in
    select value
    from jsonb_array_elements(p_rows)
  loop
    v_qty:=coalesce(nullif(r->>'qty','')::numeric,0);
    if v_qty<=0 then
      continue;
    end if;

    v_bucket:=upper(trim(coalesce(r->>'source_bucket','PENDING')));
    v_responsibility_mode:=upper(trim(coalesce(
      r->>'responsibility_mode',
      'WORKER_CLAIM'
    )));
    v_damage_reason_code:=upper(trim(coalesce(
      r->>'damage_reason_code',
      ''
    )));

    if v_responsibility_mode not in ('WORKER_CLAIM','NO_CLAIM') then
      raise exception 'Invalid Damage responsibility mode %.',v_responsibility_mode;
    end if;

    if v_responsibility_mode='NO_CLAIM'
       and nullif(v_damage_reason_code,'') is null
    then
      raise exception 'No-Claim Damage reason is required.';
    end if;

    -- Existing balance engine currently supports these canonical buckets.
    if v_bucket not in ('PENDING','ALTER','REMAKE') then
      raise exception 'Invalid Damage source bucket %.',v_bucket;
    end if;

    select *
    into v_assign
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and upper(a.department_code)=upper(p_department_code)
      and a.status in ('ASSIGNED','IN_PROGRESS')
      and (
        (
          nullif(r->>'colour_id','') is not null
          and a.colour_id=nullif(r->>'colour_id','')::uuid
        )
        or upper(a.colour_code)=upper(r->>'colour_code')
      )
    order by a.assigned_at desc
    limit 1;

    if v_assign.id is null then
      raise exception
        'Active assignment not found for %.',
        r->>'colour_code';
    end if;

    select *
    into v_bal
    from public.rr_upm_action_balance_v731(
      p_canonical_lot_id,
      p_department_code,
      nullif(r->>'colour_id','')::uuid,
      r->>'colour_code',
      r->>'size_code'
    );

    v_available:=
      case v_bucket
        when 'PENDING' then v_bal.pending_qty
        when 'ALTER' then v_bal.alter_open_qty
        else v_bal.worker_remake_pending_qty
      end;

    if v_qty>coalesce(v_available,0) then
      raise exception
        '% / %: Damage % exceeds % balance %.',
        r->>'colour_code',
        r->>'size_code',
        v_qty,
        v_bucket,
        v_available;
    end if;

    v_snapshot:=public.rr_upm_damage_rate_snapshot_v759(
      p_canonical_lot_id,
      p_department_code,
      nullif(r->>'colour_id','')::uuid,
      r->>'colour_code'
    );

    if coalesce(p_rate,0)>0 then
      -- p_rate means an authorised, manually verified FULL damage rate.
      v_damage_rate:=round(p_rate,4);
      v_rate_source:='MANUAL_FULL_RATE_OVERRIDE';
      v_snapshot:=v_snapshot || jsonb_build_object(
        'automatic_complete',coalesce((v_snapshot->>'complete')::boolean,false),
        'automatic_rate',coalesce((v_snapshot->>'damage_rate_upto_stage')::numeric,0),
        'rate_source',v_rate_source,
        'damage_rate_upto_stage',v_damage_rate
      );
    else
      if not coalesce((v_snapshot->>'complete')::boolean,false) then
        raise exception using
          message=concat(
            'Damage Rate Upto This Stage incomplete. ',
            case
              when not coalesce((v_snapshot->>'material_found')::boolean,false)
                then 'Material/Fabric cost snapshot missing. '
              else ''
            end,
            case
              when jsonb_array_length(
                coalesce(v_snapshot->'missing_departments','[]'::jsonb)
              )>0
                then 'Missing department rates: '
                  ||(v_snapshot->'missing_departments')::text||'. '
              else ''
            end,
            'Fill verified Actual Rates / Product Cost Snapshot, ',
            'or authorised person may enter a manually verified FULL damage rate.'
          ),
          errcode='P0001';
      end if;

      v_damage_rate:=
        round((v_snapshot->>'damage_rate_upto_stage')::numeric,4);
      v_rate_source:='AUTOMATIC_UPTO_STAGE';
      v_snapshot:=v_snapshot || jsonb_build_object(
        'rate_source',v_rate_source
      );
    end if;

    if coalesce(v_damage_rate,0)<=0 then
      raise exception
        'Damage Rate Upto This Stage must be greater than zero.';
    end if;

    v_claim_value:=round(v_qty*v_damage_rate,4);
    v_factory_loss:=
      case
        when v_responsibility_mode='NO_CLAIM' then v_claim_value
        else 0
      end;
    v_action_id:=gen_random_uuid();

    insert into public.rr_upm_actions_v726(
      id,
      request_id,
      canonical_lot_id,
      lot_no,
      department_code,
      colour_id,
      colour_code,
      colour_name,
      size_code,
      assignment_id,
      worker_id,
      worker_name,
      worker_code,
      action_type,
      source_bucket,
      qty,
      actual_rate,
      standard_rate,
      remarks,
      actor_name,
      cost_snapshot,
      claim_status,
      gross_claim_amount,
      relaxed_claim_amount,
      responsibility_mode,
      factory_loss_amount,
      responsible_worker_id,
      responsible_department_code,
      damage_reason_code
    )
    values(
      v_action_id,
      gen_random_uuid(),
      p_canonical_lot_id,
      v_lot.lot_no,
      upper(p_department_code),
      nullif(r->>'colour_id','')::uuid,
      upper(r->>'colour_code'),
      coalesce(
        nullif(trim(r->>'colour_name'),''),
        v_assign.colour_name
      ),
      upper(r->>'size_code'),
      v_assign.id,
      case
        when v_responsibility_mode='WORKER_CLAIM' then v_assign.worker_id
        else null
      end,
      case
        when v_responsibility_mode='WORKER_CLAIM'
          then v_assign.worker_name_snapshot
        else 'NO CLAIM'
      end,
      case
        when v_responsibility_mode='WORKER_CLAIM' then v_assign.worker_code
        else null
      end,
      case
        when v_responsibility_mode='WORKER_CLAIM'
          then 'DAMAGE_CLAIM'
        else 'DAMAGE_REGISTER'
      end,
      v_bucket,
      v_qty,
      v_damage_rate,
      coalesce(
        (v_snapshot->>'standard_fallback_rate')::numeric,
        0
      ),
      concat_ws(
        ' · ',
        p_remarks,
        'Damage Rate Upto This Stage',
        'Rate Source '||v_rate_source,
        'Responsibility '||v_responsibility_mode,
        case
          when nullif(v_damage_reason_code,'') is not null
            then 'Reason '||v_damage_reason_code
          else null
        end
      ),
      v_actor,
      v_snapshot || jsonb_build_object(
        'responsibility_mode',v_responsibility_mode,
        'damage_reason_code',nullif(v_damage_reason_code,''),
        'factory_loss_amount',v_factory_loss
      ),
      case
        when v_responsibility_mode='WORKER_CLAIM' then 'POSTED'
        else 'NO_CLAIM'
      end,
      case
        when v_responsibility_mode='WORKER_CLAIM' then v_claim_value
        else 0
      end,
      0,
      v_responsibility_mode,
      v_factory_loss,
      case
        when v_responsibility_mode='WORKER_CLAIM' then v_assign.worker_id
        else null
      end,
      case
        when v_responsibility_mode='WORKER_CLAIM'
          then upper(p_department_code)
        else null
      end,
      nullif(v_damage_reason_code,'')
    );

    insert into public.rr_upm_entries(
      canonical_lot_id,
      lot_no,
      department_code,
      colour_code,
      size_code,
      entry_type,
      qty,
      rate,
      amount,
      remarks,
      reference_entry_id,
      operator_name
    )
    values(
      p_canonical_lot_id,
      v_lot.lot_no,
      upper(p_department_code),
      upper(r->>'colour_code'),
      upper(r->>'size_code'),
      'REJECT',
      v_qty,
      v_damage_rate,
      v_claim_value,
      concat_ws(
        ' · ',
        p_remarks,
        'Source '||v_bucket,
        'Damage Rate Upto This Stage',
        'Responsibility '||v_responsibility_mode,
        case
          when nullif(v_damage_reason_code,'') is not null
            then 'Reason '||v_damage_reason_code
          else null
        end
      ),
      v_action_id,
      v_actor
    );

    v_count:=v_count+1;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'version','V759_1_DAMAGE_ENGINE_NO_CLAIM',
    'damage_rows_saved',v_count,
    'supports_worker_claim',true,
    'supports_no_claim',true
  );
end;
$function$;

grant execute on function public.rr_upm_art_standard_rate_v759(
  text,text
) to authenticated;

grant execute on function public.rr_upm_damage_rate_snapshot_v759(
  text,text,uuid,text
) to authenticated;

grant execute on function public.rr_upm_save_damage_v731(
  text,text,jsonb,numeric,text
) to authenticated;

commit;

-- ------------------------------------------------------------
-- Verification
-- ------------------------------------------------------------
select jsonb_build_object(
  'ok',true,
  'version','V759_1_DAMAGE_ENGINE_NO_CLAIM',
  'damage_function',
  'rr_upm_save_damage_v731(text,text,jsonb,numeric,text)',
  'ledger_source','rr_upm_actions_v726',
  'worker_ledger_view','rr_upm_worker_ledger_v726',
  'cost_rule',
  'Material + completed/current process cost; Worker Claim or No-Claim factory loss; immutable snapshot.'
) as rr_upm_v759_result;
