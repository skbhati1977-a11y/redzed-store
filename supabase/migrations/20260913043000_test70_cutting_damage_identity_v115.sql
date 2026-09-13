-- TEST70 V115: preserve explicit Cutting Master context through global identity guards.
begin;

create or replace function public.rr_real_chat_reconcile_cutting_damage_identity_v115()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_count integer:=0;
begin
 with cm as (
  select w.worker_id,w.worker_name
  from public.rr_worker_directory_unified_v1 w
  where coalesce(w.is_active,true)
    and (upper(coalesce(w.role_code,''))='CUTTING_MASTER' or upper(coalesce(w.department_code,''))='CUTTING')
  order by (upper(coalesce(w.role_code,''))='CUTTING_MASTER') desc,(w.linked_auth_user_id is not null) desc,w.worker_name
  limit 1
 )
 update public.rr_real_chat_message_bridge_v70 b
 set personal_payload=coalesce(b.personal_payload,'{}'::jsonb)||jsonb_build_object(
      'worker_id',cm.worker_id,'worker_name',cm.worker_name,'on_behalf_worker_id',cm.worker_id,
      'on_behalf_of_name',cm.worker_name,'delegation_requested',true),
     group_payload=coalesce(b.group_payload,'{}'::jsonb)||jsonb_build_object(
      'worker_id',cm.worker_id,'worker_name',cm.worker_name,'on_behalf_worker_id',cm.worker_id,
      'on_behalf_of_name',cm.worker_name,'delegation_requested',true)
 from cm
 where b.archived_at is null and b.source_module='CUTTING' and b.source_event_type like 'DAMAGE_%';
 get diagnostics v_count=row_count;
 return jsonb_build_object('identity_reconciled',v_count);
end $$;

revoke all on function public.rr_real_chat_reconcile_cutting_damage_identity_v115() from public,anon,authenticated;
grant execute on function public.rr_real_chat_reconcile_cutting_damage_identity_v115() to service_role;

create or replace function public.rr_real_chat_cutting_damage_identity_trigger_v115()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform public.rr_real_chat_reconcile_cutting_damage_identity_v115();
 return null;
exception when others then raise warning 'V115 Cutting damage identity reconciliation deferred: %',sqlerrm; return null; end $$;

drop trigger if exists zzzzzzzzzzzz_rr_cutting_damage_identity_v115 on public.rr_cutting_cb_actions;
create trigger zzzzzzzzzzzz_rr_cutting_damage_identity_v115 after insert or update on public.rr_cutting_cb_actions
for each statement execute function public.rr_real_chat_cutting_damage_identity_trigger_v115();

select public.rr_real_chat_reconcile_cutting_damage_identity_v115();
commit;
