-- TEST70 V199: worker assignment lifecycle is strictly
-- OPEN/ACCEPT -> WORKING/SUBMIT -> CLOSE, while assignment authority remains
-- with Line Man / Manager / Admin roles.  Super Admin ACT AS uses the target
-- role as the effective authority in both App and Real Chat.

create or replace function public.rr_real_chat_work_search_v12(
  p_status text default 'WORKING',
  p_search text default null,
  p_department_code text default null,
  p_limit integer default 500
) returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_base jsonb;
  v_working jsonb;
  v_cards jsonb := '[]'::jsonb;
  v_card jsonb;
  v_receipt record;
  v_actor jsonb;
  v_context record;
  v_role text;
  v_worker_id uuid;
  v_status text := upper(coalesce(p_status,'WORKING'));
  v_authority boolean;
  v_targeted boolean;
  v_assignment_id uuid;
  v_receipt_pending boolean;
  v_submitted boolean;
  v_duplicate boolean;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;

  v_base := public.rr_real_chat_work_search_v11(p_status,p_search,p_department_code,p_limit);
  v_actor := coalesce(v_base->'actor','{}'::jsonb);

  select c.target_worker_id,c.target_name,upper(c.target_role) target_role,c.department_codes
    into v_context
  from public.rr_test_on_behalf_context_v176 c
  where c.operator_user_id=auth.uid() and c.is_active and c.expires_at>now()
  limit 1;

  if found then
    v_worker_id:=v_context.target_worker_id;
    v_role:=v_context.target_role;
    v_actor:=v_actor||jsonb_build_object(
      'worker_id',v_worker_id,'user_id',v_worker_id,'name',v_context.target_name,
      'role',v_role,'role_code',v_role,'department_code',coalesce(v_context.department_codes[1],''),
      'department_codes',to_jsonb(v_context.department_codes),
      'on_behalf',true,'operator_user_id',auth.uid()
    );
  else
    v_role:=upper(coalesce(v_actor->>'role',v_actor->>'role_code','WORKER'));
    begin v_worker_id:=nullif(v_actor->>'worker_id','')::uuid; exception when others then v_worker_id:=null; end;
  end if;

  v_authority:=v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','CUTTING_MASTER','DEPARTMENT_HEAD');

  for v_card in select value from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) loop
    -- Group visibility must never become worker ownership/action authority.
    -- Ordinary workers receive only cards whose canonical worker_id is theirs.
    v_targeted:=v_worker_id is not null and v_card->>'worker_id'=v_worker_id::text;
    v_assignment_id:=null;
    if coalesce(v_card->>'original_record_id','')~'^[0-9a-fA-F-]{36}$' then
      begin v_assignment_id:=(v_card->>'original_record_id')::uuid; exception when others then v_assignment_id:=null; end;
    end if;
    select exists(
      select 1 from public.rr_upm_assignment_receipts_v9112 r
      where r.assignment_id=v_assignment_id and upper(r.status) in ('PENDING','DISPUTED')
    ) into v_receipt_pending;
    select exists(
      select 1 from public.rr_upm_submit_requests_v794 s
      where v_assignment_id=any(s.assignment_ids)
        and upper(s.status) not in ('CANCELLED','REJECTED','VOID')
    ) into v_submitted;

    if not v_authority then
      if v_status='OPEN' then
        if not v_targeted or upper(coalesce(v_card->>'work_category',''))='READY_TO_ASSIGN' then continue; end if;
      elsif v_status='WORKING' then
        if not v_targeted or v_receipt_pending or v_submitted then continue; end if;
      elsif not v_targeted then
        continue;
      end if;
    end if;

    if upper(coalesce(v_card->>'work_category',''))='RECEIVE_ASSIGNED_GOODS' then
      v_card:=jsonb_set(v_card,'{message}',to_jsonb('Line Man से assigned work स्वीकार करें और Good PCS confirm करें'::text),true);
      if jsonb_array_length(coalesce(v_card->'actions','[]'::jsonb))>0 then
        v_card:=jsonb_set(v_card,'{actions,0,label}',to_jsonb('ACCEPT WORK'::text),true);
      end if;
    end if;
    v_cards:=v_cards||jsonb_build_array(v_card);
  end loop;

  -- The normal inbox projects receipts for the signed-in worker.  In Super
  -- Admin ACT AS mode the signed-in auth remains the operator, so project the
  -- exact same receipt for the selected effective worker.
  if not v_authority and v_status='OPEN' and v_worker_id is not null then
    for v_receipt in
      select r.assignment_id,r.expected_qty,r.status,r.created_at,r.custody_line_man_name,
             a.canonical_lot_id,a.lot_no,a.department_code,a.colour_code
      from public.rr_upm_assignment_receipts_v9112 r
      join public.rr_upm_work_assignments_v8 a on a.id=r.assignment_id
      where r.worker_id=v_worker_id and upper(r.status) in ('PENDING','DISPUTED')
    loop
      select exists(select 1 from jsonb_array_elements(v_cards) c where c->>'event_key'='UPM_ASSIGN_RECEIPT:'||v_receipt.assignment_id) into v_duplicate;
      if v_duplicate then continue; end if;
      v_cards:=v_cards||jsonb_build_array(jsonb_build_object(
        'event_key','UPM_ASSIGN_RECEIPT:'||v_receipt.assignment_id,
        'source_module','UPM_CUSTODY','canonical_source','rr_upm_assignment_receipts_v9112',
        'original_record_id',v_receipt.assignment_id,'canonical_lot_id',v_receipt.canonical_lot_id,
        'lot_no',v_receipt.lot_no,'department_code',public.rr_upm_core_department_v9077(v_receipt.department_code),
        'colour_code',v_receipt.colour_code,'worker_id',v_worker_id,'qty',v_receipt.expected_qty,
        'source_status',v_receipt.status,'chat_status','OPEN','work_category','RECEIVE_ASSIGNED_GOODS',
        'message','Line Man से assigned work स्वीकार करें और Good PCS confirm करें',
        'receiver_name',v_receipt.custody_line_man_name,'event_at',v_receipt.created_at,
        'actions',jsonb_build_array(jsonb_build_object(
          'code','CONFIRM_RECEIVED_PCS','label','ACCEPT WORK',
          'href','real-department-lite-v9127.html?mode=TEST&from=TEST70_REAL_CHAT&dept='||public.rr_upm_core_department_v9077(v_receipt.department_code)||'&rrAssignmentReceipt='||v_receipt.assignment_id,
          'engine','rr_upm_confirm_assignment_receipt_v9112'
        )),'requires_action',false
      ));
    end loop;
  end if;

  -- A worker submission starts the Line Man chain, but the worker's own card
  -- is already complete and therefore belongs in CLOSE.
  if not v_authority and v_status='CLOSE' and v_worker_id is not null then
    v_working:=public.rr_real_chat_work_search_v11('WORKING',p_search,p_department_code,p_limit);
    for v_card in select value from jsonb_array_elements(coalesce(v_working->'cards','[]'::jsonb)) loop
      if v_card->>'worker_id'<>v_worker_id::text then continue; end if;
      v_assignment_id:=null;
      if coalesce(v_card->>'original_record_id','')~'^[0-9a-fA-F-]{36}$' then
        begin v_assignment_id:=(v_card->>'original_record_id')::uuid; exception when others then v_assignment_id:=null; end;
      end if;
      select exists(
        select 1 from public.rr_upm_submit_requests_v794 s
        where v_assignment_id=any(s.assignment_ids)
          and upper(s.status) not in ('CANCELLED','REJECTED','VOID')
      ) into v_submitted;
      if not v_submitted then continue; end if;
      select exists(select 1 from jsonb_array_elements(v_cards) c where c->>'event_key'=v_card->>'event_key') into v_duplicate;
      if v_duplicate then continue; end if;
      v_card:=v_card||jsonb_build_object(
        'chat_status','CLOSE','source_status','SUBMITTED','message','Submitted to Line Man',
        'actions','[]'::jsonb,'requires_action',false
      );
      v_cards:=v_cards||jsonb_build_array(v_card);
    end loop;
  end if;

  return jsonb_set(
    jsonb_set(jsonb_set(v_base,'{version}',to_jsonb('TEST70_WORKER_ACCEPT_WORKING_CLOSE_V199'::text),true),'{actor}',v_actor,true),
    '{cards}',v_cards,true
  );
