-- TEST70 Real Chat: permission-scoped, read-only mirror of existing UPM records.
-- This function creates no work, status, attendance, salary, payment, or chat row.
create or replace function public.rr_real_chat_work_inbox_v70(
  p_status text default 'WORKING', p_search text default null,
  p_department_code text default null, p_limit integer default 100
) returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
  v_uid uuid:=auth.uid(); v_profile public.rr_user_profiles%rowtype;
  v_worker uuid; v_role text; v_dept text; v_state text:=upper(trim(coalesce(p_status,'WORKING')));
  v_find text:=lower(trim(coalesce(p_search,''))); v_staff boolean; v_cards jsonb;
begin
  if v_uid is null then raise exception 'Login required.'; end if;
  perform public.rr_assert_active_user_v1();
  select * into v_profile from public.rr_user_profiles p where p.auth_user_id=v_uid
    and coalesce(p.is_active,false) and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
    order by p.updated_at desc nulls last limit 1;
  if not found then raise exception 'Active User Directory profile required.'; end if;
  v_worker:=public.rr_upm_current_worker_id_v9112();
  v_role:=upper(coalesce(v_profile.role_code,'WORKER'));
  v_staff:=v_role in ('SUPER_ADMIN','OWNER','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD','PRODUCTION','CUTTING_MASTER','ACCOUNTANT','ACCOUNTS','ACCOUNT');
  v_dept:=public.rr_upm_core_department_v9077(coalesce(nullif(trim(p_department_code),''),v_profile.department_code));
  if v_state not in ('OPEN','WORKING','CLOSE') then raise exception 'Status must be OPEN, WORKING or CLOSE.'; end if;
  if not v_staff and v_worker is null then raise exception 'Login is not linked to a Worker ID.'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.event_at desc),'[]'::jsonb) into v_cards from (
    select 'UPM_ASSIGNMENT:'||a.id::text event_key,'UNIVERSAL_PRODUCTION'::text source_module,
      a.id original_record_id,a.canonical_lot_id,a.lot_no,
      public.rr_upm_core_department_v9077(a.department_code) department_code,
      coalesce(d.department_name,public.rr_upm_core_department_v9077(a.department_code)) department_name,
      a.colour_code,a.colour_name,a.worker_id,a.worker_code,a.worker_name_snapshot worker_name,
      a.assigned_qty qty,a.actual_rate,a.status source_status,
      case when a.status in('ASSIGNED','IN_PROGRESS') then 'WORKING' else 'CLOSE' end chat_status,
      a.assigned_by sender_user_id,a.assigned_by_name sender_name,a.worker_id receiver_worker_id,
      a.assigned_at event_at,coalesce(l.art_image_urls,'[]'::jsonb) art_images,
      coalesce(l.print_image_urls,'[]'::jsonb) print_images,'[]'::jsonb sticker_images,'[]'::jsonb metal_id_images
    from public.rr_upm_work_assignments_v8 a
    left join public.rr_upm_lot_registry l on l.canonical_lot_id=a.canonical_lot_id
    left join public.rr_upm_department_catalog_v762 d on d.department_code=public.rr_upm_core_department_v9077(a.department_code)
    where (v_staff or a.worker_id=v_worker)
      and (not v_staff or v_dept is null or public.rr_upm_core_department_v9077(a.department_code)=v_dept)
      and ((v_state='WORKING' and a.status in('ASSIGNED','IN_PROGRESS')) or (v_state='CLOSE' and a.status in('COMPLETED','CANCELLED')) or (v_state='OPEN' and false))
      and (v_find='' or lower(concat_ws(' ',a.lot_no,a.colour_code,a.colour_name,a.worker_name_snapshot,a.department_code,a.status)) like '%'||v_find||'%')
    order by a.assigned_at desc limit least(greatest(coalesce(p_limit,100),1),200)
  ) x;
  return jsonb_build_object('version','TEST70_REAL_CHAT_WORK_V70','read_only_mirror',true,
    'actor',jsonb_build_object('profile_id',v_profile.id,'user_id',v_uid,'worker_id',v_worker,'name',v_profile.full_name,'role',v_role,'department_code',v_dept,'is_staff',v_staff),
    'status',v_state,'cards',v_cards);
end $function$;
revoke all on function public.rr_real_chat_work_inbox_v70(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_inbox_v70(text,text,text,integer) to authenticated;
comment on function public.rr_real_chat_work_inbox_v70(text,text,text,integer) is 'TEST70 read-only mirror. OPEN remains empty until its exact pre-assignment source is approved.';
