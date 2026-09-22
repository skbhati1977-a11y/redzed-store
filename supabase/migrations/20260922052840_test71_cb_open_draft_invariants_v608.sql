-- TEST71 V608 · CB Department OPEN/DRAFT invariants.
-- Preserves the existing V600 mutation engine while adding transaction-level
-- retry serialization and a canonical CB identity guard. No business record is
-- rewritten by this migration; CB 1004 is inspected read-only by the E2E RPC.

begin;

-- One active canonical CB identity. The partial expression index is the final
-- concurrency backstop; the trigger below adds transaction serialization and a
-- clear business error without creating a second CB engine.
create unique index if not exists rr_fabric_purchases_active_cb_no_v608_uq
  on public.rr_fabric_purchases(
    (regexp_replace(upper(trim(coalesce(cb_no,''))),'\s+','','g'))
  )
  where upper(coalesce(operation_status,'ACTIVE'))='ACTIVE'
    and trim(coalesce(cb_no,''))<>'';

create or replace function public.rr_guard_cb_number_identity_v608()
returns trigger
language plpgsql
security definer
set search_path='public','pg_temp'
as $function$
declare
  v_key text:=regexp_replace(upper(trim(coalesce(new.cb_no,''))),'\s+','','g');
begin
  if v_key='' or upper(coalesce(new.operation_status,'ACTIVE'))<>'ACTIVE' then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('RR_CB_NO:'||v_key,608));
  if exists(
    select 1
    from public.rr_fabric_purchases fp
    where regexp_replace(upper(trim(coalesce(fp.cb_no,''))),'\s+','','g')=v_key
      and upper(coalesce(fp.operation_status,'ACTIVE'))='ACTIVE'
      and (tg_op='INSERT' or fp.id<>new.id)
  ) then
    raise exception 'CB No. % already exists.',new.cb_no using errcode='23505';
  end if;
  return new;
end
$function$;

drop trigger if exists rr_000_cb_number_identity_v608 on public.rr_fabric_purchases;
create trigger rr_000_cb_number_identity_v608
before insert or update of cb_no,operation_status on public.rr_fabric_purchases
for each row execute function public.rr_guard_cb_number_identity_v608();

revoke all on function public.rr_guard_cb_number_identity_v608() from public,anon,authenticated;
grant execute on function public.rr_guard_cb_number_identity_v608() to service_role;

-- Same action UUID now serializes before the existing audit lookup. A double
-- tap, slow response or browser retry therefore observes the committed audit
-- result instead of racing a second canonical mutation.
do $do$
declare
  v_def text;
  v_next text;
  v_marker text:=$marker$if p_action_id is null then raise exception 'Action ID required.'; end if;
  select jsonb_build_object$marker$;
  v_replacement text:=$marker$if p_action_id is null then raise exception 'Action ID required.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('RR_CB_ACTION:'||p_action_id::text,608));
  select jsonb_build_object$marker$;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='rr_cb_department_save_v600'
    and pg_get_function_identity_arguments(p.oid)='p_cb_id uuid, p_action_id uuid, p_confirm boolean, p_payload jsonb';
  if v_def is null then raise exception 'V600 CB save RPC unavailable'; end if;
  if position('RR_CB_ACTION:' in v_def)=0 then
    v_next:=replace(v_def,v_marker,v_replacement);
    if v_next=v_def then raise exception 'CB action serialization patch did not match'; end if;
    execute v_next;
  end if;
end
$do$;

comment on function public.rr_cb_department_save_v600(uuid,uuid,boolean,jsonb) is
  'Canonical same-CB Draft/Confirm/late-DUE mutation; V608 serializes logical action retries before mutation.';

-- Parameterized read-only evidence for any reported CB. It deliberately
-- performs no UPDATE/INSERT/DELETE and is callable only by the reusable TEST
-- E2E owner. No named CB receives special business behavior.
create or replace function public.rr_test_cb_snapshot_v608(p_cb_no text)
returns jsonb
language plpgsql
stable
security definer
set search_path='public','pg_temp'
as $function$
declare
  v_role text;
  v_name text;
  v_rows jsonb;
