-- TEST71 CB Department V604: V713 uses this established helper directly.
-- Keep that creator intact while resolving authority through the canonical
-- effective identity (including Super Admin and Act As restrictions).

create or replace function public.rr_is_owner_or_admin()
returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_identity jsonb;
  v_role text;
begin
  if auth.uid() is null then return false; end if;
  v_identity:=public.rr_upm_effective_identity_v200();
  v_role:=upper(coalesce(v_identity->>'role_code',v_identity->>'resolved_role',''));
  return v_role in('OWNER','SUPER_ADMIN','ADMIN');
end;
$$;

comment on function public.rr_is_owner_or_admin() is
  'Canonical effective Owner/Super Admin/Admin authority used by the existing V713 CB creator.';
