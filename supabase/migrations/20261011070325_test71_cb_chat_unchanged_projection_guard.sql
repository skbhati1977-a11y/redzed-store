-- Skip unchanged TEST projection writes; preserve REAL behavior and all canonical values.
do $patch$ declare d text; begin select pg_get_functiondef('public.rr_real_chat_reconcile_cb_slice_v96()'::regprocedure) into d;
if (length(d)-length(replace(d,$old0$on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  sent_at=excluded.sent_at,canonical_event_id=excluded.canonical_event_id,projection_type='SOURCE',archived_at=null,archive_reason=null;$old0$,'')))/length($old0$on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  sent_at=excluded.sent_at,canonical_event_id=excluded.canonical_event_id,projection_type='SOURCE',archived_at=null,archive_reason=null;$old0$)<>3 then raise exception 'Expected CB reconciliation upsert 0 shape missing'; end if;
d:=replace(d,$old0$on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  sent_at=excluded.sent_at,canonical_event_id=excluded.canonical_event_id,projection_type='SOURCE',archived_at=null,archive_reason=null;$old0$,$new0$on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  sent_at=excluded.sent_at,canonical_event_id=excluded.canonical_event_id,projection_type='SOURCE',archived_at=null,archive_reason=null where rr_real_chat_message_bridge_v70.data_mode is distinct from 'TEST'
 or (rr_real_chat_message_bridge_v70.personal_payload,rr_real_chat_message_bridge_v70.group_payload,rr_real_chat_message_bridge_v70.sent_at,rr_real_chat_message_bridge_v70.canonical_event_id,rr_real_chat_message_bridge_v70.projection_type,rr_real_chat_message_bridge_v70.archived_at,rr_real_chat_message_bridge_v70.archive_reason) is distinct from (excluded.personal_payload,excluded.group_payload,excluded.sent_at,excluded.canonical_event_id,'SOURCE',null,null);$new0$);
if (length(d)-length(replace(d,$old1$on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  action_code=excluded.action_code,action_label=excluded.action_label,deep_link=excluded.deep_link,
  canonical_event_id=excluded.canonical_event_id,projection_type='TARGET',archived_at=null,archive_reason=null;$old1$,'')))/length($old1$on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  action_code=excluded.action_code,action_label=excluded.action_label,deep_link=excluded.deep_link,
  canonical_event_id=excluded.canonical_event_id,projection_type='TARGET',archived_at=null,archive_reason=null;$old1$)<>1 then raise exception 'Expected CB reconciliation upsert 1 shape missing'; end if;
d:=replace(d,$old1$on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  action_code=excluded.action_code,action_label=excluded.action_label,deep_link=excluded.deep_link,
  canonical_event_id=excluded.canonical_event_id,projection_type='TARGET',archived_at=null,archive_reason=null;$old1$,$new1$on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  action_code=excluded.action_code,action_label=excluded.action_label,deep_link=excluded.deep_link,
  canonical_event_id=excluded.canonical_event_id,projection_type='TARGET',archived_at=null,archive_reason=null where rr_real_chat_message_bridge_v70.data_mode is distinct from 'TEST'
 or (rr_real_chat_message_bridge_v70.personal_payload,rr_real_chat_message_bridge_v70.group_payload,rr_real_chat_message_bridge_v70.action_code,rr_real_chat_message_bridge_v70.action_label,rr_real_chat_message_bridge_v70.deep_link,rr_real_chat_message_bridge_v70.canonical_event_id,rr_real_chat_message_bridge_v70.projection_type,rr_real_chat_message_bridge_v70.archived_at,rr_real_chat_message_bridge_v70.archive_reason) is distinct from (excluded.personal_payload,excluded.group_payload,excluded.action_code,excluded.action_label,excluded.deep_link,excluded.canonical_event_id,'TARGET',null,null);$new1$);
