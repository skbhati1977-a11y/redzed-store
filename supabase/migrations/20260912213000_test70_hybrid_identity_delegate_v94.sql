-- TEST70 V94: real login identity wins; privileged users may act on behalf.
begin;
create or replace function public.rr_real_chat_hybrid_identity_v94()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_role text; v_performer_name text; v_performer_worker uuid; v_worker_name text;
 v_context_worker uuid; v_context_name text; v_privileged boolean:=false; v_delegated boolean:=false;
begin
 if new.sender_user_id is null then return new; end if;
 select upper(coalesce(p.role_code,'WORKER')),p.full_name into v_role,v_performer_name
 from public.rr_user_profiles p where p.auth_user_id=new.sender_user_id and coalesce(p.is_active,false)
 order by p.updated_at desc nulls last limit 1;
 select d.worker_id,d.worker_name into v_performer_worker,v_worker_name
 from public.rr_worker_directory_unified_v1 d where d.linked_auth_user_id=new.sender_user_id
  and coalesce(d.is_active,false) order by d.worker_id limit 1;
 v_performer_name:=coalesce(v_performer_name,v_worker_name);
 v_privileged:=v_role in ('OWNER','SUPER_ADMIN','ADMIN');

 if coalesce(new.personal_payload->>'on_behalf_worker_id','') ~*
   '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  v_context_worker:=(new.personal_payload->>'on_behalf_worker_id')::uuid;
  select d.worker_name into v_context_name from public.rr_worker_directory_unified_v1 d
   where d.worker_id=v_context_worker and coalesce(d.is_active,false) limit 1;
 end if;
 v_context_name:=coalesce(v_context_name,nullif(new.personal_payload->>'on_behalf_of_name',''));
 v_delegated:=v_privileged and v_context_name is not null
  and lower(trim(v_context_name))<>lower(trim(coalesce(v_performer_name,'')));

 if not v_delegated then
  v_context_worker:=v_performer_worker;
  v_context_name:=v_performer_name;
  if v_context_worker is not null then new.sender_worker_id:=v_context_worker; end if;
  new.personal_payload:=(coalesce(new.personal_payload,'{}'::jsonb)
    -'on_behalf_of_name'-'on_behalf_of_user_id'-'on_behalf_worker_id')
    ||jsonb_build_object('performed_by_name',coalesce(v_performer_name,'Signed-in user'),
      'performed_by_user_id',new.sender_user_id,'identity_mode','DIRECT_IDENTITY')
    ||case when v_performer_name is null then '{}'::jsonb else jsonb_build_object('sender_name',v_performer_name) end;
  new.group_payload:=(coalesce(new.group_payload,'{}'::jsonb)-'on_behalf_of_name'-'on_behalf_worker_id')
    ||jsonb_build_object('performed_by_name',coalesce(v_performer_name,'Signed-in user'),'identity_mode','DIRECT_IDENTITY')
    ||case when v_performer_name is null then '{}'::jsonb else jsonb_build_object('sender_name',v_performer_name) end;
 else
  if v_context_worker is not null then new.sender_worker_id:=v_context_worker; end if;
  new.personal_payload:=coalesce(new.personal_payload,'{}'::jsonb)
    ||jsonb_build_object('performed_by_name',coalesce(v_performer_name,'Privileged user'),
      'performed_by_user_id',new.sender_user_id,'on_behalf_of_name',v_context_name,
      'on_behalf_worker_id',v_context_worker,'identity_mode','DELEGATED_TEST_OR_ADMIN')
    ||jsonb_build_object('sender_name',v_context_name);
  new.group_payload:=coalesce(new.group_payload,'{}'::jsonb)
    ||jsonb_build_object('performed_by_name',coalesce(v_performer_name,'Privileged user'),
      'on_behalf_of_name',v_context_name,'identity_mode','DELEGATED_TEST_OR_ADMIN','sender_name',v_context_name);
 end if;
 return new;
end $$;
revoke all on function public.rr_real_chat_hybrid_identity_v94() from public,anon,authenticated;
drop trigger if exists zzzz_rr_real_chat_hybrid_identity_v94 on public.rr_real_chat_message_bridge_v70;
create trigger zzzz_rr_real_chat_hybrid_identity_v94 before insert or update
on public.rr_real_chat_message_bridge_v70 for each row execute function public.rr_real_chat_hybrid_identity_v94();
update public.rr_real_chat_message_bridge_v70 set personal_payload=personal_payload where archived_at is null;
commit;
