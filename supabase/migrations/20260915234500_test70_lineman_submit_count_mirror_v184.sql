-- TEST70 V184: Worker Ready -> selected Line Man receive/count -> Worker confirm -> final submit.
begin;

-- LINE_MANAGER is the canonical login role for UPM-wide line men.
create or replace function public.rr_upm_worker_candidates_v740(
  p_role_code text, p_department_code text default null
)
returns table(worker_id uuid,worker_name text,worker_code text,role_code text,department_code text,mobile text)
language sql stable security definer set search_path=public,pg_temp as $$
with dep as(
  select upper(trim(p_department_code)) code,upper(coalesce(parent_department_code,'')) parent
  from public.rr_upm_departments where upper(department_code)=upper(trim(p_department_code)) limit 1
),w as(
  select x.worker_id,x.worker_name,x.worker_code,x.role_code,x.department_code,
    public.rr_upm_phone_v740(to_jsonb(x)) mobile,
    regexp_replace(upper(coalesce(x.role_code,'')),'[^A-Z0-9]+','','g') raw_role,
    public.rr_upm_norm_role_v740(x.role_code) norm_role,
    upper(coalesce(x.department_code,'')) dep_code
  from public.rr_worker_directory_unified_v1 x
  where coalesce(x.is_active,true) and upper(coalesce(x.access_status,'ACTIVE'))='ACTIVE'
)
select w.worker_id,w.worker_name,w.worker_code,w.role_code,w.department_code,w.mobile
from w left join dep on true
where (
  case when public.rr_upm_norm_role_v740(p_role_code)='LINE_MAN'
    then w.raw_role in('LM','LNM','LINEM','LMAN','LINEMAN','LINEMANAGER')
    else w.norm_role=public.rr_upm_norm_role_v740(p_role_code) end
)
and (
  public.rr_upm_norm_role_v740(p_role_code)='CUTTING_MASTER'
  or p_department_code is null or w.dep_code=dep.code
  or (dep.parent<>'' and w.dep_code=dep.parent)
  or (public.rr_upm_norm_role_v740(p_role_code)='LINE_MAN' and w.dep_code='FABRICATION')
)
order by case when w.dep_code=dep.code then 0 when w.dep_code=dep.parent then 1 when w.dep_code='FABRICATION' then 2 else 3 end,w.worker_name
$$;
revoke all on function public.rr_upm_worker_candidates_v740(text,text) from public,anon;
grant execute on function public.rr_upm_worker_candidates_v740(text,text) to authenticated;

-- Fabrication is a parent operational scope, so line men are staff across UPM departments.
update public.rr_real_chat_department_membership_v70 m
set is_active=true,membership_scope='GLOBAL',source_rule='UPM_LINE_MAN_GLOBAL_V184',updated_at=now()
from public.rr_worker_directory_unified_v1 w
where m.worker_id=w.worker_id and upper(w.role_code) in('LINE_MANAGER','LINE_MAN')
  and m.membership_side='STAFF' and m.manual_lock=false
  and upper(m.department_code) in(
    'CUTTING','PRINTING','STICKER','METAL_ID','STITCHING','OVERLOCK','FOLDING',
    'KAAJ_BUTTON','TEAK_TANKI','THREAD_CUT','QC','PRESS','PACKING','DESPATCH'
  );

create or replace function public.rr_upm_ready_submit_to_lm_v184(
  p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_line_man_id uuid
)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_result jsonb;v_request uuid;v_lm record;v_target uuid;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  select c.*,coalesce(u.linked_auth_user_id,c.worker_id) target_id into v_lm
  from public.rr_upm_worker_candidates_v740('LINE_MAN',p_department_code)c
  left join public.rr_worker_directory_unified_v1 u on u.worker_id=c.worker_id
  where c.worker_id=p_line_man_id or u.linked_auth_user_id=p_line_man_id limit 1;
  if not found then raise exception 'Selected Line Man is inactive or unavailable.';end if;
  v_target:=v_lm.target_id;
  v_result:=public.rr_upm_ready_submit_v794(p_canonical_lot_id,p_department_code,p_rows);
  v_request:=(v_result->>'request_id')::uuid;
  if not exists(select 1 from public.rr_upm_submit_lm_candidates_v794 where request_id=v_request and line_man_id=v_target) then
    raise exception 'Selected Line Man is not eligible for this submit.';
  end if;
  delete from public.rr_upm_submit_lm_candidates_v794 where request_id=v_request and line_man_id<>v_target;
  delete from public.rr_upm_alert_events_v794
   where request_id=v_request and recipient_role='LINE_MAN' and recipient_id<>v_target;
  update public.rr_upm_submit_requests_v794 set status='WAITING_LM',updated_at=now() where id=v_request;
  return v_result||jsonb_build_object(
    'status','WAITING_LM','selected_line_man_id',v_target,
    'selected_line_man_name',v_lm.worker_name,'lm_candidates',1
  );
