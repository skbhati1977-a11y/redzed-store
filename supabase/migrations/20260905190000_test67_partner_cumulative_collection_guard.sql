-- TEST67 distributor -> customer cumulative Collection guard.
-- Keeps one canonical occurrence of each lot inside a Collection root and
-- archives legacy repeated rows before removing them from active projections.

create table if not exists public.rr_market_partner_collection_line_duplicate_archive_v78(
  collection_id uuid not null,
  lot_no text not null,
  category text,
  cloth_name text,
  primary_image_url text,
  media jsonb not null default '[]'::jsonb,
  stock_status text not null,
  base_rate numeric(14,2) not null,
  margin_amount numeric(14,2) not null default 0,
  distributor_sale_rate numeric(14,2) not null,
  discount_amount numeric(14,2) not null default 0,
  final_customer_rate numeric(14,2) not null,
  created_at timestamptz not null,
  size_text text,
  root_collection_id uuid not null,
  collection_no bigint,
  collection_update_no integer not null,
  archived_at timestamptz not null default now(),
  primary key(collection_id,lot_no)
);

alter table public.rr_market_partner_collection_line_duplicate_archive_v78 enable row level security;
revoke all on public.rr_market_partner_collection_line_duplicate_archive_v78 from public,anon,authenticated;
grant all on public.rr_market_partner_collection_line_duplicate_archive_v78 to service_role;

with ranked as(
  select
    l.*,
    coalesce(pc.root_collection_id,pc.id) as canonical_root_id,
    pc.collection_no as canonical_collection_no,
    pc.collection_update_no as canonical_update_no,
    row_number() over(
      partition by coalesce(pc.root_collection_id,pc.id),lower(btrim(l.lot_no))
      order by pc.collection_update_no,pc.created_at,l.created_at,pc.id
    ) as occurrence_no
  from public.rr_market_partner_collection_v67 pc
  join public.rr_market_partner_collection_line_v67 l on l.collection_id=pc.id
)
insert into public.rr_market_partner_collection_line_duplicate_archive_v78(
  collection_id,lot_no,category,cloth_name,primary_image_url,media,stock_status,
  base_rate,margin_amount,distributor_sale_rate,discount_amount,final_customer_rate,
  created_at,size_text,root_collection_id,collection_no,collection_update_no
)
select
  collection_id,lot_no,category,cloth_name,primary_image_url,media,stock_status,
  base_rate,margin_amount,distributor_sale_rate,discount_amount,final_customer_rate,
  created_at,size_text,canonical_root_id,canonical_collection_no,canonical_update_no
from ranked
where occurrence_no>1
on conflict(collection_id,lot_no)do nothing;

delete from public.rr_market_share_lots_v9420 sl
using public.rr_market_partner_collection_v67 pc,
      public.rr_market_partner_collection_line_duplicate_archive_v78 a
where pc.id=a.collection_id
  and sl.share_id=pc.share_id
  and lower(btrim(sl.lot_no))=lower(btrim(a.lot_no));

delete from public.rr_market_partner_collection_line_v67 l
using public.rr_market_partner_collection_line_duplicate_archive_v78 a
where l.collection_id=a.collection_id
  and lower(btrim(l.lot_no))=lower(btrim(a.lot_no));

alter table public.rr_market_partner_collection_v67
  add column if not exists legacy_update_no_v78 integer,
  add column if not exists legacy_hidden_v78 boolean not null default false;

drop index if exists public.rr_market_partner_collection_v67_global_chain_uniq;
create unique index rr_market_partner_collection_v67_global_chain_uniq
  on public.rr_market_partner_collection_v67(collection_no,collection_update_no)
  where collection_no is not null and status<>'CANCELLED';

-- Only unfinished TEST roots without any Requirement can be compacted safely.
-- Empty rows created by repeat-only sends remain recoverable but leave the live
-- Collection journey, then the remaining genuine sends become 0,1,2... updates.
with root_ids as(
  select distinct coalesce(root_collection_id,id) as root_id
  from public.rr_market_partner_collection_v67
), eligible_roots as(
  select r.root_id
  from root_ids r
  where not exists(
    select 1
    from public.rr_market_partner_collection_v67 cx
    join public.rr_market_partner_order_v67 o on o.collection_id=cx.id
    where coalesce(cx.root_collection_id,cx.id)=r.root_id
  )
  and not exists(
    select 1
    from public.rr_market_partner_collection_v67 cx
    where coalesce(cx.root_collection_id,cx.id)=r.root_id
      and (cx.requirement_id is not null or cx.order_id is not null)
  )
), empty_rows as(
  select pc.id
  from public.rr_market_partner_collection_v67 pc
  join eligible_roots er on er.root_id=coalesce(pc.root_collection_id,pc.id)
  where not exists(
    select 1 from public.rr_market_partner_collection_line_v67 l
    where l.collection_id=pc.id
  )
)
update public.rr_market_partner_collection_v67 pc
set legacy_update_no_v78=coalesce(pc.legacy_update_no_v78,pc.collection_update_no),
    legacy_hidden_v78=true,
    status='CANCELLED',
    collection_update_no=0,
    collection_display_no='LEGACY DUPLICATE · HIDDEN',
    updated_at=now()
