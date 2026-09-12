-- TEST70 V99: Art, Print, Sticker and Metal ID are decided only by the
-- verified Superadmin authority. OWNER is the legacy fallback until a
-- dedicated SUPER_ADMIN identity exists.
begin;

update public.rr_real_chat_action_registry_v70
set allowed_roles=array['OWNER','SUPER_ADMIN']::text[],
    receiver_rule='EXACT_SUPERADMIN_THEN_OWNER',
    message_template='{cb_code} requires Art, Print, Sticker and Metal ID decision by Superadmin.',
    notes='Existing rr_pm_save_decision_bundle_v804 only. Exact verified Superadmin receiver; OWNER fallback for legacy TEST identity.',
    updated_at=now()
where action_code='ART_DECIDE_SUBMIT';

create or replace function public.rr_real_chat_bind_art_superadmin_v99()
returns integer
language plpgsql
security definer
set search_path=public,pg_temp
as $function$
declare
  v_user uuid;
  v_worker uuid;
  v_name text;
  v_role text;
  v_count integer:=0;
begin
  select p.auth_user_id,d.worker_id,coalesce(d.worker_name,p.full_name),upper(coalesce(p.role_code,''))
    into v_user,v_worker,v_name,v_role
  from public.rr_user_profiles p
  left join public.rr_worker_directory_unified_v1 d
    on d.linked_auth_user_id=p.auth_user_id and coalesce(d.is_active,false)
  where coalesce(p.is_active,false)
    and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
    and regexp_replace(upper(coalesce(p.role_code,'')),'[^A-Z]','','g') in ('SUPERADMIN','OWNER')
  order by case when regexp_replace(upper(coalesce(p.role_code,'')),'[^A-Z]','','g')='SUPERADMIN' then 0 else 1 end,
    p.updated_at desc nulls last,d.worker_id
  limit 1;

  if v_user is null then
    raise warning 'No verified SUPER_ADMIN or OWNER identity is available for Art Decide.';
    return 0;
  end if;

  update public.rr_real_chat_message_bridge_v70 b
  set receiver_user_id=v_user,
      receiver_worker_id=v_worker,
      action_label='DECIDE ART / PRINT / STICKER / METAL ID',
      personal_payload=coalesce(b.personal_payload,'{}'::jsonb)||jsonb_build_object(
        'receiver_name',v_name,
        'receiver_role',case when regexp_replace(v_role,'[^A-Z]','','g')='SUPERADMIN' then 'SUPER_ADMIN' else 'OWNER_SUPERADMIN_AUTHORITY' end,
        'receiver_rule','EXACT_SUPERADMIN_THEN_OWNER',
        'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN'),
        'message','Art, Print, Sticker और Metal ID Superadmin को decide करना है'
      ),
      group_payload=coalesce(b.group_payload,'{}'::jsonb)||jsonb_build_object(
        'receiver_name',v_name,
        'receiver_role',case when regexp_replace(v_role,'[^A-Z]','','g')='SUPERADMIN' then 'SUPER_ADMIN' else 'OWNER_SUPERADMIN_AUTHORITY' end,
        'receiver_rule','EXACT_SUPERADMIN_THEN_OWNER',
        'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN'),
        'message','Art, Print, Sticker और Metal ID Superadmin को decide करना है'
      )
  where b.archived_at is null
    and b.source_event_type='ART_DECIDE_PENDING'
    and b.action_code='ART_DECIDE_SUBMIT';
  get diagnostics v_count=row_count;

  insert into public.rr_real_chat_receipts_v70(message_id,receiver_key,receiver_user_id,receiver_worker_id)
  select b.id,'WORKER:'||v_worker,v_user,v_worker
  from public.rr_real_chat_message_bridge_v70 b
  where b.archived_at is null and b.source_event_type='ART_DECIDE_PENDING'
    and b.action_code='ART_DECIDE_SUBMIT' and v_worker is not null
  on conflict(message_id,receiver_key) do update
    set receiver_user_id=excluded.receiver_user_id,receiver_worker_id=excluded.receiver_worker_id;

  return v_count;
end $function$;
revoke all on function public.rr_real_chat_bind_art_superadmin_v99() from public,anon,authenticated;
grant execute on function public.rr_real_chat_bind_art_superadmin_v99() to service_role;

create or replace function public.rr_real_chat_cb_slice_trigger_v96()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  perform public.rr_real_chat_reconcile_cb_slice_v96();
  perform public.rr_real_chat_bind_art_superadmin_v99();
  return null;
exception when others then
  raise warning 'Action conversation reconciliation deferred: %',sqlerrm;
  return null;
end $$;
revoke all on function public.rr_real_chat_cb_slice_trigger_v96() from public,anon,authenticated;

select public.rr_real_chat_reconcile_cb_slice_v96();
select public.rr_real_chat_bind_art_superadmin_v99();
commit;
