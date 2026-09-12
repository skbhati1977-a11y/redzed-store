-- V9787: map Salary & Wages ledgers to a locked, worker-owned Real Chat.
begin;

alter table public.rr_customer_chat_v9433 drop constraint if exists rr_customer_chat_relation_kind_v9704_ck;
alter table public.rr_customer_chat_v9433 add constraint rr_customer_chat_relation_kind_v9704_ck check(
  relation_kind in ('DIRECT_CUSTOMER','DISTRIBUTOR_REDZED','DISTRIBUTOR_CUSTOMER','WORKER_DIRECT'));

create table if not exists public.rr_worker_real_chat_map_v9787(
  worker_id uuid primary key,
  salary_ledger_id uuid not null unique references public.rr_ledgers_v805(id) on delete cascade,
  chat_id uuid not null unique references public.rr_customer_chat_v9433(id) on delete cascade,
  department_code text, linked_auth_user_id uuid, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
alter table public.rr_worker_real_chat_map_v9787 enable row level security;

create or replace function public.rr_accounts_party_chat_v9787(p_ledger_id uuid)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare l public.rr_ledgers_v805%rowtype; w public.rr_worker_accounts_map_v9785%rowtype;
  a public.rr_user_profiles%rowtype; mapped public.rr_worker_real_chat_map_v9787%rowtype; new_chat uuid;
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  select * into l from public.rr_ledgers_v805 where id=p_ledger_id and is_active;
  if l.id is null then raise exception 'Ledger not found.'; end if;
  if upper(coalesce(l.ledger_kind,''))='CUSTOMER' then return public.rr_accounts_party_chat_v9776(p_ledger_id); end if;
  select * into w from public.rr_worker_accounts_map_v9785 where salary_ledger_id=l.id and is_active limit 1;
  if w.worker_id is null then raise exception '% का worker ledger mapping उपलब्ध नहीं है।',l.ledger_name; end if;
  a:=public.rr_chat_actor_profile_v9433();
  select * into mapped from public.rr_worker_real_chat_map_v9787 where worker_id=w.worker_id and is_active limit 1;
  if mapped.chat_id is null then
    insert into public.rr_customer_chat_v9433(customer_id,customer_name,mobile,data_mode,status,relation_kind)
    values(null,w.worker_name,w.mobile,'TEST','OPEN','WORKER_DIRECT') returning id into new_chat;
    insert into public.rr_worker_real_chat_map_v9787(worker_id,salary_ledger_id,chat_id,department_code,linked_auth_user_id)
    values(w.worker_id,l.id,new_chat,w.department_code,w.linked_auth_user_id) returning * into mapped;
  end if;
  insert into public.rr_customer_chat_members_v9433(chat_id,profile_id,is_active,added_by,removed_at,removed_by)
  values(mapped.chat_id,a.id,true,a.id,null,null) on conflict(chat_id,profile_id) do update set
    is_active=true,removed_at=null,removed_by=null,added_at=now(),added_by=a.id;
  insert into public.rr_customer_chat_worker_members_v9439(chat_id,worker_id,is_active)
  values(mapped.chat_id,w.worker_id,true) on conflict(chat_id,worker_id) do update set is_active=true;
  update public.rr_worker_real_chat_map_v9787 set salary_ledger_id=l.id,department_code=w.department_code,
    linked_auth_user_id=w.linked_auth_user_id,updated_at=now() where worker_id=w.worker_id;
  return jsonb_build_object('chat_id',mapped.chat_id,'customer_id',null,'customer_name',w.worker_name,
    'mobile',w.mobile,'worker_id',w.worker_id,'department_code',w.department_code,'ledger_id',l.id,
    'ledger_name',l.ledger_name,'relation_kind','WORKER_DIRECT','locked',true);
end $function$;

create or replace function public.rr_accounts_party_upload_v9787(
  p_ledger_id uuid,p_chat_id uuid,p_file_name text,p_mime_type text,p_base64 text,p_body text)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare target jsonb; locked_chat uuid; result jsonb;
begin
  target:=public.rr_accounts_party_chat_v9787(p_ledger_id); locked_chat:=(target->>'chat_id')::uuid;
  if p_chat_id is distinct from locked_chat then raise exception 'Account privacy lock: this ledger can only be shared with %.',target->>'customer_name'; end if;
  result:=public.rr_chat_staff_upload_v9434(locked_chat,'GROUP',p_file_name,p_mime_type,p_base64,p_body,null);
  return result||jsonb_build_object('party_locked',true,'ledger_id',p_ledger_id,'worker_id',target->>'worker_id','relation_kind',target->>'relation_kind');
end $function$;

create or replace function public.rr_chat_staff_inbox_v9704()
returns table(chat_id uuid,customer_id uuid,customer_name text,mobile text,relation_kind text,
  last_message text,last_message_at timestamptz,can_private_chat boolean)
language plpgsql stable security definer set search_path='' as $function$
declare a public.rr_user_profiles%rowtype;
begin
  perform public.rr_assert_active_user_v1(); a:=public.rr_chat_actor_profile_v9433();
  if upper(coalesce(a.role_code,'')) not in('SUPER_ADMIN','OWNER','ADMIN','ACCOUNTANT','ACCOUNTS','ACCOUNT','SALES','SALESMAN') then raise exception 'Sales chat access denied.'; end if;
  return query select ch.id,ch.customer_id,ch.customer_name,ch.mobile,ch.relation_kind,l.body,l.created_at,
    upper(coalesce(a.role_code,'')) in('SUPER_ADMIN','OWNER')
  from public.rr_customer_chat_v9433 ch join public.rr_customer_chat_members_v9433 m on m.chat_id=ch.id and m.profile_id=a.id and m.is_active
  left join lateral(select mm.body,mm.created_at from public.rr_customer_chat_messages_v9433 mm
    where mm.chat_id=ch.id and mm.channel='GROUP' and mm.archived_at is null order by mm.created_at desc limit 1)l on true
  where ch.status='OPEN' and ch.relation_kind in('DIRECT_CUSTOMER','DISTRIBUTOR_REDZED','WORKER_DIRECT')
  order by l.created_at desc nulls last,ch.customer_name,ch.updated_at desc;
end $function$;

revoke all on table public.rr_worker_real_chat_map_v9787 from public,anon,authenticated;
grant select on table public.rr_worker_real_chat_map_v9787 to service_role;
revoke all on function public.rr_accounts_party_chat_v9787(uuid),public.rr_accounts_party_upload_v9787(uuid,uuid,text,text,text,text) from public,anon;
grant execute on function public.rr_accounts_party_chat_v9787(uuid),public.rr_accounts_party_upload_v9787(uuid,uuid,text,text,text,text) to authenticated,service_role;
commit;
