-- TEST67: cancellation cascade and downstream customer CI conversion.

create table if not exists public.rr_market_partner_customer_ci_v67 (
  id uuid primary key default gen_random_uuid(),
  owner_customer_id uuid not null references public.rr_customers(id),
  partner_customer_id uuid not null references public.rr_market_partner_customer_v67(id),
  source_order_id uuid not null references public.rr_market_partner_order_v67(id),
  source_upstream_ci_ref text not null,
  customer_ci_ref text not null,
  status text not null default 'FINAL' check(status in ('FINAL','CANCELLED')),
  data_mode text not null default 'TEST' check(data_mode='TEST'),
  created_at timestamptz not null default now(),
  unique(source_order_id), unique(owner_customer_id,customer_ci_ref,data_mode)
);

create table if not exists public.rr_market_partner_customer_ci_line_v67 (
  id uuid primary key default gen_random_uuid(),
  customer_ci_id uuid not null references public.rr_market_partner_customer_ci_v67(id) on delete cascade,
  source_order_line_id uuid not null references public.rr_market_partner_order_line_v67(id),
  lot_no text not null,
  article_name text,
  quantity integer not null check(quantity>0),
  customer_rate numeric(14,2) not null check(customer_rate>=0),
  line_amount numeric(16,2) generated always as (quantity*customer_rate) stored,
  unique(customer_ci_id,source_order_line_id)
);

alter table public.rr_market_partner_customer_ci_v67 enable row level security;
alter table public.rr_market_partner_customer_ci_line_v67 enable row level security;
revoke all on public.rr_market_partner_customer_ci_v67 from public,anon,authenticated;
revoke all on public.rr_market_partner_customer_ci_line_v67 from public,anon,authenticated;
grant all on public.rr_market_partner_customer_ci_v67 to service_role;
grant all on public.rr_market_partner_customer_ci_line_v67 to service_role;

create or replace function public.rr_market_partner_cancel_order_v67(
 p_session_token text,p_device_id text,p_order_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_owner uuid; v_batch uuid; v_status text;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
 v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select status into v_status from public.rr_market_partner_order_v67
  where id=p_order_id and owner_customer_id=v_owner for update;
 if v_status is null then raise exception 'Order not found.'; end if;
 if v_status not in ('READY','BATCHED','PI_PROPOSED') then raise exception 'Order cannot be cancelled at this stage.'; end if;
 select batch_id into v_batch from public.rr_market_partner_batch_member_v67 where order_id=p_order_id;
 update public.rr_market_partner_order_line_v67 set proposed_qty=coalesce(proposed_qty,0),confirmed_qty=0,
  confirmation_status='CANCELLED',updated_at=now() where order_id=p_order_id;
 update public.rr_market_partner_order_v67 set status='CANCELLED',confirmation_note=nullif(trim(p_reason),''),updated_at=now()
  where id=p_order_id;
 if v_batch is not null then
  update public.rr_market_partner_batch_v67 b set status=case
   when not exists(select 1 from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id where m.batch_id=b.id and o.status<>'CANCELLED') then 'CANCELLED'
   when b.status in ('CONFIRMED','PARTIAL_CONFIRMED','WAITING_CONFIRMATION','PI_PROPOSED') then 'PARTIAL_CONFIRMED'
   else b.status end,updated_at=now() where id=v_batch;
 end if;
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,order_id,event_type,note,actor_kind)
  values(v_owner,v_batch,p_order_id,'ORDER_CANCELLED',nullif(trim(p_reason),''),'DISTRIBUTOR');
 return jsonb_build_object('ok',true,'order_id',p_order_id,'status','CANCELLED','batch_id',v_batch);
end $$;

create or replace function public.rr_market_staff_cancel_batch_v67(p_batch_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_owner uuid;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select owner_customer_id into v_owner from public.rr_market_partner_batch_v67
  where id=p_batch_id and data_mode='TEST' and status not in ('CI_FINAL','CLOSED','CANCELLED') for update;
 if v_owner is null then raise exception 'Batch cannot be cancelled at this stage.'; end if;
 update public.rr_market_partner_order_line_v67 l set confirmed_qty=0,confirmation_status='CANCELLED',updated_at=now()
  where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=l.order_id);
 update public.rr_market_partner_order_v67 o set status='CANCELLED',confirmation_note=nullif(trim(p_reason),''),updated_at=now()
  where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=o.id);
 update public.rr_market_partner_batch_v67 set status='CANCELLED',updated_at=now() where id=p_batch_id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,note,actor_kind,actor_id)
  values(v_owner,p_batch_id,'BATCH_CANCELLED',nullif(trim(p_reason),''),'STAFF',auth.uid());
 return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

