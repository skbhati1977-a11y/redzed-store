-- TEST70 V200: one effective Act-As identity across App, Chat and backend.
-- Worker lifecycle remains OPEN/ACCEPT -> WORKING/SUBMIT -> CLOSE.

create or replace function public.rr_upm_effective_identity_v200()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_actual jsonb;
  v_operator_role text;
  v_actual_role text;
  v_worker_id uuid;
  v_worker_name text;
  v_worker_auth_id uuid;
  v_context record;
begin
  if v_uid is null then raise exception 'Login required.'; end if;

  v_actual:=coalesce(public.rr_up_user_context_v2(),'{}'::jsonb);
  select upper(p.role_code)
    into v_operator_role
  from public.rr_user_profiles p
  where p.auth_user_id=v_uid and p.is_active
  order by p.updated_at desc nulls last
  limit 1;

  select c.target_worker_id,c.target_name,upper(c.target_role) target_role,
         coalesce(c.department_codes,'{}'::text[]) department_codes,
         w.linked_auth_user_id
    into v_context
  from public.rr_test_on_behalf_context_v176 c
  left join public.rr_worker_directory_unified_v1 w on w.worker_id=c.target_worker_id
  where c.operator_user_id=v_uid
    and c.is_active and c.expires_at>now()
    and v_operator_role in ('OWNER','SUPER_ADMIN')
  limit 1;

  if found then
    return v_actual||jsonb_build_object(
      'worker_id',v_context.target_worker_id,
      'user_id',v_context.target_worker_id,
      'auth_user_id',v_uid,
      'effective_auth_user_id',coalesce(v_context.linked_auth_user_id,v_context.target_worker_id),
      'display_name',v_context.target_name,
      'name',v_context.target_name,
      'resolved_role',v_context.target_role,
      'user_category',v_context.target_role,
      'role_code',v_context.target_role,
      'department_code',coalesce(v_context.department_codes[1],''),
      'department_codes',to_jsonb(v_context.department_codes),
      'on_behalf',true,
      'operator_user_id',v_uid
    );
  end if;

  select w.worker_id,w.worker_name,w.linked_auth_user_id
    into v_worker_id,v_worker_name,v_worker_auth_id
  from public.rr_worker_directory_unified_v1 w
  where w.linked_auth_user_id=v_uid or w.worker_id=v_uid
  order by (w.linked_auth_user_id=v_uid) desc
  limit 1;
  v_actual_role:=upper(coalesce(v_operator_role,v_actual->>'resolved_role',v_actual->>'user_category',v_actual->>'role_code','WORKER'));

  return v_actual||jsonb_build_object(
    'worker_id',v_worker_id,
    'effective_auth_user_id',coalesce(v_worker_auth_id,v_uid),
    'display_name',coalesce(v_worker_name,v_actual->>'display_name','User'),
    'name',coalesce(v_worker_name,v_actual->>'display_name','User'),
    'resolved_role',v_actual_role,
    'user_category',v_actual_role,
    'role_code',v_actual_role,
    'on_behalf',false,
    'operator_user_id',v_uid
  );
end
$function$;

create or replace function public.rr_upm_effective_role_v200()
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select upper(coalesce(
    public.rr_upm_effective_identity_v200()->>'resolved_role',
    public.rr_upm_effective_identity_v200()->>'user_category',
    public.rr_upm_effective_identity_v200()->>'role_code',
    'WORKER'
  ))
$function$;

create or replace function public.rr_upm_assignment_allowed_v200()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select public.rr_upm_effective_role_v200() in
    ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN')
$function$;

create or replace function public.rr_upm_current_worker_id_v9112()
returns uuid
language sql
stable
security definer
set search_path to ''
as $function$
  select nullif(public.rr_upm_effective_identity_v200()->>'worker_id','')::uuid
$function$;

create or replace function public.rr_upm_v794_actor()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  select public.rr_upm_effective_identity_v200()
$function$;

create or replace function public.rr_upm_v794_role()
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select public.rr_upm_effective_role_v200()
$function$;

create or replace function public.rr_upm_v794_can_assign()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select public.rr_upm_assignment_allowed_v200()
$function$;

