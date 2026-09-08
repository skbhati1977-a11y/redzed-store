create or replace function public.rr_chat_staff_inbox_v9434()
returns table(
  chat_id uuid,
  customer_name text,
  mobile text,
  last_message text,
  last_message_at timestamptz,
  can_private_chat boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  a public.rr_user_profiles%rowtype;
begin
  perform public.rr_assert_active_user_v1();
  a := public.rr_chat_actor_profile_v9433();

  if upper(coalesce(a.role_code, '')) not in (
    'SUPER_ADMIN', 'OWNER', 'ADMIN', 'ACCOUNTANT', 'ACCOUNTS',
    'ACCOUNT', 'SALES', 'SALESMAN'
  ) then
    raise exception 'Sales chat access denied.';
  end if;

  return query
  select
    ch.id,
    ch.customer_name,
    ch.mobile,
    l.body,
    l.created_at,
    upper(coalesce(a.role_code, '')) in ('SUPER_ADMIN', 'OWNER')
  from public.rr_customer_chat_v9433 ch
  join public.rr_customer_chat_members_v9433 m
    on m.chat_id = ch.id
   and m.profile_id = a.id
   and m.is_active
  left join lateral (
    select mm.body, mm.created_at
    from public.rr_customer_chat_messages_v9433 mm
    where mm.chat_id = ch.id
      and mm.channel = 'GROUP'
      and mm.archived_at is null
    order by mm.created_at desc
    limit 1
  ) l on true
  where ch.status = 'OPEN'
    and not exists (
      select 1
      from public.rr_market_partner_relation_chat_v67 rc
      where rc.chat_id = ch.id
        and rc.status = 'ACTIVE'
        and rc.relation_kind = 'DISTRIBUTOR_CUSTOMER'
        and rc.data_mode = ch.data_mode
    )
  order by l.created_at desc nulls last, ch.updated_at desc;
end
$function$;

revoke all on function public.rr_chat_staff_inbox_v9434() from public, anon;
grant execute on function public.rr_chat_staff_inbox_v9434() to authenticated, service_role;
