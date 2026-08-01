-- ============================================================
-- REDZED UPM V761 — IDENTITY MAPPING FIX
-- ============================================================
--
-- Exact culprit fixed:
--   public.rr_upm_resolve_identity_v740(text,boolean,text)
--
-- Problem:
--   Identity resolver depended mainly on rr_cutting_lots_v3.art_no /
--   print_no and returned an existing incomplete lock without re-checking.
--
-- New priority:
--   ART:
--     Cutting Lot art_no
--     → Lot Registry art_no
--     → Lot Registry art_id → Art Master
--     → Product Master art_id → Art Master
--     → Registry metadata art_no
--
--   PRINT:
--     Cutting Lot print_no
--     → Lot Registry print_no
--     → Lot Registry print_id → Print Master
--     → Product Print Links
--     → Registry metadata print_no
--
--   CB:
--     Fabric Purchase cb_no
--     → CB Unit cb_base_no
--     → CB Unit cb_code
--     → Registry metadata cb_no/cb_number/cb_base_no
--
-- Existing valid immutable lock remains unchanged.
-- Existing incomplete lock is automatically rebuilt.
-- ============================================================

begin;

create table if not exists public.rr_upm_function_backup_v761 (
  id bigserial primary key,
  function_identity text not null,
  version_tag text not null,
  function_definition text not null,
  backed_up_at timestamptz not null default now()
);

insert into public.rr_upm_function_backup_v761(
  function_identity,
  version_tag,
  function_definition
)
select
  'public.rr_upm_resolve_identity_v740(text,boolean,text)',
  'PRE_V761_IDENTITY_MAPPING_FIX',
  pg_get_functiondef(
    'public.rr_upm_resolve_identity_v740(text,boolean,text)'::regprocedure
  );

create or replace function public.rr_upm_resolve_identity_v740(
  p_canonical_lot_id text,
  p_force boolean,
  p_reason text
)
returns public.rr_upm_lot_identity_lock_v740
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r public.rr_upm_lot_identity_lock_v740;

  v_reg public.rr_upm_lot_registry%rowtype;
  v_cut public.rr_cutting_lots_v3%rowtype;

  v_cb text;
  v_division text;
  v_art_no text;
  v_print_no text;
  v_frames text;
  v_item_name text;

  v_product_id uuid;
  v_actor_role text;
  v_existing_valid boolean:=false;