create or replace function public.rr_upm_ready_to_assign_v9107(
  p_canonical_lot_id text,p_department_code text,p_worker_id uuid,p_rows jsonb,p_remarks text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_ctx jsonb:=public.rr_upm_effective_identity_v200();
  v_role text:=public.rr_upm_effective_role_v200();
  v_dept text:=public.rr_upm_core_department_v9077(p_department_code);v_lot_no text;v_worker_name text;v_worker_code text;
  v_row jsonb;v_colour text;v_qty numeric;v_due jsonb;v_match jsonb;v_sizes jsonb;v_count int:=0;v_total numeric:=0;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  if not public.rr_upm_assignment_allowed_v200() then
    raise exception 'READY TO ASSIGN requires Line Man, Manager or Admin authority; effective role % is not allowed.',v_role;
  end if;
  if p_worker_id is null then raise exception 'Select worker.'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one colour.'; end if;
  if public.rr_upm_worker_has_open_rectification_v9102(p_worker_id) then raise exception 'Worker has open RECTIFICATION. Finish it before new assignment.'; end if;
  select worker_name,worker_code into v_worker_name,v_worker_code from public.rr_upm_worker_list_v8_4(v_dept) where worker_id=p_worker_id limit 1;
  if v_worker_name is null then raise exception 'Selected worker is not active/mapped in %.',v_dept; end if;
  select lot_no into v_lot_no from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
  if v_lot_no is null then raise exception 'Lot not registered.'; end if;
  v_due:=public.rr_upm_department_colour_due_card_v9107(v_dept);
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_colour:=upper(trim(v_row->>'colour_code'));
    select x into v_match from jsonb_array_elements(coalesce((select l->'assign_rows' from jsonb_array_elements(v_due->'lots') l where l->>'canonical_lot_id'=p_canonical_lot_id limit 1),'[]'::jsonb)) x where upper(x->>'colour_code')=v_colour limit 1;
    if v_match is null then raise exception 'Colour % is not currently READY TO ASSIGN in department %.',v_colour,v_dept; end if;
    v_qty:=coalesce((v_match->>'qty')::numeric,0);v_sizes:=coalesce(v_match->'size_breakup','[]'::jsonb);
    if v_qty<=0 then raise exception 'Colour % has no GOOD qty available.',v_colour; end if;
    if exists(select 1 from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.colour_code)=v_colour and a.status in('ASSIGNED','IN_PROGRESS')) then raise exception 'Colour % is already running.',v_colour; end if;
    if exists(select 1 from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.colour_code)=v_colour and public.rr_upm_core_department_v9077(a.department_code)=v_dept and a.status='COMPLETED') then raise exception 'Colour % already completed in %; normal reassignment blocked.',v_colour,v_dept; end if;
    insert into public.rr_upm_work_assignments_v8(canonical_lot_id,lot_no,department_code,colour_code,colour_name,worker_id,worker_code,worker_name_snapshot,assigned_qty,size_breakup,inbound_qty,inbound_breakup,status,source_type,assigned_by,assigned_by_name,remarks)
    values(p_canonical_lot_id,v_lot_no,v_dept,v_colour,v_colour,p_worker_id,v_worker_code,v_worker_name,ceil(v_qty)::int,v_sizes,v_qty,v_sizes,'ASSIGNED','GOOD_TRAVEL',auth.uid(),coalesce(v_ctx->>'display_name',auth.uid()::text),p_remarks);
    v_count:=v_count+1;v_total:=v_total+v_qty;
  end loop;
  return jsonb_build_object('ok',true,'version','V200_CANONICAL_ASSIGN_AUTHORITY','lot_no',v_lot_no,'department_code',v_dept,'worker_id',p_worker_id,'worker_name',v_worker_name,'colours_assigned',v_count,'qty_assigned',v_total,'effective_role',v_role);
end
$function$;

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
  v_effective_role text:=public.rr_upm_effective_role_v200();
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  if not public.rr_upm_assignment_allowed_v200() then
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
  return v_result||jsonb_build_object('version','V200_ASSIGN_CUSTODY_ROLE_GUARD','custody_owner_type','LINE_MAN','custody_line_man_id',p_line_man_id,'custody_line_man_name',v_lm_name,'worker_receipt_required',true);
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
  a_count int:=0;s_count int:=0;blocked_receipts int:=0;
