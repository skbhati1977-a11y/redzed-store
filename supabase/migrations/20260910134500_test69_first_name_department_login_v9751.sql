begin;

-- Username identity is first-name.department. Existing duplicate identities
-- receive a stable numeric suffix in profile-id order.
update public.rr_user_profiles
set login_username='__v9751__.'||id::text;

do $block$
declare r record; v_base text; v_candidate text; v_n integer;
begin
  for r in
    select id,split_part(trim(full_name),' ',1) first_name,
      coalesce(nullif(department_code,''),nullif(role_code,''),'user') department_code
    from public.rr_user_profiles order by id
  loop
    v_base:=trim(both '.' from regexp_replace(lower(trim(r.first_name)||'.'||trim(r.department_code)),'[^a-z0-9]+','.','g'));
    v_candidate:=v_base; v_n:=2;
    while exists(select 1 from public.rr_user_profiles p where lower(p.login_username)=lower(v_candidate) and p.id<>r.id) loop
      v_candidate:=v_base||'.'||v_n; v_n:=v_n+1;
    end loop;
    update public.rr_user_profiles set login_username=v_candidate where id=r.id;
  end loop;
end $block$;

create or replace function public.rr_assign_login_username_v9750() returns trigger
language plpgsql security invoker set search_path='public' as $function$
declare v_base text; v_candidate text; v_n integer:=2;
begin
  if nullif(trim(new.login_username),'') is not null then
    new.login_username:=lower(trim(new.login_username)); return new;
  end if;
  v_base:=trim(both '.' from regexp_replace(lower(split_part(trim(new.full_name),' ',1)||'.'||trim(coalesce(nullif(new.department_code,''),nullif(new.role_code,''),'user'))),'[^a-z0-9]+','.','g'));
  perform pg_advisory_xact_lock(hashtext('RR_LOGIN_USERNAME:'||v_base));
  v_candidate:=v_base;
  while exists(select 1 from public.rr_user_profiles p where lower(p.login_username)=lower(v_candidate) and p.id<>new.id) loop
    v_candidate:=v_base||'.'||v_n; v_n:=v_n+1;
  end loop;
  new.login_username:=v_candidate; return new;
end $function$;

commit;
