alter table public.rr_chat_push_outbox_v61 add column if not exists target_url text;
alter table public.rr_chat_push_outbox_v61 add column if not exists collection_cycle_id uuid;
alter table public.rr_chat_push_outbox_v61 add column if not exists collection_update_no integer;
create or replace function public.rr_chat_push_enqueue_v61() returns trigger language plpgsql security definer set search_path=public as $$
declare v_name text; v_target text; v_cycle uuid; v_update integer;
begin
 if new.channel<>'GROUP' or new.archived_at is not null then return new; end if;
 if tg_op='UPDATE' then
  if new.sender_kind is distinct from 'STAFF' or new.payload->>'source' is distinct from 'DIRECT_MARKET_WINDOW'
   or coalesce((new.payload->>'collection_update_no')::int,0)<=coalesce((old.payload->>'collection_update_no')::int,0)
   or not exists(select 1 from public.rr_customer_chat_v9433 c where c.id=new.chat_id and c.relation_kind='DIRECT_CUSTOMER' and c.data_mode='TEST') then return new; end if;
 end if;
 if new.sender_kind='STAFF' and new.payload->>'source'='DIRECT_MARKET_WINDOW' then
  v_target:=new.payload->>'url';
  if v_target like 'https://redzed-customer-collection.jggfab2011.chatgpt.site/s.html?%' or v_target ~ '^https://[a-z0-9.-]+\.(vercel\.app|github\.io)/s\.html\?' then
   v_target:=regexp_replace(v_target,'^https://[^/]+','https://redzed-customer-collection.jggfab2011.chatgpt.site');
   v_target:=v_target||'&open=collection';
   v_cycle:=nullif(new.payload->>'direct_collection_cycle_id','')::uuid;
   v_update:=coalesce(nullif(new.payload->>'collection_update_no','')::integer,0);
  else v_target:=null; end if;
 end if;
 select coalesce(nullif(new.sender_name,''),c.customer_name,'REDZED Chat') into v_name from public.rr_customer_chat_v9433 c where c.id=new.chat_id;
 if tg_op='UPDATE' then
  insert into public.rr_chat_push_outbox_v61(message_id,chat_id,customer_name,preview,target_url,collection_cycle_id,collection_update_no)
  values(new.id,new.chat_id,coalesce(v_name,'REDZED Chat'),new.body,v_target,v_cycle,v_update)
  on conflict(message_id) do update set preview=excluded.preview,target_url=excluded.target_url,
   collection_cycle_id=excluded.collection_cycle_id,collection_update_no=excluded.collection_update_no,
   processed_at=null,dispatch_token=gen_random_uuid(),created_at=now();
 else
  insert into public.rr_chat_push_outbox_v61(message_id,chat_id,customer_name,preview,target_url,collection_cycle_id,collection_update_no)
  values(new.id,new.chat_id,coalesce(v_name,'REDZED Chat'),coalesce(nullif(new.body,''),new.message_type,'New message'),v_target,v_cycle,v_update)
  on conflict(message_id) do nothing;
 end if;
 return new;
end $$;
drop trigger if exists trg_rr_chat_push_enqueue_v61 on public.rr_customer_chat_messages_v9433;
create trigger trg_rr_chat_push_enqueue_v61 after insert or update of payload on public.rr_customer_chat_messages_v9433 for each row execute function public.rr_chat_push_enqueue_v61();
drop trigger if exists trg_rr_chat_push_deliver_v61 on public.rr_chat_push_outbox_v61;
create trigger trg_rr_chat_push_deliver_v61 after insert or update of dispatch_token on public.rr_chat_push_outbox_v61 for each row when(new.processed_at is null) execute function public.rr_chat_push_deliver_v61();

