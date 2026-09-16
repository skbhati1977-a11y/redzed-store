-- TEST70 V186: Fabrication is a virtual UPM-wide Lineman operational queue.
-- App tables/actions stay authoritative; Real Chat only projects their state.
begin;

create or replace function public.rr_real_chat_work_inbox_v79(
  p_status text default 'WORKING',
  p_search text default null,
  p_department_code text default null,
  p_limit integer default 500
)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_base jsonb;
  v_cards jsonb;
  v_counts jsonb;
  v_state text := upper(coalesce(p_status,'WORKING'));
  v_role text;
  v_worker uuid;
  v_fabrication_staff boolean;
  v_link text;
  v_actions jsonb;
  v_target_auth uuid;
  v_target_worker uuid;
  r record;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if v_state not in ('OPEN','WORKING','CLOSE') then raise exception 'Invalid work state.'; end if;

  v_base := public.rr_real_chat_work_inbox_v78(v_state,p_search,p_department_code,p_limit);
  v_cards := coalesce(v_base->'cards','[]'::jsonb);
  v_role := upper(coalesce(v_base#>>'{actor,role}','WORKER'));
  v_worker := nullif(v_base#>>'{actor,worker_id}','')::uuid;
  v_fabrication_staff := v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN');

  if v_fabrication_staff then
    -- Worker submit -> selected Lineman count -> worker confirmation.
    for r in
      select q.*,
        c.line_man_id candidate_lm_id,
        c.line_man_name candidate_lm_name,
        c.response_status candidate_status
      from public.rr_upm_submit_requests_v794 q
      left join lateral (
        select x.line_man_id,x.line_man_name,x.response_status
        from public.rr_upm_submit_lm_candidates_v794 x
        where x.request_id=q.id
          and (x.line_man_id=q.accepted_lm_id or x.response_status='PENDING')
        order by case when x.line_man_id=q.accepted_lm_id then 0 else 1 end,x.response_at nulls first
        limit 1
      ) c on true
      where (
        (v_state='OPEN' and q.status in ('WAITING_LM','ESCALATED'))
        or (v_state='WORKING' and q.status in ('LM_ACCEPTED','LM_COUNTED','DISPUTED'))
        or (v_state='CLOSE' and q.status='COMPLETED')
      )
      and (
        nullif(trim(p_department_code),'') is null
        or upper(trim(p_department_code))='FABRICATION'
        or public.rr_upm_core_department_v9077(q.department_code)=public.rr_upm_core_department_v9077(p_department_code)
      )
      and (
        coalesce(trim(p_search),'')=''
        or lower(concat_ws(' ',q.lot_no,q.department_code,q.worker_name,q.accepted_lm_name,q.status)) like '%'||lower(trim(p_search))||'%'
      )
      order by coalesce(q.updated_at,q.created_at) desc
      limit least(greatest(coalesce(p_limit,500),1),500)
    loop
      v_target_auth := coalesce(r.accepted_lm_id,r.candidate_lm_id);
      select w.worker_id into v_target_worker
      from public.rr_worker_directory_unified_v1 w
      where w.worker_id=v_target_auth or w.linked_auth_user_id=v_target_auth
      order by case when w.linked_auth_user_id=v_target_auth then 0 else 1 end
      limit 1;
      v_target_worker := coalesce(v_target_worker,v_target_auth);
      v_link := 'real-department-lite-v9127.html?mode=TEST&from=TEST70_REAL_CHAT&dept='||r.department_code||'&rrSubmitRequest='||r.id;
      v_actions := case
        when v_state='OPEN' and (v_role in ('OWNER','SUPER_ADMIN') or v_target_worker=v_worker)
          then jsonb_build_array(jsonb_build_object('code','LM_ACCEPT_COUNT','label','ACCEPT & COUNT','href',v_link,'engine','rr_upm_accept_submit_v794'))
        when v_state='WORKING' and r.status='LM_ACCEPTED' and (v_role in ('OWNER','SUPER_ADMIN') or v_target_worker=v_worker)
          then jsonb_build_array(jsonb_build_object('code','LM_SEND_COUNT','label','COUNT & SEND','href',v_link,'engine','rr_upm_lm_count_submit_v794'))
        else '[]'::jsonb
      end;
      v_cards := v_cards||jsonb_build_array(jsonb_build_object(
        'event_key','UPM_FABRICATION_SUBMIT:'||r.id,
        'source_module','UPM_SUBMIT_HANDOFF',
        'original_record_id',r.id,
        'canonical_lot_id',r.canonical_lot_id,
        'lot_no',r.lot_no,
        'department_code','FABRICATION',
        'department_name','Fabrication',
        'source_department_code',public.rr_upm_core_department_v9077(r.department_code),
        'current_department_code',public.rr_upm_core_department_v9077(r.department_code),
        'visible_department_codes',jsonb_build_array('FABRICATION'),
        'worker_id',v_target_worker,
        'worker_name',coalesce(r.accepted_lm_name,r.candidate_lm_name),
        'visible_worker_ids',jsonb_strip_nulls(jsonb_build_array(v_target_worker,r.worker_id)),
        'qty',coalesce(r.lm_counted_total,r.worker_ready_total),
        'source_status',r.status,
        'chat_status',v_state,
        'work_category','READY_TO_SUBMIT',
        'message',case
          when r.status in ('WAITING_LM','ESCALATED') then 'Worker submit received · Lineman acceptance/count pending'
          when r.status='LM_ACCEPTED' then 'Lineman custody accepted · physical count pending'
          when r.status in ('LM_COUNTED','DISPUTED') then 'Lineman count sent · worker confirmation pending'
          else 'Lineman count and worker confirmation complete'
        end,
        'receiver_name',coalesce(r.accepted_lm_name,r.candidate_lm_name),
        'event_at',coalesce(r.updated_at,r.created_at),
        'actions',v_actions,
        'requires_action',false,
        'canonical_source','rr_upm_submit_requests_v794'
      ));
    end loop;

    -- After Lineman assigns goods, custody stays WORKING until worker confirms receipt.
    for r in
      select x.*,a.canonical_lot_id,a.lot_no,a.department_code,a.colour_code,a.worker_id assigned_worker_id
      from public.rr_upm_assignment_receipts_v9112 x
      join public.rr_upm_work_assignments_v8 a on a.id=x.assignment_id
      where (
        (v_state='WORKING' and x.status in ('PENDING','DISPUTED'))
        or (v_state='CLOSE' and x.status in ('CONFIRMED','CONFIRMED_SHORT'))
      )
      and (
        nullif(trim(p_department_code),'') is null
        or upper(trim(p_department_code))='FABRICATION'
        or public.rr_upm_core_department_v9077(a.department_code)=public.rr_upm_core_department_v9077(p_department_code)
      )
      and (
        coalesce(trim(p_search),'')=''
        or lower(concat_ws(' ',a.lot_no,a.department_code,a.colour_code,x.custody_line_man_name,x.status)) like '%'||lower(trim(p_search))||'%'
      )
      order by coalesce(x.confirmed_at,x.created_at) desc
      limit least(greatest(coalesce(p_limit,500),1),500)
    loop
      v_cards := v_cards||jsonb_build_array(jsonb_build_object(
        'event_key','UPM_FABRICATION_RECEIPT:'||r.assignment_id,
        'source_module','UPM_CUSTODY',
        'original_record_id',r.assignment_id,
        'canonical_lot_id',r.canonical_lot_id,
        'lot_no',r.lot_no,
        'department_code','FABRICATION',
        'department_name','Fabrication',
        'source_department_code',public.rr_upm_core_department_v9077(r.department_code),
        'visible_department_codes',jsonb_build_array('FABRICATION'),
        'worker_id',r.custody_line_man_id,
        'worker_name',r.custody_line_man_name,
        'visible_worker_ids',jsonb_strip_nulls(jsonb_build_array(r.custody_line_man_id,r.assigned_worker_id)),
        'qty',coalesce(r.confirmed_qty,r.expected_qty),
        'source_status',r.status,
        'chat_status',v_state,
        'work_category','CUSTODY_HANDOVER',
        'message',case when r.status in ('PENDING','DISPUTED') then 'Lineman custody handover · worker receipt pending' else 'Worker receipt confirmed · custody handover closed' end,
        'receiver_name',r.custody_line_man_name,
        'event_at',coalesce(r.confirmed_at,r.created_at),
        'actions','[]'::jsonb,
        'requires_action',false,
        'canonical_source','rr_upm_assignment_receipts_v9112'
      ));
    end loop;

    -- Missing stays WORKING until recovery or Packing Submit finalizes it.
    for r in
      select m.* from public.rr_upm_missing_qty_v800 m
      where (
        (v_state='WORKING' and m.status in ('WORKER_CLAIM_PENDING','RECOVERY_JOURNEY'))
        or (v_state='CLOSE' and m.status in ('RECOVERED','CONVERTED_TO_DAMAGE'))
      )
      and (
        nullif(trim(p_department_code),'') is null
        or upper(trim(p_department_code))='FABRICATION'
        or public.rr_upm_core_department_v9077(m.department_code)=public.rr_upm_core_department_v9077(p_department_code)
      )
      and (
        coalesce(trim(p_search),'')=''
        or lower(concat_ws(' ',m.lot_no,m.department_code,m.worker_name,m.status,m.responsibility_owner_type,m.liability_stage)) like '%'||lower(trim(p_search))||'%'
      )
      order by m.updated_at desc
      limit least(greatest(coalesce(p_limit,500),1),500)
    loop
      v_cards := v_cards||jsonb_build_array(jsonb_build_object(
        'event_key','UPM_FABRICATION_MISSING:'||r.id,
        'source_module','UPM_MISSING_CLAIM',
        'original_record_id',r.id,
        'canonical_lot_id',r.canonical_lot_id,
        'lot_no',r.lot_no,
        'department_code','FABRICATION',
        'department_name','Fabrication',
        'source_department_code',public.rr_upm_core_department_v9077(r.department_code),
        'visible_department_codes',jsonb_build_array('FABRICATION'),
        'worker_id',nullif(r.worker_id,''),
        'worker_name',r.worker_name,
        'visible_worker_ids',case when nullif(r.worker_id,'') is null then '[]'::jsonb else jsonb_build_array(r.worker_id) end,
        'qty',r.missing_qty,
        'source_status',r.status,
        'chat_status',v_state,
        'work_category','MISSING_CLAIM',
        'message',case when r.status in ('WORKER_CLAIM_PENDING','RECOVERY_JOURNEY') then 'Missing claim held · Packing Submit तक recovery allowed' else 'Missing claim closed · '||r.status end,
        'receiver_name',r.worker_name,
        'event_at',r.updated_at,
        'actions','[]'::jsonb,
        'requires_action',false,
        'canonical_source','rr_upm_missing_qty_v800',
        'responsibility_owner_type',r.responsibility_owner_type,
        'liability_stage',r.liability_stage,
        'finalization_stage',r.finalization_stage
      ));
    end loop;
  end if;

  select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb) into v_counts
  from (
    select coalesce(nullif(x->>'department_code',''),'UNKNOWN') department_code,count(*) cnt
    from jsonb_array_elements(v_cards) x group by 1
  ) s;
  return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V79_FABRICATION"'::jsonb,true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;
$$;

revoke all on function public.rr_real_chat_work_inbox_v79(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_inbox_v79(text,text,text,integer) to authenticated;

create or replace function public.rr_real_chat_work_search_v6(
  p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb;v_find text:=lower(trim(coalesce(p_search,'')));v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');v_cards jsonb;v_counts jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  v_base:=public.rr_real_chat_work_inbox_v79(p_status,null,p_department_code,p_limit);
  if v_find='' then return v_base;end if;
  select coalesce(jsonb_agg(card order by ord),'[]'::jsonb) into v_cards
  from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(card,ord)
  where lower(card::text)like'%'||v_find||'%' or(v_key<>'' and regexp_replace(lower(card::text),'[^a-z0-9]','','g')like'%'||v_key||'%');
  select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb) into v_counts
  from(select coalesce(nullif(card->>'department_code',''),'UNKNOWN')department_code,count(*)card_count from jsonb_array_elements(v_cards)x(card)group by 1)c;
  return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;
$$;

revoke all on function public.rr_real_chat_work_search_v6(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_search_v6(text,text,text,integer) to authenticated;

comment on function public.rr_real_chat_work_inbox_v79(text,text,text,integer) is
'Fabrication virtual UPM-wide queue: WAITING_LM open, LM_ACCEPTED/LM_COUNTED working, COMPLETED close, custody and missing mirrored from authoritative App tables.';

commit;
