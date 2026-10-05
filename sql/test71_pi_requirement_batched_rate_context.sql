create or replace function public.rr_pi_requirement_bootstrap_test71(p_requirement_id uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare d jsonb; line jsonb; c jsonb; enriched jsonb:='[]'::jsonb;
begin
 perform public.rr_fg_assert_user_v787();
 if not exists(select 1 from public.rr_market_requirements_v9420 r join public.rr_market_share_v9420 s on s.id=r.share_id where r.id=p_requirement_id and upper(s.data_mode)='TEST') then raise exception 'TEST requirement required'; end if;
 d:=public.rr_pi_requirement_bootstrap_v9541(p_requirement_id);
 for line in select value from jsonb_array_elements(coalesce(d->'lines','[]'::jsonb)) loop
 c:=public.rr_pi_lot_context_v9517(line->>'lot_no',d->>'customer_name','TEST');
 if coalesce((c->>'approved_rate')::numeric,0)<=0 then raise exception 'Approved rate unavailable for lot %',line->>'lot_no'; end if;
 enriched:=enriched||jsonb_build_array(line||jsonb_build_object('bootstrap_context',c));
 end loop;
 return d||jsonb_build_object('lines',enriched);
end $$;
revoke all on function public.rr_pi_requirement_bootstrap_test71(uuid) from public,anon;
grant execute on function public.rr_pi_requirement_bootstrap_test71(uuid) to authenticated;