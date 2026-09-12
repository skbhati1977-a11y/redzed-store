-- TEST70 V90: purchase events stay source-true after every refresh.
begin;

-- Department membership must never make one staff member the receiver of every event.
update public.rr_real_chat_department_receiver_v86
set is_active=false,updated_at=now()
where department_code='PURCHASE';

create or replace function public.rr_real_chat_enforce_action_route_v85()
returns trigger language plpgsql security invoker set search_path='' as $$
declare v_source text; v_target text;
begin
 new.department_code:=public.rr_real_chat_route_department_v85(new.source_module,new.action_code,
  new.department_code,new.personal_payload,new.group_payload);
 v_source:=new.department_code;
 v_target:=coalesce(nullif(new.personal_payload->>'target_department_code',''),
  nullif(new.personal_payload->>'receiver_department_code',''),
  nullif(new.group_payload->>'target_department_code',''),
  nullif(new.group_payload->>'receiver_department_code',''));
 if v_target is not null then v_target:=public.rr_real_chat_canonical_department_v83(v_target); end if;
 new.personal_payload:=coalesce(new.personal_payload,'{}'::jsonb)
  ||jsonb_build_object('source_department_code',v_source,'performed_by_user_id',new.sender_user_id)
  ||case when v_target is null then '{}'::jsonb else jsonb_build_object('target_department_code',v_target) end;
 new.group_payload:=coalesce(new.group_payload,'{}'::jsonb)
  ||jsonb_build_object('source_department_code',v_source)
  ||case when v_target is null then '{}'::jsonb else jsonb_build_object('target_department_code',v_target) end;
 return new;
end $$;
revoke all on function public.rr_real_chat_enforce_action_route_v85() from public,anon,authenticated;

-- The broad legacy synchronizer continues to cover all other modules, but Purchase
-- is owned by the exact-source synchronizer below.
create or replace function public.rr_real_chat_sync_e2e_events_v71(p_key text default null)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer;
begin
 insert into public.rr_real_chat_message_bridge_v70(canonical_key,source_module,source_record_id,source_event_type,department_code,
  sender_user_id,receiver_user_id,receiver_worker_id,action_code,action_label,personal_payload,group_payload,deep_link,sent_at)
 select canonical_key,module,record_id,event_type,department_code,sender_user,receiver_user,receiver_worker,action_code,action_label,
  personal_payload,group_payload,deep_link,sent_at
 from public.rr_real_chat_e2e_event_source_v71
 where module not in ('CB_PURCHASE','MATCHING_PURCHASE')
  and (p_key is null or canonical_key like p_key||'%')
 on conflict(canonical_key) do update set source_event_type=excluded.source_event_type,receiver_user_id=excluded.receiver_user_id,
  receiver_worker_id=excluded.receiver_worker_id,action_code=excluded.action_code,action_label=excluded.action_label,
  personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,deep_link=excluded.deep_link,sent_at=excluded.sent_at
 where public.rr_real_chat_message_bridge_v70.source_module=excluded.source_module;
 get diagnostics n=row_count;
 insert into public.rr_real_chat_receipts_v70(message_id,receiver_key,receiver_user_id,receiver_worker_id)
 select id,case when receiver_worker_id is not null then 'WORKER:'||receiver_worker_id else 'USER:'||receiver_user_id end,receiver_user_id,receiver_worker_id
 from public.rr_real_chat_message_bridge_v70 where receiver_user_id is not null and (p_key is null or canonical_key like p_key||'%')
 on conflict(message_id,receiver_key) do update set receiver_user_id=excluded.receiver_user_id;
 return n;
end $$;
revoke all on function public.rr_real_chat_sync_e2e_events_v71(text) from public,anon;
grant execute on function public.rr_real_chat_sync_e2e_events_v71(text) to authenticated;

