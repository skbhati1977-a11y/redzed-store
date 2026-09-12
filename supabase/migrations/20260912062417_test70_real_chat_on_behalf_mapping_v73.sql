-- TEST70 V73: separate the operational sender/receiver from the login that performed an action.
-- No source workflow row is changed. No person is inferred when the source only proves a role centre.
begin;

create or replace function public.rr_real_chat_on_behalf_bridge_v73()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_performer text; v_performer_role text; v_sender text; v_receiver text; v_behalf text;
  v_event text; v_department text; v_worker text;
  v_lm text; v_cm text; v_karigar text;
begin
  select p.full_name,upper(coalesce(p.role_code,'')) into v_performer,v_performer_role
  from public.rr_user_profiles p where p.auth_user_id=new.sender_user_id and p.is_active
  order by p.updated_at desc nulls last limit 1;

  v_sender:=nullif(new.personal_payload->>'sender_name','');
  v_receiver:=nullif(new.personal_payload->>'receiver_name','');

  if new.source_module='UPM' and new.canonical_key like 'UPM_ALTER_EVENT:%' then
    select upper(e.event_type),j.origin_department_code,j.enrolled_lm_name,j.cutting_master_name,j.karigar_name,
           coalesce(e.responsible_name,j.responsible_name)
    into v_event,v_department,v_lm,v_cm,v_karigar,v_worker
    from public.rr_upm_alter_events_v740 e join public.rr_upm_alter_journey_v740 j on j.id=e.journey_id
    where e.id=new.source_record_id::uuid;
    case v_event
      when 'ALTER_FILL' then v_sender:=v_karigar;v_receiver:=v_lm;
      when 'LM_ACCEPT_REQUEST' then v_sender:=v_karigar;v_receiver:=v_lm;
      when 'LM_ACCEPT' then v_sender:=v_lm;v_receiver:=null;
      when 'REMAKE_ISSUE' then v_sender:=v_lm;v_receiver:=v_cm;
      when 'RECEIVE_FROM_MASTER' then v_sender:=v_cm;v_receiver:=v_lm;
      when 'DELIVER_TO_KARIGAR' then v_sender:=v_lm;v_receiver:=v_karigar;
      when 'KARIGAR_SUBMIT_GOOD' then v_sender:=v_karigar;v_receiver:=v_lm;
      when 'RECEIVE_FROM_KARIGAR' then v_sender:=v_karigar;v_receiver:=v_lm;
      else v_sender:=coalesce(v_sender,v_worker);v_receiver:=v_worker;
    end case;
  elsif new.source_module='UPM' and new.canonical_key like 'UPM_ASSIGNMENT:%' then
    select a.department_code,a.worker_name_snapshot into v_department,v_worker
    from public.rr_upm_work_assignments_v8 a where a.id=new.source_record_id::uuid;
    v_sender:=coalesce(nullif(v_sender,''),replace(upper(v_department),'_',' ')||' MANAGER');v_receiver:=v_worker;
    if v_performer_role in ('OWNER','SUPER_ADMIN','ADMIN') and lower(coalesce(v_sender,''))=lower(coalesce(v_performer,'')) then
      v_sender:=replace(upper(v_department),'_',' ')||' MANAGER';
    end if;
  elsif new.source_module='UPM' and new.canonical_key like 'UPM_SUBMIT:%' then
    select s.department_code,s.worker_name into v_department,v_worker
    from public.rr_upm_dynamic_submit_history_v741 s where s.id=new.source_record_id::uuid;
    v_sender:=v_worker;v_receiver:=replace(upper(v_department),'_',' ')||' MANAGER';
  elsif new.source_module='UPM' and new.canonical_key like 'UPM_ACTION:%' then
    select x.department_code,x.worker_name,coalesce(r.worker_name,replace(upper(x.responsible_department_code),'_',' ')||' DEPARTMENT')
    into v_department,v_sender,v_receiver from public.rr_upm_actions_v726 x
    left join public.rr_worker_directory_unified_v1 r on r.worker_id=x.responsible_worker_id
    where x.id=new.source_record_id::uuid;
  elsif new.source_module='UPM' and new.canonical_key like 'UPM_RECTIFICATION:%' then
    select r.origin_department_code,coalesce(r.line_man_name,replace(upper(r.origin_department_code),'_',' ')||' MANAGER'),
           coalesce(r.assigned_worker_name,r.original_worker_name)
    into v_department,v_sender,v_receiver from public.rr_upm_rectification_cases_v9101 r
    where r.id=new.source_record_id::uuid;
  end if;

  v_sender:=coalesce(nullif(v_sender,''),v_performer,'Workflow');
  if v_performer is not null and lower(v_performer)<>lower(v_sender) then v_behalf:=v_sender; else v_behalf:=null; end if;

  new.personal_payload:=new.personal_payload||jsonb_strip_nulls(jsonb_build_object(
    'sender_name',v_sender,'receiver_name',v_receiver,'performed_by_name',v_performer,
    'performed_by_role',v_performer_role,'on_behalf_of_name',v_behalf));
  new.group_payload:=new.group_payload||jsonb_strip_nulls(jsonb_build_object(
    'sender_name',v_sender,'receiver_name',v_receiver,'performed_by_name',v_performer,
    'performed_by_role',v_performer_role,'on_behalf_of_name',v_behalf));
  if v_receiver is null then
    new.personal_payload:=new.personal_payload-'receiver_name';new.group_payload:=new.group_payload-'receiver_name';
  end if;
  if v_behalf is null then
    new.personal_payload:=new.personal_payload-'on_behalf_of_name';new.group_payload:=new.group_payload-'on_behalf_of_name';
  end if;
  return new;
end $$;
revoke all on function public.rr_real_chat_on_behalf_bridge_v73() from public,anon,authenticated;

drop trigger if exists rr_real_chat_on_behalf_bridge_v73 on public.rr_real_chat_message_bridge_v70;
create trigger rr_real_chat_on_behalf_bridge_v73 before insert or update on public.rr_real_chat_message_bridge_v70
for each row execute function public.rr_real_chat_on_behalf_bridge_v73();

-- Reconcile all existing messages through the same rule. The bridge only is updated.
update public.rr_real_chat_message_bridge_v70 set source_event_type=source_event_type;

commit;
