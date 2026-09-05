-- TEST67 shared chat hardening: remove token-only legacy chat entry points,
-- add FK lookup indexes, and avoid PostgreSQL's 63-byte identifier truncation.

alter function public.rr_market_partner_customer_chat_disappearing_cleanup_session_v6(text,text)
  rename to rr_mp_customer_chat_disappear_cleanup_v67;

create index if not exists rr_mp_customer_session_owner_v67_idx
  on public.rr_market_partner_customer_session_v67(owner_customer_id);
create index if not exists rr_mp_customer_session_customer_v67_idx
  on public.rr_market_partner_customer_session_v67(partner_customer_id);
create index if not exists rr_mp_customer_session_relation_v67_idx
  on public.rr_market_partner_customer_session_v67(relation_chat_id);
create index if not exists rr_mp_customer_session_chat_v67_idx
  on public.rr_market_partner_customer_session_v67(chat_id);
create index if not exists rr_mp_customer_session_share_v67_idx
  on public.rr_market_partner_customer_session_v67(share_id);
create index if not exists rr_mp_relation_chat_customer_v67_idx
  on public.rr_market_partner_relation_chat_v67(partner_customer_id)
  where partner_customer_id is not null;

revoke all on function public.rr_market_partner_customer_chat_messages_lane_v67(text,text)
  from public,anon,authenticated;
revoke all on function public.rr_market_partner_customer_chat_send_lane_v67(text,text,text,jsonb)
  from public,anon,authenticated;
revoke all on function public.rr_market_partner_customer_chat_messages_v67(text)
  from public,anon,authenticated;
revoke all on function public.rr_market_partner_customer_chat_send_v67(text,text,jsonb)
  from public,anon,authenticated;

grant execute on function public.rr_market_partner_customer_chat_messages_lane_v67(text,text)
  to service_role;
grant execute on function public.rr_market_partner_customer_chat_send_lane_v67(text,text,text,jsonb)
  to service_role;
grant execute on function public.rr_market_partner_customer_chat_messages_v67(text)
  to service_role;
grant execute on function public.rr_market_partner_customer_chat_send_v67(text,text,jsonb)
  to service_role;

revoke all on function public.rr_mp_customer_chat_disappear_cleanup_v67(text,text) from public;
grant execute on function public.rr_mp_customer_chat_disappear_cleanup_v67(text,text)
  to anon,authenticated,service_role;
