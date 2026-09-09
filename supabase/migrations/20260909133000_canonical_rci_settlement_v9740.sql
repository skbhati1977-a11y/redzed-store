-- Canonical RCI foundation. Existing PI/CI and legacy return records remain untouched.
begin;

create table if not exists public.rr_rci_category_lots_v9740(
  category_code text primary key,
  category_name text not null,
  anonymous_lot_no text not null unique,
  alter_lot_no text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.rr_rci_category_lots_v9740(category_code,category_name,anonymous_lot_no,alter_lot_no)
values
 ('drop-shoulder','Drop Shoulder / Down Shoulder','DS-001','ALT-DS-001'),
 ('flat-polo','Flat Polo Collar','FP-001','ALT-FP-001'),
 ('hoodies','Hoodies','HD-001','ALT-HD-001'),
 ('shorts-bermuda','Nikkar / Shorts / Bermuda','NSB-001','ALT-NSB-001'),
 ('lower-pajama','Pajama / Lower','PL-001','ALT-PL-001'),
 ('pre-winter','Pre Winter','PW-001','ALT-PW-001'),
 ('crew-neck','R.NK / Crew Neck','RN-001','ALT-RN-001'),
 ('self-collar','Self Collar','SC-001','ALT-SC-001')
on conflict(category_code) do update set
 category_name=excluded.category_name,
 anonymous_lot_no=excluded.anonymous_lot_no,
 alter_lot_no=excluded.alter_lot_no,
 updated_at=now();

create table if not exists public.rr_rci_sequence_v9740(
  data_mode text primary key check(data_mode in('TEST','REAL')),
  last_number bigint not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.rr_rci_v9740(
  id uuid primary key default gen_random_uuid(),
  rci_no text,
  flow_type text not null check(flow_type in('COMBINED','STANDALONE')),
  linked_ci_id uuid references public.rr_fg_pi_v787(id) on delete restrict,
  settlement_no text,
  buyer_id uuid not null references public.rr_buyers_v787(id) on delete restrict,
  buyer_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'DRAFT' check(status in('DRAFT','POSTED','REVERSED')),
  total_qty integer not null default 0 check(total_qty>=0),
  total_amount numeric(16,2) not null default 0 check(total_amount>=0),
  reason text,
  data_mode text not null check(data_mode in('TEST','REAL')),
  idempotency_key text not null,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  posted_by uuid,
  posted_at timestamptz,
  reversed_by uuid,
  reversed_at timestamptz,
  reversal_reason text,
  unique(data_mode,rci_no),
  unique(data_mode,idempotency_key)
);

create table if not exists public.rr_rci_lines_v9740(
  id uuid primary key default gen_random_uuid(),
  rci_id uuid not null references public.rr_rci_v9740(id) on delete restrict,
  serial_no integer not null check(serial_no>0),
  return_type text not null check(return_type in('KNOWN','ANONYMOUS','ALTER')),
  source_ci_id uuid references public.rr_fg_pi_v787(id) on delete restrict,
  source_ci_line_id uuid references public.rr_fg_pi_lines_v787(id) on delete restrict,
  original_lot_no text,
  stock_lot_no text not null,
  category_code text,
  category_name text not null,
  size_text text,
  image_url text,
  total_sold_qty integer,
  previous_rci_qty integer,
  returnable_qty integer,
  rci_qty integer not null check(rci_qty>0),
  rate numeric(14,2) not null check(rate>=0),
  amount numeric(16,2) not null check(amount>=0),
  stock_type text not null check(stock_type in('REGULAR','ASST','ALTER_DAMAGE','TRADED')),
  location_code text not null,
  valuation_source text not null,
  rate_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(rci_id,serial_no)
);

create index if not exists rr_rci_buyer_status_v9740
  on public.rr_rci_v9740(data_mode,buyer_id,status,created_at desc);
create index if not exists rr_rci_linked_ci_v9740
  on public.rr_rci_v9740(linked_ci_id,status) where linked_ci_id is not null;
create index if not exists rr_rci_lines_source_v9740
  on public.rr_rci_lines_v9740(source_ci_line_id) where source_ci_line_id is not null;
create index if not exists rr_rci_lines_stock_v9740
  on public.rr_rci_lines_v9740(stock_lot_no,stock_type);

alter table public.rr_rci_category_lots_v9740 enable row level security;
alter table public.rr_rci_sequence_v9740 enable row level security;
alter table public.rr_rci_v9740 enable row level security;
alter table public.rr_rci_lines_v9740 enable row level security;

revoke all on public.rr_rci_category_lots_v9740,public.rr_rci_sequence_v9740,
 public.rr_rci_v9740,public.rr_rci_lines_v9740 from public,anon,authenticated;

create or replace function public.rr_rci_party_average_v9740(p_buyer_id uuid,p_data_mode text default 'TEST')
returns numeric
language sql stable security definer set search_path='public'
as $function$
  select round(coalesce(sum(p.grand_total),0)/nullif(sum(x.qty),0),2)
  from public.rr_fg_pi_v787 p
  join lateral(
    select sum(l.qty)::numeric qty from public.rr_fg_pi_lines_v787 l where l.pi_id=p.id
  ) x on true
  where p.buyer_id=p_buyer_id and p.status='CI_FINAL'
    and p.data_mode=upper(coalesce(p_data_mode,'TEST'))
$function$;

create or replace function public.rr_rci_context_v9740(p_pi_id uuid)
returns jsonb
language plpgsql security definer set search_path='public'
as $function$
declare p public.rr_fg_pi_v787%rowtype; v_lines jsonb; v_categories jsonb; v_avg numeric;
begin
  perform public.rr_fg_assert_user_v787();
  select * into p from public.rr_fg_pi_v787 where id=p_pi_id;
  if p.id is null or p.buyer_id is null then raise exception 'Canonical CI buyer mapping required.'; end if;
  v_avg:=public.rr_rci_party_average_v9740(p.buyer_id,p.data_mode);
  select coalesce(jsonb_agg(jsonb_build_object(
    'source_ci_id',ci.id,'source_ci_line_id',l.id,'ci_no',ci.cpi_no,
    'lot_no',l.lot_no,'category',l.short_item_name,'size_text','',
    'image_url',coalesce(public.rr_universal_lot_image_v9545(l.lot_no,ci.data_mode)->>'image',''),
    'total_sold_qty',l.qty,'previous_rci_qty',coalesce(l.returned_qty,0),
    'returnable_qty',greatest(l.qty-coalesce(l.returned_qty,0),0),
    'rate',l.final_rate,'stock_type',l.stock_type
  ) order by ci.finalized_at desc,l.id),'[]'::jsonb) into v_lines
  from public.rr_fg_pi_v787 ci join public.rr_fg_pi_lines_v787 l on l.pi_id=ci.id
  where ci.buyer_id=p.buyer_id and ci.data_mode=p.data_mode and ci.status='CI_FINAL'
    and l.qty>coalesce(l.returned_qty,0);
  select coalesce(jsonb_agg(to_jsonb(c) order by c.category_name),'[]'::jsonb)
    into v_categories from public.rr_rci_category_lots_v9740 c where c.is_active;
  return jsonb_build_object('pi_id',p.id,'buyer_id',p.buyer_id,'buyer_snapshot',p.buyer_snapshot,
    'data_mode',p.data_mode,'status',p.status,'ci_no',p.cpi_no,'party_average_rate',v_avg,
    'returnable_lines',v_lines,'categories',v_categories);
end
$function$;

create or replace function public.rr_rci_save_draft_v9740(
  p_rci_id uuid,p_linked_ci_id uuid,p_buyer_id uuid,p_flow_type text,
  p_lines jsonb,p_reason text,p_idempotency_key text,p_data_mode text default 'TEST'
) returns jsonb
language plpgsql security definer set search_path='public'
as $function$
declare v_mode text:=upper(coalesce(p_data_mode,'TEST'));v_flow text:=upper(coalesce(p_flow_type,'STANDALONE'));
 v_id uuid;v_buyer uuid:=p_buyer_id;v_snapshot jsonb:='{}';j jsonb;i int:=0;v_type text;v_qty int;
 v_src record;v_cat public.rr_rci_category_lots_v9740%rowtype;v_rate numeric;v_avg numeric;
 v_total_qty int:=0;v_total numeric:=0;v_stock_lot text;v_stock_type text;v_location text;
begin
  perform public.rr_fg_assert_user_v787();
  if v_flow not in('COMBINED','STANDALONE') then raise exception 'Valid RCI flow required.'; end if;
  if jsonb_array_length(coalesce(p_lines,'[]'::jsonb))=0 then raise exception 'At least one RCI row required.'; end if;
  if p_linked_ci_id is not null then
    select buyer_id,buyer_snapshot,data_mode into v_buyer,v_snapshot,v_mode
      from public.rr_fg_pi_v787 where id=p_linked_ci_id;
  else
    select to_jsonb(b) into v_snapshot from public.rr_buyers_v787 b where b.id=v_buyer;
  end if;
  if v_buyer is null then raise exception 'Canonical RCI party required.'; end if;
  if p_rci_id is null then
    insert into public.rr_rci_v9740(flow_type,linked_ci_id,buyer_id,buyer_snapshot,reason,data_mode,idempotency_key)
    values(v_flow,p_linked_ci_id,v_buyer,coalesce(v_snapshot,'{}'),p_reason,v_mode,p_idempotency_key)
    on conflict(data_mode,idempotency_key) do update set reason=excluded.reason
    returning id into v_id;
  else
    select id into v_id from public.rr_rci_v9740 where id=p_rci_id and status='DRAFT' for update;
    if v_id is null then raise exception 'Editable RCI draft not found.'; end if;
    update public.rr_rci_v9740 set reason=p_reason where id=v_id;
    delete from public.rr_rci_lines_v9740 where rci_id=v_id;
  end if;
  v_avg:=public.rr_rci_party_average_v9740(v_buyer,v_mode);
  for j in select value from jsonb_array_elements(p_lines) loop
    i:=i+1;v_type:=upper(coalesce(j->>'return_type',''));v_qty:=coalesce((j->>'rci_qty')::int,0);
    if v_type not in('KNOWN','ANONYMOUS','ALTER') or v_qty<=0 then raise exception 'Invalid RCI row %.',i; end if;
    if v_type='KNOWN' then
      select l.*,p.id ci_id,p.cpi_no,p.buyer_id into v_src
      from public.rr_fg_pi_lines_v787 l join public.rr_fg_pi_v787 p on p.id=l.pi_id
      where l.id=(j->>'source_ci_line_id')::uuid and p.status='CI_FINAL' and p.data_mode=v_mode for update of l;
      if v_src.id is null or v_src.buyer_id<>v_buyer then raise exception 'RCI source CI does not belong to selected party.'; end if;
      if v_qty>v_src.qty-coalesce(v_src.returned_qty,0) then raise exception '% return exceeds available quantity.',v_src.lot_no; end if;
      v_rate:=v_src.final_rate;v_stock_lot:=v_src.lot_no;v_stock_type:=v_src.stock_type;v_location:='ORIGINAL_LOT';
      insert into public.rr_rci_lines_v9740(rci_id,serial_no,return_type,source_ci_id,source_ci_line_id,
        original_lot_no,stock_lot_no,category_name,size_text,image_url,total_sold_qty,previous_rci_qty,
        returnable_qty,rci_qty,rate,amount,stock_type,location_code,valuation_source,rate_snapshot)
      values(v_id,i,v_type,v_src.ci_id,v_src.id,v_src.lot_no,v_stock_lot,v_src.short_item_name,
        coalesce(j->>'size_text',''),coalesce(j->>'image_url',''),v_src.qty,coalesce(v_src.returned_qty,0),
        v_src.qty-coalesce(v_src.returned_qty,0),v_qty,v_rate,v_qty*v_rate,v_stock_type,v_location,
        'SOURCE_CI_LINE',jsonb_build_object('source_ci_no',v_src.cpi_no,'source_ci_line_id',v_src.id));
    else
      select * into v_cat from public.rr_rci_category_lots_v9740
       where category_code=j->>'category_code' and is_active;
      if v_cat.category_code is null then raise exception 'Canonical RCI category required.'; end if;
      if v_avg is null then raise exception 'Party finalized CI average unavailable.'; end if;
      v_rate:=v_avg;
      if v_type='ANONYMOUS' then v_stock_lot:=v_cat.anonymous_lot_no;v_stock_type:='ASST';v_location:='ANONYMOUS';
      else v_stock_lot:=v_cat.alter_lot_no;v_stock_type:='ALTER_DAMAGE';v_location:='ALTER'; end if;
      insert into public.rr_rci_lines_v9740(rci_id,serial_no,return_type,stock_lot_no,category_code,
        category_name,size_text,image_url,rci_qty,rate,amount,stock_type,location_code,valuation_source,rate_snapshot)
      values(v_id,i,v_type,v_stock_lot,v_cat.category_code,v_cat.category_name,coalesce(j->>'size_text','MIXED'),
        coalesce(j->>'image_url',''),v_qty,v_rate,v_qty*v_rate,v_stock_type,v_location,'PARTY_ALL_TIME_AVERAGE',
        jsonb_build_object('buyer_id',v_buyer,'frozen_average_rate',v_avg));
    end if;
    v_total_qty:=v_total_qty+v_qty;v_total:=v_total+v_qty*v_rate;
  end loop;
  update public.rr_rci_v9740 set total_qty=v_total_qty,total_amount=round(v_total,2) where id=v_id;
  return jsonb_build_object('rci_id',v_id,'status','DRAFT','total_qty',v_total_qty,'total_amount',round(v_total,2));
end
$function$;

create or replace function public.rr_rci_finalize_v9740(p_rci_id uuid)
returns jsonb
language plpgsql security definer set search_path='public'
as $function$
declare h public.rr_rci_v9740%rowtype;l record;v_no text;v_n bigint;v_prefix text;
begin
  select * into h from public.rr_rci_v9740 where id=p_rci_id for update;
  if h.id is null then raise exception 'RCI not found.'; end if;
  if h.status='POSTED' then return jsonb_build_object('rci_id',h.id,'rci_no',h.rci_no,'status',h.status); end if;
  if h.status<>'DRAFT' then raise exception 'RCI draft required.'; end if;
  if h.linked_ci_id is not null and not exists(select 1 from public.rr_fg_pi_v787 where id=h.linked_ci_id and status='CI_FINAL') then
    raise exception 'Linked CI must be final before RCI posting.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('RCI|'||h.data_mode,0));
  insert into public.rr_rci_sequence_v9740(data_mode,last_number) values(h.data_mode,0) on conflict do nothing;
  update public.rr_rci_sequence_v9740 set last_number=last_number+1,updated_at=now()
   where data_mode=h.data_mode returning last_number into v_n;
  v_prefix:=case when h.data_mode='TEST' then 'TRCI-' else 'RCI-' end;
  v_no:=v_prefix||lpad(v_n::text,6,'0');
  for l in select * from public.rr_rci_lines_v9740 where rci_id=h.id order by serial_no for update loop
    if l.return_type='KNOWN' then
      update public.rr_fg_pi_lines_v787 set returned_qty=returned_qty+l.rci_qty
       where id=l.source_ci_line_id and returned_qty+l.rci_qty<=qty;
      if not found then raise exception '% RCI quantity is no longer available.',l.original_lot_no; end if;
    end if;
    insert into public.rr_fg_stock_ledger_v787(txn_type,ref_type,ref_id,lot_no,stock_type,location_code,
      qty_delta,rate,data_mode,meta)
    values('RCI_IN','RCI_LINE',l.id,l.stock_lot_no,l.stock_type,l.location_code,l.rci_qty,l.rate,h.data_mode,
      jsonb_build_object('rci_id',h.id,'rci_no',v_no,'return_type',l.return_type,
        'source_ci_id',l.source_ci_id,'source_ci_line_id',l.source_ci_line_id,'buyer_id',h.buyer_id));
  end loop;
  update public.rr_rci_v9740 set rci_no=v_no,status='POSTED',posted_by=auth.uid(),posted_at=now(),
    settlement_no=case when flow_type='COMBINED' then 'SET-'||coalesce((select cpi_no from public.rr_fg_pi_v787 where id=linked_ci_id),v_no) else v_no end
   where id=h.id;
  return jsonb_build_object('rci_id',h.id,'rci_no',v_no,'status','POSTED','total_qty',h.total_qty,'total_amount',h.total_amount);
end
$function$;

create or replace function public.rr_rci_post_standalone_v9740(
  p_buyer_id uuid,p_lines jsonb,p_reason text,p_idempotency_key text,p_data_mode text default 'TEST'
) returns jsonb
language plpgsql security definer set search_path='public'
as $function$
declare d jsonb;
begin
  d:=public.rr_rci_save_draft_v9740(null,null,p_buyer_id,'STANDALONE',p_lines,p_reason,p_idempotency_key,p_data_mode);
  return public.rr_rci_finalize_v9740((d->>'rci_id')::uuid);
end
$function$;

create or replace function public.rr_rci_reverse_v9740(p_rci_id uuid,p_reason text)
returns jsonb
language plpgsql security definer set search_path='public'
as $function$
declare h public.rr_rci_v9740%rowtype;l record;
begin
  perform public.rr_fg_assert_user_v787();
  if nullif(trim(p_reason),'') is null then raise exception 'RCI reversal reason required.'; end if;
  select * into h from public.rr_rci_v9740 where id=p_rci_id for update;
  if h.status<>'POSTED' then raise exception 'Only posted RCI can be reversed.'; end if;
  for l in select * from public.rr_rci_lines_v9740 where rci_id=h.id order by serial_no for update loop
    if l.return_type='KNOWN' then
      update public.rr_fg_pi_lines_v787 set returned_qty=returned_qty-l.rci_qty
       where id=l.source_ci_line_id and returned_qty>=l.rci_qty;
      if not found then raise exception 'RCI source quantity reversal conflict.'; end if;
    end if;
    insert into public.rr_fg_stock_ledger_v787(txn_type,ref_type,ref_id,lot_no,stock_type,location_code,
      qty_delta,rate,data_mode,meta)
    values('RCI_REVERSAL','RCI_LINE',l.id,l.stock_lot_no,l.stock_type,l.location_code,-l.rci_qty,l.rate,h.data_mode,
      jsonb_build_object('rci_id',h.id,'rci_no',h.rci_no,'reversal_reason',trim(p_reason)));
  end loop;
  update public.rr_rci_v9740 set status='REVERSED',reversed_by=auth.uid(),reversed_at=now(),reversal_reason=trim(p_reason)
   where id=h.id;
  return jsonb_build_object('rci_id',h.id,'rci_no',h.rci_no,'status','REVERSED');
end
$function$;

create or replace function public.rr_rci_detail_v9740(p_rci_id uuid)
returns jsonb
language plpgsql stable security definer set search_path='public'
as $function$
declare h jsonb;ls jsonb;
begin
  perform public.rr_fg_assert_user_v787();
  select to_jsonb(x) into h from public.rr_rci_v9740 x where id=p_rci_id;
  if h is null then raise exception 'RCI not found.'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by serial_no),'[]'::jsonb) into ls
   from public.rr_rci_lines_v9740 x where rci_id=p_rci_id;
  return jsonb_build_object('header',h,'lines',ls);
