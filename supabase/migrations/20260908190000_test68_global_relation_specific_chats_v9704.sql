-- One canonical contact, separate Customer and Distributor chat relations.
alter table public.rr_customer_chat_v9433
  add column if not exists relation_kind text not null default 'DIRECT_CUSTOMER';

alter table public.rr_customer_chat_v9433
  drop constraint if exists rr_customer_chat_v9433_customer_id_data_mode_key;

alter table public.rr_customer_chat_v9433
  drop constraint if exists rr_customer_chat_relation_kind_v9704_ck;
alter table public.rr_customer_chat_v9433
  add constraint rr_customer_chat_relation_kind_v9704_ck check(
    relation_kind in ('DIRECT_CUSTOMER','DISTRIBUTOR_REDZED','DISTRIBUTOR_CUSTOMER')
  );

create unique index if not exists rr_customer_chat_relation_v9704_uq
  on public.rr_customer_chat_v9433(customer_id,data_mode,relation_kind)
  where customer_id is not null;

update public.rr_customer_chat_v9433 ch set relation_kind='DISTRIBUTOR_CUSTOMER'
from public.rr_market_partner_relation_chat_v67 r
where r.chat_id=ch.id and r.relation_kind='DISTRIBUTOR_CUSTOMER';

-- Preserve each legacy mixed chat as the direct-customer history. Give its
-- distributor relation a separate chat and move only explicit batch notices.
do $$
declare r record; v_new uuid;
begin
  for r in
    select rc.id relation_id,rc.chat_id old_chat,rc.owner_customer_id,
           ch.customer_name,ch.mobile,ch.data_mode
    from public.rr_market_partner_relation_chat_v67 rc
    join public.rr_customer_chat_v9433 ch on ch.id=rc.chat_id
    where rc.relation_kind='DISTRIBUTOR_REDZED' and rc.status='ACTIVE'
  loop
    update public.rr_customer_chat_v9433 set relation_kind='DIRECT_CUSTOMER'
    where id=r.old_chat;
    select id into v_new from public.rr_customer_chat_v9433
    where customer_id=r.owner_customer_id and data_mode=r.data_mode
      and relation_kind='DISTRIBUTOR_REDZED' limit 1;
    if v_new is null then
      insert into public.rr_customer_chat_v9433(
        customer_id,customer_name,mobile,data_mode,status,relation_kind
      ) values(r.owner_customer_id,r.customer_name,r.mobile,r.data_mode,'OPEN','DISTRIBUTOR_REDZED')
      returning id into v_new;
    end if;
    insert into public.rr_customer_chat_members_v9433(chat_id,profile_id,is_active,added_by)
    select v_new,m.profile_id,m.is_active,m.added_by
    from public.rr_customer_chat_members_v9433 m where m.chat_id=r.old_chat
    on conflict(chat_id,profile_id) do update set is_active=excluded.is_active;
    update public.rr_customer_chat_messages_v9433 set chat_id=v_new
    where chat_id=r.old_chat and (
      coalesce(body,'') ~* '\\[PBATCH:[0-9a-f-]{36}\\]'
      or coalesce(payload->>'batch_id','')<>''
    );
    update public.rr_market_partner_relation_chat_v67 set chat_id=v_new,updated_at=now()
    where id=r.relation_id;
  end loop;
end $$;

