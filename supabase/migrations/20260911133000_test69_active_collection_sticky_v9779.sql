-- V9779: one compact active-Collection row and sent-lot filtering for direct chat.
create or replace function public.rr_direct_collection_active_v9779(p_chat_id uuid)
returns jsonb language plpgsql stable security definer set search_path='public' as $$
declare cy public.rr_collection_cycle_v9586%rowtype; msg record; lots jsonb; updates jsonb;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  select c.* into cy from public.rr_collection_cycle_v9586 c where c.chat_id=p_chat_id and c.data_mode='TEST'
    and c.status not in('CLOSED','CLOSED_NO_RESPONSE','CANCELLED')
  order by greatest(c.created_at,coalesce(c.opened_at,c.created_at)) desc,c.collection_no desc limit 1;
  if cy.id is null then return jsonb_build_object('active',false); end if;
  select m.id,m.created_at,m.payload->>'url' url into msg from public.rr_customer_chat_messages_v9433 m
  where m.chat_id=p_chat_id and m.archived_at is null and m.payload->>'direct_collection_cycle_id'=cy.id::text
  order by m.created_at desc,m.id desc limit 1;
  select coalesce(jsonb_agg(distinct l.lot_no order by l.lot_no),'[]'::jsonb) into lots
  from public.rr_collection_send_v9586 cs join public.rr_market_share_lots_v9420 l on l.share_id=cs.share_id
  where cs.collection_cycle_id=cy.id;
  select coalesce(jsonb_agg(jsonb_build_object('update_no',cs.send_seq-1,'kind',cs.send_kind,'sent_at',cs.sent_at,
    'lots',(select jsonb_agg(l.lot_no order by l.sort_no) from public.rr_market_share_lots_v9420 l where l.share_id=cs.share_id))
    order by cs.send_seq desc),'[]'::jsonb) into updates
  from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=cy.id;
  return jsonb_build_object('active',true,'collection_cycle_id',cy.id,'collection_no',cy.collection_no,
    'collection_display_no',cy.display_no,'status',cy.status,'update_no',greatest(jsonb_array_length(updates)-1,0),
    'last_updated_at',coalesce(msg.created_at,(select max(sent_at) from public.rr_collection_send_v9586 where collection_cycle_id=cy.id),cy.created_at),
    'chat_message_id',msg.id,'url',msg.url,'sent_lots',lots,'updates',updates);
end $$;
revoke all on function public.rr_direct_collection_active_v9779(uuid) from public,anon;
grant execute on function public.rr_direct_collection_active_v9779(uuid) to authenticated,service_role;
