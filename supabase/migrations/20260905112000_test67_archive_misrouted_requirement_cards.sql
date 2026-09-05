begin;

update public.rr_customer_chat_messages_v9433 m
set archived_at=coalesce(m.archived_at,clock_timestamp()),
    archive_reason='TEST67_PARTNER_ROUTE_CORRECTION',
    archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object(
      'reason','Partner customer requirement must remain with distributor until distributor pushes it to REDZED.',
      'corrected_at',clock_timestamp()
    )
where m.archived_at is null
  and m.message_type='REQUIREMENT'
  and m.payload->>'source'='MARKET_REQUIREMENT'
  and exists(
    select 1
    from public.rr_market_partner_collection_v67 pc
    join public.rr_market_share_v9420 s on s.id=pc.share_id
    where pc.share_id=(m.payload->>'share_id')::uuid
      and s.data_mode='TEST'
  );

commit;
