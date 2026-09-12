begin;

alter table public.rr_user_profiles add column if not exists login_username text;

do $block$
declare r record; v_base text; v_candidate text; v_n integer;
begin
  for r in select id,full_name,coalesce(nullif(department_code,''),nullif(role_code,''),'user') department_code
    from public.rr_user_profiles where login_username is null order by created_at nulls first,id
  loop
    v_base:=trim(both '.' from regexp_replace(lower(trim(r.full_name)||'.'||trim(r.department_code)),'[^a-z0-9]+','.','g'));
    v_candidate:=v_base; v_n:=2;
    while exists(select 1 from public.rr_user_profiles p where lower(p.login_username)=lower(v_candidate) and p.id<>r.id) loop
      v_candidate:=v_base||'.'||v_n; v_n:=v_n+1;
    end loop;
    update public.rr_user_profiles set login_username=v_candidate where id=r.id;
  end loop;
end $block$;

create unique index if not exists rr_user_profiles_login_username_v9750
  on public.rr_user_profiles(lower(login_username)) where login_username is not null;

create or replace function public.rr_assign_login_username_v9750() returns trigger
language plpgsql security invoker set search_path='public' as $function$
declare v_base text; v_candidate text; v_n integer:=2;
begin
  if nullif(trim(new.login_username),'') is not null then
    new.login_username:=lower(trim(new.login_username)); return new;
  end if;
  v_base:=trim(both '.' from regexp_replace(lower(trim(new.full_name)||'.'||trim(coalesce(nullif(new.department_code,''),nullif(new.role_code,''),'user'))),'[^a-z0-9]+','.','g'));
  perform pg_advisory_xact_lock(hashtext('RR_LOGIN_USERNAME:'||v_base));
  v_candidate:=v_base;
  while exists(select 1 from public.rr_user_profiles p where lower(p.login_username)=lower(v_candidate) and p.id<>new.id) loop
    v_candidate:=v_base||'.'||v_n; v_n:=v_n+1;
  end loop;
  new.login_username:=v_candidate; return new;
end $function$;

drop trigger if exists rr_assign_login_username_v9750 on public.rr_user_profiles;
create trigger rr_assign_login_username_v9750 before insert or update of full_name,department_code,role_code,login_username
on public.rr_user_profiles for each row execute function public.rr_assign_login_username_v9750();

create or replace function public.rr_internal_login_target_v9750(p_identifier text) returns uuid
language sql security definer set search_path='public' as $function$
  select p.auth_user_id from public.rr_user_profiles p
  where p.auth_user_id is not null and p.is_active and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
    and (lower(p.login_username)=lower(trim(p_identifier))
      or right(regexp_replace(coalesce(p.mobile,''),'[^0-9]','','g'),10)=right(regexp_replace(coalesce(p_identifier,''),'[^0-9]','','g'),10))
    and (lower(p.login_username)=lower(trim(p_identifier)) or length(regexp_replace(coalesce(p_identifier,''),'[^0-9]','','g'))>=10)
  order by p.updated_at desc nulls last limit 1
$function$;

revoke all on function public.rr_internal_login_target_v9750(text) from public,anon,authenticated;
grant execute on function public.rr_internal_login_target_v9750(text) to service_role;

commit;
