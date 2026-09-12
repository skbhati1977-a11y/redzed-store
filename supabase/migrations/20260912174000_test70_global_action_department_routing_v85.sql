-- TEST70 V85: route every Real Chat action by its button/module context, never by actor home.
begin;

alter table public.rr_real_chat_action_registry_v70
 add column if not exists source_department_code text,
 add column if not exists target_department_code text,
 add column if not exists routing_mode text not null default 'SOURCE_GROUP'
   check (routing_mode in ('SOURCE_GROUP','TARGET_GROUP','HANDOVER','PERSONAL_ONLY'));

update public.rr_real_chat_action_registry_v70 a set
 source_department_code=coalesce(a.source_department_code,
  case upper(a.source_module)
   when 'CB_PURCHASE' then 'PURCHASE' when 'MATCHING_PURCHASE' then 'PURCHASE'
   when 'PRODUCT_MASTER' then 'PRODUCT_MASTER' when 'CUTTING' then 'CUTTING'
   when 'PACKING' then 'PACKING' when 'PACKING_RATE' then 'PACKING'
   when 'DESPATCH' then 'DESPATCH' when 'DISPATCH' then 'DESPATCH'
   when 'SALES' then 'SALES' when 'SALES_RETURN' then 'SALES'
   when 'ACCOUNTS' then 'ACCOUNTS' when 'RCI_ACCOUNTS' then 'ACCOUNTS'
   when 'ATTENDANCE' then 'ATTENDANCE' when 'WORKER_PAYROLL' then 'ACCOUNTS'
   else null end);

create or replace function public.rr_real_chat_route_department_v85(
 p_source_module text,p_action_code text,p_supplied_department text,
 p_personal_payload jsonb default '{}'::jsonb,p_group_payload jsonb default '{}'::jsonb)
returns text language plpgsql stable security invoker set search_path='' as $$
declare v_explicit text; v_registered text; v_module text:=upper(trim(coalesce(p_source_module,'')));
begin
 -- The exact button context supplied by an existing workflow has first priority.
 v_explicit:=coalesce(nullif(p_personal_payload->>'action_source_department_code',''),
  nullif(p_group_payload->>'action_source_department_code',''),
  nullif(p_personal_payload->>'source_department_code',''),
  nullif(p_group_payload->>'source_department_code',''));
 if v_explicit is not null then return public.rr_real_chat_canonical_department_v83(v_explicit); end if;

 select a.source_department_code into v_registered
 from public.rr_real_chat_action_registry_v70 a
 where upper(a.action_code)=upper(trim(coalesce(p_action_code,'')))
   and a.registry_status='ACTIVE' and a.source_department_code is not null limit 1;
 if v_registered is not null then return public.rr_real_chat_canonical_department_v83(v_registered); end if;

 -- Module ownership is used where the module itself defines the action context.
 return public.rr_real_chat_canonical_department_v83(case
  when v_module in ('CB_PURCHASE','MATCHING_PURCHASE','PURCHASE') then 'PURCHASE'
  when v_module='PRODUCT_MASTER' then 'PRODUCT_MASTER'
  when v_module='CUTTING' then 'CUTTING'
  when v_module in ('PACKING','PACKING_RATE') then 'PACKING'
  when v_module in ('DESPATCH','DISPATCH') then 'DESPATCH'
  when v_module in ('SALES','SALES_RETURN','COLLECTION','COLLECTION_ACTIVITY',
    'REQUIREMENT','MARKET_REQUIREMENT','PARTNER_ORDER') then 'SALES'
  when v_module in ('ACCOUNTS','RCI_ACCOUNTS','WORKER_PAYROLL','PAYROLL',
    'SALARY','SALARY_WAGES','SALARY_PAYMENT') then 'ACCOUNTS'
  when v_module='ATTENDANCE' then 'ATTENDANCE'
  -- UPM and departmental engines already supply the exact performing department.
  else p_supplied_department end);
end $$;
revoke all on function public.rr_real_chat_route_department_v85(text,text,text,jsonb,jsonb) from public,anon;
grant execute on function public.rr_real_chat_route_department_v85(text,text,text,jsonb,jsonb) to authenticated;

create or replace function public.rr_real_chat_enforce_action_route_v85()
returns trigger language plpgsql security invoker set search_path='' as $$
declare v_source text; v_target text;
begin
 new.department_code:=public.rr_real_chat_route_department_v85(new.source_module,new.action_code,
  new.department_code,new.personal_payload,new.group_payload);
 v_source:=new.department_code;
 v_target:=coalesce(nullif(new.personal_payload->>'target_department_code',''),
  nullif(new.personal_payload->>'receiver_department_code',''),
  nullif(new.group_payload->>'target_department_code',''),
  nullif(new.group_payload->>'receiver_department_code',''));
 if v_target is not null then v_target:=public.rr_real_chat_canonical_department_v83(v_target); end if;
 new.personal_payload:=coalesce(new.personal_payload,'{}'::jsonb)
  ||jsonb_build_object('source_department_code',v_source,'performed_by_user_id',new.sender_user_id)
  ||case when v_target is null then '{}'::jsonb else jsonb_build_object('target_department_code',v_target) end;
 new.group_payload:=coalesce(new.group_payload,'{}'::jsonb)
  ||jsonb_build_object('source_department_code',v_source)
  ||case when v_target is null then '{}'::jsonb else jsonb_build_object('target_department_code',v_target) end;
 return new;
end $$;
revoke all on function public.rr_real_chat_enforce_action_route_v85() from public,anon,authenticated;

drop trigger if exists rr_real_chat_enforce_action_route_v85 on public.rr_real_chat_message_bridge_v70;
create trigger rr_real_chat_enforce_action_route_v85
before insert or update of source_module,action_code,department_code,personal_payload,group_payload
on public.rr_real_chat_message_bridge_v70 for each row
execute function public.rr_real_chat_enforce_action_route_v85();

-- Reconcile existing active messages through the same global resolver.
update public.rr_real_chat_message_bridge_v70 b set
 department_code=public.rr_real_chat_route_department_v85(
  b.source_module,b.action_code,b.department_code,b.personal_payload,b.group_payload)
where b.archived_at is null;

commit;