end
$function$;

create or replace function public.rr_rci_for_ci_v9740(p_ci_id uuid)
returns jsonb
language plpgsql stable security definer set search_path='public'
as $function$
declare v_id uuid;
begin
  perform public.rr_fg_assert_user_v787();
  select id into v_id from public.rr_rci_v9740
   where linked_ci_id=p_ci_id and status in('DRAFT','POSTED')
   order by case status when 'POSTED' then 0 else 1 end,created_at desc limit 1;
  if v_id is null then return null; end if;
  return public.rr_rci_detail_v9740(v_id);
end
$function$;

create or replace function public.rr_rci_post_combined_on_ci_v9740()
returns trigger language plpgsql security definer set search_path='public'
as $function$
declare r record;
begin
  if old.status is distinct from new.status and new.status='CI_FINAL' then
    for r in select id from public.rr_rci_v9740 where linked_ci_id=new.id and flow_type='COMBINED' and status='DRAFT' order by created_at loop
      perform public.rr_rci_finalize_v9740(r.id);
    end loop;
  end if;
  return new;
end
$function$;

drop trigger if exists rr_rci_post_combined_on_ci_v9740 on public.rr_fg_pi_v787;
create trigger rr_rci_post_combined_on_ci_v9740
after update of status on public.rr_fg_pi_v787 for each row
execute function public.rr_rci_post_combined_on_ci_v9740();

