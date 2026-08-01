-- ============================================================
-- REDZED UPM V760 — LOT COSTING FOUNDATION
-- ============================================================
--
-- ADDITIVE PACKAGE:
-- Existing Production, Assignment, Alter, Remake and Damage functions
-- are not replaced.
--
-- LOCKED RULES:
-- * One Lot + one canonical Department = one Actual Rate.
-- * First Submit from a Department requires Actual Rate.
-- * Standard Rate is suggestion/fallback, not primary.
-- * Department aliases resolve to one canonical costing head.
-- * QC is a dedicated costing head.
-- * TH CUT resolves to THREAD_CUT.
-- * Kaaj/Btn aliases resolve to KAJ_BUTTON.
-- * Tanki/Tack/Teak/Teek aliases resolve to TANKI_TACK.
-- * Damage never rewrites Product Cost. It appears as Company Loss.
-- * Universal Owner Margin is prospective.
-- * Store/Web locked Sale Price is unaffected by later universal margin.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Canonical alias table
-- ------------------------------------------------------------
create table if not exists public.rr_costing_department_aliases_v760 (
  id uuid primary key default gen_random_uuid(),
  alias_key text not null unique,
  alias_label text,
  canonical_code text not null,
  display_name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);

create index if not exists rr_costing_department_aliases_v760_canonical_idx
  on public.rr_costing_department_aliases_v760(canonical_code)
  where is_active;

create or replace function public.rr_costing_normalize_key_v760(p_value text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    upper(coalesce(trim(p_value),'')),
    '[^A-Z0-9]+',
    '',
    'g'
  )
$$;

insert into public.rr_costing_department_aliases_v760(
  alias_key,alias_label,canonical_code,display_name
)
values
  ('CUTTING','Cutting','CUTTING','Cutting'),

  ('PRINT','Print','PRINTING','Print'),
  ('PRINTING','Printing','PRINTING','Print'),

  ('KR','KR','STITCHING','Karigar / Stitching'),
  ('KARIGAR','Karigar','STITCHING','Karigar / Stitching'),
  ('STITCHING','Stitching','STITCHING','Karigar / Stitching'),

  ('OV','OV','OVERLOCK','Overlock'),
  ('OVERLOCK','Overlock','OVERLOCK','Overlock'),

  ('FLD','FLD','FOLDING','Folding'),
  ('FOLD','Fold','FOLDING','Folding'),
  ('FOLDING','Folding','FOLDING','Folding'),

  ('QC','QC','QC','QC'),
  ('CHECKING','Checking','QC','QC'),
  ('QUALITYCHECK','Quality Check','QC','QC'),
  ('QUALITYCHECKING','Quality Checking','QC','QC'),

  ('THCUT','TH Cut','THREAD_CUT','Thread Cut'),
  ('THREADCUT','Thread Cut','THREAD_CUT','Thread Cut'),
  ('THREADCUTTING','Thread Cutting','THREAD_CUT','Thread Cut'),

  ('PRESS','Press','PRESS','Press'),
  ('PRESSING','Pressing','PRESS','Press'),

  ('PACK','Pack','PACKING','Packing'),
  ('PACKING','Packing','PACKING','Packing'),

  ('STICKER','Sticker','STICKER','Sticker'),

  ('KAJ','Kaj','KAJ_BUTTON','Kaaj / Button'),
  ('KAAJ','Kaaj','KAJ_BUTTON','Kaaj / Button'),
  ('BTN','Btn','KAJ_BUTTON','Kaaj / Button'),
  ('BUTTON','Button','KAJ_BUTTON','Kaaj / Button'),
  ('KAJBTN','Kaj Btn','KAJ_BUTTON','Kaaj / Button'),
  ('KAAJBTN','Kaaj Btn','KAJ_BUTTON','Kaaj / Button'),
  ('KAJBUTTON','Kaj Button','KAJ_BUTTON','Kaaj / Button'),
  ('KAAJBUTTON','Kaaj Button','KAJ_BUTTON','Kaaj / Button'),

  ('TANKI','Tanki','TANKI_TACK','Tanki / Tack'),
  ('TACK','Tack','TANKI_TACK','Tanki / Tack'),
  ('TEAK','Teak','TANKI_TACK','Tanki / Tack'),
  ('TEEK','Teek','TANKI_TACK','Tanki / Tack'),
  ('TANKITACK','Tanki Tack','TANKI_TACK','Tanki / Tack'),
  ('TANKITEAK','Tanki Teak','TANKI_TACK','Tanki / Tack'),
  ('TANKITEEK','Tanki Teek','TANKI_TACK','Tanki / Tack'),

  ('OTHER','Other','OTHER','Other')