begin
  select upper(coalesce(role_code,'')),coalesce(full_name,'')
    into v_role,v_name
  from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active
  order by updated_at desc nulls last
  limit 1;
  if v_role not in('OWNER','SUPER_ADMIN') or lower(v_name) not like '%test%e2e%' then
    raise exception 'TEST71 E2E Super Admin session required.' using errcode='42501';
  end if;
  if nullif(regexp_replace(upper(trim(coalesce(p_cb_no,''))),'\s+','','g'),'') is null then
    raise exception 'CB No. required.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'cb_id',fp.id,
    'cb_no',fp.cb_no,
    'department_state',fp.cb_department_state,
    'division_count',fp.division_count,
    'colour_count',fp.colour_count,
    'updated_at',fp.updated_at,
    'entries',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,
        'entry_notes',p.entry_notes,
        'quantity',p.quantity,
        'rate',p.rate,
        'amount',p.amount,
        'original_quantity',p.original_quantity,
        'original_rate',p.original_rate,
        'original_amount',p.original_amount,
        'available_quantity',p.available_quantity,
        'unit',p.unit,
        'requirement_state',p.requirement_state,
        'rolls',coalesce((
          select jsonb_agg(jsonb_build_object(
            'id',r.id,
            'colour_id',r.cb_colour_id,
            'colour_no',c.col_no,
            'roll_no',r.roll_no,
            'quantity',r.quantity,
            'original_quantity',r.original_quantity
          ) order by c.col_no,r.roll_no)
          from public.rr_cb_purchase_rolls r
          join public.rr_cb_colours c on c.id=r.cb_colour_id
          where r.purchase_entry_id=p.id
        ),'[]'::jsonb)
      ) order by p.created_at)
      from public.rr_cb_purchase_entries p
      where p.cb_id=fp.id
    ),'[]'::jsonb),
    'frontend_detail',public.rr_cb_department_detail_v600(fp.id)
  ) order by fp.updated_at desc),'[]'::jsonb)
  into v_rows
  from public.rr_fabric_purchases fp
  where regexp_replace(upper(trim(coalesce(fp.cb_no,''))),'\s+','','g')
    =regexp_replace(upper(trim(p_cb_no)),'\s+','','g');

  return jsonb_build_object(
    'read_only',true,
    'found_count',jsonb_array_length(v_rows),
    'rows',v_rows
  );
end
$function$;

revoke all on function public.rr_test_cb_snapshot_v608(text) from public,anon;
grant execute on function public.rr_test_cb_snapshot_v608(text) to authenticated,service_role;

-- Transactional proof: Roll 1 / Qty 120, Rate 365 and Value 43,800
-- survive an identical retry plus a second intentional Draft Save. The fixture
-- is rolled back before the RPC returns.
create or replace function public.rr_test_cb_open_draft_invariants_v608()
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $function$
declare
  v_role text;
  v_name text;
  v_regular uuid;
  v_cb uuid;
  v_cb_no text:='TEST71-CB-DRAFT-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  v_regular_key uuid:=gen_random_uuid();
  v_action uuid:=gen_random_uuid();
  v_payload jsonb;
  v_first jsonb;
  v_retry jsonb;
  v_second jsonb;
  v_natural_retry jsonb;
  v_natural_duplicate_blocked boolean:=false;
  v_detail jsonb;
  v_counts jsonb;
  v_result jsonb:='{}'::jsonb;
  v_residue integer:=0;