revoke all on function public.rr_rci_party_average_v9740(uuid,text),
 public.rr_rci_context_v9740(uuid),
 public.rr_rci_save_draft_v9740(uuid,uuid,uuid,text,jsonb,text,text,text),
 public.rr_rci_finalize_v9740(uuid),
 public.rr_rci_post_standalone_v9740(uuid,jsonb,text,text,text),
 public.rr_rci_reverse_v9740(uuid,text),public.rr_rci_detail_v9740(uuid),
 public.rr_rci_for_ci_v9740(uuid)
 from public,anon;
grant execute on function public.rr_rci_context_v9740(uuid),
 public.rr_rci_save_draft_v9740(uuid,uuid,uuid,text,jsonb,text,text,text),
 public.rr_rci_post_standalone_v9740(uuid,jsonb,text,text,text),
 public.rr_rci_reverse_v9740(uuid,text),public.rr_rci_detail_v9740(uuid),
 public.rr_rci_for_ci_v9740(uuid)
 to authenticated;
revoke all on function public.rr_rci_finalize_v9740(uuid),public.rr_rci_post_combined_on_ci_v9740()
 from public,anon,authenticated;
grant execute on function public.rr_rci_finalize_v9740(uuid),public.rr_rci_post_combined_on_ci_v9740() to service_role;

commit;
