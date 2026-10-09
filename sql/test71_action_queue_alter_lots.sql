-- Counts and the Fabrication list must discover Alter from the same active
-- journey inventory, independent of whichever regular cards were loaded.
CREATE OR REPLACE FUNCTION public.rr_chat_alter_lots_test71()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
declare result jsonb;
begin
 perform public.rr_assert_active_user_v1();
 if auth.uid() is null then raise exception 'Login required.';end if;
 select coalesce(jsonb_agg(x),'[]') into result from
 (select distinct canonical_lot_id,lot_no from public.rr_upm_alter_journey_v740 where stage not like 'CLOSED%' and open_qty>0)x;
 return result;
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_alter_lots_test71() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_alter_lots_test71() TO authenticated;
