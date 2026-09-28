-- TEST71 targeted business web-push delivery parity.
create table if not exists public.rr_targeted_push_outbox_v708(id uuid primary key default gen_random_uuid(),event_key text not null,recipient_worker_id uuid not null,title text not null,body text not null,route_url text,payload jsonb not null default '{}'::jsonb,dispatch_token uuid not null default gen_random_uuid(),processed_at timestamptz,created_at timestamptz not null default now(),unique(event_key,recipient_worker_id));
alter table public.rr_targeted_push_outbox_v708 enable row level security;
revoke all on public.rr_targeted_push_outbox_v708 from anon,authenticated;
create or replace function public.rr_targeted_push_deliver_v708() returns trigger language plpgsql security definer set search_path to 'public','extensions' as $function$
begin perform net.http_post(url:='https://hruartsemierwhtzonei.supabase.co/functions/v1/rr-web-push-dispatch-v61',headers:=jsonb_build_object('Content-Type','application/json'),body:=jsonb_build_object('targeted_outbox_id',new.id,'dispatch_token',new.dispatch_token,'event_key',new.event_key));return new;end $function$;
drop trigger if exists rr_targeted_push_deliver_v708 on public.rr_targeted_push_outbox_v708;
create trigger rr_targeted_push_deliver_v708 after insert on public.rr_targeted_push_outbox_v708 for each row execute function public.rr_targeted_push_deliver_v708();
