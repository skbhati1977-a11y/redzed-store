-- TEST67 distributor collection bridge. Additive and TEST-only.

create table if not exists public.rr_market_partner_collection_v67 (
  id uuid primary key default gen_random_uuid(),
  owner_customer_id uuid not null references public.rr_customers(id),
  partner_customer_id uuid not null references public.rr_market_partner_customer_v67(id),
  share_id uuid not null unique references public.rr_market_share_v9420(id),
  requirement_id uuid references public.rr_market_requirements_v9420(id),
  order_id uuid references public.rr_market_partner_order_v67(id),
  status text not null default 'SENT' check(status in('SENT','REQUIREMENT_RECEIVED','CANCELLED')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.rr_market_partner_collection_v67 enable row level security;
revoke all on public.rr_market_partner_collection_v67 from public,anon,authenticated;
grant all on public.rr_market_partner_collection_v67 to service_role;

create or replace function public.rr_market_partner_cards_v67(
  p_session_token text,p_device_id text,p_search text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  perform public.rr_market_partner_context_v67(p_session_token,p_device_id);
  return coalesce((select jsonb_agg(to_jsonb(x)) from public.rr_web_window_cards_v9329(
    p_search,null,null,'TEST',150,0)x),'[]'::jsonb);
end $$;

create or replace function public.rr_market_partner_collection_create_v67(
  p_session_token text,p_device_id text,p_partner_customer_id uuid,p_lots text[]
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_share uuid;v_token text;v_code text;v_name text;v_tries int:=0;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  if not (v_ctx->>'send_collection_enabled')::boolean then raise exception 'Collection sending is disabled.';end if;
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  select private_name into v_name from public.rr_market_partner_customer_v67
   where id=p_partner_customer_id and owner_customer_id=v_owner and status='ACTIVE';
  if v_name is null then raise exception 'Private customer not found.';end if;
  if coalesce(array_length(p_lots,1),0)=0 then raise exception 'Select at least one lot.';end if;
  loop
    v_code:=upper(substr(md5(random()::text||clock_timestamp()::text),1,10));
    begin
      insert into public.rr_market_share_v9420(customer_id,customer_name,data_mode,status,short_code)
      values(null,v_name,'TEST','ACTIVE',v_code) returning id,token into v_share,v_token;exit;
    exception when unique_violation then v_tries:=v_tries+1;if v_tries>8 then raise;end if;end;
  end loop;
  insert into public.rr_market_share_lots_v9420(share_id,lot_no,sort_no)
   select v_share,trim(x),ord from unnest(p_lots)with ordinality u(x,ord)
   where trim(x)<>'' on conflict do nothing;
  if not exists(select 1 from public.rr_market_share_lots_v9420 where share_id=v_share)then
    raise exception 'Selected TEST lots are unavailable.';
  end if;
  insert into public.rr_market_partner_collection_v67(owner_customer_id,partner_customer_id,share_id)
   values(v_owner,p_partner_customer_id,v_share);
  return jsonb_build_object('share_id',v_share,'token',v_token,'short_code',v_code,
   'lot_count',(select count(*) from public.rr_market_share_lots_v9420 where share_id=v_share));
end $$;

create or replace function public.rr_market_partner_submit_requirement_v67(
 p_token text,p_customer_name text,p_mobile text,p_message text,p_lines jsonb
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_map public.rr_market_partner_collection_v67%rowtype;v_result jsonb;v_req uuid;
 v_seq bigint;v_prefix text;v_ref text;v_order uuid;v_line record;v_card record;
begin
 select pc.* into v_map from public.rr_market_partner_collection_v67 pc
 join public.rr_market_share_v9420 s on s.id=pc.share_id
 where (s.token=p_token or s.short_code=upper(p_token)) and s.data_mode='TEST' and s.status='ACTIVE';
 v_result:=public.rr_market_submit_requirement_v9508(p_token,p_customer_name,p_mobile,p_message,p_lines,null);
 if v_map.id is null then return v_result;end if;
 v_req:=(v_result->>'requirement_id')::uuid;
 select prefix,current_no+1 into v_prefix,v_seq from public.rr_market_owner_sequence_v67
  where owner_key='CUSTOMER:'||v_map.owner_customer_id::text and data_mode='TEST' for update;
 if v_prefix is null then raise exception 'Distributor prefix is not configured.';end if;
 update public.rr_market_owner_sequence_v67 set current_no=v_seq,updated_at=now()
  where owner_key='CUSTOMER:'||v_map.owner_customer_id::text and data_mode='TEST';
 v_ref:=v_prefix||'-'||lpad(v_seq::text,3,'0');
 insert into public.rr_market_partner_order_v67(owner_customer_id,partner_customer_id,sequence_no,order_ref,status,linked_requirement_id)
 values(v_map.owner_customer_id,v_map.partner_customer_id,v_seq,v_ref,'READY',v_req)returning id into v_order;
 for v_line in select l.* from public.rr_market_requirement_lines_v9420 l where l.requirement_id=v_req loop
   select * into v_card from public.rr_web_window_cards_v9329(v_line.lot_no,null,null,'TEST',10,0)where lot_no=v_line.lot_no limit 1;
   insert into public.rr_market_partner_order_line_v67(order_id,lot_no,article_name,image_url,requested_qty,base_rate,rate_enhancement)
   values(v_order,v_line.lot_no,coalesce(v_card.full_item_name,v_card.short_item_name),v_card.primary_image_url,
    v_line.accepted_qty,coalesce(v_card.sale_rate,0),0);
 end loop;
 update public.rr_market_partner_collection_v67 set requirement_id=v_req,order_id=v_order,status='REQUIREMENT_RECEIVED',updated_at=now()where id=v_map.id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,actor_kind,payload)
 values(v_map.owner_customer_id,v_order,'COLLECTION_REQUIREMENT_RECEIVED','SYSTEM',jsonb_build_object('order_ref',v_ref,'share_id',v_map.share_id));
 return v_result||jsonb_build_object('order_id',v_order,'order_ref',v_ref,'requirement_no',v_ref);
end $$;

revoke all on function public.rr_market_partner_cards_v67(text,text,text)from public;
revoke all on function public.rr_market_partner_collection_create_v67(text,text,uuid,text[])from public;
revoke all on function public.rr_market_partner_submit_requirement_v67(text,text,text,text,jsonb)from public;
grant execute on function public.rr_market_partner_cards_v67(text,text,text)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_collection_create_v67(text,text,uuid,text[])to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_submit_requirement_v67(text,text,text,text,jsonb)to anon,authenticated,service_role;

-- Existing collection page calls this canonical RPC. The bridge preserves the
-- normal result and only adds a distributor order when the share is mapped.
create or replace function public.rr_market_submit_requirement_v9420(
 p_token text,p_customer_name text,p_mobile text,p_message text,p_lines jsonb
)returns jsonb language sql security definer set search_path=public as $$
 select public.rr_market_partner_submit_requirement_v67(
  p_token,p_customer_name,p_mobile,p_message,p_lines
 );
$$;
revoke all on function public.rr_market_submit_requirement_v9420(text,text,text,text,jsonb)from public;
grant execute on function public.rr_market_submit_requirement_v9420(text,text,text,text,jsonb)to anon,authenticated,service_role;