end
$function$;

revoke all on function public.rr_real_chat_work_search_v12(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_search_v12(text,text,text,integer) to authenticated;

create or replace function public.rr_upm_ready_to_assign_with_custody_v185(
  p_canonical_lot_id text,p_department_code text,p_worker_id uuid,p_rows jsonb,
  p_line_man_id uuid,p_remarks text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_result jsonb;v_lm_name text;v_row jsonb;v_a public.rr_upm_work_assignments_v8%rowtype;
  v_effective_role text;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  select upper(c.target_role) into v_effective_role
  from public.rr_test_on_behalf_context_v176 c
  where c.operator_user_id=auth.uid() and c.is_active and c.expires_at>now()
  limit 1;
  if v_effective_role is not null and v_effective_role not in
    ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','CUTTING_MASTER','DEPARTMENT_HEAD') then
    raise exception 'ACT AS % is view/work scoped: READY TO ASSIGN requires Line Man, Manager or Admin authority.',v_effective_role;
  end if;
  v_lm_name:=public.rr_upm_validate_line_man_v9112(p_line_man_id);
  v_result:=public.rr_upm_ready_to_assign_v9107(p_canonical_lot_id,p_department_code,p_worker_id,p_rows,concat_ws(' · ',p_remarks,'CUSTODY LM '||v_lm_name));
  for v_row in select value from jsonb_array_elements(p_rows) loop
    select * into v_a from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and public.rr_upm_core_department_v9077(a.department_code)=public.rr_upm_core_department_v9077(p_department_code)
      and upper(a.colour_code)=upper(v_row->>'colour_code') and a.worker_id=p_worker_id
      and a.status in('ASSIGNED','IN_PROGRESS') order by a.assigned_at desc limit 1 for update;
    if v_a.id is null then raise exception 'Assignment missing after save for %.',v_row->>'colour_code';end if;
    insert into public.rr_upm_assignment_receipts_v9112(assignment_id,worker_id,expected_qty,status,custody_line_man_id,custody_line_man_name)
    values(v_a.id,p_worker_id,greatest(coalesce(v_a.inbound_qty,0),coalesce(v_a.assigned_qty,0)),'PENDING',p_line_man_id,v_lm_name)
    on conflict(assignment_id)do update set custody_line_man_id=excluded.custody_line_man_id,custody_line_man_name=excluded.custody_line_man_name;
  end loop;
  return v_result||jsonb_build_object('version','V199_ASSIGN_CUSTODY_ROLE_GUARD','custody_owner_type','LINE_MAN','custody_line_man_id',p_line_man_id,'custody_line_man_name',v_lm_name,'worker_receipt_required',true);
end
$function$;

revoke all on function public.rr_upm_ready_to_assign_with_custody_v185(text,text,uuid,jsonb,uuid,text) from public,anon;
grant execute on function public.rr_upm_ready_to_assign_with_custody_v185(text,text,uuid,jsonb,uuid,text) to authenticated;
