begin;
create or replace function public.rr_real_chat_resolve_action_v83(p_message_id uuid,p_action_code text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_profile public.rr_user_profiles%rowtype; v_worker uuid;
 v_role text; v_message public.rr_real_chat_message_bridge_v70%rowtype; v_state text; v_allowed boolean:=false; v_href text;
begin
 if v_uid is null then raise exception 'Login required.'; end if;
 perform public.rr_assert_active_user_v1();
 select * into v_profile from public.rr_user_profiles p where p.auth_user_id=v_uid
  and coalesce(p.is_active,false) and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  order by p.updated_at desc nulls last limit 1;
 if not found then raise exception 'Active User Directory profile required.'; end if;
 select * into v_message from public.rr_real_chat_message_bridge_v70 b where b.id=p_message_id and b.archived_at is null;
 if not found then raise exception 'Message is unavailable.'; end if;
 if upper(coalesce(v_message.action_code,''))<>upper(trim(coalesce(p_action_code,''))) then raise exception 'Action does not belong to this message.'; end if;
 v_state:=public.rr_real_chat_canonical_state_v83(v_message.source_module,v_message.source_event_type,v_message.action_code,v_message.personal_payload);
 if v_state='CLOSE' then raise exception 'This work is already closed.'; end if;
 v_worker:=public.rr_upm_current_worker_id_v9112(); v_role:=upper(coalesce(v_profile.role_code,'WORKER'));
 v_allowed:=v_role in ('OWNER','SUPER_ADMIN','ADMIN') or v_message.receiver_user_id=v_uid or v_message.receiver_worker_id=v_worker
  or (coalesce(v_message.personal_payload->'allowed_roles','[]'::jsonb) ? v_role and exists(
   select 1 from public.rr_real_chat_department_membership_v70 m where m.worker_id=v_worker and m.is_active
    and public.rr_real_chat_canonical_department_v83(m.department_code)=public.rr_real_chat_canonical_department_v83(v_message.department_code)));
 if not v_allowed then raise exception 'This action is not assigned to your identity.'; end if;
 if exists(select 1 from public.rr_real_chat_action_registry_v70 a where a.action_code=v_message.action_code and a.registry_status='DISABLED')
  then raise exception 'This action is disabled.'; end if;
 v_href:=coalesce(nullif(v_message.personal_payload->>'action_href',''),nullif(v_message.group_payload->>'action_href',''),nullif(v_message.deep_link,''));
 if v_href is null then raise exception 'Existing workflow link is unavailable.'; end if;
 return jsonb_build_object('allowed',true,'message_id',v_message.id,'action_code',v_message.action_code,
  'canonical_state',v_state,'href',v_href,'engine',coalesce(v_message.personal_payload->>'action_engine','EXISTING_WORKFLOW'));
end $$;
revoke all on function public.rr_real_chat_resolve_action_v83(uuid,text) from public,anon;
grant execute on function public.rr_real_chat_resolve_action_v83(uuid,text) to authenticated;
commit;
