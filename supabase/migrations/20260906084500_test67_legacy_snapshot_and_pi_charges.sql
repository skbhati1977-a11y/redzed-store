-- TEST67: repair legacy pricing snapshots and persist the shared PI charge format.
alter table public.rr_market_partner_order_v67
  add column if not exists distributor_pi_value_pct numeric(8,3) not null default 0,
  add column if not exists distributor_pi_freight numeric(14,2) not null default 0,
  add column if not exists distributor_pi_other numeric(14,2) not null default 0,
  add column if not exists distributor_pi_tax_pct numeric(8,3) not null default 0;

update public.rr_market_partner_collection_line_v67 l
set margin_amount=c.default_margin_amount,
    distributor_sale_rate=l.base_rate+c.default_margin_amount,
    discount_amount=c.default_discount_amount,
    final_customer_rate=greatest(0,l.base_rate+c.default_margin_amount-c.default_discount_amount)
from public.rr_market_partner_collection_v67 pc
join public.rr_market_partner_customer_v67 c on c.id=pc.partner_customer_id
where l.collection_id=pc.id and c.data_mode='TEST'
  and l.margin_amount=0 and l.discount_amount=0;

update public.rr_market_partner_order_line_v67 l
set rate_enhancement=c.default_margin_amount,
    customer_discount=c.default_discount_amount,
    final_customer_rate=greatest(0,l.base_rate+c.default_margin_amount-c.default_discount_amount)
from public.rr_market_partner_order_v67 o
join public.rr_market_partner_customer_v67 c on c.id=o.partner_customer_id
where l.order_id=o.id and c.data_mode='TEST'
  and l.rate_enhancement=0 and l.customer_discount=0;

-- A collection/requirement is one commercial snapshot.  Individual lots may
-- never carry different margin/discount values inside that snapshot.
create or replace function public.rr_market_partner_uniform_collection_pricing_v67()
returns trigger language plpgsql set search_path=public as $$
begin
 if exists(
  select 1 from public.rr_market_partner_collection_line_v67 x
  where x.collection_id=new.collection_id and x.id<>new.id
   and (x.margin_amount is distinct from new.margin_amount
    or x.discount_amount is distinct from new.discount_amount)
 ) then raise exception 'One collection/update must use one margin and one discount for every lot.';end if;
 return new;
end $$;
drop trigger if exists rr_partner_uniform_collection_pricing_v67 on public.rr_market_partner_collection_line_v67;
create trigger rr_partner_uniform_collection_pricing_v67 before insert or update of margin_amount,discount_amount
on public.rr_market_partner_collection_line_v67 for each row execute function public.rr_market_partner_uniform_collection_pricing_v67();

create or replace function public.rr_market_partner_uniform_requirement_pricing_v67()
returns trigger language plpgsql set search_path=public as $$
begin
 if exists(
  select 1 from public.rr_market_partner_order_line_v67 x
  where x.order_id=new.order_id and x.id<>new.id
   and (x.rate_enhancement is distinct from new.rate_enhancement
    or x.customer_discount is distinct from new.customer_discount)
 ) then raise exception 'One requirement/update must use one margin and one discount for every lot.';end if;
 return new;
end $$;
drop trigger if exists rr_partner_uniform_requirement_pricing_v67 on public.rr_market_partner_order_line_v67;
create trigger rr_partner_uniform_requirement_pricing_v67 before insert or update of rate_enhancement,customer_discount
on public.rr_market_partner_order_line_v67 for each row execute function public.rr_market_partner_uniform_requirement_pricing_v67();

