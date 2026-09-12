-- TEST70 V93: Sudesh is the test operator; chat identities remain the real actors.
begin;

-- Shailender is the configured Purchase-side conversational actor.
update public.rr_real_chat_department_receiver_v86 r set is_active=true,updated_at=now()
from public.rr_worker_directory_unified_v1 d
where r.department_code='PURCHASE' and lower(trim(d.worker_name))='shailender'
 and coalesce(d.is_active,false) and r.worker_id=d.worker_id;

create or replace function public.rr_real_chat_test_operator_context_v93()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_operator_name text; v_sudesh_user uuid; v_sudesh_worker uuid; v_context_worker uuid; v_context_name text;
 v_existing_context text;
begin
 select d.linked_auth_user_id,d.worker_id,d.worker_name into v_sudesh_user,v_sudesh_worker,v_operator_name
 from public.rr_worker_directory_unified_v1 d
 where lower(trim(d.worker_name))='sudesh bhati' and coalesce(d.is_active,false)
 order by (d.linked_auth_user_id is not null) desc,d.worker_id limit 1;

 -- This override is TEST-only and activates only for Sudesh's test login.
 if new.sender_user_id is distinct from v_sudesh_user then return new; end if;

 v_existing_context:=nullif(trim(coalesce(new.personal_payload->>'on_behalf_of_name','')),'');
 if lower(coalesce(v_existing_context,'')) in ('sudesh bhati','sales team','purchase team','workflow','production','accounts')
   then v_existing_context:=null; end if;

 -- Prefer an explicit source worker. It is the strongest legacy/present/future identity.
 if coalesce(new.personal_payload->>'worker_id','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  select d.worker_id,d.worker_name into v_context_worker,v_context_name
  from public.rr_worker_directory_unified_v1 d
  where d.worker_id=(new.personal_payload->>'worker_id')::uuid and coalesce(d.is_active,false) limit 1;
 end if;
 if v_context_worker is null and nullif(new.personal_payload->>'worker_name','') is not null then
  select d.worker_id,d.worker_name into v_context_worker,v_context_name
  from public.rr_worker_directory_unified_v1 d
  where lower(trim(d.worker_name))=lower(trim(new.personal_payload->>'worker_name')) and coalesce(d.is_active,false)
  order by d.worker_id limit 1;
 end if;
 if v_context_worker is null and new.sender_worker_id is not null and new.sender_worker_id<>v_sudesh_worker then
  select d.worker_id,d.worker_name into v_context_worker,v_context_name
  from public.rr_worker_directory_unified_v1 d where d.worker_id=new.sender_worker_id limit 1;
 end if;
 if v_context_worker is null and new.source_module in ('CB_PURCHASE','MATCHING_PURCHASE') then
  select r.worker_id,d.worker_name into v_context_worker,v_context_name
  from public.rr_real_chat_department_receiver_v86 r
  join public.rr_worker_directory_unified_v1 d on d.worker_id=r.worker_id
  where r.department_code='PURCHASE' and r.is_active limit 1;
 end if;
 v_context_name:=coalesce(v_context_name,v_existing_context,
  nullif(new.personal_payload->>'worker_name',''),nullif(new.personal_payload->>'sender_name',''));

 -- The chat participant stays contextual; Sudesh is recorded only as the operator audit.
 if v_context_worker is not null then new.sender_worker_id:=v_context_worker; end if;
 new.personal_payload:=coalesce(new.personal_payload,'{}'::jsonb)
  ||jsonb_build_object('performed_by_name',coalesce(v_operator_name,'Sudesh Bhati'),
    'performed_by_user_id',new.sender_user_id,
    'on_behalf_of_name',coalesce(v_context_name,'Context actor'),
    'on_behalf_worker_id',v_context_worker,
    'test_operator_mode',true)
  ||case when v_context_name is null then '{}'::jsonb else jsonb_build_object('sender_name',v_context_name) end;
 new.group_payload:=coalesce(new.group_payload,'{}'::jsonb)
  ||jsonb_build_object('performed_by_name',coalesce(v_operator_name,'Sudesh Bhati'),
    'on_behalf_of_name',coalesce(v_context_name,'Context actor'),'test_operator_mode',true)
  ||case when v_context_name is null then '{}'::jsonb else jsonb_build_object('sender_name',v_context_name) end;
 return new;
end $$;
revoke all on function public.rr_real_chat_test_operator_context_v93() from public,anon,authenticated;

drop trigger if exists zzz_rr_real_chat_test_operator_context_v93 on public.rr_real_chat_message_bridge_v70;
create trigger zzz_rr_real_chat_test_operator_context_v93
before insert or update on public.rr_real_chat_message_bridge_v70
for each row execute function public.rr_real_chat_test_operator_context_v93();

-- Backfill every active test message through the same contextual resolver.
update public.rr_real_chat_message_bridge_v70 set personal_payload=personal_payload
where archived_at is null;

commit;