create or replace function public.rr_market_partner_convert_customer_ci_v67(
 p_session_token text,p_device_id text,p_order_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_owner uuid; v_order public.rr_market_partner_order_v67%rowtype;
 v_prefix text; v_no bigint; v_ci_ref text; v_ci uuid;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
 if not (v_ctx->>'ci_convert_enabled')::boolean then raise exception 'Customer CI conversion is disabled.'; end if;
 v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select * into v_order from public.rr_market_partner_order_v67
  where id=p_order_id and owner_customer_id=v_owner and status='CI_FINAL' for update;
 if v_order.id is null or v_order.ci_ref is null then raise exception 'Final upstream CI allocation not found.'; end if;
 if exists(select 1 from public.rr_market_partner_customer_ci_v67 where source_order_id=p_order_id) then
  return (select jsonb_build_object('customer_ci_id',id,'customer_ci_ref',customer_ci_ref,
   'source_upstream_ci_ref',source_upstream_ci_ref,'status',status) from public.rr_market_partner_customer_ci_v67 where source_order_id=p_order_id);
 end if;
 select prefix into v_prefix from public.rr_market_owner_sequence_v67
  where owner_key='CUSTOMER:'||v_owner::text and data_mode='TEST';
 select coalesce(max((regexp_match(customer_ci_ref,'([0-9]+)$'))[1]::bigint),0)+1 into v_no
  from public.rr_market_partner_customer_ci_v67 where owner_customer_id=v_owner;
 v_ci_ref:=v_prefix||'-CI-'||lpad(v_no::text,4,'0');
 insert into public.rr_market_partner_customer_ci_v67(owner_customer_id,partner_customer_id,source_order_id,
  source_upstream_ci_ref,customer_ci_ref) values(v_owner,v_order.partner_customer_id,p_order_id,v_order.ci_ref,v_ci_ref)
  returning id into v_ci;
 insert into public.rr_market_partner_customer_ci_line_v67(customer_ci_id,source_order_line_id,lot_no,article_name,quantity,customer_rate)
  select v_ci,id,lot_no,article_name,confirmed_qty,customer_rate from public.rr_market_partner_order_line_v67
   where order_id=p_order_id and confirmation_status in ('CONFIRMED','CHANGE_REQUESTED') and confirmed_qty>0;
 if not found then raise exception 'No confirmed allocation is available for customer CI.'; end if;
 update public.rr_market_partner_order_v67 set status='CLOSED',updated_at=now() where id=p_order_id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,actor_kind,payload)
  values(v_owner,p_order_id,'CUSTOMER_CI_CREATED','DISTRIBUTOR',jsonb_build_object('customer_ci_ref',v_ci_ref,'upstream_ci_ref',v_order.ci_ref));
 return jsonb_build_object('customer_ci_id',v_ci,'customer_ci_ref',v_ci_ref,
  'source_upstream_ci_ref',v_order.ci_ref,'status','FINAL');
end $$;

create or replace function public.rr_market_partner_customer_ci_detail_v67(
 p_session_token text,p_device_id text,p_customer_ci_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_owner uuid;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id); v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 return (select jsonb_build_object('id',ci.id,'customer_ci_ref',ci.customer_ci_ref,
  'source_upstream_ci_ref',ci.source_upstream_ci_ref,'status',ci.status,'created_at',ci.created_at,
  'customer',jsonb_build_object('customer_ref',c.customer_ref,'name',c.private_name,'mobile',c.private_mobile),
  'lines',(select jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'article_name',l.article_name,
    'quantity',l.quantity,'customer_rate',l.customer_rate,'line_amount',l.line_amount) order by l.lot_no)
    from public.rr_market_partner_customer_ci_line_v67 l where l.customer_ci_id=ci.id),
  'total_amount',(select coalesce(sum(l.line_amount),0) from public.rr_market_partner_customer_ci_line_v67 l where l.customer_ci_id=ci.id))
  from public.rr_market_partner_customer_ci_v67 ci join public.rr_market_partner_customer_v67 c on c.id=ci.partner_customer_id
  where ci.id=p_customer_ci_id and ci.owner_customer_id=v_owner);
end $$;

revoke all on function public.rr_market_partner_cancel_order_v67(text,text,uuid,text) from public;
revoke all on function public.rr_market_staff_cancel_batch_v67(uuid,text) from public,anon;
revoke all on function public.rr_market_partner_convert_customer_ci_v67(text,text,uuid) from public;
revoke all on function public.rr_market_partner_customer_ci_detail_v67(text,text,uuid) from public;
grant execute on function public.rr_market_partner_cancel_order_v67(text,text,uuid,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_convert_customer_ci_v67(text,text,uuid) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_ci_detail_v67(text,text,uuid) to anon,authenticated,service_role;
grant execute on function public.rr_market_staff_cancel_batch_v67(uuid,text) to authenticated,service_role;
