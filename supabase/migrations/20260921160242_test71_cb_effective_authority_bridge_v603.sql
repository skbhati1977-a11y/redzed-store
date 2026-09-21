-- TEST71 CB Department V603: the reused V713 CB creator delegates to the
-- shared Product admin gate. Resolve that gate through the same canonical
-- effective identity as CB Department so duplicate profile rows cannot make
-- authority nondeterministic and Act As Worker remains intentionally blocked.

create or replace function public.rr_product_require_admin_v1()
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_identity jsonb;
  v_role text;
begin
  if auth.uid() is null then return; end if;
  v_identity:=public.rr_upm_effective_identity_v200();
  v_role:=upper(coalesce(v_identity->>'role_code',v_identity->>'resolved_role',''));
  if v_role not in('OWNER','SUPER_ADMIN','ADMIN') then
    raise exception 'Owner/Admin permission is required' using errcode='42501';
  end if;
end;
$$;

comment on function public.rr_product_require_admin_v1() is
  'Shared Product/CB/MC1 admin gate using canonical effective identity; Act As authority is enforced.';
