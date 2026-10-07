-- Retain only the most recent workflow card of each kind for a latest closed cycle.
WITH candidates AS(
 SELECT m.id,c.status,row_number() OVER(PARTITION BY c.id,m.message_type ORDER BY m.created_at DESC,m.id DESC) rn
 FROM public.rr_customer_chat_messages_v9433 m JOIN public.rr_collection_cycle_v9586 c ON c.id::text=m.payload->>'direct_collection_cycle_id'
 WHERE c.data_mode='TEST' AND c.closed_at IS NOT NULL AND m.archive_reason='ONE_OPEN_COLLECTION_RULE_CLEANUP' AND m.message_type IN('LINK','REQUIREMENT','ATTACHMENT') AND coalesce(m.payload->>'source','')<>'DIRECT_CATEGORY_REQUEST_TEST71'
 AND NOT EXISTS(SELECT 1 FROM public.rr_collection_cycle_v9586 nc JOIN public.rr_collection_send_v9586 cs ON cs.collection_cycle_id=nc.id WHERE nc.customer_id=c.customer_id AND nc.data_mode='TEST' AND nc.collection_no>c.collection_no)
)
UPDATE public.rr_customer_chat_messages_v9433 m SET archived_at=NULL,archive_reason=NULL,payload=coalesce(m.payload,'{}'::jsonb)||jsonb_build_object('read_only',true,'collection_status',c.status),archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('restored_latest_readonly_card',true) FROM candidates c WHERE m.id=c.id AND c.rn=1;
