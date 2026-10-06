CREATE OR REPLACE FUNCTION public.rr_collection_current_state_v9633(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cyid uuid; cy public.rr_collection_cycle_v9586%rowtype; n integer; cn integer; rn integer;
begin
  cyid:=public.rr_collection_cycle_for_share_v9631(p_token);
  select * into cy from public.rr_collection_cycle_v9586 where id=cyid;
  if cy.data_mode='TEST' and exists(select 1 from public.rr_customer_chat_v9433 ch where ch.id=cy.chat_id and ch.customer_id=cy.customer_id and ch.relation_kind='DIRECT_CUSTOMER') then
    select newest.id into cyid from public.rr_collection_cycle_v9586 newest left join lateral (select max(s.created_at) sent_at from public.rr_collection_send_v9586 cs join public.rr_market_share_v9420 s on s.id=cs.share_id where cs.collection_cycle_id=newest.id) latest on true where newest.chat_id=cy.chat_id and newest.customer_id=cy.customer_id and newest.data_mode='TEST' order by greatest(newest.created_at,coalesce(latest.sent_at,newest.created_at)) desc,newest.id desc limit 1;
    select * into cy from public.rr_collection_cycle_v9586 where id=cyid;
  end if;
  select greatest(
    coalesce((select max(update_no) from public.rr_collection_activity_v9633 where collection_cycle_id=cyid),0),
    coalesce((select max(update_no) from public.rr_collection_update_request_v9630 where collection_cycle_id=cyid),0)
  ) into n;
  select greatest(coalesce(max(send_seq),1)-1,0) into cn
  from public.rr_collection_send_v9586 where collection_cycle_id=cyid;
  select coalesce(max(r.requirement_update_no),0) into rn
  from public.rr_market_requirements_v9420 r where r.collection_cycle_id=cyid;
  return jsonb_build_object('collection_cycle_id',cy.id,'collection_display_no',cy.display_no,
    'collection_status',cy.status,'update_no',n,'collection_update_no',cn,'requirement_update_no',rn,'requirement_response_collection_update_no',coalesce((select greatest(coalesce((select max(cs.send_seq) from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=cy.id and cs.sent_at<=a.created_at),1)-1,0) from public.rr_collection_activity_v9633 a where a.collection_cycle_id=cy.id and a.activity_kind in('REQUIREMENT','REQUIREMENT_UPDATE') order by a.created_at desc,a.update_no desc limit 1),-1),'update_history',public.rr_direct_cycle_history_test71(cy.id))||public.rr_direct_cycle_live_meta_test71(cy.id)||jsonb_build_object('latest_collection_token',(select s.token from public.rr_collection_send_v9586 cs join public.rr_market_share_v9420 s on s.id=cs.share_id where cs.collection_cycle_id=cy.id and s.status='ACTIVE' order by cs.send_seq desc limit 1));
end $function$
