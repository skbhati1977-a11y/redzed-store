begin;

alter table public.rr_upm_work_assignments_v8
  add column if not exists actual_rate numeric(12,4),
  add column if not exists rate_filled_by uuid,
  add column if not exists rate_filled_by_name text,
  add column if not exists rate_filled_at timestamptz;

alter table public.rr_upm_work_assignments_v8
  drop constraint if exists rr_upm_work_assignments_v8_actual_rate_check;

alter table public.rr_upm_work_assignments_v8
  add constraint rr_upm_work_assignments_v8_actual_rate_check
  check (actual_rate is null or actual_rate >= 0);

create or replace function public.rr_upm_assign_colours_v8_3(
  p_canonical_lot_id text,
  p_lot_no text,
  p_department_code text,
  p_rows jsonb,
  p_remarks text default null
)
returns setof public.rr_upm_work_assignments_v8
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_profile public.rr_user_profiles%rowtype;
  v_allowed boolean := false;
  v_lot_no text;
  v_cut uuid;
  v_row jsonb;
  v_colour text;
  v_worker uuid;
  v_qty integer;
  v_rate numeric(12,4);
  v_expected integer;
  v_sizes jsonb;
  v_cname text;
  v_wname text;
  v_wcode text;
  v_wdept text;
  v_active boolean;
  v_status text;
  v_out public.rr_upm_work_assignments_v8;
begin
  select rup.*
  into v_profile
  from public.rr_user_profiles rup
  where rup.auth_user_id = auth.uid()
    and coalesce(rup.is_active,false)
    and upper(coalesce(rup.access_status,'ACTIVE')) = 'ACTIVE'
  limit 1;

  if not found then
    raise exception 'Active User Directory profile required.';
  end if;

  v_allowed := lower(coalesce(v_profile.role_code,'')) in
    ('owner','admin','manager','line_man','department_head','production','cutting_master');

  if to_regprocedure('public.rr_has_action_permission_v1(text)') is not null then
    begin
      v_allowed := v_allowed or public.rr_has_action_permission_v1('upm.assign_work');
    exception when others then null;
    end;
  end if;

  if not v_allowed then
    raise exception 'Assign Work permission denied by Role & Permission Directory.';
  end if;

  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'Select at least one colour.';
  end if;

  select coalesce(
    (
      select b.lot_no
      from public.rr_upm_lot_board_v1 b
      where b.canonical_lot_id = nullif(trim(p_canonical_lot_id),'')
      limit 1
    ),
    nullif(trim(p_lot_no),'')
  )
  into v_lot_no;

  if v_lot_no is null then
    raise exception 'Lot No is required.';
  end if;

  select cl.id
  into v_cut
  from public.rr_cutting_lots_v3 cl
  where upper(trim(cl.lot_no)) = upper(trim(v_lot_no))
  order by cl.created_at desc
  limit 1;

  if v_cut is null then
    raise exception 'Cutting Lot mapping not found for Lot %.', v_lot_no;
  end if;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_colour := upper(trim(v_row->>'colour_code'));
    v_worker := nullif(v_row->>'worker_id','')::uuid;
    v_qty := coalesce(nullif(v_row->>'assigned_qty','')::integer,0);
    v_rate := nullif(v_row->>'actual_rate','')::numeric;

    if v_worker is null then
      raise exception 'Worker is required for colour %.', v_colour;
    end if;

    if v_rate is null or v_rate < 0 then
      raise exception 'Valid Actual Rate is required for colour %.', v_colour;
    end if;

    select
      max(coalesce(
        nullif(trim(x.colour_name_snapshot),''),
        nullif(trim(c.colour_name),''),
        v_colour
      )),
      sum(coalesce(x.planned_qty,0))::integer,
      jsonb_agg(
        jsonb_build_object(
          'size_code', upper(trim(x.size_code)),
          'qty', coalesce(x.planned_qty,0)
        )
        order by upper(trim(x.size_code))
      )
    into v_cname, v_expected, v_sizes
    from public.rr_cutting_breakup_v3 x
    left join public.rr_cb_colours c on c.id = x.cb_colour_id
    where x.cutting_lot_id = v_cut
      and (
        case
          when c.col_no is not null then upper('C'||c.col_no::text)
          when nullif(trim(x.colour_name_snapshot),'') is not null
            then upper(trim(x.colour_name_snapshot))
          else 'COLOUR'
        end
      ) = v_colour
      and coalesce(x.planned_qty,0) > 0;

    if v_expected is null then
      raise exception 'Mapped Cutting qty missing for colour %.', v_colour;
    end if;

    if v_qty <> v_expected then
      raise exception 'Colour % qty must equal Cutting mapped qty %.', v_colour, v_expected;
    end if;

    select
      u.worker_name,
      u.worker_code,
      u.department_code,
      u.is_active,
      u.access_status
    into
      v_wname,
      v_wcode,
      v_wdept,
      v_active,
      v_status
    from public.rr_worker_directory_unified_v1 u
    where u.worker_id = v_worker
    limit 1;

    if v_wname is null
       or not coalesce(v_active,false)
       or upper(coalesce(v_status,'ACTIVE')) <> 'ACTIVE' then
      raise exception 'Selected worker is inactive or missing from Unified Worker Directory.';
    end if;

    if lower(coalesce(v_wdept,'')) <> lower(trim(p_department_code)) then
      raise exception 'Selected worker belongs to department %, not %.',
        v_wdept, p_department_code;
    end if;

    begin
      insert into public.rr_upm_work_assignments_v8 (
        canonical_lot_id, lot_no, department_code,
        colour_code, colour_name,
        worker_id, worker_code, worker_name_snapshot,
        assigned_qty, size_breakup,
        actual_rate, rate_filled_by, rate_filled_by_name, rate_filled_at,
        assigned_by, assigned_by_name, remarks
      )
      values (
        nullif(trim(p_canonical_lot_id),''),
        v_lot_no,
        upper(trim(p_department_code)),
        v_colour,
        coalesce(v_cname,v_colour),
        v_worker,
        v_wcode,
        v_wname,
        v_expected,
        coalesce(v_sizes,'[]'::jsonb),
        round(v_rate,4),
        auth.uid(),
        coalesce(v_profile.full_name,v_profile.email),
        now(),
        auth.uid(),
        coalesce(v_profile.full_name,v_profile.email),
        p_remarks
      )
      returning * into v_out;
    exception
      when unique_violation then
        raise exception 'Colour % already assigned in %.', v_colour, p_department_code;
    end;

    return next v_out;
  end loop;
end;
$function$;

grant execute on function
public.rr_upm_assign_colours_v8_3(text,text,text,jsonb,text)
to authenticated;

commit;

select
  to_regprocedure('public.rr_upm_worker_list_v8_3(text)') as worker_list,
  to_regprocedure('public.rr_upm_get_work_assign_context_v8_2(text,text,text)') as assign_context,
  to_regprocedure('public.rr_upm_assign_colours_v8_3(text,text,text,jsonb,text)') as assign_colours,
  to_regprocedure('public.rr_upm_set_actual_rate_v8_4(uuid,numeric)') as actual_rate_function;
