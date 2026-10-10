-- TEST71 only: Cutting readiness must use the same live gate as release.
CREATE OR REPLACE FUNCTION public.rr_chat_cutting_queue_test71(p_status text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
declare s text:=upper(p_status);role text;cards jsonb;u record;life jsonb;b record;actions jsonb;can_release boolean;
begin
 perform public.rr_assert_active_user_v1();
 if auth.uid() is null then raise exception 'Login required.';end if;
 if s not in('OPEN','WORKING','CLOSE') then raise exception 'Invalid queue.';end if;
 select upper(replace(role_code,' ','_')) into role from public.rr_user_profiles where auth_user_id=auth.uid() and is_active;
 if coalesce(role,'') not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','CUTTING_MASTER','DEPARTMENT_HEAD') and not exists(select 1 from public.rr_worker_directory_unified_v1 w join public.rr_real_chat_department_membership_v70 m on m.worker_id=w.worker_id where w.linked_auth_user_id=auth.uid() and m.is_active and public.rr_real_chat_canonical_department_v83(m.department_code)='CUTTING') then raise exception 'Cutting access denied.';end if;
 cards:=coalesce(public.rr_real_chat_work_search_v10(s,null,'CUTTING',500)->'cards','[]');
 if s='OPEN' then
  -- Old READY_FOR_CUTTING mirrors cannot override the current child gate.
  select coalesce(jsonb_agg(x),'[]') into cards from jsonb_array_elements(cards)x where coalesce(x->>'card_type',x->>'source_event_type','')<>'READY_FOR_CUTTING';
  can_release:=role in('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER');
  for u in select * from public.rr_cb_units where is_final and is_cutting_enabled and upper(operation_status)='ACTIVE' loop
   life:=public.rr_cutting_child_lifecycle_v615(u.id);
   if life->>'state'<>'READY_FOR_CUTTING' or not coalesce((life->>'all_decisions_complete')::boolean,false) or coalesce((life->>'material_due_count')::int,0)>0 then continue;end if;
   select * into b from public.rr_real_chat_message_bridge_v70 where data_mode='TEST' and archived_at is null and source_event_type='READY_FOR_CUTTING' and coalesce(group_payload->>'cb_unit_id',source_record_id)=u.id::text order by sent_at desc,id desc limit 1;
   actions:=case when can_release then jsonb_build_array(jsonb_build_object('code','CUTTING_SINGLE_LOT','label','SINGLE LOT','href','real-cutting-master.html?cb_unit_id='||u.id||'&lot_mode=single','engine','EXISTING_CUTTING_RELEASE_CHAIN'),jsonb_build_object('code','CUTTING_MULTI_LOT','label','MULTI LOT','href','real-cutting-master.html?cb_unit_id='||u.id||'&lot_mode=multi','engine','EXISTING_CUTTING_RELEASE_CHAIN')) else '[]'::jsonb end;
   cards:=cards||jsonb_build_array(jsonb_build_object('event_key','CUTTING_READY:'||u.id,'source_event_keys',case when b.canonical_key is null then '[]'::jsonb else jsonb_build_array(b.canonical_key) end,'source_module','CUTTING','source_event_type','READY_FOR_CUTTING','card_type','READY_FOR_CUTTING','cb_unit_id',u.id,'original_record_id',u.id,'cb_no',u.cb_base_no,'cb_code',u.cb_code,'department_code','CUTTING','department_name','Cutting','source_status','READY_FOR_CUTTING','canonical_state','OPEN','chat_status','OPEN','search_status','OPEN','message','Art / Print decision complete · Cutting Lot बनाना बाकी है','event_at',coalesce(b.sent_at,u.updated_at),'sender_name',coalesce(b.group_payload->>'performed_by_name','Art / Print workflow'),'receiver_name','Cutting Master','pending_actor_name','Cutting Master','next_action','CUTTING_SINGLE_LOT','requires_action',can_release,'actions',actions,'material_due_count',life->'material_due_count','all_decisions_complete',life->'all_decisions_complete'));
  end loop;
 end if;
 return jsonb_build_object('version','TEST71_CANONICAL_CUTTING_QUEUE','department_code','CUTTING','status',s,'cards',cards,'count',jsonb_array_length(cards));
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_cutting_queue_test71(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_cutting_queue_test71(text) TO authenticated;
