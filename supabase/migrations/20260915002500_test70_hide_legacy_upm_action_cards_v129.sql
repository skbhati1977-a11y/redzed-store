begin;

create or replace function public.rr_real_chat_conversation_history_v83(p_limit integer default 2000)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_profile public.rr_user_profiles%rowtype;
  v_worker uuid;
  v_role text;
  v_global boolean;
  v_rows jsonb;
begin
  if v_uid is null then raise exception 'Login required.'; end if;
  perform public.rr_assert_active_user_v1();
  select * into v_profile from public.rr_user_profiles p
  where p.auth_user_id=v_uid and coalesce(p.is_active,false)
    and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  order by p.updated_at desc nulls last limit 1;
  if not found then raise exception 'Active User Directory profile required.'; end if;
  v_worker:=public.rr_upm_current_worker_id_v9112();
  v_role:=upper(coalesce(v_profile.role_code,'WORKER'));
  v_global:=v_role in ('OWNER','SUPER_ADMIN','ADMIN');

  select coalesce(jsonb_agg(to_jsonb(q) order by q.sent_at desc),'[]'::jsonb) into v_rows
  from (
    select b.id,b.canonical_key,b.source_module,b.source_record_id,b.source_event_type,
      public.rr_real_chat_canonical_department_v83(b.department_code) department_code,
      b.sender_worker_id,b.receiver_user_id,b.receiver_worker_id,
      case when public.rr_real_chat_canonical_state_v83(b.source_module,b.source_event_type,b.action_code,b.personal_payload)='CLOSE'
        then null else b.action_code end action_code,
      case when public.rr_real_chat_canonical_state_v83(b.source_module,b.source_event_type,b.action_code,b.personal_payload)='CLOSE'
        then null else b.action_label end action_label,
      public.rr_real_chat_canonical_state_v83(b.source_module,b.source_event_type,b.action_code,b.personal_payload) canonical_state,
      case when v_global or b.receiver_user_id=v_uid or b.receiver_worker_id=v_worker
        then b.personal_payload else '{}'::jsonb end personal_payload,
      b.group_payload,b.deep_link,b.sent_at,
      (select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb)
       from public.rr_real_chat_receipts_v70 r
       where r.message_id=b.id and (v_global or r.receiver_user_id=v_uid)) rr_real_chat_receipts_v70
    from public.rr_real_chat_message_bridge_v70 b
    where b.archived_at is null
      -- Rate changes are audit metadata, not OPEN/WORKING/CLOSE work cards.
      -- The canonical assignment card already carries the effective rate.
      and upper(coalesce(b.source_module,''))<>'UPM_RATE'
      and upper(coalesce(b.source_event_type,'')) not in ('DEPARTMENT_RATE_UPDATED','ASSIGNMENT_RATE_UPDATED')
      -- Alter transition messages remain in the audit bridge, but the lifecycle
      -- list renders only the canonical current journey card.
      and coalesce(b.canonical_key,'') not like 'UPM_ALTER_EVENT:%'
      -- Legacy GOOD action rows are closed audit facts, not actionable cards.
      and coalesce(b.canonical_key,'') not like 'UPM_ACTION:%'
      and (
        v_global or b.receiver_user_id=v_uid or b.receiver_worker_id=v_worker
        or (
          upper(coalesce(b.source_module,'')) not in ('ACCOUNTS','WORKER_PAYROLL','PAYROLL','SALARY','SALARY_WAGES')
          and exists(
            select 1 from public.rr_real_chat_department_membership_v70 m
            where m.worker_id=v_worker and m.is_active
              and public.rr_real_chat_canonical_department_v83(m.department_code)=public.rr_real_chat_canonical_department_v83(b.department_code)
          )
        )
      )
    order by b.sent_at desc
    limit least(greatest(coalesce(p_limit,2000),1),5000)
  ) q;
  return v_rows;
end;
$$;

revoke all on function public.rr_real_chat_conversation_history_v83(integer) from public;
revoke all on function public.rr_real_chat_conversation_history_v83(integer) from anon;
grant execute on function public.rr_real_chat_conversation_history_v83(integer) to authenticated;

commit;