create or replace function public.rr_real_chat_sync_purchase_v90(p_record_id uuid default null)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer;
begin
 insert into public.rr_real_chat_message_bridge_v70(
  canonical_key,source_module,source_record_id,source_event_type,department_code,
  sender_user_id,sender_worker_id,receiver_user_id,receiver_worker_id,
  action_code,action_label,personal_payload,group_payload,deep_link,sent_at,archived_at,archive_reason)
 select 'CB_PURCHASE:'||p.id||':PURCHASE','CB_PURCHASE',p.id::text,'CB_PURCHASE_CONFIRMED','PURCHASE',
  p.created_by,actor.worker_id,null,null,null,null,
  payload.j,payload.j,'test70-cb-purchase-real-chat-pilot.html?chat=group&department=PURCHASE',p.created_at,null,null
 from public.rr_cb_purchase_entries p
 left join public.rr_cb_master c on c.id=p.cb_id
 left join lateral(select d.worker_id,d.worker_name from public.rr_worker_directory_unified_v1 d
  where d.linked_auth_user_id=p.created_by and coalesce(d.is_active,false) order by d.worker_id limit 1) actor on true
 left join lateral(select count(*)::int roll_count,coalesce(sum(x.quantity),0) roll_quantity
  from public.rr_cb_purchase_rolls x where x.purchase_entry_id=p.id and coalesce(x.operation_status,'ACTIVE')<>'REVERSED') r on true
 left join lateral(select coalesce(jsonb_agg(x.image_url order by x.colour_order)
  filter(where x.image_url is not null),'[]'::jsonb) images
  from public.rr_cb_colours x where x.cb_id=p.cb_id) imgs on true
 cross join lateral(select jsonb_build_object(
  'conversation_type','PURCHASE','purchase_kind','REGULAR_CLOTH','cb_no',coalesce(c.cb_no,p.cb_id::text),
  'supplier',p.vendor_name,'bill_no',p.vendor_bill_no,'bill_date',p.bill_date,
  'fabric_name',p.fabric_name,'quantity',p.quantity,'quantity_unit','KG','rate',p.rate,'amount',p.amount,
  'available_quantity',p.available_quantity,'roll_count',coalesce(r.roll_count,0),'roll_quantity',coalesce(r.roll_quantity,0),
  'colour_count',coalesce(c.colour_count,0),'colour_images',coalesce(imgs.images,'[]'::jsonb),
  'status','COMPLETED','message','Cloth purchase completed','sender_name',coalesce(actor.worker_name,'Purchase Team'),
  'receiver_name','Art Decide Queue','source_department_code','PURCHASE','target_department_code','PRODUCT_MASTER') j) payload
 where p_record_id is null or p.id=p_record_id
 on conflict(canonical_key) do update set source_event_type=excluded.source_event_type,department_code=excluded.department_code,
  sender_user_id=excluded.sender_user_id,sender_worker_id=excluded.sender_worker_id,
  receiver_user_id=null,receiver_worker_id=null,action_code=null,action_label=null,
  personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,deep_link=excluded.deep_link,
  sent_at=excluded.sent_at,archived_at=null,archive_reason=null;
 get diagnostics n=row_count;

 update public.rr_real_chat_message_bridge_v70 b set archived_at=coalesce(b.archived_at,now()),archive_reason='REPLACED_BY_SOURCE_TRUE_PURCHASE_V90'
 where b.source_module='CB_PURCHASE' and b.canonical_key not like '%:PURCHASE'
  and (p_record_id is null or b.source_record_id=p_record_id::text);
 return n;
end $$;
revoke all on function public.rr_real_chat_sync_purchase_v90(uuid) from public,anon;
grant execute on function public.rr_real_chat_sync_purchase_v90(uuid) to authenticated,service_role;

create or replace function public.rr_real_chat_purchase_trigger_v90()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin perform public.rr_real_chat_sync_purchase_v90(new.id); return new;
exception when others then raise warning 'Purchase chat sync deferred: %',sqlerrm; return new; end $$;
drop trigger if exists rr_real_chat_e2e_sync_v71 on public.rr_cb_purchase_entries;
drop trigger if exists rr_real_chat_purchase_sync_v90 on public.rr_cb_purchase_entries;
create trigger rr_real_chat_purchase_sync_v90 after insert or update on public.rr_cb_purchase_entries
for each row execute function public.rr_real_chat_purchase_trigger_v90();

-- Owner/Super Admin membership grants supervision, not a worker salary chip.
create or replace function public.rr_test70_worker_accounts_map_v78()
returns table(worker_id uuid,salary_ledger_id uuid,worker_name text,department_code text,
 payroll_category text,linked_login boolean,chat_id uuid)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin
 if auth.uid() is null or not public.rr_real_chat_is_global_staff_v70(auth.uid()) then raise exception 'STAFF_ACCESS_REQUIRED'; end if;
 return query
 select m.worker_id,m.salary_ledger_id,m.worker_name,m.department_code,m.payroll_category,
  m.linked_auth_user_id is not null,c.chat_id
 from public.rr_worker_accounts_map_v9785 m
 join public.rr_worker_directory_unified_v1 d on d.worker_id=m.worker_id
 left join public.rr_worker_real_chat_map_v9787 c on c.worker_id=m.worker_id and c.is_active
 where m.is_active and upper(coalesce(d.role_code,'')) not in ('OWNER','SUPER_ADMIN')
 order by m.department_code,m.worker_name,m.worker_id;
end $function$;
revoke all on function public.rr_test70_worker_accounts_map_v78() from public,anon;
grant execute on function public.rr_test70_worker_accounts_map_v78() to authenticated,service_role;

select public.rr_real_chat_sync_purchase_v90(null);
commit;
