-- TEST67 only: every distributor customer has a group; active staff join every active distributor group.

create table if not exists public.rr_market_partner_staff_group_v67(
  staff_id uuid not null references public.rr_market_partner_staff_v67(id) on delete cascade,
  group_id uuid not null references public.rr_market_partner_group_v67(id) on delete cascade,
  owner_customer_id uuid not null references public.rr_customers(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(staff_id,group_id)
);
alter table public.rr_market_partner_staff_group_v67 enable row level security;
revoke all on public.rr_market_partner_staff_group_v67 from public,anon,authenticated;
grant all on public.rr_market_partner_staff_group_v67 to service_role;
create index if not exists rr_market_partner_staff_group_v67_owner_idx
  on public.rr_market_partner_staff_group_v67(owner_customer_id);
create index if not exists rr_market_partner_staff_group_v67_group_idx
  on public.rr_market_partner_staff_group_v67(group_id);

create or replace function public.rr_market_partner_customer_private_group_v67()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_group uuid;
begin
  if new.data_mode<>'TEST' or new.group_id is not null then return new; end if;
  insert into public.rr_market_partner_group_v67(owner_customer_id,group_name,group_info,status,data_mode)
  values(new.owner_customer_id,'PRIVATE '||new.customer_ref,'Private customer group','ACTIVE','TEST')
  on conflict(owner_customer_id,group_name,data_mode)
  do update set status='ACTIVE',updated_at=now()
  returning id into v_group;
  update public.rr_market_partner_customer_v67 set group_id=v_group,updated_at=now() where id=new.id;
  return new;
end
$$;

drop trigger if exists rr_market_partner_customer_private_group_v67 on public.rr_market_partner_customer_v67;
create trigger rr_market_partner_customer_private_group_v67
after insert on public.rr_market_partner_customer_v67
for each row execute function public.rr_market_partner_customer_private_group_v67();

do $$
declare c record;v_group uuid;
begin
  for c in
    select id,owner_customer_id,customer_ref
    from public.rr_market_partner_customer_v67
    where data_mode='TEST' and group_id is null
  loop
    insert into public.rr_market_partner_group_v67(owner_customer_id,group_name,group_info,status,data_mode)
    values(c.owner_customer_id,'PRIVATE '||c.customer_ref,'Private customer group','ACTIVE','TEST')
    on conflict(owner_customer_id,group_name,data_mode)
    do update set status='ACTIVE',updated_at=now()
    returning id into v_group;
    update public.rr_market_partner_customer_v67 set group_id=v_group,updated_at=now() where id=c.id;
  end loop;
end
$$;

create or replace function public.rr_market_partner_group_staff_sync_v67()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.data_mode='TEST' and new.status='ACTIVE' then
    insert into public.rr_market_partner_staff_group_v67(staff_id,group_id,owner_customer_id)
    select s.id,new.id,new.owner_customer_id
    from public.rr_market_partner_staff_v67 s
    where s.owner_customer_id=new.owner_customer_id and s.data_mode='TEST' and s.status='ACTIVE'
    on conflict do nothing;
  end if;
  return new;
end
$$;

drop trigger if exists rr_market_partner_group_staff_sync_v67 on public.rr_market_partner_group_v67;
create trigger rr_market_partner_group_staff_sync_v67
after insert or update of status on public.rr_market_partner_group_v67
for each row execute function public.rr_market_partner_group_staff_sync_v67();

insert into public.rr_market_partner_staff_group_v67(staff_id,group_id,owner_customer_id)
select s.id,g.id,s.owner_customer_id
from public.rr_market_partner_staff_v67 s
join public.rr_market_partner_group_v67 g on g.owner_customer_id=s.owner_customer_id
where s.data_mode='TEST' and g.data_mode='TEST' and s.status='ACTIVE' and g.status='ACTIVE'
on conflict do nothing;

create or replace function public.rr_market_partner_staff_status_set_v67(
  p_session_token text,
  p_device_id text,
  p_staff_id uuid,
  p_active boolean
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_ctx jsonb;v_owner uuid;v_status text;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  v_status:=case when coalesce(p_active,false) then 'ACTIVE' else 'INACTIVE' end;
  update public.rr_market_partner_staff_v67
  set status=v_status,updated_at=now()
  where id=p_staff_id and owner_customer_id=v_owner and data_mode='TEST';
  if not found then raise exception 'Distributor staff is unavailable.'; end if;
  if v_status='ACTIVE' then
    insert into public.rr_market_partner_staff_group_v67(staff_id,group_id,owner_customer_id)
    select p_staff_id,g.id,v_owner
    from public.rr_market_partner_group_v67 g
    where g.owner_customer_id=v_owner and g.data_mode='TEST' and g.status='ACTIVE'
    on conflict do nothing;
  else
    delete from public.rr_market_partner_staff_group_v67
    where staff_id=p_staff_id and owner_customer_id=v_owner;
  end if;
  return jsonb_build_object('ok',true,'staff_id',p_staff_id,'status',v_status,
    'group_count',(select count(*) from public.rr_market_partner_staff_group_v67 where staff_id=p_staff_id));
end
$$;

revoke all on function public.rr_market_partner_customer_private_group_v67() from public,anon,authenticated;
revoke all on function public.rr_market_partner_group_staff_sync_v67() from public,anon,authenticated;
revoke all on function public.rr_market_partner_staff_status_set_v67(text,text,uuid,boolean) from public;
grant execute on function public.rr_market_partner_staff_status_set_v67(text,text,uuid,boolean) to anon,authenticated,service_role;
