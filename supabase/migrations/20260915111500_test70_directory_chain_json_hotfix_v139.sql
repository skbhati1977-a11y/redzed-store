-- The v84 directory delegates to v83, so both version fields must be built as
-- JSON values rather than backslash-escaped SQL strings.
create or replace function public.rr_real_chat_directory_v83()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_base jsonb;
  v_profile public.rr_user_profiles%rowtype;
  v_worker uuid;
  v_role text;
  v_global boolean;
  v_members jsonb;
  v_purchase jsonb;
begin
  if v_uid is null then raise exception 'Login required.'; end if;
  perform public.rr_assert_active_user_v1();

  select * into v_profile
  from public.rr_user_profiles p
  where p.auth_user_id = v_uid
    and coalesce(p.is_active, false)
  order by p.updated_at desc nulls last
  limit 1;

  if not found then raise exception 'Active User Directory profile required.'; end if;

  v_worker := public.rr_upm_current_worker_id_v9112();
  v_role := upper(coalesce(v_profile.role_code, 'WORKER'));
  v_global := v_role in ('OWNER', 'SUPER_ADMIN', 'ADMIN');
  v_base := public.rr_real_chat_directory_v71();

  if v_global or exists (
    select 1
    from public.rr_real_chat_department_membership_v70 m
    where m.department_code = 'PURCHASE'
      and m.worker_id = v_worker
      and m.is_active
  ) then
    select coalesce(jsonb_agg(jsonb_build_object(
      'worker_id', d.worker_id,
      'worker_code', d.worker_code,
      'worker_name', d.worker_name,
      'role_code', d.role_code,
      'home_department_code', d.department_code,
      'linked_login', d.linked_auth_user_id is not null,
      'membership_side', m.membership_side,
      'source_rule', m.source_rule
    ) order by d.worker_name), '[]'::jsonb)
    into v_members
    from public.rr_real_chat_department_membership_v70 m
    join public.rr_worker_directory_unified_v1 d on d.worker_id = m.worker_id
    where m.department_code = 'PURCHASE'
      and m.is_active
      and coalesce(d.is_active, false);

    v_purchase := jsonb_build_object(
      'department_code', 'PURCHASE',
      'department_name', 'Purchase',
      'sort_order', 5,
      'open_count', 0,
      'working_count', 0,
      'close_count', 0,
      'last_at', null,
      'worker_count', 0,
      'staff_count', jsonb_array_length(v_members),
      'workers', '[]'::jsonb,
      'staff', v_members
    );
    v_base := jsonb_set(
      v_base,
      '{departments}',
      jsonb_build_array(v_purchase) || coalesce(v_base->'departments', '[]'::jsonb)
    );
  end if;

  return jsonb_set(
    v_base,
    '{version}',
    to_jsonb('TEST70_REAL_CHAT_DIRECTORY_V83_IDENTITY_FIRST'::text),
    true
  );
end
$function$;

revoke all on function public.rr_real_chat_directory_v83() from public, anon;
grant execute on function public.rr_real_chat_directory_v83() to authenticated;

create or replace function public.rr_real_chat_directory_v84()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  perform public.rr_real_chat_auto_inactive_v136();
  v_result := public.rr_real_chat_directory_v83();
  return jsonb_set(
    v_result,
    '{version}',
    to_jsonb('TEST70_REAL_CHAT_DIRECTORY_V84_STAFF_LIFECYCLE'::text),
    true
  );
end
$function$;

revoke all on function public.rr_real_chat_directory_v84() from public, anon;
grant execute on function public.rr_real_chat_directory_v84() to authenticated;
