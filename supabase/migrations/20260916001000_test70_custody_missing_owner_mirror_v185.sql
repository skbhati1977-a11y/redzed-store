-- TEST70 V185: custody-based missing ownership, App + Real Chat mirror.
alter table public.rr_upm_assignment_receipts_v9112
  add column if not exists custody_line_man_id uuid,
  add column if not exists custody_line_man_name text;

alter table public.rr_upm_missing_qty_v800
  add column if not exists responsibility_owner_type text,
  add column if not exists liability_stage text,
  add column if not exists finalization_stage text default 'PACKING_SUBMITTED';

create or replace function public.rr_upm_ready_to_assign_with_custody_v185(
 p_canonical_lot_id text,p_department_code text,p_worker_id uuid,p_rows jsonb,
 p_line_man_id uuid,p_remarks text default null)
returns jsonb language plpgsql security definer set search_path='public' as $$
declare v_result jsonb;v_lm_name text;v_row jsonb;v_a public.rr_upm_work_assignments_v8%rowtype;
begin
 if auth.uid() is null then raise exception 'Login required.';end if;
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
 return v_result||jsonb_build_object('version','V185_ASSIGN_CUSTODY','custody_owner_type','LINE_MAN','custody_line_man_id',p_line_man_id,'custody_line_man_name',v_lm_name,'worker_receipt_required',true);
end$$;

create or replace function public.rr_upm_register_custody_missing_v185(
 p_assignment_id uuid,p_expected_good numeric,p_received_good numeric,p_owner_id text,p_owner_name text,p_owner_type text,p_stage text)
returns jsonb language plpgsql security definer set search_path='public' as $$
declare a public.rr_upm_work_assignments_v8%rowtype;v_short numeric;v_result jsonb;v_size text;
begin
 select * into a from public.rr_upm_work_assignments_v8 where id=p_assignment_id;
 if not found then raise exception 'Assignment not found.';end if;
 v_short:=greatest(coalesce(p_expected_good,0)-coalesce(p_received_good,0),0);
 if v_short<=0 then return jsonb_build_object('ok',true,'missing_qty',0,'owner_type',upper(p_owner_type));end if;
 v_size:=case when upper(p_stage)='ASSIGN_RECEIPT' then 'ASSIGN_ALL' else 'SUBMIT_ALL' end;
 v_result:=public.rr_upm_submit_count_missing_v800(a.canonical_lot_id,a.lot_no,a.department_code,a.id::text,p_owner_id,p_owner_name,coalesce(a.actual_rate,0),
  jsonb_build_array(jsonb_build_object('colour_code',a.colour_code,'size_code',v_size,'assigned_qty',p_expected_good,'submitted_good_qty',p_received_good,'alter_pending_qty',0,'remake_pending_qty',0,'damage_qty',0,'liability_stage',upper(p_stage),'responsibility_owner_type',upper(p_owner_type),'hold_until','PACKING_SUBMITTED')));
 update public.rr_upm_missing_qty_v800 set responsibility_owner_type=upper(p_owner_type),liability_stage=upper(p_stage),finalization_stage='PACKING_SUBMITTED',
  payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('expected_good_qty',p_expected_good,'received_good_qty',p_received_good,'responsibility_owner_id',p_owner_id,'responsibility_owner_name',p_owner_name,'responsibility_owner_type',upper(p_owner_type),'liability_stage',upper(p_stage),'hold_until','PACKING_SUBMITTED')
 where assignment_id=a.id::text and upper(colour_code)=upper(a.colour_code) and size_code=v_size and status in('WORKER_CLAIM_PENDING','RECOVERY_JOURNEY');
 return v_result||jsonb_build_object('owner_id',p_owner_id,'owner_name',p_owner_name,'owner_type',upper(p_owner_type),'liability_stage',upper(p_stage),'claim_status','HELD_UNTIL_PACKING_SUBMITTED');
end$$;

