-- TEST71 Final Rate role-targeted web-push trigger parity.
create or replace function public.rr_pack_rate_web_push_v714() returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare p record;role text;route text;ttl text;msg text;wid uuid;
begin
 if new.status not in('REQUESTED','SUGGESTED') then return new;end if;
 for p in select id,lower(role_code) role_code from public.rr_user_profiles where is_active and lower(role_code) in('owner','super_admin','admin','sales') loop
  wid:=public.rr_push_worker_id_v712(p.id);if wid is null then continue;end if;role:=p.role_code;
  if role='sales' then route:=public.rr_real_chat_route_v713('SALES',new.lot_no,'SALES_RATE_SUGGESTION');ttl:='Final Rate Suggestion · Lot '||new.lot_no;msg:='Mapped rate ₹'||new.source_rate||' · Sales suggestion required.';
  elsif role='admin' then route:=public.rr_real_chat_route_v713('PACKING',new.lot_no,'ADMIN_RATE_SUGGESTION');ttl:='Admin Rate Suggestion · Lot '||new.lot_no;msg:='Mapped rate ₹'||new.source_rate||' · Fill Admin suggestion.';
  else route:=public.rr_real_chat_route_v713('PACKING',new.lot_no,'FINAL_RATE_APPROVAL');ttl:='Final Rate Approval · Lot '||new.lot_no;msg:='Mapped rate ₹'||new.source_rate||' · Sales '||coalesce('₹'||new.sales_suggested_rate::text,'pending')||' · Admin '||coalesce('₹'||new.admin_suggested_rate::text,'pending')||'.';end if;
  insert into public.rr_targeted_push_outbox_v708(event_key,recipient_worker_id,title,body,route_url,payload) values('FINAL_RATE_V714:'||new.id::text||':'||new.status||':'||role,wid,ttl,msg,route,jsonb_build_object('type','FINAL_RATE','approval_id',new.id,'lot_no',new.lot_no,'role',role,'source_rate',new.source_rate,'sales_suggested_rate',new.sales_suggested_rate,'admin_suggested_rate',new.admin_suggested_rate)) on conflict(event_key,recipient_worker_id) do nothing;
 end loop;return new;
end $function$;
drop trigger if exists rr_pack_rate_web_push_v708 on public.rr_pack_rate_approval_v9340;
drop trigger if exists rr_pack_rate_web_push_v714 on public.rr_pack_rate_approval_v9340;
create trigger rr_pack_rate_web_push_v714 after insert or update of status,source_rate,sales_suggested_rate,admin_suggested_rate on public.rr_pack_rate_approval_v9340 for each row execute function public.rr_pack_rate_web_push_v714();