create or replace function public.rr_ensure_contact_relation_chats_v9704(p_customer_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.rr_customers%rowtype; d uuid; r uuid;
begin
  select * into c from public.rr_customers where id=p_customer_id and is_active;
  if c.id is null then raise exception 'Active contact not found.'; end if;
  insert into public.rr_customer_chat_v9433(customer_id,customer_name,mobile,data_mode,status,relation_kind)
  values(c.id,c.customer_name,c.mobile,'TEST','OPEN','DIRECT_CUSTOMER')
  on conflict(customer_id,data_mode,relation_kind) where customer_id is not null do update
    set customer_name=excluded.customer_name,mobile=excluded.mobile,status='OPEN',updated_at=now()
  returning id into d;
  insert into public.rr_customer_chat_v9433(customer_id,customer_name,mobile,data_mode,status,relation_kind)
  values(c.id,c.customer_name,c.mobile,'TEST','OPEN','DISTRIBUTOR_REDZED')
  on conflict(customer_id,data_mode,relation_kind) where customer_id is not null do update
    set customer_name=excluded.customer_name,mobile=excluded.mobile,status='OPEN',updated_at=now()
  returning id into r;
  insert into public.rr_customer_chat_members_v9433(chat_id,profile_id,is_active,added_by)
  select x.chat_id,p.id,true,p.id from (values(d),(r)) x(chat_id)
  cross join public.rr_user_profiles p
  where p.is_active and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
    and upper(coalesce(p.role_code,'')) in('SUPER_ADMIN','OWNER','ADMIN','ACCOUNTANT','ACCOUNTS','ACCOUNT','SALES','SALESMAN')
  on conflict(chat_id,profile_id) do update set is_active=true,removed_at=null,removed_by=null;
  insert into public.rr_market_partner_relation_chat_v67(relation_kind,owner_customer_id,partner_customer_id,chat_id,status,data_mode)
  values('DISTRIBUTOR_REDZED',c.id,null,r,'ACTIVE','TEST')
  on conflict(owner_customer_id) where relation_kind='DISTRIBUTOR_REDZED' do update
    set chat_id=excluded.chat_id,status='ACTIVE',updated_at=now();
  return jsonb_build_object('customer_id',c.id,'customer_chat_id',d,'distributor_chat_id',r);
end $$;
revoke all on function public.rr_ensure_contact_relation_chats_v9704(uuid) from public,anon,authenticated;
grant execute on function public.rr_ensure_contact_relation_chats_v9704(uuid) to service_role;

create or replace function public.rr_customer_relation_chats_trigger_v9704()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.is_active then perform public.rr_ensure_contact_relation_chats_v9704(new.id); end if;
  return new;
end $$;
drop trigger if exists rr_customer_relation_chats_v9704 on public.rr_customers;
create trigger rr_customer_relation_chats_v9704
after insert or update of customer_name,mobile,is_active on public.rr_customers
for each row execute function public.rr_customer_relation_chats_trigger_v9704();

do $$ declare x record; begin
  for x in select id from public.rr_customers where is_active loop
    perform public.rr_ensure_contact_relation_chats_v9704(x.id);
  end loop;
end $$;

create or replace function public.rr_chat_staff_inbox_v9704()
returns table(chat_id uuid,customer_id uuid,customer_name text,mobile text,relation_kind text,
  last_message text,last_message_at timestamptz,can_private_chat boolean)
language plpgsql stable security definer set search_path='' as $$
declare a public.rr_user_profiles%rowtype;
begin
  perform public.rr_assert_active_user_v1(); a:=public.rr_chat_actor_profile_v9433();
  if upper(coalesce(a.role_code,'')) not in('SUPER_ADMIN','OWNER','ADMIN','ACCOUNTANT','ACCOUNTS','ACCOUNT','SALES','SALESMAN')
  then raise exception 'Sales chat access denied.'; end if;
  return query select ch.id,ch.customer_id,ch.customer_name,ch.mobile,ch.relation_kind,l.body,l.created_at,
    upper(coalesce(a.role_code,'')) in('SUPER_ADMIN','OWNER')
  from public.rr_customer_chat_v9433 ch
  join public.rr_customer_chat_members_v9433 m on m.chat_id=ch.id and m.profile_id=a.id and m.is_active
  left join lateral(select mm.body,mm.created_at from public.rr_customer_chat_messages_v9433 mm
    where mm.chat_id=ch.id and mm.channel='GROUP' and mm.archived_at is null
    order by mm.created_at desc limit 1)l on true
  where ch.status='OPEN' and ch.relation_kind in('DIRECT_CUSTOMER','DISTRIBUTOR_REDZED')
  order by l.created_at desc nulls last,ch.customer_name,ch.updated_at desc;
end $$;
revoke all on function public.rr_chat_staff_inbox_v9704() from public,anon;
grant execute on function public.rr_chat_staff_inbox_v9704() to authenticated,service_role;

create or replace function public.rr_chat_customer_context_v9434(p_token text,p_mobile text)
returns table(share_id uuid,customer_id uuid,chat_id uuid,data_mode text,customer_name text)
language plpgsql security definer set search_path='public' as $$
declare s public.rr_market_share_v9420%rowtype;c public.rr_customers%rowtype;ch public.rr_customer_chat_v9433%rowtype;
 norm text:=regexp_replace(coalesce(p_mobile,''),'\\D','','g');
begin
 select ms.* into s from public.rr_market_share_v9420 ms where(ms.token=p_token or ms.short_code=upper(p_token))and ms.status='ACTIVE' order by case when ms.token=p_token then 0 else 1 end limit 1;
 if s.id is null then raise exception 'Share link unavailable.';end if;
 if s.customer_id is not null then select cu.* into c from public.rr_customers cu where cu.id=s.customer_id and cu.is_active limit 1;end if;
 if c.id is null and norm<>'' then select cu.* into c from public.rr_customers cu where regexp_replace(coalesce(cu.mobile,''),'\\D','','g')=norm and cu.is_active order by cu.updated_at desc nulls last limit 1;end if;
 if c.id is null then select cu.* into c from public.rr_market_requirements_v9420 r join public.rr_customers cu on cu.id=r.customer_id and cu.is_active where r.share_id=s.id order by r.submitted_at desc limit 1;end if;
 if c.id is null then raise exception 'Customer identity required.';end if;
 select cc.* into ch from public.rr_customer_chat_v9433 cc where cc.customer_id=c.id and cc.data_mode=s.data_mode and cc.relation_kind='DIRECT_CUSTOMER' order by cc.created_at limit 1;
 if ch.id is null then raise exception 'Customer chat not started.';end if;
 return query select s.id,c.id,ch.id,s.data_mode,c.customer_name;
end $$;

create or replace function public.rr_chat_customer_bootstrap_v9434(p_token text,p_customer_name text,p_mobile text)
returns jsonb language plpgsql security definer set search_path='public' as $$
declare s public.rr_market_share_v9420%rowtype;cj jsonb;cid uuid;ch uuid;creator_profile uuid;pair jsonb;
begin
 select * into s from public.rr_market_share_v9420 where(token=p_token or short_code=upper(p_token))and status='ACTIVE' order by case when token=p_token then 0 else 1 end limit 1;
 if s.id is null then raise exception 'Share link unavailable.';end if;
 cj:=public.rr_market_register_customer_v9423(p_customer_name,p_mobile);cid:=(cj->>'customer_id')::uuid;
 pair:=public.rr_ensure_contact_relation_chats_v9704(cid);ch:=(pair->>'customer_chat_id')::uuid;
 select id into creator_profile from public.rr_user_profiles where auth_user_id=s.created_by and is_active and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' order by updated_at desc nulls last limit 1;
 if creator_profile is not null then insert into public.rr_customer_chat_members_v9433(chat_id,profile_id,is_active,added_by)values(ch,creator_profile,true,creator_profile)on conflict(chat_id,profile_id)do update set is_active=true;end if;
 return jsonb_build_object('chat_id',ch,'customer_id',cid,'customer_name',cj->>'customer_name','mobile',cj->>'mobile','distributor_chat_id',pair->>'distributor_chat_id');
end $$;

create or replace function public.rr_market_partner_relation_chat_resolve_v67(p_owner_customer_id uuid,p_partner_customer_id uuid default null,p_relation_kind text default 'DISTRIBUTOR_CUSTOMER')
returns uuid language plpgsql security definer set search_path='' as $$
declare v_kind text:=upper(trim(coalesce(p_relation_kind,'')));v_chat uuid;v_name text;v_mobile text;
begin
 if v_kind not in('DISTRIBUTOR_CUSTOMER','DISTRIBUTOR_REDZED')then raise exception 'Invalid distributor chat relation.';end if;
 if v_kind='DISTRIBUTOR_REDZED' then
   return (public.rr_ensure_contact_relation_chats_v9704(p_owner_customer_id)->>'distributor_chat_id')::uuid;
 end if;
 select r.chat_id into v_chat from public.rr_market_partner_relation_chat_v67 r where r.owner_customer_id=p_owner_customer_id and r.partner_customer_id=p_partner_customer_id and r.relation_kind=v_kind and r.status='ACTIVE' limit 1;
 if v_chat is not null then return v_chat;end if;
 select c.private_name,c.private_mobile into v_name,v_mobile from public.rr_market_partner_customer_v67 c where c.id=p_partner_customer_id and c.owner_customer_id=p_owner_customer_id and c.status='ACTIVE' and c.data_mode='TEST';
 if v_name is null then raise exception 'Distributor customer relation is unavailable.';end if;
 insert into public.rr_customer_chat_v9433(customer_id,customer_name,mobile,data_mode,status,relation_kind)values(null,v_name,v_mobile,'TEST','OPEN','DISTRIBUTOR_CUSTOMER')returning id into v_chat;
 insert into public.rr_market_partner_relation_chat_v67(relation_kind,owner_customer_id,partner_customer_id,chat_id)values(v_kind,p_owner_customer_id,p_partner_customer_id,v_chat);
 return v_chat;
end $$;

-- Direct collection creation must never select the Distributor chat.
create or replace function public.rr_collection_create_first_v9587(p_customer_id uuid,p_lots text[],p_data_mode text default 'TEST')
returns jsonb language plpgsql security definer set search_path='public' as $$
declare dm text:=upper(coalesce(nullif(trim(p_data_mode),''),'TEST'));ch uuid;cn int;cy uuid;sj jsonb;sid uuid;disp text;actor uuid:=auth.uid();
begin
 perform public.rr_market_assert_sales_actor_v9420();
 if p_customer_id is null then raise exception 'Customer is required.';end if;
 if coalesce(array_length(p_lots,1),0)=0 then raise exception 'Select at least one lot.';end if;
 select id into ch from public.rr_customer_chat_v9433 where customer_id=p_customer_id and data_mode=dm and status='OPEN' and relation_kind='DIRECT_CUSTOMER' limit 1;
 if ch is null then raise exception 'Permanent customer chat is required before Collection creation.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_customer_id::text||'|'||dm,9587));
 select coalesce(max(collection_no),0)+1 into cn from public.rr_collection_cycle_v9586 where customer_id=p_customer_id and data_mode=dm;
 disp:='RZ COLLECTION '||lpad(cn::text,2,'0');
 insert into public.rr_collection_cycle_v9586(customer_id,chat_id,data_mode,collection_no,display_no,status,created_by)values(p_customer_id,ch,dm,cn,disp,'DRAFT',actor)returning id into cy;
 sj:=public.rr_market_create_share_v9420(p_lots,p_customer_id,(select customer_name from public.rr_customer_chat_v9433 where id=ch),dm);sid:=(sj->>'share_id')::uuid;
 insert into public.rr_collection_send_v9586(collection_cycle_id,share_id,send_seq,send_kind,sent_by)values(cy,sid,1,'FIRST',actor);
 update public.rr_collection_cycle_v9586 set status='SENT_NOT_OPENED'where id=cy;
 return sj||jsonb_build_object('collection_cycle_id',cy,'collection_no',cn,'collection_display_no',disp,'send_seq',1,'send_kind','FIRST','chat_id',ch);
end $$;

-- Future customer maintenance automatically returns both relation IDs.
create or replace function public.rr_sales_customer_relation_ids_v9704(p_customer_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin perform public.rr_assert_active_user_v1();return public.rr_ensure_contact_relation_chats_v9704(p_customer_id);end $$;
revoke all on function public.rr_sales_customer_relation_ids_v9704(uuid) from public,anon;
grant execute on function public.rr_sales_customer_relation_ids_v9704(uuid) to authenticated,service_role;

create or replace function public.rr_sales_customer_search_v9704(p_search text default null,p_limit integer default 30)
returns table(customer_id uuid,customer_name text,mobile text,address text,gstin text,dispatch_details text,
  allowed_discount_per_piece numeric,source_labels text[],chat_id uuid)
language sql stable security definer set search_path='' as $$
  select s.customer_id,s.customer_name,s.mobile,s.address,s.gstin,s.dispatch_details,
         s.allowed_discount_per_piece,s.source_labels,d.id
  from public.rr_sales_customer_search_v68(p_search,p_limit)s
  left join public.rr_customer_chat_v9433 d on d.customer_id=s.customer_id
    and d.data_mode='TEST' and d.status='OPEN' and d.relation_kind='DIRECT_CUSTOMER'
  order by s.customer_name;
$$;
revoke all on function public.rr_sales_customer_search_v9704(text,integer) from public,anon;
grant execute on function public.rr_sales_customer_search_v9704(text,integer) to authenticated,service_role;

create or replace function public.rr_chat_staff_create_invite_v9704(
  p_name text,p_mobiles text[],p_default_mobile text,p_kind text default 'CUSTOMER',p_prefix text default null
) returns jsonb language plpgsql security definer set search_path='public' as $$
declare a public.rr_user_profiles%rowtype;n text:=nullif(trim(p_name),'');k text:=upper(coalesce(nullif(trim(p_kind),''),'CUSTOMER'));
 d text:=regexp_replace(coalesce(p_default_mobile,''),'[^0-9+]','','g');m text;cid uuid;pair jsonb;
 t text:=encode(extensions.gen_random_bytes(24),'hex');sc text:=upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,10));