end $$;
revoke all on function public.rr_upm_ready_submit_to_lm_v184(text,text,jsonb,uuid) from public,anon;
grant execute on function public.rr_upm_ready_submit_to_lm_v184(text,text,jsonb,uuid) to authenticated;

-- Add canonical Line Man receive/count and Worker confirmation cards to Real Chat.
create or replace function public.rr_real_chat_work_inbox_v76(
 p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_base jsonb;v_cards jsonb;v_counts jsonb;v_role text;v_worker uuid;v_state text:=upper(coalesce(p_status,'WORKING'));r record;v_actions jsonb;v_link text;
begin
 if auth.uid() is null then raise exception 'Login required.';end if;
 v_base:=public.rr_real_chat_work_inbox_v75(v_state,p_search,p_department_code,p_limit);
 v_cards:=coalesce(v_base->'cards','[]'::jsonb);
 v_role:=upper(coalesce(v_base#>>'{actor,role}','WORKER'));
 v_worker:=nullif(v_base#>>'{actor,worker_id}','')::uuid;
 for r in
  select q.*,c.line_man_id,c.line_man_name candidate_lm_name,c.response_status
  from public.rr_upm_submit_requests_v794 q
  left join public.rr_upm_submit_lm_candidates_v794 c on c.request_id=q.id
  where (nullif(trim(p_department_code),'') is null or public.rr_upm_core_department_v9077(q.department_code)=public.rr_upm_core_department_v9077(p_department_code))
    and (coalesce(trim(p_search),'')='' or lower(concat_ws(' ',q.lot_no,q.department_code,q.worker_name,q.accepted_lm_name,q.status)) like '%'||lower(trim(p_search))||'%')
    and (
      (v_state='OPEN' and q.status in('WAITING_LM','ESCALATED') and c.line_man_id=v_worker and c.response_status='PENDING')
      or (v_state='WORKING' and q.status='LM_ACCEPTED' and q.accepted_lm_id=v_worker)
      or (v_state='WORKING' and q.status in('LM_COUNTED','DISPUTED') and q.worker_auth_id=v_worker)
      or (v_state='CLOSE' and q.status='COMPLETED' and v_worker in(q.worker_auth_id,q.accepted_lm_id))
    )
  order by q.created_at desc limit least(greatest(coalesce(p_limit,500),1),500)
 loop
  v_link:='real-department-lite-v9127.html?mode=TEST&from=TEST70_REAL_CHAT&dept='||r.department_code||'&rrSubmitRequest='||r.id;
  v_actions:=case
   when v_state='OPEN' then jsonb_build_array(jsonb_build_object('code','LM_ACCEPT_COUNT','label','ACCEPT & COUNT','href',v_link,'engine','rr_upm_accept_submit_v794'))
   when v_state='WORKING' and r.status='LM_ACCEPTED' then jsonb_build_array(jsonb_build_object('code','LM_SEND_COUNT','label','COUNT & SEND','href',v_link,'engine','rr_upm_lm_count_submit_v794'))
   when v_state='WORKING' and r.status in('LM_COUNTED','DISPUTED') then jsonb_build_array(jsonb_build_object('code','WORKER_CONFIRM_COUNT','label','CONFIRM FINAL COUNT','href',v_link,'engine','rr_upm_worker_decide_submit_v794'))
   else '[]'::jsonb end;
  v_cards:=v_cards||jsonb_build_array(jsonb_build_object(
   'event_key','UPM_SUBMIT_REQUEST:'||r.id,'source_module','UPM_SUBMIT_HANDOFF','original_record_id',r.id,
   'canonical_lot_id',r.canonical_lot_id,'lot_no',r.lot_no,'department_code',public.rr_upm_core_department_v9077(r.department_code),
   'department_name',r.department_code,'worker_id',r.worker_id,'worker_name',r.worker_name,
   'qty',coalesce(r.lm_counted_total,r.worker_ready_total),'source_status',r.status,'chat_status',v_state,
   'work_category','READY_TO_SUBMIT','message',case when r.status='WAITING_LM' then 'Worker ने माल Line Man को receive और count के लिए भेजा' when r.status='LM_ACCEPTED' then 'Line Man physical count pending' when r.status in('LM_COUNTED','DISPUTED') then 'Worker final count confirmation pending' else 'Line Man count और Worker confirmation complete' end,
   'receiver_name',coalesce(r.accepted_lm_name,r.candidate_lm_name),'event_at',coalesce(r.updated_at,r.created_at),
   'actions',v_actions,'requires_action',false,'canonical_source','rr_upm_submit_requests_v794'
  ));
 end loop;
 select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb) into v_counts
 from(select coalesce(nullif(x->>'department_code',''),'UNKNOWN')department_code,count(*)cnt from jsonb_array_elements(v_cards)x group by 1)s;
 return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V76_LM_COUNT"'::jsonb,true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end $$;
revoke all on function public.rr_real_chat_work_inbox_v76(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_inbox_v76(text,text,text,integer) to authenticated;

create or replace function public.rr_real_chat_work_search_v5(
 p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_base jsonb;v_find text:=lower(trim(coalesce(p_search,'')));v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');v_cards jsonb;v_counts jsonb;
begin
 v_base:=public.rr_real_chat_work_inbox_v76(p_status,null,p_department_code,p_limit);
 if v_find='' then return v_base;end if;
 select coalesce(jsonb_agg(card order by ord),'[]'::jsonb) into v_cards
 from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(card,ord)
 where lower(card::text)like'%'||v_find||'%' or(v_key<>'' and regexp_replace(lower(card::text),'[^a-z0-9]','','g')like'%'||v_key||'%');
 select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb)into v_counts
 from(select coalesce(nullif(card->>'department_code',''),'UNKNOWN')department_code,count(*)card_count from jsonb_array_elements(v_cards)x(card)group by 1)c;
 return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end $$;
revoke all on function public.rr_real_chat_work_search_v5(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_search_v5(text,text,text,integer) to authenticated;

insert into public.rr_real_chat_action_registry_v70(action_code,exact_button_label,source_module,source_page,rpc_name,allowed_roles,registry_status,notes)
values
 ('SUBMIT','READY TO SUBMIT','UPM','real-upm-department-view-v789.js','rr_upm_ready_submit_to_lm_v184',array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','WORKER'],'ACTIVE','Creates selected Line Man receive/count request; does not complete assignment'),
 ('LM_ACCEPT_COUNT','ACCEPT & COUNT','UPM_SUBMIT_HANDOFF','real-upm-submit-confirm-v796.js','rr_upm_accept_submit_v794',array['OWNER','SUPER_ADMIN','LINE_MANAGER','LINE_MAN'],'ACTIVE','Selected Line Man accepts physical custody'),
 ('LM_SEND_COUNT','COUNT & SEND','UPM_SUBMIT_HANDOFF','real-upm-submit-confirm-v796.js','rr_upm_lm_count_submit_v794',array['OWNER','SUPER_ADMIN','LINE_MANAGER','LINE_MAN'],'ACTIVE','Selected Line Man enters colour-size physical count'),
 ('WORKER_CONFIRM_COUNT','CONFIRM FINAL COUNT','UPM_SUBMIT_HANDOFF','real-upm-submit-confirm-v796.js','rr_upm_worker_decide_submit_v794',array['OWNER','SUPER_ADMIN','WORKER'],'ACTIVE','Assigned worker accepts or disputes Line Man count; accepted count executes canonical final submit')
on conflict(action_code)do update set exact_button_label=excluded.exact_button_label,source_module=excluded.source_module,source_page=excluded.source_page,rpc_name=excluded.rpc_name,allowed_roles=excluded.allowed_roles,registry_status=excluded.registry_status,notes=excluded.notes,updated_at=now();

commit;
