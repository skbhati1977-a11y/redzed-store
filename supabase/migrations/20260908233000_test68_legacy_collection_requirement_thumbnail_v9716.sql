-- TEST68: give legacy direct Customer Collection / Requirement chat records
-- the canonical share token needed by the first-image card renderer.
-- Scope is intentionally limited to recognized market workflow sources.

update public.rr_customer_chat_messages_v9433 m
set payload = coalesce(m.payload, '{}'::jsonb) || jsonb_build_object(
  'market_share_id', s.id,
  'share_token', s.token,
  'share_short_code', s.short_code
)
from public.rr_market_share_v9420 s
where m.archived_at is null
  and upper(coalesce(m.payload->>'source', '')) in ('MARKET_WINDOW', 'MARKET_REQUIREMENT')
  and s.id = coalesce(
    nullif(m.payload->>'market_share_id', '')::uuid,
    nullif(m.payload->>'share_id', '')::uuid
  )
  and s.status = 'ACTIVE';

-- Older Collection messages may only contain the public share URL. Resolve its
-- token/short code without touching unrelated LINK messages.
update public.rr_customer_chat_messages_v9433 m
set payload = coalesce(m.payload, '{}'::jsonb) || jsonb_build_object(
  'market_share_id', s.id,
  'share_token', s.token,
  'share_short_code', s.short_code
)
from public.rr_market_share_v9420 s
where m.archived_at is null
  and upper(coalesce(m.payload->>'source', '')) = 'MARKET_WINDOW'
  and coalesce(m.payload->>'market_share_id', m.payload->>'share_id', '') = ''
  and (
    coalesce(m.payload->>'url', '') like '%' || s.token || '%'
    or coalesce(m.payload->>'url', '') ilike '%c=' || s.short_code || '%'
  )
  and s.status = 'ACTIVE';