begin
 perform public.rr_assert_active_user_v1();a:=public.rr_chat_actor_profile_v9433();
 if upper(coalesce(a.role_code,'')) not in('SUPER_ADMIN','OWNER','ADMIN')then raise exception 'Admin or Superadmin permission required.';end if;
 if n is null or d='' or k not in('CUSTOMER','DISTRIBUTOR')then raise exception 'Valid name, type and default mobile are required.';end if;
 select id into cid from public.rr_customers where is_active and regexp_replace(coalesce(mobile,''),'[^0-9+]','','g')=d order by updated_at desc limit 1;
 if cid is null then insert into public.rr_customers(customer_name,mobile)values(n,d)returning id into cid;
 else update public.rr_customers set customer_name=n,mobile=d,updated_at=now()where id=cid;end if;
 pair:=public.rr_ensure_contact_relation_chats_v9704(cid);
 update public.rr_customer_contact_phone_v67 set is_default=false where customer_id=cid and data_mode='TEST';
 foreach m in array coalesce(p_mobiles,array[d])loop
   m:=regexp_replace(coalesce(m,''),'[^0-9+]','','g');
   if m<>''then insert into public.rr_customer_contact_phone_v67(customer_id,mobile,is_default)values(cid,m,m=d)
     on conflict(customer_id,mobile,data_mode)do update set is_default=excluded.is_default;end if;
 end loop;
 insert into public.rr_market_share_v9420(token,customer_id,customer_name,created_by,data_mode,status,short_code)
 values(t,cid,n,auth.uid(),'TEST','ACTIVE',sc);
 if k='DISTRIBUTOR'then perform public.rr_market_configure_distributor_v67(cid,coalesce(nullif(trim(p_prefix),''),'T67'));end if;
 return pair||jsonb_build_object('kind',k,'token',t,'short_code',sc,'data_mode','TEST');
end $$;
revoke all on function public.rr_chat_staff_create_invite_v9704(text,text[],text,text,text) from public,anon;
grant execute on function public.rr_chat_staff_create_invite_v9704(text,text[],text,text,text) to authenticated,service_role;
