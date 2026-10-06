create or replace function public.rr_pi_rate_recovery_test71(p_requirement_id uuid,p_lot_no text,p_notify boolean default false)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare a public.rr_user_profiles%rowtype; r public.rr_market_requirements_v9420%rowtype; cy public.rr_collection_cycle_v9586%rowtype; s public.rr_rm_stock_v849_2c6%rowtype; owner_ok boolean; cost jsonb; route text; recipients integer:=0;
begin
 perform public.rr_assert_active_user_v1();a:=public.rr_chat_actor_profile_v9433();
 select * into r from public.rr_market_requirements_v9420 where id=p_requirement_id;
 select * into cy from public.rr_collection_cycle_v9586 where id=r.collection_cycle_id and data_mode='TEST';
 if cy.id is null or not exists(select 1 from public.rr_customer_chat_members_v9433 m where m.chat_id=cy.chat_id and m.profile_id=a.id and m.is_active) then raise exception 'Authorized TEST requirement required.';end if;
 if not exists(select 1 from public.rr_market_requirement_lines_v9420 l where l.requirement_id=r.id and upper(trim(l.lot_no))=upper(trim(p_lot_no))) then raise exception 'Lot does not belong to this requirement.';end if;
 owner_ok:=upper(a.role_code) in('OWNER','SUPER_ADMIN','SUPERADMIN');
 select * into s from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode='TEST';
 if s.stock_id is not null then cost:=public.rr_rm_costing_test71(s.lot_no,'TEST');end if;
 route:='real-pi-specimen-v9514.html?requirement_id='||r.id::text||'&rate_recovery_lot='||pg_catalog.replace(trim(p_lot_no),' ','%20');
 if p_notify and not owner_ok then
  insert into public.rr_targeted_push_outbox_v708(event_key,recipient_worker_id,title,body,route_url,payload)
  select 'PI_RATE_RECOVERY:'||r.id::text||':'||upper(trim(p_lot_no)),w.worker_id,'Sale-rate approval required',coalesce(cy.display_no,'Collection')||' · Lot '||trim(p_lot_no)||' · PI blocked. Complete costing and approve sale rate.',route,
   jsonb_build_object('source','PI_RATE_RECOVERY_TEST71','requirement_id',r.id,'lot_no',trim(p_lot_no),'chat_id',cy.chat_id)
  from public.rr_user_profiles p join public.rr_worker_directory_unified_v1 w on w.linked_auth_user_id=p.auth_user_id
  where p.is_active and upper(p.role_code) in('OWNER','SUPER_ADMIN','SUPERADMIN') and w.is_active
  on conflict(event_key,recipient_worker_id) do nothing;
  get diagnostics recipients=row_count;
 end if;
 return jsonb_build_object('lot_no',trim(p_lot_no),'readymade',s.stock_id is not null,'can_approve',owner_ok,'costing_complete',coalesce((cost->>'costing_complete')::boolean,false),'suggested_rate',case when owner_ok then cost->'source_rate' else null end,'approved_rate',s.target_sale_rate,'costing',case when owner_ok then cost else null end,'request_status',case when p_notify and not owner_ok then 'REQUESTED' else 'NOT_REQUESTED' end,'new_notifications',recipients);
end $$;
revoke all on function public.rr_pi_rate_recovery_test71(uuid,text,boolean) from public,anon;
grant execute on function public.rr_pi_rate_recovery_test71(uuid,text,boolean) to authenticated;