begin
  select upper(coalesce(role_code,'')),coalesce(full_name,'')
    into v_role,v_name
  from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active
  order by updated_at desc nulls last
  limit 1;
  if v_role not in('OWNER','SUPER_ADMIN') or lower(v_name) not like '%test%e2e%' then
    raise exception 'TEST71 E2E Super Admin session required.' using errcode='42501';
  end if;
  if coalesce((public.rr_upm_effective_identity_v200()->>'on_behalf')::boolean,false) then
    raise exception 'Return Act As to signed-in TEST E2E Super Admin first.';
  end if;

  select id into v_regular
  from public.rr_material_categories
  where lower(category_code)='regular-cloth' and is_active
  limit 1;
  if v_regular is null then raise exception 'Canonical Regular Cloth mapping unavailable.'; end if;

  begin
    v_payload:=jsonb_build_object(
      'cb_no',v_cb_no,
      'division_count',2,
      'colour_count',1,
      'remarks','TEST71 V608 rollback-only draft invariant',
      'colours',jsonb_build_array(jsonb_build_object(
        'index',1,'name','Colour 1',
        'image_url','https://example.invalid/test71-v608.jpg',
        'confirmed',true
      )),
      'regular',jsonb_build_object(
        'client_key',v_regular_key,
        'category_id',v_regular,
        'vendor','TEST71 Supplier',
        'bill_no','TEST71-V608-1',
        'bill_date',current_date,
        'fabric_name','TEST71 Regular Cloth',
        'qty',120,
        'rate',365,
        'amount',43800,
        'rolls',jsonb_build_array(jsonb_build_object(
          'colour_index',1,'roll_no',1,'qty',120
        ))
      ),
      'materials','[]'::jsonb
    );

    v_first:=public.rr_cb_department_save_v600(null,v_action,false,v_payload);
    v_cb:=(v_first->>'cb_id')::uuid;
    v_retry:=public.rr_cb_department_save_v600(null,v_action,false,v_payload);
    v_second:=public.rr_cb_department_save_v600(v_cb,gen_random_uuid(),false,v_payload);

    begin
      v_natural_retry:=public.rr_cb_department_save_v600(null,gen_random_uuid(),false,v_payload);
      v_natural_duplicate_blocked:=(v_natural_retry->>'cb_id')::uuid=v_cb;
    exception when unique_violation then
      v_natural_duplicate_blocked:=true;
    end;

    v_detail:=public.rr_cb_department_detail_v600(v_cb);
    select jsonb_build_object(
      'cb_rows',(select count(*) from public.rr_fabric_purchases where cb_no=v_cb_no),
      'regular_rows',(select count(*) from public.rr_cb_purchase_entries where cb_id=v_cb and lower(coalesce(entry_notes,''))='regular cloth'),
      'roll_rows',(select count(*) from public.rr_cb_purchase_rolls r join public.rr_cb_purchase_entries p on p.id=r.purchase_entry_id where p.cb_id=v_cb),
      'roll1_rows',(select count(*) from public.rr_cb_purchase_rolls r join public.rr_cb_purchase_entries p on p.id=r.purchase_entry_id where p.cb_id=v_cb and r.roll_no=1 and r.quantity=120),
      'roll2_rows',(select count(*) from public.rr_cb_purchase_rolls r join public.rr_cb_purchase_entries p on p.id=r.purchase_entry_id where p.cb_id=v_cb and r.roll_no=2),
      'quantity',(select quantity from public.rr_cb_purchase_entries where cb_id=v_cb and lower(coalesce(entry_notes,''))='regular cloth' limit 1),
      'rate',(select rate from public.rr_cb_purchase_entries where cb_id=v_cb and lower(coalesce(entry_notes,''))='regular cloth' limit 1),
      'amount',(select amount from public.rr_cb_purchase_entries where cb_id=v_cb and lower(coalesce(entry_notes,''))='regular cloth' limit 1),
      'same_action_audits',(select count(*) from public.rr_cb_department_audit_v600 where action_id=v_action)
    ) into v_counts;

    v_result:=jsonb_build_object(
      'fixture',v_cb_no,
      'first',v_first,
      'retry',v_retry,
      'second_draft',v_second,
      'natural_duplicate_blocked',v_natural_duplicate_blocked,
      'detail',v_detail,
      'counts',v_counts,
      'exact_invariant',
        (v_counts->>'cb_rows')::integer=1
        and (v_counts->>'regular_rows')::integer=1
        and (v_counts->>'roll_rows')::integer=1
        and (v_counts->>'roll1_rows')::integer=1
        and (v_counts->>'roll2_rows')::integer=0
        and (v_counts->>'quantity')::numeric=120
        and (v_counts->>'rate')::numeric=365
        and (v_counts->>'amount')::numeric=43800
        and (v_counts->>'same_action_audits')::integer=1
    );
    raise exception using errcode='P6081',message='TEST71_CB_OPEN_DRAFT_ROLLBACK';
  exception when sqlstate 'P6081' then
    if sqlerrm<>'TEST71_CB_OPEN_DRAFT_ROLLBACK' then raise; end if;
  end;

  select count(*) into v_residue
  from public.rr_fabric_purchases
  where cb_no=v_cb_no;
  return v_result||jsonb_build_object(
    'rolled_back',v_residue=0,
    'fixture_residue',v_residue
  );
end
$function$;

revoke all on function public.rr_test_cb_open_draft_invariants_v608() from public,anon;
grant execute on function public.rr_test_cb_open_draft_invariants_v608() to authenticated,service_role;

comment on function public.rr_test_cb_snapshot_v608(text) is
  'Parameterized read-only TEST71 audit of raw CB purchase/roll values and current frontend projection.';
comment on function public.rr_test_cb_open_draft_invariants_v608() is
  'Rollback-only TEST71 proof for exact Qty/Rate/Value, Roll identity and retry idempotency.';

notify pgrst,'reload schema';
commit;
