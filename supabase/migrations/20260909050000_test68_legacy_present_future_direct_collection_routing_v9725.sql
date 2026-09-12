-- TEST68: repair legacy/current direct Collection routes and enforce the same
-- canonical chat boundary for future sends. Distributor-owned shares are never
-- adopted into the REDZED direct-customer lane.

-- Present/legacy records that already belong to a canonical direct cycle.
update public.rr_market_share_v9420 s set
  origin_chat_id=c.chat_id,
  origin_relation_kind='DIRECT_CUSTOMER',
  origin_collection_cycle_id=c.id,
  origin_owner_customer_id=c.customer_id,
  origin_partner_customer_id=null
from public.rr_collection_send_v9586 cs
join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id
join public.rr_customer_chat_v9433 ch on ch.id=c.chat_id
where cs.share_id=s.id
  and ch.customer_id=c.customer_id
  and ch.data_mode=c.data_mode
  and ch.relation_kind='DIRECT_CUSTOMER'
  and ch.status='OPEN'
  and (
    s.origin_chat_id is distinct from c.chat_id or
    s.origin_relation_kind is distinct from 'DIRECT_CUSTOMER' or
    s.origin_collection_cycle_id is distinct from c.id or
    s.origin_owner_customer_id is distinct from c.customer_id or
    s.origin_partner_customer_id is not null
  );

-- Legacy shares without a cycle are adopted conservatively. The share must
-- have one permanent direct customer chat and must not be a distributor share.
do $block$
declare
  x record;
  v_chat uuid;
  v_cycle uuid;
  v_no integer;
  v_dm text;
begin
  for x in
    select s.id,s.customer_id,s.data_mode,s.created_at
    from public.rr_market_share_v9420 s
    where s.status='ACTIVE'
      and s.customer_id is not null
      and not exists(
        select 1 from public.rr_collection_send_v9586 cs where cs.share_id=s.id
      )
      and not exists(
        select 1 from public.rr_market_partner_collection_v67 pc where pc.share_id=s.id
      )
    order by s.customer_id,upper(coalesce(nullif(trim(s.data_mode),''),'TEST')),s.created_at,s.id
  loop
    v_dm:=upper(coalesce(nullif(trim(x.data_mode),''),'TEST'));
    select (array_agg(ch.id))[1] into v_chat
    from public.rr_customer_chat_v9433 ch
    where ch.customer_id=x.customer_id
      and ch.data_mode=v_dm
      and ch.relation_kind='DIRECT_CUSTOMER'
      and ch.status='OPEN'
    having count(*)=1;
    if v_chat is null then continue; end if;

    perform pg_advisory_xact_lock(
      hashtextextended(x.customer_id::text||'|'||v_dm||'|LEGACY_DIRECT_ADOPT',9725)
    );
    if exists(select 1 from public.rr_collection_send_v9586 cs where cs.share_id=x.id)
    then continue; end if;

    select coalesce(max(c.collection_no),0)+1 into v_no
    from public.rr_collection_cycle_v9586 c
    where c.customer_id=x.customer_id and c.data_mode=v_dm;

    insert into public.rr_collection_cycle_v9586(
      customer_id,chat_id,data_mode,collection_no,display_no,status,opened_at,created_at
    ) values(
      x.customer_id,v_chat,v_dm,v_no,'RZ COLLECTION '||lpad(v_no::text,2,'0'),
      'OPENED_NO_RESPONSE',null,x.created_at
    ) returning id into v_cycle;

    insert into public.rr_collection_send_v9586(
      collection_cycle_id,share_id,send_seq,send_kind,sent_at
    ) values(v_cycle,x.id,1,'FIRST',x.created_at);

    update public.rr_market_share_v9420 set
      origin_chat_id=v_chat,
      origin_relation_kind='DIRECT_CUSTOMER',
      origin_collection_cycle_id=v_cycle,
      origin_owner_customer_id=x.customer_id,
      origin_partner_customer_id=null
    where id=x.id;
  end loop;
end
$block$;

-- Future guard: collection_send is the canonical link. Synchronize origin
-- metadata only when its cycle is unquestionably a direct-customer cycle.
create or replace function public.rr_sync_direct_share_origin_v9725()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_cycle public.rr_collection_cycle_v9586%rowtype;
begin
  select c.* into v_cycle
  from public.rr_collection_cycle_v9586 c
  join public.rr_customer_chat_v9433 ch on ch.id=c.chat_id
  where c.id=new.collection_cycle_id
    and ch.customer_id=c.customer_id
    and ch.data_mode=c.data_mode
    and ch.relation_kind='DIRECT_CUSTOMER'
    and ch.status='OPEN';

  if v_cycle.id is not null then
    update public.rr_market_share_v9420 set
      origin_chat_id=v_cycle.chat_id,
      origin_relation_kind='DIRECT_CUSTOMER',
      origin_collection_cycle_id=v_cycle.id,
      origin_owner_customer_id=v_cycle.customer_id,
      origin_partner_customer_id=null
    where id=new.share_id;
  end if;
  return new;
end
$function$;

revoke all on function public.rr_sync_direct_share_origin_v9725() from public,anon,authenticated;

drop trigger if exists rr_collection_send_sync_origin_v9725
  on public.rr_collection_send_v9586;
create trigger rr_collection_send_sync_origin_v9725
after insert or update of collection_cycle_id,share_id
on public.rr_collection_send_v9586
for each row execute function public.rr_sync_direct_share_origin_v9725();
