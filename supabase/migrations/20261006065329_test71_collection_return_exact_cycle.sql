create or replace function public.rr_sales_collection_cycle_status_test71(p_chat_id uuid,p_collection_cycle_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ctx jsonb;
begin
 ctx:=public.rr_sales_collection_context_test71(p_chat_id,null,p_collection_cycle_id);
 if p_collection_cycle_id is null then return public.rr_sales_collection_live_status_test71(p_chat_id);end if;
 return ctx||public.rr_direct_cycle_live_meta_test71(p_collection_cycle_id);
end $$;
revoke all on function public.rr_sales_collection_cycle_status_test71(uuid,uuid) from public,anon;
grant execute on function public.rr_sales_collection_cycle_status_test71(uuid,uuid) to authenticated,service_role;
