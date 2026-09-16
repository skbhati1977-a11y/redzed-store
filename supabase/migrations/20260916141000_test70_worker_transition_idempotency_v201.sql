-- TEST70 V201: make ACCEPT a truthful backend WORKING transition and make
-- READY TO SUBMIT idempotent across the App queue and mutation boundary.

create or replace function public.rr_upm_confirm_assignment_receipt_v9112(
  p_assignment_id uuid,p_confirmed_qty numeric,p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_r public.rr_upm_assignment_receipts_v9112%rowtype;
  v_worker uuid:=public.rr_upm_current_worker_id_v9112();
  v_status text;v_a public.rr_upm_work_assignments_v8%rowtype;v_claim jsonb:='{}'::jsonb;
begin
  select * into v_r from public.rr_upm_assignment_receipts_v9112 where assignment_id=p_assignment_id for update;
  if not found then raise exception 'Assignment receipt confirmation not found.';end if;
  if v_worker is null or v_worker<>v_r.worker_id then raise exception 'Only assigned worker can confirm received quantity.';end if;
  if p_confirmed_qty is null or p_confirmed_qty<0 or p_confirmed_qty>v_r.expected_qty then
    raise exception 'Confirmed Qty must be between 0 and %.',v_r.expected_qty;
  end if;
  select * into v_a from public.rr_upm_work_assignments_v8 where id=p_assignment_id for update;
  v_status:=case when p_confirmed_qty=v_r.expected_qty then 'CONFIRMED' else 'CONFIRMED_SHORT' end;
  update public.rr_upm_assignment_receipts_v9112
     set confirmed_qty=p_confirmed_qty,status=v_status,confirmed_at=now(),confirmed_by=auth.uid(),note=p_note
   where assignment_id=p_assignment_id;
  update public.rr_upm_work_assignments_v8
     set status='IN_PROGRESS',updated_at=now()
   where id=p_assignment_id and status='ASSIGNED';
  if p_confirmed_qty<v_r.expected_qty then
    if v_r.custody_line_man_id is null then raise exception 'Custody Line Man mapping required before short receipt can be confirmed.';end if;
    v_claim:=public.rr_upm_register_custody_missing_v185(
      p_assignment_id,v_r.expected_qty,p_confirmed_qty,v_r.custody_line_man_id::text,
      v_r.custody_line_man_name,'LINE_MAN','ASSIGN_RECEIPT'
    );
  end if;
  return jsonb_build_object(
    'ok',true,'version','V201_WORKER_RECEIPT_WORKING','assignment_id',p_assignment_id,
    'lot_no',v_a.lot_no,'colour_code',v_a.colour_code,'expected_qty',v_r.expected_qty,
    'confirmed_qty',p_confirmed_qty,'status',v_status,'work_status','WORKING',
    'custody_owner_type','LINE_MAN','custody_owner_name',v_r.custody_line_man_name,'claim',v_claim
  );
end
$function$;

create or replace function public.rr_upm_department_colour_due_card_v9109(p_department_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  base jsonb:=public.rr_upm_department_colour_due_card_v9107(p_department_code);
  outlots jsonb:='[]'::jsonb;l jsonb;r jsonb;ar jsonb;sr jsonb;ds timestamptz;
  v_dept text:=public.rr_upm_core_department_v9077(p_department_code);
  v_assignment_id uuid;a_count int:=0;s_count int:=0;blocked_receipts int:=0;blocked_submits int:=0;
begin
  for l in select value from jsonb_array_elements(coalesce(base->'lots','[]'::jsonb)) loop
    if public.rr_upm_lot_is_terminal_v125(l->>'lot_no') then continue;end if;
    if v_dept in('PRINTING','STICKER','METAL_ID') and not public.rr_upm_lot_department_applicable_v9167(l->>'lot_no',v_dept) then continue;end if;
    ar:='[]'::jsonb;
    for r in select value from jsonb_array_elements(coalesce(l->'assign_rows','[]'::jsonb)) loop
      ds:=nullif(r->>'due_since','')::timestamptz;
      ar:=ar||jsonb_build_array(r||jsonb_build_object(
        'working_seconds',case when ds is null then 0 else public.rr_upm_working_seconds_v9109(ds,now()) end
      ));
      a_count:=a_count+1;
    end loop;
    sr:='[]'::jsonb;
    for r in select value from jsonb_array_elements(coalesce(l->'submit_rows','[]'::jsonb)) loop
      v_assignment_id:=nullif(r->>'assignment_id','')::uuid;
      if exists(
        select 1 from public.rr_upm_assignment_receipts_v9112 receipt
        where receipt.assignment_id=v_assignment_id and upper(receipt.status) in('PENDING','DISPUTED')
      ) then
        blocked_receipts:=blocked_receipts+1;continue;
      end if;
      if exists(
        select 1 from public.rr_upm_submit_requests_v794 request
        where v_assignment_id=any(request.assignment_ids)
          and upper(request.status) not in('CANCELLED','REJECTED','VOID')
      ) then
        blocked_submits:=blocked_submits+1;continue;
      end if;
      ds:=nullif(r->>'due_since','')::timestamptz;
      sr:=sr||jsonb_build_array(r||jsonb_build_object(
        'working_seconds',case when ds is null then 0 else public.rr_upm_working_seconds_v9109(ds,now()) end,
        'thumbnail_url',public.rr_upm_colour_thumbnail_v9107(l->>'lot_no',r->>'colour_code')
      ));
      s_count:=s_count+1;
    end loop;
    outlots:=outlots||jsonb_build_array(l||jsonb_build_object(
      'assign_rows',ar,'submit_rows',sr,'assign_count',jsonb_array_length(ar),'submit_count',jsonb_array_length(sr)
    ));
  end loop;
  return (base-'lots'-'version'-'assign_count'-'submit_count')||jsonb_build_object(
    'version','V201_IDEMPOTENT_SUBMIT_QUEUE','lots',outlots,'assign_count',a_count,'submit_count',s_count,
    'receipt_blocked_submit_count',blocked_receipts,'active_submit_blocked_count',blocked_submits
  );
end
$function$;

create or replace function public.rr_upm_ready_submit_v794(
  p_canonical_lot_id text,p_department_code text,p_rows jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  ctx jsonb:=public.rr_upm_effective_identity_v200();actor_worker uuid:=public.rr_upm_current_worker_id_v9112();
  actor_role text:=public.rr_upm_effective_role_v200();can_assign boolean:=public.rr_upm_assignment_allowed_v200();
  r jsonb;a public.rr_upm_work_assignments_v8%rowtype;ids uuid[]:='{}';outrows jsonb:='[]'::jsonb;sizes jsonb;assigned numeric:=0;ready numeric:=0;
  req public.rr_upm_submit_requests_v794%rowtype;lm record;lm_count int:=0;lot text;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one running Colour.';end if;
  select lot_no into lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
  for r in select value from jsonb_array_elements(p_rows) loop
    select * into a from public.rr_upm_work_assignments_v8 x
    where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(p_department_code)
      and x.status in('ASSIGNED','IN_PROGRESS') and upper(x.colour_code)=upper(r->>'colour_code')
    order by x.assigned_at desc limit 1 for update;
    if not found then raise exception 'Active assignment missing for Colour %.',r->>'colour_code';end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(a.id::text,0));
    if a.worker_id is distinct from actor_worker and not can_assign then
      raise exception 'Only the assigned worker can mark this Colour READY TO SUBMIT.';
    end if;
    if exists(
      select 1 from public.rr_upm_assignment_receipts_v9112 receipt
      where receipt.assignment_id=a.id and upper(receipt.status) in('PENDING','DISPUTED')
    ) then
      raise exception 'ACCEPT WORK and confirm received PCS before READY TO SUBMIT.';
    end if;
    if exists(
      select 1 from public.rr_upm_submit_requests_v794 request
      where a.id=any(request.assignment_ids) and upper(request.status) not in('CANCELLED','REJECTED','VOID')
    ) then
      raise exception 'This Colour is already submitted to Line Man.';
    end if;
    if array_length(ids,1)>0 and a.worker_id<>(select worker_id from public.rr_upm_work_assignments_v8 where id=ids[1]) then
      raise exception 'Selected Colours belong to different workers. Send one worker request at a time.';
    end if;
    sizes:=coalesce((select jsonb_agg(jsonb_build_object(
      'size_code',upper(z->>'size_code'),'assigned_qty',coalesce((z->>'qty')::numeric,0),
      'ready_qty',coalesce((z->>'qty')::numeric,0)
    ) order by upper(z->>'size_code')) from jsonb_array_elements(coalesce(a.size_breakup,'[]'::jsonb)) z),'[]'::jsonb);
    ids:=array_append(ids,a.id);assigned:=assigned+a.assigned_qty;ready:=ready+a.assigned_qty;
    outrows:=outrows||jsonb_build_array(jsonb_build_object(
      'assignment_id',a.id,'colour_id',a.colour_id,'colour_code',a.colour_code,
      'colour_name',a.colour_name,'sizes',sizes,'assigned_total',a.assigned_qty
    ));
  end loop;
  insert into public.rr_upm_submit_requests_v794(
    canonical_lot_id,lot_no,department_code,worker_id,worker_auth_id,worker_name,
    assignment_ids,colour_rows,assigned_total,worker_ready_total
  ) values(
    p_canonical_lot_id,coalesce(lot,p_canonical_lot_id),upper(p_department_code),
    (select worker_id from public.rr_upm_work_assignments_v8 where id=ids[1]),
    coalesce((select linked_auth_user_id from public.rr_worker_directory_unified_v1 where worker_id=(select worker_id from public.rr_upm_work_assignments_v8 where id=ids[1]) limit 1),(select worker_id from public.rr_upm_work_assignments_v8 where id=ids[1])),
    (select worker_name_snapshot from public.rr_upm_work_assignments_v8 where id=ids[1]),
    ids,outrows,assigned,ready
  ) returning * into req;
  for lm in
    select coalesce(u.linked_auth_user_id,c.worker_id) worker_id,c.worker_name
    from public.rr_upm_worker_candidates_v740('LINE_MAN',p_department_code)c
    left join public.rr_worker_directory_unified_v1 u on u.worker_id=c.worker_id
    where coalesce(u.linked_auth_user_id,c.worker_id) is not null
      and not exists(select 1 from public.rr_upm_activity_lease_v794 lease where lease.actor_id=coalesce(u.linked_auth_user_id,c.worker_id) and lease.expires_at>now())
      and not exists(select 1 from public.rr_upm_submit_requests_v794 active where active.accepted_lm_id=coalesce(u.linked_auth_user_id,c.worker_id) and active.status='LM_ACCEPTED')
  loop
    insert into public.rr_upm_submit_lm_candidates_v794(request_id,line_man_id,line_man_name)
    values(req.id,lm.worker_id,lm.worker_name) on conflict do nothing;
    insert into public.rr_upm_alert_events_v794(recipient_id,recipient_role,request_id,alert_code,message_text)
    values(lm.worker_id,'LINE_MAN',req.id,'READY_TO_SUBMIT',format('Lot %s · %s · %s PCS ready. ACCEPT & COUNT करें.',req.lot_no,req.worker_name,req.worker_ready_total))
    on conflict do nothing;
    lm_count:=lm_count+1;
  end loop;
  if lm_count=0 then update public.rr_upm_submit_requests_v794 set status='ESCALATED',updated_at=now() where id=req.id;end if;
  insert into public.rr_upm_submit_audit_v794(request_id,action_code,actor_name,details)
  values(req.id,'WORKER_READY',ctx->>'display_name',jsonb_build_object(
    'assigned_total',assigned,'ready_total',ready,'lm_candidates',lm_count,
    'effective_worker_id',actor_worker,'effective_role',actor_role
  ));
  return jsonb_build_object(
    'ok',true,'version','V201_IDEMPOTENT_EFFECTIVE_WORKER_SUBMIT','request_id',req.id,
    'lot_no',req.lot_no,'colours',jsonb_array_length(outrows),'assigned_total',assigned,
    'worker_ready_total',ready,'lm_candidates',lm_count,
    'status',case when lm_count=0 then 'ESCALATED' else 'WAITING_LM' end
  );
end
$function$;

revoke all on function public.rr_upm_confirm_assignment_receipt_v9112(uuid,numeric,text) from public,anon;
revoke all on function public.rr_upm_department_colour_due_card_v9109(text) from public,anon;
revoke all on function public.rr_upm_ready_submit_v794(text,text,jsonb) from public,anon;
grant execute on function public.rr_upm_confirm_assignment_receipt_v9112(uuid,numeric,text) to authenticated;
grant execute on function public.rr_upm_department_colour_due_card_v9109(text) to authenticated;
grant execute on function public.rr_upm_ready_submit_v794(text,text,jsonb) to authenticated;

