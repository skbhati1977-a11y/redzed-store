-- TEST67 chat allowlist: only owner/superadmin, admin, accounting and sales profiles.
update public.rr_customer_chat_members_v9433 m set is_active=false,removed_at=now()
where m.is_active and exists(
 select 1 from public.rr_customer_chat_v9433 ch join public.rr_user_profiles p on p.id=m.profile_id
 where ch.id=m.chat_id and ch.data_mode='TEST'
 and upper(coalesce(p.role_code,'')) not in('SUPER_ADMIN','OWNER','ADMIN','ACCOUNTANT','ACCOUNTS','ACCOUNT','SALES','SALESMAN'));

update public.rr_customer_chat_worker_members_v9439 m set is_active=false
where m.is_active and exists(select 1 from public.rr_customer_chat_v9433 ch where ch.id=m.chat_id and ch.data_mode='TEST');

create or replace function public.rr_chat_staff_inbox_v9434()
returns table(chat_id uuid,customer_name text,mobile text,last_message text,last_message_at timestamptz,can_private_chat boolean)
language plpgsql stable security definer set search_path=public as $$
declare a public.rr_user_profiles%rowtype;
begin
 perform public.rr_assert_active_user_v1();a:=public.rr_chat_actor_profile_v9433();
 if upper(coalesce(a.role_code,'')) not in('SUPER_ADMIN','OWNER','ADMIN','ACCOUNTANT','ACCOUNTS','ACCOUNT','SALES','SALESMAN')then raise exception 'Sales chat access denied.';end if;
 return query select ch.id,ch.customer_name,ch.mobile,l.body,l.created_at,upper(coalesce(a.role_code,''))in('SUPER_ADMIN','OWNER')
 from public.rr_customer_chat_v9433 ch join public.rr_customer_chat_members_v9433 m on m.chat_id=ch.id and m.profile_id=a.id and m.is_active
 left join lateral(select mm.body,mm.created_at from public.rr_customer_chat_messages_v9433 mm where mm.chat_id=ch.id and mm.channel='GROUP'and mm.archived_at is null order by mm.created_at desc limit 1)l on true
 where ch.status='OPEN' order by l.created_at desc nulls last,ch.updated_at desc;
end$$;

create or replace function public.rr_chat_set_member_v9433(p_chat_id uuid,p_profile_id uuid,p_active boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare a public.rr_user_profiles%rowtype;target_role text;chat_mode text;
begin
 perform public.rr_chat_assert_superadmin_v9433();a:=public.rr_chat_actor_profile_v9433();
 select upper(coalesce(p.role_code,''))into target_role from public.rr_user_profiles p where p.id=p_profile_id and p.is_active and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE';
 select upper(coalesce(ch.data_mode,''))into chat_mode from public.rr_customer_chat_v9433 ch where ch.id=p_chat_id;
 if chat_mode='TEST'and p_active and coalesce(target_role,'')not in('SUPER_ADMIN','OWNER','ADMIN','ACCOUNTANT','ACCOUNTS','ACCOUNT','SALES','SALESMAN')then raise exception 'This role is not allowed in TEST67 customer chat.';end if;
 insert into public.rr_customer_chat_members_v9433(chat_id,profile_id,is_active,added_by,removed_by,removed_at)
 values(p_chat_id,p_profile_id,p_active,a.id,case when p_active then null else a.id end,case when p_active then null else now()end)
 on conflict(chat_id,profile_id)do update set is_active=excluded.is_active,removed_by=excluded.removed_by,removed_at=excluded.removed_at,added_by=case when excluded.is_active then a.id else rr_customer_chat_members_v9433.added_by end,added_at=case when excluded.is_active then now()else rr_customer_chat_members_v9433.added_at end;
 return jsonb_build_object('ok',true,'active',p_active);
end$$;

create or replace function public.rr_chat_staff_directory_v9434(p_chat_id uuid)
returns table(profile_id uuid,full_name text,is_member boolean,is_active boolean,can_private_chat boolean)
language plpgsql stable security definer set search_path=public as $$
declare chat_mode text;
begin
 perform public.rr_chat_assert_superadmin_v9433();select upper(coalesce(data_mode,''))into chat_mode from public.rr_customer_chat_v9433 where id=p_chat_id;
 return query select p.id,p.full_name,coalesce(m.is_active,false),p.is_active and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE',upper(coalesce(p.role_code,''))in('SUPER_ADMIN','OWNER')
 from public.rr_user_profiles p left join public.rr_customer_chat_members_v9433 m on m.chat_id=p_chat_id and m.profile_id=p.id
 where (chat_mode<>'TEST'and upper(coalesce(p.role_code,''))in('SALES','SALESMAN','ADMIN','ACCOUNTANT','ACCOUNTS','ACCOUNT','SUPER_ADMIN','OWNER'))
 or(chat_mode='TEST'and upper(coalesce(p.role_code,''))in('SUPER_ADMIN','OWNER','ADMIN','ACCOUNTANT','ACCOUNTS','ACCOUNT','SALES','SALESMAN'))order by 2;
end$$;

revoke all on function public.rr_chat_staff_inbox_v9434()from public,anon;
revoke all on function public.rr_chat_set_member_v9433(uuid,uuid,boolean)from public,anon;
revoke all on function public.rr_chat_staff_directory_v9434(uuid)from public,anon;
grant execute on function public.rr_chat_staff_inbox_v9434()to authenticated,service_role;
grant execute on function public.rr_chat_set_member_v9433(uuid,uuid,boolean)to authenticated,service_role;
grant execute on function public.rr_chat_staff_directory_v9434(uuid)to authenticated,service_role;