begin
  for l in select value from jsonb_array_elements(coalesce(base->'lots','[]'::jsonb)) loop
    if public.rr_upm_lot_is_terminal_v125(l->>'lot_no') then continue; end if;
    if v_dept in ('PRINTING','STICKER','METAL_ID') and not public.rr_upm_lot_department_applicable_v9167(l->>'lot_no',v_dept) then continue; end if;
    ar:='[]'::jsonb;
    for r in select value from jsonb_array_elements(coalesce(l->'assign_rows','[]'::jsonb)) loop
      ds:=nullif(r->>'due_since','')::timestamptz;
      ar:=ar||jsonb_build_array(r||jsonb_build_object('working_seconds',case when ds is null then 0 else public.rr_upm_working_seconds_v9109(ds,now()) end));
      a_count:=a_count+1;
    end loop;
    sr:='[]'::jsonb;
    for r in select value from jsonb_array_elements(coalesce(l->'submit_rows','[]'::jsonb)) loop
      if exists(
        select 1 from public.rr_upm_assignment_receipts_v9112 receipt
        where receipt.assignment_id=nullif(r->>'assignment_id','')::uuid
          and upper(receipt.status) in ('PENDING','DISPUTED')
      ) then
        blocked_receipts:=blocked_receipts+1;
        continue;
      end if;
      ds:=nullif(r->>'due_since','')::timestamptz;
      sr:=sr||jsonb_build_array(r||jsonb_build_object('working_seconds',case when ds is null then 0 else public.rr_upm_working_seconds_v9109(ds,now()) end,'thumbnail_url',public.rr_upm_colour_thumbnail_v9107(l->>'lot_no',r->>'colour_code')));
      s_count:=s_count+1;
    end loop;
    outlots:=outlots||jsonb_build_array(l||jsonb_build_object('assign_rows',ar,'submit_rows',sr,'assign_count',jsonb_array_length(ar),'submit_count',jsonb_array_length(sr)));
  end loop;
  return (base-'lots'-'version'-'assign_count'-'submit_count')||jsonb_build_object(
    'version','V200_RECEIPT_GATED_SUBMIT_QUEUE','lots',outlots,'assign_count',a_count,'submit_count',s_count,
    'receipt_blocked_submit_count',blocked_receipts
  );
end
$function$;

