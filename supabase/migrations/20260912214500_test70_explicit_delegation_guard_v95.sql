-- TEST70 V95: non-Sudesh real logins are direct unless delegation was explicitly requested.
begin;
create or replace function public.rr_real_chat_explicit_delegation_guard_v95()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_sudesh_user uuid; v_role text; v_name text; v_worker uuid; v_worker_name text;
 v_explicit boolean; v_privileged boolean;
begin
 if new.sender_user_id is null then return new; end if;
 select d.linked_auth_user_id into v_sudesh_user from public.rr_worker_directory_unified_v1 d
 where lower(trim(d.worker_name))='sudesh bhati' and coalesce(d.is_active,false)
 order by (d.linked_auth_user_id is not null) desc,d.worker_id limit 1;
 if new.sender_user_id=v_sudesh_user then return new; end if;
 select upper(coalesce(p.role_code,'WORKER')),p.full_name into v_role,v_name
 from public.rr_user_profiles p where p.auth_user_id=new.sender_user_id and coalesce(p.is_active,false)
 order by p.updated_at desc nulls last limit 1;
 select d.worker_id,d.worker_name into v_worker,v_worker_name
 from public.rr_worker_directory_unified_v1 d where d.linked_auth_user_id=new.sender_user_id
  and coalesce(d.is_active,false) order by d.worker_id limit 1;
 v_name:=coalesce(v_name,v_worker_name);
 v_privileged:=v_role in ('OWNER','SUPER_ADMIN','ADMIN');
 v_explicit:=lower(coalesce(new.personal_payload->>'delegation_requested','false'))='true';
 if v_privileged and v_explicit then return new; end if;
 if v_worker is not null then new.sender_worker_id:=v_worker; end if;
 new.personal_payload:=(coalesce(new.personal_payload,'{}'::jsonb)
   -'on_behalf_of_name'-'on_behalf_of_user_id'-'on_behalf_worker_id'-'delegation_requested')
  ||jsonb_build_object('performed_by_name',coalesce(v_name,'Signed-in user'),
    'performed_by_user_id',new.sender_user_id,'sender_name',coalesce(v_name,'Signed-in user'),
    'identity_mode','DIRECT_IDENTITY');
 new.group_payload:=(coalesce(new.group_payload,'{}'::jsonb)-'on_behalf_of_name'-'on_behalf_worker_id')
  ||jsonb_build_object('performed_by_name',coalesce(v_name,'Signed-in user'),
    'sender_name',coalesce(v_name,'Signed-in user'),'identity_mode','DIRECT_IDENTITY');
 return new;
end $$;
revoke all on function public.rr_real_chat_explicit_delegation_guard_v95() from public,anon,authenticated;
drop trigger if exists zzzzz_rr_real_chat_explicit_delegation_guard_v95 on public.rr_real_chat_message_bridge_v70;
create trigger zzzzz_rr_real_chat_explicit_delegation_guard_v95 before insert or update
on public.rr_real_chat_message_bridge_v70 for each row execute function public.rr_real_chat_explicit_delegation_guard_v95();
update public.rr_real_chat_message_bridge_v70 set personal_payload=personal_payload where archived_at is null;
commit;
