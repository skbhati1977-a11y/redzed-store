-- TEST70 V92: the global business-owner audit runs after legacy bridge decorators.
begin;
create or replace function public.rr_real_chat_sudesh_on_behalf_v92()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_operator_worker uuid; v_operator_name text; v_owner_user uuid; v_owner_name text;
begin
 if new.action_code is null then return new; end if;
 select d.worker_id,d.worker_name into v_operator_worker,v_operator_name
 from public.rr_worker_directory_unified_v1 d
 where d.linked_auth_user_id=new.sender_user_id and coalesce(d.is_active,false)
 order by d.worker_id limit 1;
 select d.linked_auth_user_id,d.worker_name into v_owner_user,v_owner_name
 from public.rr_worker_directory_unified_v1 d
 where lower(trim(d.worker_name))='sudesh bhati' and coalesce(d.is_active,false)
 order by (d.linked_auth_user_id is not null) desc,d.worker_id limit 1;
 if new.sender_worker_id is null and v_operator_worker is not null then new.sender_worker_id:=v_operator_worker; end if;
 new.personal_payload:=coalesce(new.personal_payload,'{}'::jsonb)
  ||jsonb_build_object('performed_by_name',coalesce(v_operator_name,new.personal_payload->>'sender_name','Workflow'),
    'on_behalf_of_name',coalesce(v_owner_name,'Sudesh Bhati'),'on_behalf_of_user_id',v_owner_user);
 new.group_payload:=coalesce(new.group_payload,'{}'::jsonb)
  ||jsonb_build_object('performed_by_name',coalesce(v_operator_name,new.group_payload->>'sender_name','Workflow'),
    'on_behalf_of_name',coalesce(v_owner_name,'Sudesh Bhati'));
 return new;
end $$;
revoke all on function public.rr_real_chat_sudesh_on_behalf_v92() from public,anon,authenticated;
drop trigger if exists zz_rr_real_chat_sudesh_on_behalf_v92 on public.rr_real_chat_message_bridge_v70;
create trigger zz_rr_real_chat_sudesh_on_behalf_v92
before insert or update on public.rr_real_chat_message_bridge_v70
for each row execute function public.rr_real_chat_sudesh_on_behalf_v92();
update public.rr_real_chat_message_bridge_v70 set personal_payload=personal_payload
where archived_at is null and action_code is not null;
commit;