from empty_rows e
where pc.id=e.id;

with root_ids as(
  select distinct coalesce(root_collection_id,id) as root_id
  from public.rr_market_partner_collection_v67
), eligible_roots as(
  select r.root_id
  from root_ids r
  where not exists(
    select 1
    from public.rr_market_partner_collection_v67 cx
    join public.rr_market_partner_order_v67 o on o.collection_id=cx.id
    where coalesce(cx.root_collection_id,cx.id)=r.root_id
  )
  and not exists(
    select 1
    from public.rr_market_partner_collection_v67 cx
    where coalesce(cx.root_collection_id,cx.id)=r.root_id
      and (cx.requirement_id is not null or cx.order_id is not null)
  )
), numbered as(
  select pc.id,
         row_number() over(
           partition by coalesce(pc.root_collection_id,pc.id)
           order by coalesce(pc.legacy_update_no_v78,pc.collection_update_no),pc.created_at,pc.id
         )-1 as normalized_update_no
  from public.rr_market_partner_collection_v67 pc
  join eligible_roots er on er.root_id=coalesce(pc.root_collection_id,pc.id)
  where pc.status<>'CANCELLED'
)
update public.rr_market_partner_collection_v67 pc
set legacy_update_no_v78=coalesce(pc.legacy_update_no_v78,pc.collection_update_no),
    collection_update_no=n.normalized_update_no,
    collection_display_no='COLLECTION '||pc.collection_no::text||
      case when n.normalized_update_no>0
        then ' · UPDATE '||n.normalized_update_no::text else '' end,
    updated_at=now()
from numbered n
where pc.id=n.id;

create index if not exists rr_market_partner_collection_line_v78_lot_idx
  on public.rr_market_partner_collection_line_v67(lower(btrim(lot_no)),collection_id);

create or replace function public.rr_market_partner_collection_line_once_v78()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_root uuid;
  v_collection_no bigint;
begin
  select coalesce(pc.root_collection_id,pc.id),pc.collection_no
  into v_root,v_collection_no
  from public.rr_market_partner_collection_v67 pc
  where pc.id=new.collection_id;

  if v_root is null then
    raise exception 'TEST67 Collection parent is unavailable.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_root::text||'|'||lower(btrim(new.lot_no)),78)
  );

  if tg_op='UPDATE' then
    if exists(
      select 1
      from public.rr_market_partner_collection_line_v67 prior
      join public.rr_market_partner_collection_v67 pc on pc.id=prior.collection_id
      where coalesce(pc.root_collection_id,pc.id)=v_root
        and lower(btrim(prior.lot_no))=lower(btrim(new.lot_no))
        and (prior.collection_id,prior.lot_no)<>(old.collection_id,old.lot_no)
    ) then
      raise exception 'Lot % was already sent in COLLECTION %. Select only fresh samples.',
        new.lot_no,v_collection_no;
    end if;
  elsif exists(
    select 1
    from public.rr_market_partner_collection_line_v67 prior
    join public.rr_market_partner_collection_v67 pc on pc.id=prior.collection_id
    where coalesce(pc.root_collection_id,pc.id)=v_root
      and lower(btrim(prior.lot_no))=lower(btrim(new.lot_no))
  ) then
    raise exception 'Lot % was already sent in COLLECTION %. Select only fresh samples.',
      new.lot_no,v_collection_no;
  end if;

  return new;
end
$$;

drop trigger if exists rr_market_partner_collection_line_once_v78
  on public.rr_market_partner_collection_line_v67;
create trigger rr_market_partner_collection_line_once_v78
before insert or update of collection_id,lot_no
on public.rr_market_partner_collection_line_v67
for each row execute function public.rr_market_partner_collection_line_once_v78();

revoke all on function public.rr_market_partner_collection_line_once_v78()
  from public,anon,authenticated;

comment on table public.rr_market_partner_collection_line_duplicate_archive_v78 is
  'TEST67 recovery archive for repeated distributor collection lots removed by V78 cumulative normalization.';
comment on function public.rr_market_partner_collection_line_once_v78() is
  'TEST67 invariant: a lot may occur only once inside one distributor customer Collection root.';