if (length(d)-length(replace(d,$old2$on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  action_code=excluded.action_code,action_label=excluded.action_label,deep_link=excluded.deep_link,
  department_code=excluded.department_code,canonical_event_id=excluded.canonical_event_id,projection_type='TARGET',archived_at=null,archive_reason=null;$old2$,'')))/length($old2$on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  action_code=excluded.action_code,action_label=excluded.action_label,deep_link=excluded.deep_link,
  department_code=excluded.department_code,canonical_event_id=excluded.canonical_event_id,projection_type='TARGET',archived_at=null,archive_reason=null;$old2$)<>1 then raise exception 'Expected CB reconciliation upsert 2 shape missing'; end if;
d:=replace(d,$old2$on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  action_code=excluded.action_code,action_label=excluded.action_label,deep_link=excluded.deep_link,
  department_code=excluded.department_code,canonical_event_id=excluded.canonical_event_id,projection_type='TARGET',archived_at=null,archive_reason=null;$old2$,$new2$on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  action_code=excluded.action_code,action_label=excluded.action_label,deep_link=excluded.deep_link,
  department_code=excluded.department_code,canonical_event_id=excluded.canonical_event_id,projection_type='TARGET',archived_at=null,archive_reason=null where rr_real_chat_message_bridge_v70.data_mode is distinct from 'TEST'
 or (rr_real_chat_message_bridge_v70.personal_payload,rr_real_chat_message_bridge_v70.group_payload,rr_real_chat_message_bridge_v70.action_code,rr_real_chat_message_bridge_v70.action_label,rr_real_chat_message_bridge_v70.deep_link,rr_real_chat_message_bridge_v70.department_code,rr_real_chat_message_bridge_v70.canonical_event_id,rr_real_chat_message_bridge_v70.projection_type,rr_real_chat_message_bridge_v70.archived_at,rr_real_chat_message_bridge_v70.archive_reason) is distinct from (excluded.personal_payload,excluded.group_payload,excluded.action_code,excluded.action_label,excluded.deep_link,excluded.department_code,excluded.canonical_event_id,'TARGET',null,null);$new2$);
execute d; end $patch$;;
CREATE OR REPLACE FUNCTION public.rr_real_chat_bind_art_superadmin_v99()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    and b.action_code='ART_DECIDE_SUBMIT'
    and (b.data_mode is distinct from 'TEST' or
      (b.receiver_user_id,b.receiver_worker_id,b.action_label,b.personal_payload,b.group_payload)
      is distinct from
      (v_user,v_worker,'DECIDE ART / PRINT / STICKER / METAL ID',coalesce(b.personal_payload,'{}'::jsonb)||jsonb_build_object(
        'receiver_name',v_name,
        'receiver_role',case when regexp_replace(v_role,'[^A-Z]','','g')='SUPERADMIN' then 'SUPER_ADMIN' else 'OWNER_SUPERADMIN_AUTHORITY' end,
        'receiver_rule','EXACT_SUPERADMIN_THEN_OWNER',
        'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN'),
        'message','Art, Print, Sticker और Metal ID Superadmin को decide करना है'
      ),coalesce(b.group_payload,'{}'::jsonb)||jsonb_build_object(
        'receiver_name',v_name,
        'receiver_role',case when regexp_replace(v_role,'[^A-Z]','','g')='SUPERADMIN' then 'SUPER_ADMIN' else 'OWNER_SUPERADMIN_AUTHORITY' end,
        'receiver_rule','EXACT_SUPERADMIN_THEN_OWNER',
        'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN'),
        'message','Art, Print, Sticker और Metal ID Superadmin को decide करना है'
      )));
  get diagnostics v_count=row_count;

  insert into public.rr_real_chat_receipts_v70(message_id,receiver_key,receiver_user_id,receiver_worker_id)
  select b.id,'WORKER:'||v_worker,v_user,v_worker
  from public.rr_real_chat_message_bridge_v70 b
  where b.archived_at is null and b.source_event_type='ART_DECIDE_PENDING'
    and b.action_code='ART_DECIDE_SUBMIT' and v_worker is not null
  on conflict(message_id,receiver_key) do update
    set receiver_user_id=excluded.receiver_user_id,receiver_worker_id=excluded.receiver_worker_id;

  return v_count;
end $function$
;
