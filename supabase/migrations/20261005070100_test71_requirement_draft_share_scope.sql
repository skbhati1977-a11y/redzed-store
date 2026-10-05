create or replace function public.rr_pi_requirement_save_test71(
 p_requirement_id uuid,p_pi_id uuid,p_customer_name text,p_dispatch_details text,p_lines jsonb,p_party_discount numeric,
 p_value_added_pct numeric,p_freight_amount numeric default 0,p_packing_other numeric default 0,
 p_gst_pct numeric default 0,p_finalize boolean default false,p_data_mode text default 'TEST'
) returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare r public.rr_market_requirements_v9420%rowtype; target uuid; current_pi public.rr_fg_pi_v787%rowtype; result jsonb;
begin
 perform public.rr_fg_assert_user_v787();
 perform public.rr_market_assert_sales_actor_v9420();
 if upper(coalesce(p_data_mode,''))<>'TEST' then raise exception 'TEST71 billing requires TEST mode.'; end if;
 select * into r from public.rr_market_requirements_v9420 where id=p_requirement_id for update;
 if not found or not exists(select 1 from public.rr_market_share_v9420 s where s.id=r.share_id and s.data_mode='TEST') then raise exception 'TEST requirement required.'; end if;
 if lower(trim(r.customer_name)) is distinct from lower(trim(p_customer_name)) then raise exception 'PI party must match requirement.'; end if;
 select id into target from public.rr_fg_pi_v787 where market_requirement_id=r.id and data_mode='TEST' and status='DRAFT' order by updated_at desc limit 1 for update;
 if target is null then
   if exists(select 1 from public.rr_fg_pi_v787 where market_requirement_id=r.id and data_mode='TEST' and status<>'DRAFT') then
     raise exception 'Requirement already finalized. Open its saved bill.';
   end if;
   if p_pi_id is not null then
     select * into current_pi from public.rr_fg_pi_v787 where id=p_pi_id and data_mode='TEST' and status='DRAFT' for update;
     if not found or (current_pi.market_requirement_id is not null and current_pi.market_requirement_id<>r.id)
       or nullif(current_pi.buyer_snapshot->>'contact_customer_id','')::uuid is distinct from r.customer_id then
       raise exception 'Editable PI belongs to another requirement or party.';
     end if;
     target:=current_pi.id;
   end if;
 end if;
 result:=public.rr_fg_save_pi_value_adjustment_test71(target,p_customer_name,p_dispatch_details,p_lines,p_party_discount,
 p_value_added_pct,p_freight_amount,p_packing_other,p_gst_pct,p_finalize,'TEST');
 perform public.rr_market_link_requirement_pi_v9432(r.id,(result->>'pi_id')::uuid);
 return result||jsonb_build_object('requirement_id',r.id,'reused_requirement_draft',target is not null);
end $fn$;
revoke all on function public.rr_pi_requirement_save_test71(uuid,uuid,text,text,jsonb,numeric,numeric,numeric,numeric,numeric,boolean,text) from public,anon;
grant execute on function public.rr_pi_requirement_save_test71(uuid,uuid,text,text,jsonb,numeric,numeric,numeric,numeric,numeric,boolean,text) to authenticated,service_role;