create or replace function public.rr_upm_confirm_assignment_receipt_v9112(p_assignment_id uuid,p_confirmed_qty numeric,p_note text default null)
returns jsonb language plpgsql security definer set search_path='public' as $$
declare v_r public.rr_upm_assignment_receipts_v9112%rowtype;v_worker uuid:=public.rr_upm_current_worker_id_v9112();v_status text;v_a public.rr_upm_work_assignments_v8%rowtype;v_claim jsonb:='{}'::jsonb;
begin
 select * into v_r from public.rr_upm_assignment_receipts_v9112 where assignment_id=p_assignment_id for update;
 if not found then raise exception 'Assignment receipt confirmation not found.';end if;
 if v_worker is null or v_worker<>v_r.worker_id then raise exception 'Only assigned worker can confirm received quantity.';end if;
 if p_confirmed_qty is null or p_confirmed_qty<0 or p_confirmed_qty>v_r.expected_qty then raise exception 'Confirmed Qty must be between 0 and %.',v_r.expected_qty;end if;
 select * into v_a from public.rr_upm_work_assignments_v8 where id=p_assignment_id;
 v_status:=case when p_confirmed_qty=v_r.expected_qty then 'CONFIRMED' else 'CONFIRMED_SHORT' end;
 update public.rr_upm_assignment_receipts_v9112 set confirmed_qty=p_confirmed_qty,status=v_status,confirmed_at=now(),confirmed_by=auth.uid(),note=p_note where assignment_id=p_assignment_id;
 if p_confirmed_qty<v_r.expected_qty then
  if v_r.custody_line_man_id is null then raise exception 'Custody Line Man mapping required before short receipt can be confirmed.';end if;
  v_claim:=public.rr_upm_register_custody_missing_v185(p_assignment_id,v_r.expected_qty,p_confirmed_qty,v_r.custody_line_man_id::text,v_r.custody_line_man_name,'LINE_MAN','ASSIGN_RECEIPT');
 end if;
 return jsonb_build_object('ok',true,'version','V185_WORKER_RECEIPT_CUSTODY','assignment_id',p_assignment_id,'lot_no',v_a.lot_no,'colour_code',v_a.colour_code,'expected_qty',v_r.expected_qty,'confirmed_qty',p_confirmed_qty,'status',v_status,'custody_owner_type','LINE_MAN','custody_owner_name',v_r.custody_line_man_name,'claim',v_claim);
end$$;

create or replace function public.rr_upm_submit_claim_trigger_v185()returns trigger language plpgsql security definer set search_path='public' as $$
declare c jsonb;lm jsonb;aid uuid;v_expected numeric;v_received numeric;a public.rr_upm_work_assignments_v8%rowtype;
begin
 if new.status='COMPLETED' and old.status is distinct from new.status then
  for c in select value from jsonb_array_elements(coalesce(new.colour_rows,'[]'::jsonb)) loop
   aid:=nullif(c->>'assignment_id','')::uuid;
   select * into a from public.rr_upm_work_assignments_v8 where id=aid;
   select coalesce(r.confirmed_qty,r.expected_qty,a.assigned_qty) into v_expected from public.rr_upm_assignment_receipts_v9112 r where r.assignment_id=aid;
   if v_expected is null then v_expected:=coalesce((c->>'assigned_total')::numeric,a.assigned_qty,0);end if;
   select value into lm from jsonb_array_elements(coalesce(new.lm_count_rows,'[]'::jsonb)) where upper(value->>'colour_code')=upper(c->>'colour_code') limit 1;
   select coalesce(sum((s->>'qty')::numeric),0) into v_received from jsonb_array_elements(coalesce(lm->'sizes','[]'::jsonb))s;
   if v_received<v_expected then perform public.rr_upm_register_custody_missing_v185(aid,v_expected,v_received,new.worker_id::text,new.worker_name,'WORKER','SUBMIT_COUNT');end if;
  end loop;
 end if;return new;
end$$;
drop trigger if exists rr_upm_submit_claim_v185 on public.rr_upm_submit_requests_v794;
create trigger rr_upm_submit_claim_v185 after update of status on public.rr_upm_submit_requests_v794 for each row execute function public.rr_upm_submit_claim_trigger_v185();

create or replace function public.rr_upm_missing_packing_finalize_v185(p_canonical_lot_id text)returns jsonb language plpgsql security definer set search_path='public' as $$
declare m public.rr_upm_missing_qty_v800%rowtype;v_count int:=0;v_qty numeric:=0;v_amount numeric:=0;
begin
 for m in select * from public.rr_upm_missing_qty_v800 where canonical_lot_id=p_canonical_lot_id and status in('WORKER_CLAIM_PENDING','RECOVERY_JOURNEY') and missing_qty>0 for update loop
  insert into public.rr_worker_claim_debit_v800(debit_code,worker_id,worker_name,debit_type,source_id,canonical_lot_id,lot_no,department_code,assignment_id,colour_code,size_code,qty,frozen_rate,debit_amount,payload)
  values(public.rr_v800_code('DBT'),m.worker_id,m.worker_name,'MISSING_TO_DAMAGE',m.id::text,m.canonical_lot_id,m.lot_no,m.department_code,m.assignment_id,m.colour_code,m.size_code,m.missing_qty,m.frozen_claim_rate,m.missing_qty*m.frozen_claim_rate,jsonb_build_object('rule','PACKING_SUBMITTED_UNRECOVERED_MISSING','responsibility_owner_type',m.responsibility_owner_type,'liability_stage',m.liability_stage,'finalized_at_stage','PACKING_SUBMITTED'))
  on conflict(debit_type,source_id)do nothing;
  update public.rr_payroll_claim_reserve_v800 set status='CONVERTED_TO_FINAL_DEBIT',converted_at=now() where reserve_type='MISSING' and source_id=m.id::text and status='HELD';
  update public.rr_upm_missing_qty_v800 set status='CONVERTED_TO_DAMAGE',despatch_converted_at=now(),updated_at=now(),payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('finalized_at_stage','PACKING_SUBMITTED') where id=m.id;
  v_count:=v_count+1;v_qty:=v_qty+m.missing_qty;v_amount:=v_amount+m.missing_qty*m.frozen_claim_rate;
 end loop;
 return jsonb_build_object('ok',true,'finalized_at_stage','PACKING_SUBMITTED','converted_rows',v_count,'claim_qty',v_qty,'final_debit_amount',v_amount);
