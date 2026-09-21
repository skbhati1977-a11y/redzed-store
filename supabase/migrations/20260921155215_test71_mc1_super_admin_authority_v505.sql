-- TEST71 V505: align MC1 with the established Super Admin financial authority.
-- This only adds the omitted canonical role alias; worker and staff access stays unchanged.

create or replace function public.rr_role_can_view_financials_v1()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select lower(coalesce(public.rr_current_role(),'')) in(
    'owner','super_admin','admin','account','accounts'
  );
$$;

create or replace function public.rr_product_require_admin_v1()
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_role text;
begin
  if auth.uid() is null then return; end if;
  v_role:=lower(coalesce(public.rr_current_role(),''));
  if v_role not in('owner','super_admin','admin') then
    raise exception 'Owner/Admin permission is required' using errcode='42501';
  end if;
end;
$$;

create or replace function public.rr_mc1_real_chat_queue_v504(p_status text,p_search text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_status text:=upper(trim(coalesce(p_status,'OPEN')));
  v_search text:=lower(trim(coalesce(p_search,'')));
  v_financial boolean:=public.rr_role_can_view_financials_v1();
  v_role text:=lower(coalesce(public.rr_current_role(),''));
  v_cards jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if v_status not in('OPEN','WORKING','CLOSE') then raise exception 'Invalid MC1 view.'; end if;

  if v_status='OPEN' and v_financial then
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind','PURCHASE_IN','purchase_id',p.id,'fabric_id',p.fabric_id,'fabric_name',coalesce(p.fabric_name,f.fabric_name),
      'supplier_ledger_id',p.supplier_ledger_id,'vendor_name',p.vendor_name,'bill_no',p.bill_no,'bill_date',p.bill_date,
      'qty',p.bill_qty,'rate',p.bill_rate,'value',p.bill_value,'status',coalesce(p.operation_status,'ACTIVE'),
      'posted_at',p.posted_at,'purchase_account','Matching Cloth Purchase'
    ) order by p.posted_at desc),'[]'::jsonb) into v_cards
    from public.rr_mc1_purchases p left join public.rr_mc1_fabrics f on f.id=p.fabric_id
    where v_search='' or lower(concat_ws(' ',p.fabric_name,f.fabric_name,p.vendor_name,p.bill_no)) like '%'||v_search||'%';
  elsif v_status='WORKING' then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.posted_at desc),'[]'::jsonb) into v_cards from(
      select 'LOT_CONSUMPTION'::text kind,m.lot_no,m.fabric_id,max(f.fabric_name) fabric_name,
        round(sum(m.qty),3) qty,
        case when v_financial then round(sum(m.total_cost)/nullif(sum(m.qty),0),4) else null end rate,
        case when v_financial then round(sum(m.total_cost),2) else null end value,
        'CONSUMPTION_RECORDED'::text status,max(m.posted_at) posted_at,count(*) movement_count,
        'MC1'::text source
      from public.rr_mc1_lot_matchings_v2 m join public.rr_mc1_fabrics f on f.id=m.fabric_id
      where m.status='POSTED' and (v_search='' or lower(concat_ws(' ',m.lot_no,f.fabric_name)) like '%'||v_search||'%')
      group by m.lot_no,m.fabric_id
    )x;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind','CLOSING_STOCK','fabric_id',f.fabric_id,'fabric_name',f.fabric_name,
      'total_purchase_in',f.total_purchase_qty,'total_consumption_out',f.total_consumption_qty,
      'gr_adjustment',coalesce(f.total_exchange_qty,0)-coalesce(f.total_gr_qty,0),
      'total_gr_qty',f.total_gr_qty,'total_exchange_qty',f.total_exchange_qty,
      'closing_qty',f.current_qty,'available_qty',f.available_qty,
      'avg_rate',case when v_financial then f.avg_cost else null end,
      'closing_value',case when v_financial then f.current_value else null end,
      'updated_at',f.updated_at
    ) order by lower(f.fabric_name)),'[]'::jsonb) into v_cards
    from public.rr_mc1_fabric_stock_v2 f
    where f.is_active and (v_search='' or lower(f.fabric_name) like '%'||v_search||'%');
  end if;

  return jsonb_build_object(
    'ok',true,'version','V505_MC1_REAL_CHAT','status',v_status,'cards',v_cards,
    'can_view_financials',v_financial,'can_operate',v_role in('owner','super_admin','admin'),
    'purchase_restricted',v_status='OPEN' and not v_financial,
    'headings',jsonb_build_object('OPEN','Purchase / Stock IN','WORKING','Lot Consumption','CLOSE','Closing Stock')
  );
end;
$$;

revoke all on function public.rr_mc1_real_chat_queue_v504(text,text) from public,anon;
grant execute on function public.rr_mc1_real_chat_queue_v504(text,text) to authenticated,service_role;
