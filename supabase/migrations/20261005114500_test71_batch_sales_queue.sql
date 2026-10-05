-- Isolated TEST71 queue; keep production v500 unchanged.
create or replace function public.rr_sales_real_chat_queue_test71(p_status text default 'OPEN',p_search text default null,p_data_mode text default 'TEST')
returns jsonb language plpgsql stable security definer set search_path='' set jit=off as $$
declare s text:=upper(coalesce(p_status,'OPEN')); rows_json jsonb;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 if upper(coalesce(p_data_mode,''))<>'TEST' then raise exception 'TEST scope required';end if;
 if s not in('OPEN','WORKING','CLOSE') then raise exception 'OPEN / WORKING / CLOSE required';end if;
 if s<>'OPEN' then return public.rr_sales_real_chat_queue_v500(s,p_search,'TEST');end if;
 with cycles as materialized (
 select c.*,ch.customer_name chat_customer_name from public.rr_collection_cycle_v9586 c
 left join public.rr_customer_chat_v9433 ch on ch.id=c.chat_id
 where c.data_mode='TEST' and c.status not in('CLOSED','CLOSED_NO_RESPONSE','CANCELLED')
 ), roots as (
 select coalesce(r.root_requirement_id,r.id) root_id,max(r.requirement_display_no) requirement_no,max(r.pi_generated_at) pi_generated_at
 from public.rr_market_requirements_v9420 r group by coalesce(r.root_requirement_id,r.id)
 ), meta as (
 select l.collection_cycle_id,max(r.requirement_no) requirement_no,max(r.pi_generated_at) pi_generated_at
 from public.rr_collection_requirement_link_v9586 l join cycles c on c.id=l.collection_cycle_id
 join roots r on r.root_id=l.requirement_id group by l.collection_cycle_id
 ), eligible as materialized (
 select c.*,m.requirement_no from cycles c left join meta m on m.collection_cycle_id=c.id where m.pi_generated_at is null
 ), ranked as (
 select l.collection_cycle_id,ml.lot_no,ml.accepted_qty,
 row_number() over(partition by l.collection_cycle_id,ml.lot_no order by coalesce(a.update_no,0) desc,r.submitted_at desc,r.id desc) rn
 from eligible c join public.rr_collection_requirement_link_v9586 l on l.collection_cycle_id=c.id
 join public.rr_market_requirements_v9420 r on r.id=l.requirement_id
 left join public.rr_collection_activity_v9633 a on a.collection_cycle_id=l.collection_cycle_id and a.reference_id=l.requirement_id and a.activity_kind in('REQUIREMENT','REQUIREMENT_UPDATE')
 join public.rr_market_requirement_lines_v9420 ml on ml.requirement_id=r.id
 ), qty as (
 select collection_cycle_id,coalesce(sum(accepted_qty),0) present_qty from ranked where rn=1 group by collection_cycle_id
 ), sends as (
 select cs.collection_cycle_id,coalesce(max(cs.send_seq)-1,0) update_no,max(cs.sent_at) last_update
 from public.rr_collection_send_v9586 cs join eligible c on c.id=cs.collection_cycle_id group by cs.collection_cycle_id
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'card_type','COLLECTION_FOLLOWUP','customer',c.chat_customer_name,
 'collection_no',c.display_no,'collection_update_no',coalesce(z.update_no,0),'requirement_no',c.requirement_no,
 'present_qty',coalesce(q.present_qty,0),'present_amount',0,'all_qty',coalesce(q.present_qty,0),'all_amount',0,
 'last_update',coalesce(z.last_update,c.created_at),'current_status',c.status,'chat_id',c.chat_id)
 order by coalesce(z.last_update,c.created_at) desc),'[]'::jsonb) into rows_json
 from eligible c left join qty q on q.collection_cycle_id=c.id left join sends z on z.collection_cycle_id=c.id
 where nullif(trim(p_search),'') is null or concat_ws(' ',c.chat_customer_name,c.display_no,c.requirement_no) ilike '%'||trim(p_search)||'%';
 return jsonb_build_object('version','TEST71_BATCH_SALES_QUEUE','status',s,'cards',rows_json,
 'market_window','real-web-window-v9329.html','direct_pi','real-web-window-v9329.html?share_mode=direct_pi',
 'direct_ci','real-finished-goods-v787.html?view=sale&direct_ci=1','rci','real-rci-v9740.html');
end $$;
revoke all on function public.rr_sales_real_chat_queue_test71(text,text,text) from public,anon;
grant execute on function public.rr_sales_real_chat_queue_test71(text,text,text) to authenticated;
notify pgrst,'reload schema';
