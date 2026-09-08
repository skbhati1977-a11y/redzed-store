-- Keep the established RZ REQUIREMENT label while assigning future updates.
create or replace function public.rr_direct_requirement_identity_v9685(
  p_requirement_id uuid,p_collection_cycle_id uuid,p_is_update boolean
) returns public.rr_market_requirements_v9420
language plpgsql security definer set search_path='' as $function$
declare v_req public.rr_market_requirements_v9420%rowtype; v_seq bigint; v_up integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_requirement_id::text||'|DIRECT_REQ_ID',9685));
  select * into v_req from public.rr_market_requirements_v9420 where id=p_requirement_id for update;
  if v_req.id is null then raise exception 'Requirement unavailable.'; end if;
  v_seq:=v_req.requirement_sequence_no;
  if v_seq is null then
    select coalesce(max(requirement_sequence_no),0)+1 into v_seq from public.rr_market_requirements_v9420;
  end if;
  v_up:=case when p_is_update then coalesce(v_req.requirement_update_no,0)+1
             else coalesce(v_req.requirement_update_no,0) end;
  update public.rr_market_requirements_v9420 set
    root_requirement_id=coalesce(root_requirement_id,id),requirement_sequence_no=v_seq,
    requirement_update_no=v_up,
    requirement_display_no='RZ REQUIREMENT '||lpad(v_seq::text,2,'0')||case when v_up>0 then ' · UPDATE '||v_up else '' end,
    collection_cycle_id=p_collection_cycle_id,
    collection_no=(select collection_no from public.rr_collection_cycle_v9586 where id=p_collection_cycle_id),
    collection_update_no=greatest(coalesce((select max(send_seq) from public.rr_collection_send_v9586 where collection_cycle_id=p_collection_cycle_id),1)-1,0),
    collection_display_no=(select display_no from public.rr_collection_cycle_v9586 where id=p_collection_cycle_id),
    lifecycle_stage=case when lifecycle_stage='CI_FINAL' then lifecycle_stage else 'READY_FOR_PI' end
  where id=p_requirement_id returning * into v_req;
  return v_req;
end
$function$;
revoke all on function public.rr_direct_requirement_identity_v9685(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.rr_direct_requirement_identity_v9685(uuid,uuid,boolean) to service_role;
