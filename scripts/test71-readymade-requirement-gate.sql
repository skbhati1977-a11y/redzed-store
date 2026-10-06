CREATE OR REPLACE FUNCTION public.rr_market_submit_requirement_v9508(p_token text, p_customer_name text, p_mobile text, p_message text, p_lines jsonb, p_requirement_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if exists(select 1 from jsonb_array_elements(coalesce(p_lines,'[]')) e join public.rr_rm_stock_v849_2c6 rm on rm.lot_no=e->>'lot_no' and rm.data_mode='TEST' join public.rr_market_share_v9420 sh on sh.token=p_token or sh.short_code=upper(p_token) where sh.data_mode='TEST' and (not coalesce((public.rr_rm_market_readiness_test71(rm.lot_no)->>'market_ready')::boolean,false) or exists(select 1 from public.rr_rm_retired_share_cards_test71 retired where retired.share_id=sh.id and retired.lot_no=rm.lot_no))) then raise exception 'Readymade card retired: complete mapping and final approval in Working, then send a fresh approved collection.';end if;
  if exists(
    select 1
    from public.rr_market_share_v9420 s
    join public.rr_market_partner_collection_v67 pc on pc.share_id=s.id
    join public.rr_market_partner_customer_v67 c on c.id=pc.partner_customer_id
    where (s.token=p_token or s.short_code=upper(p_token))
      and s.status='ACTIVE'
      and s.data_mode='TEST'
      and c.status='ACTIVE'
  ) then
    return public.rr_market_partner_submit_requirement_v67(
      p_token,
      p_customer_name,
      p_mobile,
      p_message,
      p_lines
    );
  end if;

  return public.rr_market_submit_requirement_v9508_legacy_v67(
    p_token,
    p_customer_name,
    p_mobile,
    p_message,
    p_lines,
    p_requirement_id
  );
end
$function$
;
CREATE OR REPLACE FUNCTION public.rr_pi_requirement_bootstrap_test71(p_requirement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d jsonb; line jsonb; c jsonb; enriched jsonb:='[]'::jsonb;
begin
 perform public.rr_fg_assert_user_v787();
 if not exists(select 1 from public.rr_market_requirements_v9420 r join public.rr_market_share_v9420 s on s.id=r.share_id where r.id=p_requirement_id and upper(s.data_mode)='TEST') then raise exception 'TEST requirement required'; end if;
 d:=public.rr_pi_requirement_bootstrap_v9541(p_requirement_id);
 for line in select value from jsonb_array_elements(coalesce(d->'lines','[]'::jsonb)) loop
 if exists(select 1 from public.rr_rm_stock_v849_2c6 s where s.lot_no=line->>'lot_no' and s.data_mode='TEST') and (not coalesce((public.rr_rm_market_readiness_test71(line->>'lot_no')->>'market_ready')::boolean,false) or exists(select 1 from public.rr_market_requirements_v9420 r join public.rr_rm_retired_share_cards_test71 retired on retired.share_id=r.share_id and retired.lot_no=line->>'lot_no' where r.id=p_requirement_id)) then continue;end if;
 c:=public.rr_pi_lot_context_v9517(line->>'lot_no',d->>'customer_name','TEST');
 if coalesce((c->>'approved_rate')::numeric,0)<=0 then raise exception 'Approved rate unavailable for lot %',line->>'lot_no'; end if;
 enriched:=enriched||jsonb_build_array(line||jsonb_build_object('bootstrap_context',c));
 end loop;
 return d||jsonb_build_object('lines',enriched);
end $function$
;