end$$;

create or replace function public.rr_upm_packing_claim_trigger_v185()returns trigger language plpgsql security definer set search_path='public' as $$
declare v_canonical text;
begin
 if new.status='SUBMITTED' and old.status is distinct from new.status then
  select canonical_lot_id into v_canonical from public.rr_upm_lot_registry where upper(trim(lot_no))=upper(trim(new.lot_no)) limit 1;
  if v_canonical is not null then perform public.rr_upm_missing_packing_finalize_v185(v_canonical);end if;
 end if;return new;
end$$;
drop trigger if exists rr_upm_packing_claim_finalize_v185 on public.rr_fg_packing_assignments_v788;
create trigger rr_upm_packing_claim_finalize_v185 after update of status on public.rr_fg_packing_assignments_v788 for each row execute function public.rr_upm_packing_claim_trigger_v185();

create or replace function public.rr_upm_my_pending_receipts_v9112()
returns jsonb language sql stable security definer set search_path='public' as $$
with me as(select public.rr_upm_current_worker_id_v9112()worker_id)
select jsonb_build_object('ok',true,'version','V185_MY_CUSTODY_RECEIPTS','rows',coalesce(jsonb_agg(jsonb_build_object(
 'assignment_id',r.assignment_id,'lot_no',a.lot_no,'department_code',public.rr_upm_core_department_v9077(a.department_code),
 'colour_code',a.colour_code,'expected_qty',r.expected_qty,'confirmed_qty',r.confirmed_qty,'status',r.status,'assigned_at',a.assigned_at,
 'custody_line_man_id',r.custody_line_man_id,'custody_line_man_name',r.custody_line_man_name
)order by a.assigned_at),'[]'::jsonb))
from public.rr_upm_assignment_receipts_v9112 r join public.rr_upm_work_assignments_v8 a on a.id=r.assignment_id
where r.worker_id=(select worker_id from me)and r.status in('PENDING','DISPUTED')
$$;

