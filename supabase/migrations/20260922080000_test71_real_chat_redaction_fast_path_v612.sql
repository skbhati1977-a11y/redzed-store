-- TEST71 V612: avoid recursively rebuilding the complete Real Chat history
-- when the canonical effective scope is already allowed to receive both
-- private costing and rate fields. Unauthorized roles keep the same recursive
-- server-side redaction. No business/history row is changed.
begin;

create or replace function public.rr_real_chat_redact_v401(p_payload jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760(null);
  v_allow_private boolean:=coalesce((v_scope->>'can_view_private_cost')::boolean,false);
  v_allow_rate boolean:=coalesce((v_scope->>'can_edit_rate')::boolean,false);
begin
  -- The payload is already the canonical authorized projection. Traversing
  -- thousands of nested history objects is redundant only when neither class
  -- of field needs removal. All other roles still use the recursive redactor.
  if v_allow_private and v_allow_rate then
    return coalesce(p_payload,'{}'::jsonb);
  end if;

  return public.rr_costing_redact_payload_v401(
    coalesce(p_payload,'{}'::jsonb),
    v_allow_private,
    v_allow_rate
  );
end
$function$;

revoke all on function public.rr_real_chat_redact_v401(jsonb) from public,anon;
grant execute on function public.rr_real_chat_redact_v401(jsonb) to authenticated,service_role;

comment on function public.rr_real_chat_redact_v401(jsonb) is
  'TEST71 V612 canonical Real Chat redaction: effective-scope fast path only when private cost and rate are both authorized; every other role remains recursively redacted.';

notify pgrst,'reload schema';
commit;