begin
  /*
    Existing lock is returned only when the identity is actually complete.
    An old incomplete lock must not permanently block correct re-resolution.
  */
  select *
  into r
  from public.rr_upm_lot_identity_lock_v740
  where canonical_lot_id=p_canonical_lot_id
  limit 1;

  if found then
    v_existing_valid :=
      nullif(trim(coalesce(r.lot_no,'')),'') is not null
      and nullif(trim(coalesce(r.cb_no,'')),'') is not null
      and nullif(trim(coalesce(r.art_no,'')),'') is not null
      and upper(trim(coalesce(r.cb_no,''))) <> 'MAPPING REQUIRED'
      and upper(trim(coalesce(r.art_no,''))) <> 'MAPPING REQUIRED';

    if v_existing_valid and not coalesce(p_force,false) then
      return r;
    end if;
  end if;

  if coalesce(p_force,false) then
    v_actor_role :=
      public.rr_upm_norm_role_v740(
        public.rr_up_user_context_v2()->>'user_category'
      );

    if v_actor_role not in ('OWNER','ADMIN') then
      raise exception 'Only Owner/Admin can re-sync locked identity.';
    end if;

    if nullif(trim(coalesce(p_reason,'')),'') is null then
      raise exception 'Re-sync reason is required.';
    end if;
  end if;

  select *
  into v_reg
  from public.rr_upm_lot_registry
  where canonical_lot_id=p_canonical_lot_id
  limit 1;

  if not found then
    raise exception 'Lot not found in Universal Production registry.';
  end if;

  /*
    Prefer immutable source_id mapping.
    Lot No fallback is allowed only when source_id mapping cannot resolve.
  */
  if v_reg.source_id is not null then
    begin
      select *
      into v_cut
      from public.rr_cutting_lots_v3 c
      where c.id=v_reg.source_id::uuid
      limit 1;
    exception
      when invalid_text_representation then
        null;
    end;
  end if;

  if v_cut.id is null then
    select *
    into v_cut
    from public.rr_cutting_lots_v3 c
    where upper(trim(c.lot_no))=upper(trim(v_reg.lot_no))
    order by c.created_at desc nulls last
    limit 1;
  end if;

  if v_cut.id is null then
    raise exception
      'Released Cutting Lot mapping missing for Lot %.',
      v_reg.lot_no;
  end if;

  /*
    CB and Division mapping.
  */
  select
    coalesce(
      nullif(trim(fp.cb_no),''),
      nullif(trim(u.cb_base_no),''),
      nullif(trim(u.cb_code),'')
    ),
    coalesce(
      nullif(trim(u.cb_code),''),
      case
        when u.division_index is not null
          then 'D'||u.division_index
        else null
      end
    )
  into v_cb,v_division
  from public.rr_cb_units u
  left join public.rr_fabric_purchases fp
    on fp.id=coalesce(v_cut.cb_purchase_id,u.purchase_id)
  where u.id=v_cut.cb_unit_id
  limit 1;

  v_cb := coalesce(
    nullif(trim(v_cb),''),
    nullif(trim(v_reg.metadata->>'cb_no'),''),
    nullif(trim(v_reg.metadata->>'cb_number'),''),
    nullif(trim(v_reg.metadata->>'cb_base_no'),'')
  );

  v_division := coalesce(
    nullif(trim(v_division),''),
    nullif(trim(v_reg.metadata->>'division_code'),''),
    nullif(trim(v_reg.metadata->>'division'),'')
  );

  /*
    Product Master fallback link by Lot No.
  */
  select pm.id
  into v_product_id
  from public.rr_product_master pm
  where upper(trim(pm.lot_no))=upper(trim(v_reg.lot_no))
    and coalesce(pm.is_active,true)
  order by pm.updated_at desc nulls last,
           pm.created_at desc nulls last
  limit 1;

  /*
    ART mapping priority.
  */
  v_art_no := coalesce(
    nullif(trim(v_cut.art_no),''),
    nullif(trim(v_reg.art_no),''),
    (
      select nullif(trim(a.art_no),'')
      from public.rr_art_master a
      where a.id=v_reg.art_id
      limit 1
    ),
    (
      select nullif(trim(a.art_no),'')
      from public.rr_product_master pm
      join public.rr_art_master a on a.id=pm.art_id
      where pm.id=v_product_id
      limit 1
    ),
    nullif(trim(v_reg.metadata->>'art_no'),''),
    nullif(trim(v_reg.metadata->>'art'),'')
  );

  /*
    PRINT mapping priority.
  */
  v_print_no := coalesce(
    nullif(trim(v_cut.print_no),''),
    nullif(trim(v_reg.print_no),''),
    (
      select nullif(trim(pm.print_no),'')
      from public.rr_print_master pm
      where pm.id=v_reg.print_id
      limit 1
    ),
    (
      select string_agg(
        distinct nullif(trim(pm.print_no),''),
        ', '
        order by nullif(trim(pm.print_no),'')
      )
      from public.rr_product_print_links l
      join public.rr_print_master pm on pm.id=l.print_id
      where l.product_id=v_product_id
        and coalesce(pm.is_active,true)
    ),
    nullif(trim(v_reg.metadata->>'print_no'),''),
    nullif(trim(v_reg.metadata->>'print'),'')
  );

  /*
    Frame mapping follows the final resolved Print No.
  */
  if nullif(trim(coalesce(v_print_no,'')),'') is not null then
    select string_agg(
      distinct nullif(trim(f.frame_no),''),
      ', '
      order by nullif(trim(f.frame_no),'')
    )
    into v_frames
    from regexp_split_to_table(v_print_no,'\s*,\s*') z(print_no)
    join public.rr_print_master pm
      on upper(trim(pm.print_no))=upper(trim(z.print_no))
    join public.rr_print_frames f
      on f.print_id=pm.id
    where upper(coalesce(f.frame_status,'ACTIVE'))
      not in ('RETIRED','CANCELLED');
  end if;

  v_frames := coalesce(
    nullif(trim(v_frames),''),
    nullif(trim(v_reg.metadata->>'frame_no'),''),
    nullif(trim(v_reg.metadata->>'frames'),'')
  );

  v_item_name := coalesce(
    nullif(trim(v_reg.item_name),''),
    nullif(trim(v_reg.metadata->>'item_name'),''),
    nullif(trim(v_reg.metadata->>'product_name'),'')
  );

  /*
    Only truly missing mandatory identity should block Production.
  */
  if nullif(trim(coalesce(v_cb,'')),'') is null then
    raise exception
      'CB mapping missing after Cutting, Registry and Metadata checks.';
  end if;

  if nullif(trim(coalesce(v_art_no,'')),'') is null then
    raise exception
      'Art No mapping missing after Cutting, Registry, Art Master and Product Master checks.';
  end if;

  /*
    Rebuild only an incomplete lock, or an explicitly forced lock.
  */
  if r.canonical_lot_id is not null
     and (coalesce(p_force,false) or not v_existing_valid)
  then
    delete from public.rr_upm_lot_identity_lock_v740
    where canonical_lot_id=p_canonical_lot_id;
  end if;

  insert into public.rr_upm_lot_identity_lock_v740(
    canonical_lot_id,
    cutting_lot_id,
    lot_no,
    cb_no,
    division_code,
    art_no,
    print_no,
    frame_no,
    item_name
  )
  values(
    p_canonical_lot_id,
    v_cut.id,
    coalesce(nullif(trim(v_cut.lot_no),''),v_reg.lot_no),
    v_cb,
    v_division,
    v_art_no,
    v_print_no,
    v_frames,
    v_item_name
  )
  on conflict(canonical_lot_id)
  do update set
    cutting_lot_id=excluded.cutting_lot_id,
    lot_no=excluded.lot_no,
    cb_no=excluded.cb_no,
    division_code=excluded.division_code,
    art_no=excluded.art_no,
    print_no=excluded.print_no,
    frame_no=excluded.frame_no,
    item_name=excluded.item_name
  returning *
  into r;

  return r;
end;
$function$;

grant execute on function public.rr_upm_resolve_identity_v740(
  text,boolean,text
) to authenticated;

commit;

-- ============================================================
-- Verification — safe read/resolution for test Lot 2SKB6
-- ============================================================
select to_jsonb(
  public.rr_upm_resolve_identity_v740(
    (
      select canonical_lot_id
      from public.rr_upm_lot_registry
      where upper(trim(lot_no))='2SKB6'
      limit 1
    ),
    false,
    null
  )
) as rr_upm_v761_identity_result;