create or replace function public.rr_upm_ready_submit_v794(p_canonical_lot_id text,p_department_code text,p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  ctx jsonb:=public.rr_upm_effective_identity_v200();actor_worker uuid:=public.rr_upm_current_worker_id_v9112();
  actor_role text:=public.rr_upm_effective_role_v200();can_assign boolean:=public.rr_upm_assignment_allowed_v200();
  r jsonb;a public.rr_upm_work_assignments_v8%rowtype;ids uuid[]:='{}';outrows jsonb:='[]';sizes jsonb;assigned numeric:=0;ready numeric:=0;
  req public.rr_upm_submit_requests_v794%rowtype;lm record;lm_count int:=0;lot text;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one running Colour.'; end if;
  select lot_no into lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
  for r in select value from jsonb_array_elements(p_rows) loop
    select * into a from public.rr_upm_work_assignments_v8 x
    where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(p_department_code)
      and x.status in('ASSIGNED','IN_PROGRESS') and upper(x.colour_code)=upper(r->>'colour_code')
    order by x.assigned_at desc limit 1 for update;
    if not found then raise exception 'Active assignment missing for Colour %.',r->>'colour_code'; end if;
    if a.worker_id is distinct from actor_worker and not can_assign then
      raise exception 'Only the assigned worker can mark this Colour READY TO SUBMIT.';
    end if;
    if exists(
      select 1 from public.rr_upm_assignment_receipts_v9112 receipt
      where receipt.assignment_id=a.id and upper(receipt.status) in ('PENDING','DISPUTED')
    ) then
      raise exception 'ACCEPT WORK and confirm received PCS before READY TO SUBMIT.';
    end if;
    if array_length(ids,1)>0 and a.worker_id<>(select worker_id from public.rr_upm_work_assignments_v8 where id=ids[1]) then
      raise exception 'Selected Colours belong to different workers. Send one worker request at a time.';
    end if;
    sizes:=coalesce((select jsonb_agg(jsonb_build_object('size_code',upper(z->>'size_code'),'assigned_qty',coalesce((z->>'qty')::numeric,0),'ready_qty',coalesce((z->>'qty')::numeric,0)) order by upper(z->>'size_code')) from jsonb_array_elements(coalesce(a.size_breakup,'[]'::jsonb)) z),'[]'::jsonb);
    ids:=array_append(ids,a.id);assigned:=assigned+a.assigned_qty;ready:=ready+a.assigned_qty;
    outrows:=outrows||jsonb_build_array(jsonb_build_object('assignment_id',a.id,'colour_id',a.colour_id,'colour_code',a.colour_code,'colour_name',a.colour_name,'sizes',sizes,'assigned_total',a.assigned_qty));
  end loop;
  insert into public.rr_upm_submit_requests_v794(canonical_lot_id,lot_no,department_code,worker_id,worker_auth_id,worker_name,assignment_ids,colour_rows,assigned_total,worker_ready_total)
  values(p_canonical_lot_id,coalesce(lot,p_canonical_lot_id),upper(p_department_code),(select worker_id from public.rr_upm_work_assignments_v8 where id=ids[1]),coalesce((select linked_auth_user_id from public.rr_worker_directory_unified_v1 where worker_id=(select worker_id from public.rr_upm_work_assignments_v8 where id=ids[1]) limit 1),(select worker_id from public.rr_upm_work_assignments_v8 where id=ids[1])),(select worker_name_snapshot from public.rr_upm_work_assignments_v8 where id=ids[1]),ids,outrows,assigned,ready)
  returning * into req;
  for lm in
    select coalesce(u.linked_auth_user_id,c.worker_id) worker_id,c.worker_name from public.rr_upm_worker_candidates_v740('LINE_MAN',p_department_code)c
    left join public.rr_worker_directory_unified_v1 u on u.worker_id=c.worker_id
    where coalesce(u.linked_auth_user_id,c.worker_id) is not null
      and not exists(select 1 from public.rr_upm_activity_lease_v794 l where l.actor_id=coalesce(u.linked_auth_user_id,c.worker_id) and l.expires_at>now())
      and not exists(select 1 from public.rr_upm_submit_requests_v794 q where q.accepted_lm_id=coalesce(u.linked_auth_user_id,c.worker_id) and q.status in('LM_ACCEPTED'))
  loop
    insert into public.rr_upm_submit_lm_candidates_v794(request_id,line_man_id,line_man_name) values(req.id,lm.worker_id,lm.worker_name) on conflict do nothing;
    insert into public.rr_upm_alert_events_v794(recipient_id,recipient_role,request_id,alert_code,message_text)
    values(lm.worker_id,'LINE_MAN',req.id,'READY_TO_SUBMIT',format('Lot %s · %s · %s PCS ready. ACCEPT & COUNT करें.',req.lot_no,req.worker_name,req.worker_ready_total)) on conflict do nothing;
    lm_count:=lm_count+1;
  end loop;
  if lm_count=0 then update public.rr_upm_submit_requests_v794 set status='ESCALATED',updated_at=now() where id=req.id; end if;
  insert into public.rr_upm_submit_audit_v794(request_id,action_code,actor_name,details)
  values(req.id,'WORKER_READY',ctx->>'display_name',jsonb_build_object('assigned_total',assigned,'ready_total',ready,'lm_candidates',lm_count,'effective_worker_id',actor_worker,'effective_role',actor_role));
  return jsonb_build_object('ok',true,'version','V200_EFFECTIVE_WORKER_SUBMIT','request_id',req.id,'lot_no',req.lot_no,'colours',jsonb_array_length(outrows),'assigned_total',assigned,'worker_ready_total',ready,'lm_candidates',lm_count,'status',case when lm_count=0 then 'ESCALATED' else 'WAITING_LM' end);
end
$function$;

create or replace function public.rr_upm_submit_inbox_v794()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  role text:=public.rr_upm_effective_role_v200();items jsonb;canassign boolean:=public.rr_upm_assignment_allowed_v200();
  effective_worker uuid:=public.rr_upm_current_worker_id_v9112();effective_auth uuid;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  select coalesce(w.linked_auth_user_id,effective_worker) into effective_auth
  from public.rr_worker_directory_unified_v1 w where w.worker_id=effective_worker limit 1;
  effective_auth:=coalesce(effective_auth,effective_worker);
  perform public.rr_upm_submit_tick_v794();
  if role in('LINE_MAN','LINE_MANAGER') then
    select coalesce(jsonb_agg(jsonb_build_object('request_id',r.id,'kind',case when r.accepted_lm_id=effective_auth then 'LM_ACTIVE' else 'LM_OFFER' end,'status',r.status,'lot_no',r.lot_no,'department_code',r.department_code,'premise_code',r.premise_code,'premise_name',r.premise_name,'worker_id',r.worker_id,'worker_name',r.worker_name,'assigned_total',r.assigned_total,'worker_ready_total',r.worker_ready_total,'colour_rows',r.colour_rows,'lm_count_rows',r.lm_count_rows,'created_at',r.created_at) order by r.created_at),'[]'::jsonb) into items
    from public.rr_upm_submit_requests_v794 r left join public.rr_upm_submit_lm_candidates_v794 c on c.request_id=r.id and c.line_man_id=effective_auth
    where (c.response_status='PENDING' and r.status in('WAITING_LM','ESCALATED')) or (r.accepted_lm_id=effective_auth and r.status='LM_ACCEPTED');
  elsif role in('MANAGER','OWNER','SUPER_ADMIN','ADMIN') then
    items:='[]'::jsonb;
  else
    select coalesce(jsonb_agg(jsonb_build_object('request_id',r.id,'kind','WORKER_CONFIRM','status',r.status,'lot_no',r.lot_no,'department_code',r.department_code,'premise_code',r.premise_code,'premise_name',r.premise_name,'worker_name',r.worker_name,'assigned_total',r.assigned_total,'worker_ready_total',r.worker_ready_total,'lm_counted_total',r.lm_counted_total,'difference',r.difference_qty,'colour_rows',r.colour_rows,'lm_count_rows',r.lm_count_rows,'accepted_lm_name',r.accepted_lm_name,'created_at',r.created_at) order by r.created_at),'[]'::jsonb) into items
    from public.rr_upm_submit_requests_v794 r where r.worker_id=effective_worker and r.status in('LM_COUNTED','DISPUTED');
  end if;
  return jsonb_build_object('version','V200_EFFECTIVE_WORKER_INBOX','role',role,'effective_worker_id',effective_worker,'can_assign',canassign,'items',items,'location_routing','L1_TO_L1__L2_TO_L2','payroll_rule','RESPONSE_OVERDUE_ONLY_NO_AUTOMATIC_DEDUCTION');
end
$function$;

create or replace function public.rr_real_chat_work_search_v12(
  p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500
) returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_base jsonb;v_working jsonb;v_cards jsonb:='[]'::jsonb;v_card jsonb;v_receipt record;
  v_actor jsonb;v_effective jsonb:=public.rr_upm_effective_identity_v200();v_role text;v_worker_id uuid;
  v_status text:=upper(coalesce(p_status,'WORKING'));v_authority boolean;v_targeted boolean;
  v_assignment_id uuid;v_receipt_pending boolean;v_submitted boolean;v_duplicate boolean;v_counts jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  v_base:=public.rr_real_chat_work_search_v11(p_status,p_search,p_department_code,p_limit);
  v_actor:=coalesce(v_base->'actor','{}'::jsonb);
  v_role:=public.rr_upm_effective_role_v200();
  v_worker_id:=nullif(v_effective->>'worker_id','')::uuid;
  v_authority:=public.rr_upm_assignment_allowed_v200();
  v_actor:=v_actor||jsonb_build_object(
    'worker_id',v_worker_id,'user_id',v_worker_id,'name',v_effective->>'display_name',
    'role',v_role,'role_code',v_role,'department_code',coalesce(v_effective->>'department_code',''),
    'department_codes',coalesce(v_effective->'department_codes','[]'::jsonb),
    'on_behalf',coalesce((v_effective->>'on_behalf')::boolean,false),'operator_user_id',auth.uid()
  );

  for v_card in select value from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) loop
    v_targeted:=v_worker_id is not null and v_card->>'worker_id'=v_worker_id::text;
    v_assignment_id:=null;
    if coalesce(v_card->>'original_record_id','')~'^[0-9a-fA-F-]{36}$' then
      begin v_assignment_id:=(v_card->>'original_record_id')::uuid;exception when others then v_assignment_id:=null;end;
    end if;
    select exists(select 1 from public.rr_upm_assignment_receipts_v9112 r where r.assignment_id=v_assignment_id and upper(r.status) in('PENDING','DISPUTED')) into v_receipt_pending;
    select exists(select 1 from public.rr_upm_submit_requests_v794 s where v_assignment_id=any(s.assignment_ids) and upper(s.status) not in('CANCELLED','REJECTED','VOID')) into v_submitted;
    if not v_authority then
      if v_status='OPEN' then
        if not v_targeted or upper(coalesce(v_card->>'work_category',''))='READY_TO_ASSIGN' then continue;end if;
      elsif v_status='WORKING' then
        if not v_targeted or v_receipt_pending or v_submitted then continue;end if;
      elsif not v_targeted then continue;
      end if;
    end if;
    if upper(coalesce(v_card->>'work_category',''))='RECEIVE_ASSIGNED_GOODS' then
      v_card:=jsonb_set(v_card,'{message}',to_jsonb('Line Man से assigned work स्वीकार करें और Good PCS confirm करें'::text),true);
      if jsonb_array_length(coalesce(v_card->'actions','[]'::jsonb))>0 then v_card:=jsonb_set(v_card,'{actions,0,label}',to_jsonb('ACCEPT WORK'::text),true);end if;
    end if;
    v_cards:=v_cards||jsonb_build_array(v_card);
  end loop;

  if not v_authority and v_status='OPEN' and v_worker_id is not null then
    for v_receipt in
      select r.assignment_id,r.expected_qty,r.status,r.created_at,r.custody_line_man_name,a.canonical_lot_id,a.lot_no,a.department_code,a.colour_code
      from public.rr_upm_assignment_receipts_v9112 r join public.rr_upm_work_assignments_v8 a on a.id=r.assignment_id
      where r.worker_id=v_worker_id and upper(r.status) in('PENDING','DISPUTED')
    loop
      select exists(select 1 from jsonb_array_elements(v_cards)c where c->>'event_key'='UPM_ASSIGN_RECEIPT:'||v_receipt.assignment_id)into v_duplicate;
      if v_duplicate then continue;end if;
      v_cards:=v_cards||jsonb_build_array(jsonb_build_object(
        'event_key','UPM_ASSIGN_RECEIPT:'||v_receipt.assignment_id,'source_module','UPM_CUSTODY','canonical_source','rr_upm_assignment_receipts_v9112',
        'original_record_id',v_receipt.assignment_id,'canonical_lot_id',v_receipt.canonical_lot_id,'lot_no',v_receipt.lot_no,
        'department_code',public.rr_upm_core_department_v9077(v_receipt.department_code),'colour_code',v_receipt.colour_code,
        'worker_id',v_worker_id,'qty',v_receipt.expected_qty,'source_status',v_receipt.status,'chat_status','OPEN',
        'work_category','RECEIVE_ASSIGNED_GOODS','message','Line Man से assigned work स्वीकार करें और Good PCS confirm करें',
        'receiver_name',v_receipt.custody_line_man_name,'event_at',v_receipt.created_at,
        'actions',jsonb_build_array(jsonb_build_object('code','CONFIRM_RECEIVED_PCS','label','ACCEPT WORK',
          'href','real-department-lite-v9127.html?mode=TEST&from=TEST70_REAL_CHAT&dept='||public.rr_upm_core_department_v9077(v_receipt.department_code)||'&rrAssignmentReceipt='||v_receipt.assignment_id,
          'engine','rr_upm_confirm_assignment_receipt_v9112')),'requires_action',false
      ));
    end loop;
  end if;

  if not v_authority and v_status='CLOSE' and v_worker_id is not null then
    v_working:=public.rr_real_chat_work_search_v11('WORKING',p_search,p_department_code,p_limit);
    for v_card in select value from jsonb_array_elements(coalesce(v_working->'cards','[]'::jsonb)) loop
      if v_card->>'worker_id'<>v_worker_id::text then continue;end if;
      v_assignment_id:=null;
      if coalesce(v_card->>'original_record_id','')~'^[0-9a-fA-F-]{36}$' then begin v_assignment_id:=(v_card->>'original_record_id')::uuid;exception when others then v_assignment_id:=null;end;end if;
      select exists(select 1 from public.rr_upm_submit_requests_v794 s where v_assignment_id=any(s.assignment_ids) and upper(s.status) not in('CANCELLED','REJECTED','VOID'))into v_submitted;
      if not v_submitted then continue;end if;
      select exists(select 1 from jsonb_array_elements(v_cards)c where c->>'event_key'=v_card->>'event_key')into v_duplicate;
      if v_duplicate then continue;end if;
      v_card:=v_card||jsonb_build_object('chat_status','CLOSE','source_status','SUBMITTED','message','Submitted to Line Man','actions','[]'::jsonb,'requires_action',false);
      v_cards:=v_cards||jsonb_build_array(v_card);
    end loop;
  end if;

  select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb) into v_counts
  from(select coalesce(nullif(card->>'department_code',''),'UNKNOWN')department_code,count(*)card_count from jsonb_array_elements(v_cards)x(card)group by 1)c;
  return jsonb_set(jsonb_set(jsonb_set(jsonb_set(v_base,'{version}',to_jsonb('TEST70_EFFECTIVE_WORKER_LIFECYCLE_V200'::text),true),'{actor}',v_actor,true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end
$function$;

update public.rr_real_chat_action_registry_v70
set allowed_roles=array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN']::text[]
where action_code='ASSIGN_WORKER';

revoke all on function public.rr_upm_effective_identity_v200() from public,anon;
revoke all on function public.rr_upm_effective_role_v200() from public,anon;
revoke all on function public.rr_upm_assignment_allowed_v200() from public,anon;
revoke all on function public.rr_upm_current_worker_id_v9112() from public,anon;
revoke all on function public.rr_upm_v794_actor() from public,anon;
revoke all on function public.rr_upm_v794_role() from public,anon;
revoke all on function public.rr_upm_v794_can_assign() from public,anon;
revoke all on function public.rr_upm_ready_to_assign_v9107(text,text,uuid,jsonb,text) from public,anon;
revoke all on function public.rr_upm_ready_to_assign_with_custody_v185(text,text,uuid,jsonb,uuid,text) from public,anon;
revoke all on function public.rr_upm_department_colour_due_card_v9109(text) from public,anon;
revoke all on function public.rr_upm_ready_submit_v794(text,text,jsonb) from public,anon;
revoke all on function public.rr_upm_submit_inbox_v794() from public,anon;
revoke all on function public.rr_real_chat_work_search_v12(text,text,text,integer) from public,anon;

grant execute on function public.rr_upm_effective_identity_v200() to authenticated;
grant execute on function public.rr_upm_effective_role_v200() to authenticated;
grant execute on function public.rr_upm_assignment_allowed_v200() to authenticated;
grant execute on function public.rr_upm_current_worker_id_v9112() to authenticated;
grant execute on function public.rr_upm_v794_actor() to authenticated;
grant execute on function public.rr_upm_v794_role() to authenticated;
grant execute on function public.rr_upm_v794_can_assign() to authenticated;
grant execute on function public.rr_upm_ready_to_assign_v9107(text,text,uuid,jsonb,text) to authenticated;
grant execute on function public.rr_upm_ready_to_assign_with_custody_v185(text,text,uuid,jsonb,uuid,text) to authenticated;
grant execute on function public.rr_upm_department_colour_due_card_v9109(text) to authenticated;
grant execute on function public.rr_upm_ready_submit_v794(text,text,jsonb) to authenticated;
grant execute on function public.rr_upm_submit_inbox_v794() to authenticated;
grant execute on function public.rr_real_chat_work_search_v12(text,text,text,integer) to authenticated;
