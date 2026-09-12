-- TEST70 V91: every actionable workflow records the real operator and Sudesh as business owner.
begin;

create or replace function public.rr_real_chat_enforce_action_route_v85()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_source text; v_target text; v_operator_worker uuid; v_operator_name text;
 v_owner_user uuid; v_owner_name text;
begin
 new.department_code:=public.rr_real_chat_route_department_v85(new.source_module,new.action_code,
  new.department_code,new.personal_payload,new.group_payload);
 v_source:=new.department_code;
 v_target:=coalesce(nullif(new.personal_payload->>'target_department_code',''),
  nullif(new.personal_payload->>'receiver_department_code',''),
  nullif(new.group_payload->>'target_department_code',''),
  nullif(new.group_payload->>'receiver_department_code',''));
 if v_target is not null then v_target:=public.rr_real_chat_canonical_department_v83(v_target); end if;

 if new.sender_user_id is not null then
  select d.worker_id,d.worker_name into v_operator_worker,v_operator_name
  from public.rr_worker_directory_unified_v1 d
  where d.linked_auth_user_id=new.sender_user_id and coalesce(d.is_active,false)
  order by d.worker_id limit 1;
  if new.sender_worker_id is null and v_operator_worker is not null then new.sender_worker_id:=v_operator_worker; end if;
 end if;
 if new.action_code is not null then
  select d.linked_auth_user_id,d.worker_name into v_owner_user,v_owner_name
  from public.rr_worker_directory_unified_v1 d
  where lower(trim(d.worker_name))='sudesh bhati' and coalesce(d.is_active,false)
  order by (d.linked_auth_user_id is not null) desc,d.worker_id limit 1;
 end if;

 new.personal_payload:=coalesce(new.personal_payload,'{}'::jsonb)
  ||jsonb_build_object('source_department_code',v_source,'performed_by_user_id',new.sender_user_id)
  ||case when v_operator_name is null then '{}'::jsonb
    else jsonb_build_object('performed_by_name',v_operator_name) end
  ||case when v_owner_name is null then '{}'::jsonb
    else jsonb_build_object('on_behalf_of_name',v_owner_name,'on_behalf_of_user_id',v_owner_user) end
  ||case when v_target is null then '{}'::jsonb else jsonb_build_object('target_department_code',v_target) end;
 new.group_payload:=coalesce(new.group_payload,'{}'::jsonb)
  ||jsonb_build_object('source_department_code',v_source)
  ||case when v_operator_name is null then '{}'::jsonb
    else jsonb_build_object('performed_by_name',v_operator_name) end
  ||case when v_owner_name is null then '{}'::jsonb
    else jsonb_build_object('on_behalf_of_name',v_owner_name) end
  ||case when v_target is null then '{}'::jsonb else jsonb_build_object('target_department_code',v_target) end;
 return new;
end $$;
revoke all on function public.rr_real_chat_enforce_action_route_v85() from public,anon,authenticated;

-- Re-run active actionable messages so legacy, present and future use one audit rule.
update public.rr_real_chat_message_bridge_v70
set personal_payload=personal_payload
where archived_at is null and action_code is not null;

commit;
