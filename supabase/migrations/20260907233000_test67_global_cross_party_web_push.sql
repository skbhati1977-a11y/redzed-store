-- TEST67 global cross-party Web Push bridge.
-- Reuses the existing V61 subscription/outbox/dispatcher infrastructure.
alter table public.rr_web_push_subscriptions_v61
  add column if not exists actor_kind text,
  add column if not exists actor_id uuid,
  add column if not exists chat_id uuid,
  add column if not exists route_url text;

update public.rr_web_push_subscriptions_v61
set actor_kind=coalesce(actor_kind,'STAFF'),
    actor_id=coalesce(actor_id,worker_id)
where actor_kind is null or actor_id is null;

create index if not exists rr_web_push_subscriptions_v61_actor_idx
  on public.rr_web_push_subscriptions_v61(actor_kind,actor_id)
  where enabled;

create or replace function public.rr_chat_push_enqueue_v61()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_name text;
begin
  if new.channel='GROUP' then
    select coalesce(nullif(new.sender_name,''),c.customer_name,'REDZED Chat')
      into v_name
      from public.rr_customer_chat_v9433 c
     where c.id=new.chat_id;

    insert into public.rr_chat_push_outbox_v61
      (message_id,chat_id,customer_name,preview)
    values
      (new.id,new.chat_id,coalesce(v_name,'REDZED Chat'),
       coalesce(nullif(new.body,''),
         case when new.message_type='ATTACHMENT'
              then 'Attachment received'
              else coalesce(new.message_type,'New message') end))
    on conflict(message_id) do nothing;
  end if;
  return new;
end
$function$;