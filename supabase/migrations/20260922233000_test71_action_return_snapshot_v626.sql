-- TEST71 V626: preserve the shared embedded action-return contract even when a
-- canonical form replaces its own URL after assigning a permanent identity.
-- Extend the existing parameterized, read-only TEST E2E snapshot so deployed
-- evidence never needs direct access to the protected CB audit table.
begin;

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
    'operation_status',fp.operation_status,
    'status',fp.status,
    'division_count',fp.division_count,
    'colour_count',fp.colour_count,
    'total_weight',fp.total_weight,
    'total_amount',fp.total_amount,
    'remarks',fp.notes,
    'updated_at',fp.updated_at,
    'units',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',u.id,
        'cb_code',u.cb_code,
        'division_index',u.division_index,
        'status',u.status,
        'operation_status',u.operation_status
      ) order by u.division_index)
      from public.rr_cb_units u
      where u.purchase_id=fp.id
    ),'[]'::jsonb),
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
    'audit',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',a.id,
        'action_id',a.action_id,
        'action_code',a.action_code,
        'previous_state',a.previous_state,
        'new_state',a.new_state,
        'actual_actor_id',a.actual_actor_id,
        'effective_actor_id',a.effective_actor_id,
        'effective_name',a.effective_name,
        'effective_role',a.effective_role,
        'created_at',a.created_at
      ) order by a.created_at,a.id)
      from public.rr_cb_department_audit_v600 a
      where a.cb_id=fp.id
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

comment on function public.rr_test_cb_snapshot_v608(text) is
  'Parameterized read-only TEST E2E CB evidence, including canonical units and idempotency audits; never changes a named business record.';

notify pgrst,'reload schema';
commit;