on conflict(alias_key) do update set
  alias_label=excluded.alias_label,
  canonical_code=excluded.canonical_code,
  display_name=excluded.display_name,
  is_active=true;

create or replace function public.rr_costing_canonical_department_v760(
  p_department text
)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_key text;
  v_code text;
begin
  v_key:=public.rr_costing_normalize_key_v760(p_department);

  select canonical_code
  into v_code
  from public.rr_costing_department_aliases_v760
  where alias_key=v_key
    and is_active
  limit 1;

  return coalesce(v_code,upper(trim(p_department)));
end;
$$;

create or replace function public.rr_costing_department_display_v760(
  p_department text
)
returns text
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    (
      select display_name
      from public.rr_costing_department_aliases_v760
      where canonical_code=
        public.rr_costing_canonical_department_v760(p_department)
        and is_active
      order by alias_key=canonical_code desc
      limit 1
    ),
    p_department
  )
$$;

-- ------------------------------------------------------------
-- 2. Universal Owner Margin — prospective only
-- ------------------------------------------------------------
create table if not exists public.rr_costing_universal_settings_v760 (
  setting_key text primary key,
  numeric_value numeric,
  text_value text,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  updated_by_name text
);

insert into public.rr_costing_universal_settings_v760(
  setting_key,numeric_value,text_value
)
values('OWNER_MARGIN_FLAT_PER_PCS',22,'Universal flat Owner Margin')
on conflict(setting_key) do nothing;

-- ------------------------------------------------------------
-- 3. Lot costing master
-- ------------------------------------------------------------
create table if not exists public.rr_upm_lot_costing_v760 (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null unique,
  lot_no text not null,
  art_no text,
  item_name text,

  regular_fabric_cost_per_piece numeric not null default 0,
  matching_cost_per_piece numeric not null default 0,
  other_material_cost_per_piece numeric not null default 0,
  material_cost_status text not null default 'MISSING',

  owner_margin_flat numeric not null default 0,
  owner_margin_source text not null default 'UNIVERSAL',
  owner_margin_applied_at timestamptz,

  process_actual_total numeric not null default 0,
  process_standard_fallback_total numeric not null default 0,
  material_total numeric not null default 0,
  base_cost_per_piece numeric not null default 0,
  final_sale_price numeric not null default 0,

  costing_status text not null default 'DRAFT',
  store_price_locked boolean not null default false,
  store_price_locked_at timestamptz,
  store_price_locked_by uuid,
  locked_sale_price numeric,

  dispatched_at timestamptz,
  archived_at timestamptz,
  archived_by uuid,

  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),

  constraint rr_upm_lot_costing_v760_material_status_chk
    check(material_cost_status in ('MISSING','PARTIAL','ACTUAL','NOT_APPLICABLE')),
  constraint rr_upm_lot_costing_v760_status_chk
    check(costing_status in (
      'DRAFT','IN_PROGRESS','READY_FOR_REVIEW',
      'FINALIZED','DISPATCH_LOCKED','OWNER_REOPENED','ARCHIVED'
    ))
);

create index if not exists rr_upm_lot_costing_v760_lot_idx
  on public.rr_upm_lot_costing_v760(upper(lot_no));

