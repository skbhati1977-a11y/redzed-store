create or replace function public.rr_user_profiles_owner_guard_v772()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_actor_role text;
  v_security_changed boolean:=false;
  v_owner_count integer;
  v_admin_controller boolean:=false;
begin
  select lower(coalesce(p.role_code,'')) into v_actor_role
  from public.rr_user_profiles p
  where p.auth_user_id=auth.uid()
    and coalesce(p.is_active,false)
    and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  limit 1;
  v_admin_controller:=coalesce(v_actor_role,'') in ('owner','super_admin','superadmin');

  if tg_op='INSERT' then
    if lower(coalesce(new.role_code,''))='owner' then
      select count(*) into v_owner_count from public.rr_user_profiles p where lower(coalesce(p.role_code,''))='owner';
      if v_owner_count>0 then raise exception 'Second OWNER create nahi ho sakta. Existing OWNER protected hai.'; end if;
    elsif lower(coalesce(new.role_code,'')) in ('admin','super_admin','superadmin') and not v_admin_controller then
      raise exception 'Sirf OWNER/SUPER ADMIN naya ADMIN create/promote kar sakta hai.';
    end if;
    return new;
  end if;

  if tg_op='DELETE' then
    if lower(coalesce(old.role_code,''))='owner' then raise exception 'OWNER delete nahi ho sakta.'; end if;
    if lower(coalesce(old.role_code,'')) in ('admin','super_admin','superadmin') and not v_admin_controller then
      raise exception 'Sirf OWNER/SUPER ADMIN ADMIN ko delete/deactivate control kar sakta hai.';
    end if;
    return old;
  end if;

  v_security_changed:=lower(coalesce(old.role_code,'')) is distinct from lower(coalesce(new.role_code,''))
    or coalesce(old.is_active,false) is distinct from coalesce(new.is_active,false)
    or upper(coalesce(old.access_status,'ACTIVE')) is distinct from upper(coalesce(new.access_status,'ACTIVE'))
    or old.auth_user_id is distinct from new.auth_user_id;

  if lower(coalesce(old.role_code,''))='owner' then
    if v_security_changed then raise exception 'OWNER security lock: role, active status, access status aur auth identity change nahi ho sakti.'; end if;
    return new;
  end if;
  if lower(coalesce(new.role_code,''))='owner' then raise exception 'Existing OWNER ke hote hue kisi User ko OWNER promote nahi kar sakte.'; end if;
  if (lower(coalesce(old.role_code,'')) in ('admin','super_admin','superadmin')
      or lower(coalesce(new.role_code,'')) in ('admin','super_admin','superadmin'))
     and v_security_changed and not v_admin_controller then
    raise exception 'Sirf OWNER/SUPER ADMIN ADMIN ka role/status/access control kar sakta hai.';
  end if;
  return new;
end $function$;
