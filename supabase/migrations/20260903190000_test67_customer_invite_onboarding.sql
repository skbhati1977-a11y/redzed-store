-- TEST67 direct customer/distributor invite. Additive; REAL mode is never accepted.
create table if not exists public.rr_customer_contact_phone_v67(
 id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.rr_customers(id) on delete cascade,
 mobile text not null,is_default boolean not null default false,data_mode text not null default 'TEST' check(data_mode='TEST'),created_at timestamptz not null default now(),unique(customer_id,mobile,data_mode));
create unique index if not exists rr_customer_contact_phone_v67_default on public.rr_customer_contact_phone_v67(customer_id,data_mode) where is_default;
alter table public.rr_customer_contact_phone_v67 enable row level security;
revoke all on public.rr_customer_contact_phone_v67 from public,anon,authenticated;
grant all on public.rr_customer_contact_phone_v67 to service_role;

create or replace function public.rr_chat_staff_create_invite_v67(p_name text,p_mobiles text[],p_default_mobile text,p_kind text default 'CUSTOMER',p_prefix text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare a public.rr_user_profiles%rowtype;n text:=nullif(trim(p_name),'');k text:=upper(coalesce(nullif(trim(p_kind),''),'CUSTOMER'));
 d text:=regexp_replace(coalesce(p_default_mobile,''),'[^0-9+]','','g');m text;cid uuid;ch uuid;t text:=encode(extensions.gen_random_bytes(24),'hex');sc text:=upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,10));
begin
 perform public.rr_assert_active_user_v1();a:=public.rr_chat_actor_profile_v9433();
 if upper(coalesce(a.role_code,'')) not in('SALES','SALESMAN','ADMIN','SUPER_ADMIN','OWNER') then raise exception 'Customer invite permission denied.';end if;
 if n is null or d='' or k not in('CUSTOMER','DISTRIBUTOR') then raise exception 'Valid name, type and default mobile are required.';end if;
 if k='DISTRIBUTOR' then perform public.rr_market_superadmin_required_v61();end if;
 select id into cid from public.rr_customers where is_active and regexp_replace(coalesce(mobile,''),'[^0-9+]','','g')=d order by updated_at desc limit 1;
 if cid is null then insert into public.rr_customers(customer_name,mobile)values(n,d)returning id into cid;else update public.rr_customers set customer_name=n,mobile=d,updated_at=now()where id=cid;end if;
 update public.rr_customer_contact_phone_v67 set is_default=false where customer_id=cid and data_mode='TEST';
 foreach m in array coalesce(p_mobiles,array[d]) loop m:=regexp_replace(coalesce(m,''),'[^0-9+]','','g');if m<>'' then insert into public.rr_customer_contact_phone_v67(customer_id,mobile,is_default)values(cid,m,m=d)on conflict(customer_id,mobile,data_mode)do update set is_default=excluded.is_default;end if;end loop;
 update public.rr_customer_contact_phone_v67 set is_default=(mobile=d)where customer_id=cid and data_mode='TEST';
 insert into public.rr_customer_chat_v9433(customer_id,customer_name,mobile,data_mode,status)values(cid,n,d,'TEST','OPEN')on conflict(customer_id,data_mode)do update set customer_name=excluded.customer_name,mobile=excluded.mobile,status='OPEN',updated_at=now()returning id into ch;
 insert into public.rr_customer_chat_members_v9433(chat_id,profile_id,is_active,added_by)values(ch,a.id,true,a.id)on conflict(chat_id,profile_id)do update set is_active=true,removed_at=null;
 insert into public.rr_customer_chat_members_v9433(chat_id,profile_id,is_active,added_by)select ch,p.id,true,a.id from public.rr_user_profiles p where p.is_active and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'and upper(coalesce(p.role_code,''))in('SUPER_ADMIN','OWNER')on conflict(chat_id,profile_id)do update set is_active=true,removed_at=null;
 insert into public.rr_market_share_v9420(token,customer_id,customer_name,created_by,data_mode,status,short_code)values(t,cid,n,auth.uid(),'TEST','ACTIVE',sc);
 if k='DISTRIBUTOR'then perform public.rr_market_configure_distributor_v67(cid,coalesce(nullif(trim(p_prefix),''),'T67'));end if;
 return jsonb_build_object('customer_id',cid,'chat_id',ch,'kind',k,'token',t,'short_code',sc,'data_mode','TEST');
end$$;
revoke all on function public.rr_chat_staff_create_invite_v67(text,text[],text,text,text)from public,anon;
grant execute on function public.rr_chat_staff_create_invite_v67(text,text[],text,text,text)to authenticated,service_role;