-- ------------------------------------------------------------
-- 4. First-submit rate requests
-- ------------------------------------------------------------
create table if not exists public.rr_upm_rate_requests_v760 (
  id uuid primary key default gen_random_uuid(),
  request_token uuid not null unique default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  colour_code text,
  request_status text not null default 'PENDING',
  requested_by uuid default auth.uid(),
  requested_by_name text,
  requested_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '24 hours'),
  opened_at timestamptz,
  opened_by uuid,
  filled_rate numeric,
  filled_at timestamptz,
  filled_by uuid,
  filled_by_name text,
  completed_at timestamptz,
  archived_at timestamptz,
  whatsapp_message_id text,
  metadata jsonb not null default '{}'::jsonb,

  constraint rr_upm_rate_requests_v760_status_chk
    check(request_status in (
      'PENDING','OPENED','RATE_FILLED','COMPLETED','EXPIRED','ARCHIVED','CANCELLED'
    ))
);

create unique index if not exists rr_upm_rate_requests_v760_one_pending_idx
  on public.rr_upm_rate_requests_v760(
    canonical_lot_id,department_code
  )
  where request_status in ('PENDING','OPENED','RATE_FILLED');

-- ------------------------------------------------------------
-- 5. Standard Rate resolver
--    Process table first; legacy summary second.
-- ------------------------------------------------------------
create or replace function public.rr_costing_standard_rate_v760(
  p_art_no text,
  p_department_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_canonical text;
  v_art_id uuid;
  v_rate numeric:=0;
  v_source text:='MISSING';
begin
  v_canonical:=
    public.rr_costing_canonical_department_v760(p_department_code);

  select id
  into v_art_id
  from public.rr_art_master
  where upper(art_no)=upper(trim(p_art_no))
    and coalesce(is_active,true)
  limit 1;

  if v_art_id is not null then
    select coalesce(total_rate,basic_rate+coalesce(extra_rate,0),0)
    into v_rate
    from public.rr_art_process_costs
    where art_id=v_art_id
      and public.rr_costing_canonical_department_v760(process_code)=v_canonical
    order by updated_at desc
    limit 1;

    if coalesce(v_rate,0)>0 then
      v_source:='ART_PROCESS_STANDARD';
    end if;
  end if;

  if coalesce(v_rate,0)<=0 then
    select
      case v_canonical
        when 'CUTTING' then coalesce(a.cutting_rate,0)
        when 'PRINTING' then coalesce(a.printing_rate,0)
        when 'STICKER' then coalesce(a.sticker_rate,0)
        when 'STITCHING' then coalesce(a.kr_rate,0)
        when 'OVERLOCK' then coalesce(a.ov_rate,0)
        when 'FOLDING' then coalesce(a.fld_rate,0)
        when 'KAJ_BUTTON' then coalesce(a.kaj_button_rate,0)
        when 'TANKI_TACK' then coalesce(a.tanki_tack_rate,0)
        when 'THREAD_CUT' then coalesce(a.thread_cut_rate,0)
        when 'PRESS' then coalesce(a.press_rate,0)
        when 'PACKING' then coalesce(a.packing_rate,0)
        when 'QC' then 0
        else coalesce(a.other_rate,0)
      end
    into v_rate
    from public.rr_art_cost_summary a
    where upper(a.art_no)=upper(trim(p_art_no))
      and coalesce(a.is_active,true)
    limit 1;

    if coalesce(v_rate,0)>0 then
      v_source:='ART_LEGACY_STANDARD';
    end if;
  end if;

  return jsonb_build_object(
    'canonical_code',v_canonical,
    'display_name',public.rr_costing_department_display_v760(v_canonical),
    'standard_rate',round(coalesce(v_rate,0),4),
    'source',v_source
  );
end;
$$;

-- ------------------------------------------------------------
-- 6. Permission helper
-- ------------------------------------------------------------
create or replace function public.rr_costing_user_scope_v760(
  p_department_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_profile public.rr_user_profiles%rowtype;
  v_role text;
  v_canonical text;
  v_owner boolean:=false;
  v_full boolean:=false;
  v_own_department boolean:=false;
begin
  select *
  into v_profile
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found then
    raise exception 'Active User Directory profile required.';
  end if;

  v_role:=lower(coalesce(v_profile.role_code,''));
  v_canonical:=
    public.rr_costing_canonical_department_v760(p_department_code);

  v_owner:=v_role='owner';
  v_full:=v_role in ('owner','admin','manager');

  if p_department_code is not null then
    begin
      v_own_department:=
        public.rr_up_is_department_head_v2(v_canonical);
    exception when others then
      v_own_department:=false;
    end;
  end if;

  return jsonb_build_object(
    'role',v_role,
    'is_owner',v_owner,
    'full_rate_access',v_full,
    'own_department_access',v_own_department,
    'can_view_material',v_owner,
    'can_edit_material',v_owner,
    'can_edit_owner_margin',v_owner,
    'can_edit_rate',v_full or v_own_department
  );
end;
$$;

-- ------------------------------------------------------------
-- 7. Canonical Actual Rate save
-- ------------------------------------------------------------
create or replace function public.rr_upm_set_department_rate_v760(
  p_canonical_lot_id text,
  p_department_code text,
  p_actual_rate numeric,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_lot public.rr_upm_lot_registry%rowtype;
  v_code text;
  v_scope jsonb;
  v_name text;
  v_old numeric;
  v_row public.rr_upm_department_rates_v2%rowtype;
  v_request public.rr_upm_rate_requests_v760%rowtype;
  v_line_man_request boolean:=false;
begin
  if p_actual_rate is null or p_actual_rate<0 then
    raise exception 'Actual Rate zero ya usse zyada honi chahiye.';
  end if;

  select *
  into v_lot
  from public.rr_upm_lot_registry
  where canonical_lot_id=p_canonical_lot_id
  limit 1;

  if not found then
    raise exception 'Production Lot nahi mila.';
  end if;

  v_code:=public.rr_costing_canonical_department_v760(p_department_code);
  v_scope:=public.rr_costing_user_scope_v760(v_code);
  v_name:=coalesce(
    public.rr_up_user_context_v2()->>'display_name',
    auth.uid()::text
  );

  if p_request_id is not null then
    select *
    into v_request
    from public.rr_upm_rate_requests_v760
    where id=p_request_id
      and canonical_lot_id=p_canonical_lot_id
      and department_code=v_code
      and request_status in ('PENDING','OPENED')
      and expires_at>now()
    for update;

    v_line_man_request:=
      found
      and v_request.requested_by=auth.uid();
  end if;

  if not coalesce((v_scope->>'can_edit_rate')::boolean,false)
     and not v_line_man_request
  then
    raise exception
      'Is Department ki Actual Rate fill/edit permission nahi hai.';
  end if;

  select actual_rate
  into v_old
  from public.rr_upm_department_rates_v2
  where canonical_lot_id=p_canonical_lot_id
    and public.rr_costing_canonical_department_v760(department_code)=v_code
  order by updated_at desc
  limit 1;

  -- Remove alias duplicate only when the canonical row is being saved.
  delete from public.rr_upm_department_rates_v2
  where canonical_lot_id=p_canonical_lot_id
    and public.rr_costing_canonical_department_v760(department_code)=v_code
    and department_code<>v_code;

  insert into public.rr_upm_department_rates_v2(
    canonical_lot_id,lot_no,department_code,actual_rate,
    filled_by,filled_by_name,
    updated_by,updated_by_name,updated_at
  )
  values(
    p_canonical_lot_id,v_lot.lot_no,v_code,round(p_actual_rate,4),
    auth.uid(),v_name,
    auth.uid(),v_name,now()
  )
  on conflict(canonical_lot_id,department_code)
  do update set
    actual_rate=excluded.actual_rate,
    updated_by=auth.uid(),
    updated_by_name=v_name,
    updated_at=now()
  returning *
  into v_row;

  insert into public.rr_upm_department_rate_log_v2(
    rate_id,old_rate,new_rate,changed_by_name
  )
  values(v_row.id,v_old,round(p_actual_rate,4),v_name);

  if p_request_id is not null then
    update public.rr_upm_rate_requests_v760
    set
      request_status='COMPLETED',
      filled_rate=round(p_actual_rate,4),
      filled_at=now(),
      filled_by=auth.uid(),
      filled_by_name=v_name,
      completed_at=now(),
      archived_at=now()
    where id=p_request_id;
  else
    update public.rr_upm_rate_requests_v760
    set
      request_status='COMPLETED',
      filled_rate=round(p_actual_rate,4),
      filled_at=now(),
      filled_by=auth.uid(),
      filled_by_name=v_name,
      completed_at=now(),
      archived_at=now()
    where canonical_lot_id=p_canonical_lot_id
      and department_code=v_code
      and request_status in ('PENDING','OPENED','RATE_FILLED');
  end if;

  return jsonb_build_object(
    'ok',true,
    'version','V760_COSTING_FOUNDATION',
    'canonical_lot_id',p_canonical_lot_id,
    'lot_no',v_lot.lot_no,
    'department_code',v_code,
    'department_name',public.rr_costing_department_display_v760(v_code),
    'actual_rate',v_row.actual_rate,
    'rate_id',v_row.id,
    'filled_by_name',v_name
  );
end;
$$;

-- ------------------------------------------------------------
-- 8. First-submit Actual Rate gate
-- ------------------------------------------------------------
create or replace function public.rr_upm_first_submit_rate_gate_v760(
  p_canonical_lot_id text,
  p_department_code text,
  p_colour_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_lot public.rr_upm_lot_registry%rowtype;
  v_code text;
  v_rate numeric;
  v_standard jsonb;
  v_request public.rr_upm_rate_requests_v760%rowtype;
  v_name text;
  v_first_submit boolean;
begin
  select *
  into v_lot
  from public.rr_upm_lot_registry
  where canonical_lot_id=p_canonical_lot_id
  limit 1;

  if not found then
    raise exception 'Lot nahi mila.';
  end if;

  v_code:=public.rr_costing_canonical_department_v760(p_department_code);

  select actual_rate
  into v_rate
  from public.rr_upm_department_rates_v2
  where canonical_lot_id=p_canonical_lot_id
    and public.rr_costing_canonical_department_v760(department_code)=v_code
  order by updated_at desc
  limit 1;

  -- Gate matters only until the first completed submit of this department.
  select not exists(
    select 1
    from public.rr_upm_work_assignments_v8
    where canonical_lot_id=p_canonical_lot_id
      and public.rr_costing_canonical_department_v760(department_code)=v_code
      and status='COMPLETED'
  )
  into v_first_submit;

  if coalesce(v_rate,0)>0 or not v_first_submit then
    return jsonb_build_object(
      'ok',true,
      'allowed',true,
      'first_submit',v_first_submit,
      'department_code',v_code,
      'actual_rate',coalesce(v_rate,0)
    );
  end if;

  v_standard:=
    public.rr_costing_standard_rate_v760(v_lot.art_no,v_code);
  v_name:=coalesce(
    public.rr_up_user_context_v2()->>'display_name',
    auth.uid()::text
  );

  insert into public.rr_upm_rate_requests_v760(
    canonical_lot_id,lot_no,department_code,colour_code,
    requested_by,requested_by_name,
    metadata
  )
  values(
    p_canonical_lot_id,v_lot.lot_no,v_code,upper(p_colour_code),
    auth.uid(),v_name,
    jsonb_build_object(
      'art_no',v_lot.art_no,
      'item_name',v_lot.item_name,
      'standard_rate',v_standard->'standard_rate',
      'standard_source',v_standard->>'source',
      'request_purpose','FIRST_SUBMIT_RATE_GATE'
    )
  )
  on conflict(canonical_lot_id,department_code)
    where request_status in ('PENDING','OPENED','RATE_FILLED')
  do update set
    colour_code=excluded.colour_code,
    requested_by=auth.uid(),
    requested_by_name=v_name,
    requested_at=now(),
    expires_at=now()+interval '24 hours',
    metadata=public.rr_upm_rate_requests_v760.metadata||excluded.metadata
  returning *
  into v_request;

  return jsonb_build_object(
    'ok',true,
    'allowed',false,
    'first_submit',true,
    'reason','ACTUAL_RATE_REQUIRED',
    'message','First Submit se pehle Actual Rate fill karna mandatory hai.',
    'canonical_lot_id',p_canonical_lot_id,
    'lot_no',v_lot.lot_no,
    'colour_code',upper(p_colour_code),
    'department_code',v_code,
    'department_name',public.rr_costing_department_display_v760(v_code),
    'standard_rate',coalesce((v_standard->>'standard_rate')::numeric,0),
    'standard_source',v_standard->>'source',
    'request_id',v_request.id,
    'request_token',v_request.request_token,
    'expires_at',v_request.expires_at
  );
end;
$$;

-- ------------------------------------------------------------
-- 9. Lot costing refresh and Company Loss summary
-- ------------------------------------------------------------
create or replace function public.rr_upm_refresh_lot_costing_v760(
  p_canonical_lot_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
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
  d record;
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
    v_universal_margin,'UNIVERSAL',now(),
    auth.uid(),auth.uid()
  )
  on conflict(canonical_lot_id) do nothing;

  select *
  into v_row
  from public.rr_upm_lot_costing_v760
  where canonical_lot_id=p_canonical_lot_id
  for update;

  v_material:=
    coalesce(v_row.regular_fabric_cost_per_piece,0)
    +coalesce(v_row.matching_cost_per_piece,0)
    +coalesce(v_row.other_material_cost_per_piece,0);

  for d in
    select distinct
      public.rr_costing_canonical_department_v760(department_code) as department_code
    from public.rr_upm_work_assignments_v8
    where canonical_lot_id=p_canonical_lot_id
  loop
    select actual_rate
    into d
    from public.rr_upm_department_rates_v2
    where canonical_lot_id=p_canonical_lot_id
      and public.rr_costing_canonical_department_v760(department_code)
        =d.department_code
    order by updated_at desc
    limit 1;

    if found and coalesce(d.actual_rate,0)>0 then
      v_actual_total:=v_actual_total+d.actual_rate;
    else
      v_standard:=
        public.rr_costing_standard_rate_v760(
          v_lot.art_no,
          d.department_code
        );
      v_standard_total:=
        v_standard_total+
        coalesce((v_standard->>'standard_rate')::numeric,0);
    end if;
  end loop;

  select
    coalesce(sum(
      case
        when action_type in ('DAMAGE','DAMAGE_CLAIM','DAMAGE_REGISTER','ALTER_TO_DAMAGE')
          then coalesce(gross_claim_amount,qty*actual_rate,0)
        else 0
      end
    ),0),
    coalesce(sum(
      case
        when action_type='DAMAGE_CLAIM'
          then coalesce(gross_claim_amount,qty*actual_rate,0)
        else 0
      end
    ),0),
    coalesce(sum(
      case
        when action_type='DAMAGE_REGISTER'
          then coalesce(factory_loss_amount,qty*actual_rate,0)
        else 0
      end
    ),0),
    coalesce(sum(
      case
        when action_type in ('CLAIM_RELAXATION','CLAIM_REVOKE')
          then abs(coalesce(qty*actual_rate,gross_claim_amount,0))
        else 0
      end
    ),0)
  into
    v_damage_loss,
    v_worker_claim,
    v_no_claim_loss,
    v_recovery
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
  returning *
  into v_row;

  return jsonb_build_object(
    'ok',true,
    'version','V760_COSTING_FOUNDATION',
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
$$;

-- ------------------------------------------------------------
-- 10. Costing popup data
-- ------------------------------------------------------------
create or replace function public.rr_upm_costing_panel_v760(
  p_canonical_lot_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
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

  if not found then
    raise exception 'Lot nahi mila.';
  end if;

  v_refresh:=public.rr_upm_refresh_lot_costing_v760(p_canonical_lot_id);

  for d in
    select distinct
      public.rr_costing_canonical_department_v760(department_code) as code
    from public.rr_upm_departments
    where is_active
      and coalesce(rate_enabled,true)
    union
    select distinct
      public.rr_costing_canonical_department_v760(department_code)
    from public.rr_upm_work_assignments_v8
    where canonical_lot_id=p_canonical_lot_id
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

    if not v_visible then
      continue;
    end if;

    select actual_rate
    into v_actual
    from public.rr_upm_department_rates_v2
    where canonical_lot_id=p_canonical_lot_id
      and public.rr_costing_canonical_department_v760(department_code)=d.code
    order by updated_at desc
    limit 1;

    v_standard:=
      public.rr_costing_standard_rate_v760(v_lot.art_no,d.code);

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
        'department_name',
          public.rr_costing_department_display_v760(d.code),
        'actual_rate',v_actual,
        'standard_rate',coalesce((v_standard->>'standard_rate')::numeric,0),
        'standard_source',v_standard->>'source',
        'rate_used',
          case
            when coalesce(v_actual,0)>0 then v_actual
            else coalesce((v_standard->>'standard_rate')::numeric,0)
          end,
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
    'version','V760_COSTING_FOUNDATION',
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
$$;

-- ------------------------------------------------------------
-- 11. Owner material/margin updates and store lock
-- ------------------------------------------------------------
create or replace function public.rr_upm_update_lot_costing_v760(
  p_canonical_lot_id text,
  p_regular_fabric numeric default null,
  p_matching numeric default null,
  p_other_material numeric default null,
  p_material_status text default null,
  p_owner_margin numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_scope jsonb;
  v_row public.rr_upm_lot_costing_v760%rowtype;
begin
  v_scope:=public.rr_costing_user_scope_v760(null);

  if not coalesce((v_scope->>'is_owner')::boolean,false) then
    raise exception 'Material aur Owner Margin sirf Owner edit kar sakta hai.';
  end if;

  perform public.rr_upm_refresh_lot_costing_v760(p_canonical_lot_id);

  select *
  into v_row
  from public.rr_upm_lot_costing_v760
  where canonical_lot_id=p_canonical_lot_id
  for update;

  if v_row.store_price_locked then
    raise exception
      'Store Sale Price locked hai. Pehle Owner Reopen action required hai.';
  end if;

  update public.rr_upm_lot_costing_v760
  set
    regular_fabric_cost_per_piece=
      coalesce(p_regular_fabric,regular_fabric_cost_per_piece),
    matching_cost_per_piece=
      coalesce(p_matching,matching_cost_per_piece),
    other_material_cost_per_piece=
      coalesce(p_other_material,other_material_cost_per_piece),
    material_cost_status=
      coalesce(upper(p_material_status),material_cost_status),
    owner_margin_flat=
      coalesce(p_owner_margin,owner_margin_flat),
    owner_margin_source=
      case when p_owner_margin is null then owner_margin_source else 'LOT_OVERRIDE' end,
    owner_margin_applied_at=
      case when p_owner_margin is null then owner_margin_applied_at else now() end,
    updated_at=now(),
    updated_by=auth.uid()
  where canonical_lot_id=p_canonical_lot_id;

  return public.rr_upm_refresh_lot_costing_v760(p_canonical_lot_id);
end;
$$;

create or replace function public.rr_upm_set_universal_owner_margin_v760(
  p_margin numeric
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_scope jsonb;
  v_name text;
  v_updated integer;
begin
  v_scope:=public.rr_costing_user_scope_v760(null);

  if not coalesce((v_scope->>'is_owner')::boolean,false) then
    raise exception 'Universal Owner Margin sirf Owner change kar sakta hai.';
  end if;

  if p_margin is null or p_margin<0 then
    raise exception 'Owner Margin zero ya usse zyada honi chahiye.';
  end if;

  v_name:=coalesce(
    public.rr_up_user_context_v2()->>'display_name',
    auth.uid()::text
  );

  insert into public.rr_costing_universal_settings_v760(
    setting_key,numeric_value,text_value,
    updated_at,updated_by,updated_by_name
  )
  values(
    'OWNER_MARGIN_FLAT_PER_PCS',
    round(p_margin,4),
    'Universal flat Owner Margin',
    now(),auth.uid(),v_name
  )
  on conflict(setting_key) do update set
    numeric_value=excluded.numeric_value,
    updated_at=now(),
    updated_by=auth.uid(),
    updated_by_name=v_name;

  update public.rr_upm_lot_costing_v760
  set
    owner_margin_flat=round(p_margin,4),
    owner_margin_source='UNIVERSAL',
    owner_margin_applied_at=now(),
    updated_at=now(),
    updated_by=auth.uid()
  where not store_price_locked
    and owner_margin_source='UNIVERSAL'
    and costing_status not in ('ARCHIVED','DISPATCH_LOCKED');

  get diagnostics v_updated=row_count;

  return jsonb_build_object(
    'ok',true,
    'version','V760_COSTING_FOUNDATION',
    'universal_owner_margin',round(p_margin,4),
    'unlocked_lots_updated',v_updated,
    'locked_store_prices_unchanged',true
  );
end;
$$;

create or replace function public.rr_upm_lock_store_price_v760(
  p_canonical_lot_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_scope jsonb;
  v_refresh jsonb;
  v_row public.rr_upm_lot_costing_v760%rowtype;
begin
  v_scope:=public.rr_costing_user_scope_v760(null);

  if not coalesce((v_scope->>'is_owner')::boolean,false)
     and coalesce(v_scope->>'role','')<>'admin'
  then
    raise exception 'Store Price lock permission denied.';
  end if;

  v_refresh:=public.rr_upm_refresh_lot_costing_v760(p_canonical_lot_id);

  select *
  into v_row
  from public.rr_upm_lot_costing_v760
  where canonical_lot_id=p_canonical_lot_id
  for update;

  if v_row.material_cost_status not in ('ACTUAL','NOT_APPLICABLE') then
    raise exception 'Material Cost complete/final nahi hai.';
  end if;

  if exists(
    select 1
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and not exists(
        select 1
        from public.rr_upm_department_rates_v2 r
        where r.canonical_lot_id=p_canonical_lot_id
          and public.rr_costing_canonical_department_v760(r.department_code)
            =public.rr_costing_canonical_department_v760(a.department_code)
          and r.actual_rate>0
      )
  ) then
    raise exception 'Applicable Department Actual Rates abhi complete nahi hain.';
  end if;

  update public.rr_upm_lot_costing_v760
  set
    store_price_locked=true,
    store_price_locked_at=now(),
    store_price_locked_by=auth.uid(),
    locked_sale_price=final_sale_price,
    costing_status='DISPATCH_LOCKED',
    updated_at=now(),
    updated_by=auth.uid()
  where canonical_lot_id=p_canonical_lot_id
  returning *
  into v_row;

  return jsonb_build_object(
    'ok',true,
    'version','V760_COSTING_FOUNDATION',
    'locked',true,
    'lot_no',v_row.lot_no,
    'locked_sale_price',v_row.locked_sale_price,
    'future_universal_margin_effect',false
  );
end;
$$;

grant execute on function public.rr_costing_canonical_department_v760(text)
  to authenticated;
grant execute on function public.rr_costing_department_display_v760(text)
  to authenticated;
grant execute on function public.rr_costing_standard_rate_v760(text,text)
  to authenticated;
grant execute on function public.rr_costing_user_scope_v760(text)
  to authenticated;
grant execute on function public.rr_upm_set_department_rate_v760(text,text,numeric,uuid)
  to authenticated;
grant execute on function public.rr_upm_first_submit_rate_gate_v760(text,text,text)
  to authenticated;
grant execute on function public.rr_upm_refresh_lot_costing_v760(text)
  to authenticated;
grant execute on function public.rr_upm_costing_panel_v760(text)
  to authenticated;
grant execute on function public.rr_upm_update_lot_costing_v760(
  text,numeric,numeric,numeric,text,numeric
) to authenticated;
grant execute on function public.rr_upm_set_universal_owner_margin_v760(numeric)
  to authenticated;
grant execute on function public.rr_upm_lock_store_price_v760(text)
  to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V760_COSTING_FOUNDATION',
  'actual_rate_identity','Canonical Lot + Canonical Department',
  'first_submit_gate',true,
  'qc_dedicated',true,
  'thread_cut_aliases',jsonb_build_array('TH CUT','THREAD CUT','THREAD CUTTING'),
  'kaaj_button_aliases',jsonb_build_array(
    'KAAJ BTN','KAAJ/BTN','KAJ BTN','KAJ.BTN','KAAJ.BTN','KAJ/BTN'
  ),
  'tanki_tack_aliases',jsonb_build_array(
    'TANKI TACK','TANKI TEAK','TANKI TEEK','TACK','TEAK','TEEK'
  ),
  'damage_costing_rule','Every Damage is Company Loss; recovery remains separate.',
  'locked_store_price_protected_from_future_margin',true
) as rr_upm_v760_result;
