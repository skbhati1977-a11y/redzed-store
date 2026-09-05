begin;

alter function public.rr_market_submit_requirement_v9508(text,text,text,text,jsonb,uuid)
  rename to rr_market_submit_requirement_v9508_legacy_v67;

revoke all on function public.rr_market_submit_requirement_v9508_legacy_v67(text,text,text,text,jsonb,uuid) from public, anon, authenticated;

create or replace function public.rr_market_submit_requirement_v9508(
  p_token text,
  p_customer_name text,
  p_mobile text,
  p_message text,
  p_lines jsonb,
  p_requirement_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if exists(
    select 1
    from public.rr_market_share_v9420 s
    join public.rr_market_partner_collection_v67 pc on pc.share_id=s.id
    join public.rr_market_partner_customer_v67 c on c.id=pc.partner_customer_id
    where (s.token=p_token or s.short_code=upper(p_token))
      and s.status='ACTIVE'
      and s.data_mode='TEST'
      and c.status='ACTIVE'
  ) then
    return public.rr_market_partner_submit_requirement_v67(
      p_token,
      p_customer_name,
      p_mobile,
      p_message,
      p_lines
    );
  end if;

  return public.rr_market_submit_requirement_v9508_legacy_v67(
    p_token,
    p_customer_name,
    p_mobile,
    p_message,
    p_lines,
    p_requirement_id
  );
end
$function$;

revoke all on function public.rr_market_submit_requirement_v9508(text,text,text,text,jsonb,uuid) from public;
grant execute on function public.rr_market_submit_requirement_v9508(text,text,text,text,jsonb,uuid) to anon, authenticated;

commit;
