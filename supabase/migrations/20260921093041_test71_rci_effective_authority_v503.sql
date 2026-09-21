-- RCI is a post-CI canonical Sales/Accounts action. Apply the same effective
-- Act As authority boundary and include the canonical SUPER_ADMIN role.
create or replace function public.rr_rci_assert_role_v9746()
returns void language plpgsql security definer set search_path=public as $$
declare identity_json jsonb; effective_role text;
begin
  perform public.rr_fg_assert_user_v787();
  identity_json:=public.rr_upm_effective_identity_v200();
  effective_role:=upper(coalesce(identity_json->>'resolved_role',identity_json->>'role_code','WORKER'));
  if effective_role not in('OWNER','SUPER_ADMIN','ADMIN','SALES','ACCOUNTS') then
    raise exception 'Owner/Super Admin/Admin/Sales/Accounts access required.';
  end if;
end $$;