create or replace function public.rr_market_partner_customer_pi_charges_v67(
 p_session_token text,p_device_id text,p_order_id uuid,
 p_value_pct numeric default 0,p_freight numeric default 0,
 p_other numeric default 0,p_tax_pct numeric default 0
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_ctx jsonb;v_owner uuid;v_order public.rr_market_partner_order_v67%rowtype;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
 v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 if coalesce(p_value_pct,0)<-100 or coalesce(p_value_pct,0)>100 then raise exception 'Value Added/Less must be between -100 and 100.';end if;
 if coalesce(p_freight,0)<0 or coalesce(p_other,0)<0 or coalesce(p_tax_pct,0)<0 then raise exception 'Charges cannot be negative.';end if;
 update public.rr_market_partner_order_v67 set
  distributor_pi_value_pct=coalesce(p_value_pct,0),
  distributor_pi_freight=coalesce(p_freight,0),
  distributor_pi_other=coalesce(p_other,0),
  distributor_pi_tax_pct=coalesce(p_tax_pct,0),updated_at=now()
 where id=p_order_id and owner_customer_id=v_owner
 returning * into v_order;
 if v_order.id is null then raise exception 'Requirement unavailable.';end if;
 return jsonb_build_object('value_pct',v_order.distributor_pi_value_pct,
  'freight',v_order.distributor_pi_freight,'other',v_order.distributor_pi_other,
  'tax_pct',v_order.distributor_pi_tax_pct);
end $$;

create or replace function public.rr_market_partner_customer_pi_charges_get_v67(
 p_session_token text,p_device_id text,p_order_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_ctx jsonb;v_owner uuid;v_order public.rr_market_partner_order_v67%rowtype;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select * into v_order from public.rr_market_partner_order_v67 where id=p_order_id and owner_customer_id=v_owner;
 if v_order.id is null then raise exception 'Requirement unavailable.';end if;
 return jsonb_build_object('value_pct',v_order.distributor_pi_value_pct,
  'freight',v_order.distributor_pi_freight,'other',v_order.distributor_pi_other,
  'tax_pct',v_order.distributor_pi_tax_pct);
end $$;

revoke all on function public.rr_market_partner_customer_pi_charges_v67(text,text,uuid,numeric,numeric,numeric,numeric) from public;
revoke all on function public.rr_market_partner_customer_pi_charges_get_v67(text,text,uuid) from public;
grant execute on function public.rr_market_partner_customer_pi_charges_v67(text,text,uuid,numeric,numeric,numeric,numeric) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_pi_charges_get_v67(text,text,uuid) to anon,authenticated,service_role;

create or replace function public.rr_market_partner_customer_invoice_view_v67(p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_map public.rr_market_partner_collection_v67%rowtype;v_root uuid;
 v_order public.rr_market_partner_order_v67%rowtype;v_customer_ci public.rr_market_partner_customer_ci_v67%rowtype;
 v_charges jsonb;
begin
 select pc.* into v_map from public.rr_market_partner_collection_v67 pc
 join public.rr_market_share_v9420 s on s.id=pc.share_id
 where(s.token=p_token or s.short_code=upper(p_token))and s.data_mode='TEST'and s.status='ACTIVE'
 order by case when s.token=p_token then 0 else 1 end limit 1;
 if v_map.id is null then return null;end if;
 v_root:=coalesce(v_map.root_collection_id,v_map.id);
 select o.* into v_order from public.rr_market_partner_order_v67 o
 join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
 where pc.root_collection_id=v_root and o.status<>'SUPERSEDED'
 order by o.requirement_update_no desc,o.created_at desc limit 1;
 if v_order.id is null then return null;end if;
 v_charges:=jsonb_build_object('value_pct',v_order.distributor_pi_value_pct,
  'freight',v_order.distributor_pi_freight,'other',v_order.distributor_pi_other,
  'tax_pct',v_order.distributor_pi_tax_pct);
 select * into v_customer_ci from public.rr_market_partner_customer_ci_v67
 where source_order_id=v_order.id order by created_at desc limit 1;
 if v_customer_ci.id is not null then
  return jsonb_build_object('kind','CI','ref',v_customer_ci.customer_ci_ref,'status',v_customer_ci.status,
   'created_at',v_customer_ci.created_at,'requirement_display_no',v_order.requirement_display_no,
   'collection_display_no',v_map.collection_display_no,'charges',v_charges,
   'lines',(select coalesce(jsonb_agg(jsonb_build_object('id',cl.id,'lot_no',cl.lot_no,
    'article_name',cl.article_name,'category',ol.category,'size_text',ol.size_text,'image_url',ol.image_url,
    'quantity',cl.quantity,'rate',cl.customer_rate,'line_amount',cl.line_amount)order by cl.lot_no),'[]'::jsonb)
    from public.rr_market_partner_customer_ci_line_v67 cl left join public.rr_market_partner_order_line_v67 ol on ol.id=cl.source_order_line_id
    where cl.customer_ci_id=v_customer_ci.id));
 end if;
 if not v_order.distributor_pi_visible or v_order.distributor_pi_ref is null then return null;end if;
 return jsonb_build_object('kind','PI','ref',v_order.distributor_pi_ref,'status',v_order.distributor_pi_status,
  'note',v_order.distributor_pi_note,'pushed_at',v_order.distributor_pi_pushed_at,
  'requirement_display_no',v_order.requirement_display_no,'collection_display_no',v_map.collection_display_no,
  'charges',v_charges,'lines',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'lot_no',l.lot_no,
   'article_name',l.article_name,'category',l.category,'size_text',l.size_text,'image_url',l.image_url,
   'requested_qty',l.requested_qty,'proposed_qty',coalesce(l.distributor_pi_qty,l.requested_qty),
   'rate',l.final_customer_rate,'decision',l.distributor_pi_decision,'customer_qty',l.distributor_pi_customer_qty)
   order by l.lot_no),'[]'::jsonb)from public.rr_market_partner_order_line_v67 l where l.order_id=v_order.id));
end $$;
revoke all on function public.rr_market_partner_customer_invoice_view_v67(text) from public;
grant execute on function public.rr_market_partner_customer_invoice_view_v67(text) to anon,authenticated,service_role;