create or replace function public.rr_real_chat_work_inbox_v78(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit int default 500)
returns jsonb language plpgsql stable security definer set search_path='public','pg_temp' as $$
declare v_base jsonb;v_cards jsonb;v_counts jsonb;v_state text:=upper(coalesce(p_status,'WORKING'));v_worker uuid;v_role text;r record;v_link text;
begin
 if auth.uid() is null then raise exception 'Login required.';end if;
 v_base:=public.rr_real_chat_work_inbox_v77(v_state,p_search,p_department_code,p_limit);v_cards:=coalesce(v_base->'cards','[]'::jsonb);
 v_worker:=nullif(v_base#>>'{actor,worker_id}','')::uuid;v_role:=upper(coalesce(v_base#>>'{actor,role}','WORKER'));
 if v_state='OPEN' then
  for r in select x.*,a.lot_no,a.department_code,a.colour_code from public.rr_upm_assignment_receipts_v9112 x join public.rr_upm_work_assignments_v8 a on a.id=x.assignment_id
   where x.worker_id=v_worker and x.status in('PENDING','DISPUTED')
    and(nullif(trim(p_department_code),'')is null or public.rr_upm_core_department_v9077(a.department_code)=public.rr_upm_core_department_v9077(p_department_code))
  loop
   v_link:='real-department-lite-v9127.html?mode=TEST&from=TEST70_REAL_CHAT&dept='||r.department_code||'&rrAssignmentReceipt='||r.assignment_id;
   v_cards:=v_cards||jsonb_build_array(jsonb_build_object('event_key','UPM_ASSIGN_RECEIPT:'||r.assignment_id,'source_module','UPM_CUSTODY','original_record_id',r.assignment_id,'lot_no',r.lot_no,'department_code',public.rr_upm_core_department_v9077(r.department_code),'worker_id',r.worker_id,'qty',r.expected_qty,'source_status',r.status,'chat_status','OPEN','work_category','RECEIVE_ASSIGNED_GOODS','message','Line Man custody से assigned Good PCS receive/count करें','receiver_name',r.custody_line_man_name,'event_at',r.created_at,'actions',jsonb_build_array(jsonb_build_object('code','CONFIRM_RECEIVED_PCS','label','RECEIVE & COUNT','href',v_link,'engine','rr_upm_confirm_assignment_receipt_v9112')),'requires_action',false,'canonical_source','rr_upm_assignment_receipts_v9112'));
  end loop;
 end if;
 for r in select m.* from public.rr_upm_missing_qty_v800 m
  where((v_state='WORKING'and m.status in('WORKER_CLAIM_PENDING','RECOVERY_JOURNEY'))or(v_state='CLOSE'and m.status in('RECOVERED','CONVERTED_TO_DAMAGE')))
   and(v_role in('OWNER','SUPER_ADMIN','ADMIN')or m.worker_id=v_worker::text)
   and(nullif(trim(p_department_code),'')is null or public.rr_upm_core_department_v9077(m.department_code)=public.rr_upm_core_department_v9077(p_department_code))
 loop
  v_cards:=v_cards||jsonb_build_array(jsonb_build_object('event_key','UPM_MISSING:'||r.id,'source_module','UPM_MISSING_CLAIM','original_record_id',r.id,'canonical_lot_id',r.canonical_lot_id,'lot_no',r.lot_no,'department_code',public.rr_upm_core_department_v9077(r.department_code),'worker_name',r.worker_name,'qty',r.missing_qty,'source_status',r.status,'chat_status',v_state,'work_category','MISSING_CLAIM','message',case when r.status in('WORKER_CLAIM_PENDING','RECOVERY_JOURNEY')then 'Missing claim HELD · Packing Submit तक recovery allowed'else 'Missing claim closed · '||r.status end,'receiver_name',r.worker_name,'event_at',r.updated_at,'actions','[]'::jsonb,'requires_action',false,'canonical_source','rr_upm_missing_qty_v800','responsibility_owner_type',r.responsibility_owner_type,'liability_stage',r.liability_stage,'finalization_stage',r.finalization_stage));
 end loop;
 select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb)into v_counts from(select coalesce(nullif(x->>'department_code',''),'UNKNOWN')department_code,count(*)cnt from jsonb_array_elements(v_cards)x group by 1)s;
 return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V78_CUSTODY_MISSING"'::jsonb,true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end$$;

create or replace function public.rr_real_chat_work_search_v5(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit int default 500)
returns jsonb language plpgsql stable security definer set search_path='public','pg_temp' as $$
declare v_base jsonb;v_find text:=lower(trim(coalesce(p_search,'')));v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');v_cards jsonb;v_counts jsonb;
begin
 v_base:=public.rr_real_chat_work_inbox_v78(p_status,null,p_department_code,p_limit);if v_find=''then return v_base;end if;
 select coalesce(jsonb_agg(card order by ord),'[]'::jsonb)into v_cards from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(card,ord)
 where lower(card::text)like'%'||v_find||'%'or(v_key<>''and regexp_replace(lower(card::text),'[^a-z0-9]','','g')like'%'||v_key||'%');
 select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb)into v_counts from(select coalesce(nullif(card->>'department_code',''),'UNKNOWN')department_code,count(*)card_count from jsonb_array_elements(v_cards)x(card)group by 1)c;
 return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end$$;

revoke all on function public.rr_upm_ready_to_assign_with_custody_v185(text,text,uuid,jsonb,uuid,text) from public,anon;
revoke all on function public.rr_upm_register_custody_missing_v185(uuid,numeric,numeric,text,text,text,text) from public,anon;
revoke all on function public.rr_upm_missing_packing_finalize_v185(text) from public,anon;
revoke all on function public.rr_upm_register_custody_missing_v185(uuid,numeric,numeric,text,text,text,text) from authenticated;
revoke all on function public.rr_upm_missing_packing_finalize_v185(text) from authenticated;
revoke all on function public.rr_upm_submit_claim_trigger_v185() from public,anon,authenticated;
revoke all on function public.rr_upm_packing_claim_trigger_v185() from public,anon,authenticated;
grant execute on function public.rr_upm_ready_to_assign_with_custody_v185(text,text,uuid,jsonb,uuid,text) to authenticated;
revoke all on function public.rr_real_chat_work_inbox_v78(text,text,text,int) from public,anon;
grant execute on function public.rr_real_chat_work_inbox_v78(text,text,text,int) to authenticated;
