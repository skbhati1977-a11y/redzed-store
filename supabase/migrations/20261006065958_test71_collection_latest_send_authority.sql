create or replace function public.rr_sales_collection_live_status_test71(p_chat_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cy uuid;ctx jsonb;
begin
 ctx:=public.rr_sales_collection_context_test71(p_chat_id);
 select c.id into cy from public.rr_collection_cycle_v9586 c
 left join lateral (select max(s.created_at) sent_at from public.rr_collection_send_v9586 cs join public.rr_market_share_v9420 s on s.id=cs.share_id where cs.collection_cycle_id=c.id) latest on true
 where c.chat_id=p_chat_id and c.data_mode='TEST'
 order by greatest(c.created_at,coalesce(latest.sent_at,c.created_at)) desc,c.id desc limit 1;
 if cy is null then return ctx;end if;
 ctx:=public.rr_sales_collection_context_test71(p_chat_id,null,cy);
 return ctx||public.rr_direct_cycle_live_meta_test71(cy);
end $$;
revoke all on function public.rr_sales_collection_live_status_test71(uuid) from public,anon;
grant execute on function public.rr_sales_collection_live_status_test71(uuid) to authenticated,service_role;
