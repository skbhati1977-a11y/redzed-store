-- TEST70 V104: put exact existing Art Decision actions on Purchase OPEN cards.
begin;

create or replace function public.rr_real_chat_purchase_next_actions_v104()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid; v_worker uuid; v_name text; v_rows integer:=0;
begin
 select p.auth_user_id,d.worker_id,coalesce(d.worker_name,p.full_name)
 into v_user,v_worker,v_name
 from public.rr_user_profiles p
 left join public.rr_worker_directory_unified_v1 d
  on d.linked_auth_user_id=p.auth_user_id and coalesce(d.is_active,false)
 where coalesce(p.is_active,false) and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  and regexp_replace(upper(coalesce(p.role_code,'')),'[^A-Z]','','g') in ('SUPERADMIN','OWNER')
 order by case when regexp_replace(upper(coalesce(p.role_code,'')),'[^A-Z]','','g')='SUPERADMIN' then 0 else 1 end,
  p.updated_at desc nulls last,d.worker_id limit 1;

 with pending as (
  select b.id,
   jsonb_agg(jsonb_build_object(
    'code','ART_DECIDE_SUBMIT','label','DECIDE ART · '||u.cb_code,
    'href','real-art-decide-master.html?cb_unit_id='||u.id,
    'engine','rr_pm_save_decision_bundle_v804','cb_unit_id',u.id
   ) order by u.created_at,u.cb_code) actions,
   min('real-art-decide-master.html?cb_unit_id='||u.id::text) first_href
  from public.rr_real_chat_message_bridge_v70 b
  join public.rr_cb_units u on u.purchase_id=b.source_record_id::uuid
  left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=u.id
  where b.archived_at is null and b.source_module='CB_PURCHASE'
   and b.source_event_type='CREATE_CB_SUCCEEDED'
   and b.personal_payload->>'canonical_state'='OPEN'
   and coalesce(d.all_decisions_complete,false)=false
  group by b.id
 )
 update public.rr_real_chat_message_bridge_v70 b
 set receiver_user_id=v_user,receiver_worker_id=v_worker,
  action_code='ART_DECIDE_SUBMIT',action_label='DECIDE ART / PRINT / STICKER / METAL ID',
  deep_link=p.first_href,
  personal_payload=coalesce(b.personal_payload,'{}'::jsonb)||jsonb_build_object(
   'action_href',p.first_href,'action_engine','rr_pm_save_decision_bundle_v804',
   'next_actions',p.actions,'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN'),
   'receiver_name',v_name,'receiver_rule','EXACT_SUPERADMIN_THEN_OWNER',
   'message','अगले pending CB unit का Art / Print / Sticker / Metal ID decide करें'),
  group_payload=coalesce(b.group_payload,'{}'::jsonb)||jsonb_build_object(
   'action_href',p.first_href,'action_engine','rr_pm_save_decision_bundle_v804',
   'next_actions',p.actions,'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN'),
   'receiver_name',v_name,'receiver_rule','EXACT_SUPERADMIN_THEN_OWNER',
   'message','अगले pending CB unit का Art / Print / Sticker / Metal ID decide करें')
 from pending p where b.id=p.id;
 get diagnostics v_rows=row_count;

 update public.rr_real_chat_message_bridge_v70 b
 set personal_payload=coalesce(b.personal_payload,'{}'::jsonb)-'action_href'-'action_engine'-'next_actions',
     group_payload=coalesce(b.group_payload,'{}'::jsonb)-'action_href'-'action_engine'-'next_actions'
 where b.archived_at is null and b.source_module='CB_PURCHASE'
  and coalesce(b.personal_payload->>'canonical_state','')<>'OPEN';

 return jsonb_build_object('open_purchase_cards',v_rows,
  'open_missing_action',(select count(*) from public.rr_real_chat_message_bridge_v70
   where archived_at is null and source_module='CB_PURCHASE'
    and personal_payload->>'canonical_state'='OPEN'
    and (action_code is null or nullif(personal_payload->>'action_href','') is null)));
end $$;

revoke all on function public.rr_real_chat_purchase_next_actions_v104() from public,anon;
grant execute on function public.rr_real_chat_purchase_next_actions_v104() to authenticated,service_role;

create or replace function public.rr_real_chat_purchase_next_actions_trigger_v104()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform public.rr_real_chat_purchase_next_actions_v104(); return null;
exception when others then
 raise warning 'V104 Purchase action reconciliation deferred: %',sqlerrm; return null;
end $$;

do $$ declare t text; begin
 foreach t in array array['rr_cb_units','rr_cb_art_assignments'] loop
  execute format('drop trigger if exists zzzzzzzz_rr_purchase_actions_v104 on public.%I',t);
  execute format('create trigger zzzzzzzz_rr_purchase_actions_v104 after insert or update or delete on public.%I for each statement execute function public.rr_real_chat_purchase_next_actions_trigger_v104()',t);
 end loop;
end $$;

select public.rr_real_chat_purchase_next_actions_v104();
commit;
