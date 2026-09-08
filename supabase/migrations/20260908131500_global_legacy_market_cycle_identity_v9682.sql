-- Global legacy Collection -> Requirement -> PI/CI identity normalization.
-- Keeps source rows and IDs intact; adds canonical display metadata and adopts
-- legacy direct-customer shares into the current collection-cycle registry.

alter table public.rr_market_requirements_v9420
  add column if not exists legacy_requirement_no text,
  add column if not exists root_requirement_id uuid references public.rr_market_requirements_v9420(id),
  add column if not exists requirement_sequence_no bigint,
  add column if not exists requirement_update_no integer,
  add column if not exists requirement_display_no text,
  add column if not exists collection_cycle_id uuid references public.rr_collection_cycle_v9586(id),
  add column if not exists collection_no bigint,
  add column if not exists collection_update_no integer,
  add column if not exists collection_display_no text,
  add column if not exists lifecycle_stage text;

create index if not exists rr_market_requirements_v9682_cycle_idx
  on public.rr_market_requirements_v9420(collection_cycle_id, requirement_sequence_no, requirement_update_no);
create index if not exists rr_market_requirements_v9682_root_idx
  on public.rr_market_requirements_v9420(root_requirement_id, requirement_update_no);

do $body$
declare
  v_collection_base bigint := coalesce((select max(collection_no) from public.rr_market_partner_collection_v67), 0);
  v_requirement_base bigint := coalesce((select max(requirement_no) from public.rr_market_partner_collection_v67), 0);
begin
  perform pg_advisory_xact_lock(hashtext('RR_MARKET_GLOBAL_LEGACY_V9682'));

  update public.rr_market_requirements_v9420
  set legacy_requirement_no = coalesce(legacy_requirement_no, requirement_no)
  where legacy_requirement_no is null;

  with source as (
    select r.*,
      coalesce(r.customer_id::text,
        'M:' || right(regexp_replace(coalesce(r.mobile,''),'\D','','g'),10) || ':' || lower(trim(coalesce(r.customer_name,'')))) party_key,
      coalesce(nullif(trim(r.legacy_requirement_no),''), 'LEGACY') old_req
    from public.rr_market_requirements_v9420 r
  ), collection_groups as (
    select share_id, party_key, min(submitted_at) first_at
    from source group by share_id, party_key
  ), collection_ranked as (
    select *, v_collection_base + row_number() over(order by first_at, share_id, party_key) collection_seq
    from collection_groups
  ), requirement_groups as (
    select share_id, party_key, old_req, min(submitted_at) first_at
    from source group by share_id, party_key, old_req
  ), requirement_ranked as (
    select *, v_requirement_base + row_number() over(order by first_at, share_id, party_key, old_req) requirement_seq
    from requirement_groups
  ), numbered as (
    select s.id,
      cr.collection_seq,
      rr.requirement_seq,
      first_value(s.id) over(partition by s.share_id,s.party_key,s.old_req order by s.submitted_at,s.id) root_id,
      row_number() over(partition by s.share_id,s.party_key,s.old_req order by s.submitted_at,s.id)-1 update_no,
      count(*) over(partition by s.share_id,s.party_key,s.old_req)-1 max_update_no
    from source s
    join collection_ranked cr using(share_id,party_key)
    join requirement_ranked rr using(share_id,party_key,old_req)
  )
  update public.rr_market_requirements_v9420 r
  set root_requirement_id=n.root_id,
      requirement_sequence_no=n.requirement_seq,
      requirement_update_no=n.update_no,
      requirement_display_no='RZ REQUIREMENT '||lpad(n.requirement_seq::text,2,'0')||case when n.update_no>0 then ' · UPDATE '||n.update_no else '' end,
      collection_no=n.collection_seq,
      collection_update_no=0,
      collection_display_no='RZ COLLECTION '||lpad(n.collection_seq::text,2,'0'),
      lifecycle_stage=case
        when exists(select 1 from public.rr_fg_pi_v787 p where p.market_requirement_id=r.id and p.status='CI_FINAL') then 'CI_FINAL'
        when exists(select 1 from public.rr_fg_pi_v787 p where p.market_requirement_id=r.id and p.status='CANCELLED') then 'PI_CANCELLED'
        when exists(select 1 from public.rr_fg_pi_v787 p where p.market_requirement_id=r.id) or r.pi_generated_at is not null then 'PI_GENERATED'
        when n.update_no < n.max_update_no then 'SUPERSEDED'
        else 'READY_FOR_PI'
      end,
      status=case
        when exists(select 1 from public.rr_fg_pi_v787 p where p.market_requirement_id=r.id and p.status='CI_FINAL') then 'CI_FINAL'
        when exists(select 1 from public.rr_fg_pi_v787 p where p.market_requirement_id=r.id and p.status='CANCELLED') then 'PI_CANCELLED'
        when exists(select 1 from public.rr_fg_pi_v787 p where p.market_requirement_id=r.id) or r.pi_generated_at is not null then 'PI_GENERATED'
        when n.update_no < n.max_update_no then 'SUPERSEDED'
        else 'READY_FOR_PI'
      end
  from numbered n where r.id=n.id;

  -- Adopt every eligible legacy direct-customer share into a canonical cycle.
  with eligible as (
    select distinct on(r.share_id) r.share_id,r.customer_id,r.collection_no,r.collection_display_no,
      s.data_mode,r.submitted_at,
      (select c.id from public.rr_customer_chat_v9433 c
       where c.customer_id=r.customer_id and c.data_mode=s.data_mode and c.status='OPEN'
       order by c.created_at limit 1) chat_id
    from public.rr_market_requirements_v9420 r
    join public.rr_market_share_v9420 s on s.id=r.share_id
    where r.customer_id is not null
    order by r.share_id,r.submitted_at,r.id
  )
  insert into public.rr_collection_cycle_v9586(customer_id,chat_id,data_mode,collection_no,display_no,status,opened_at,created_at)
  select e.customer_id,e.chat_id,upper(coalesce(e.data_mode,'TEST')),e.collection_no::integer,e.collection_display_no,
    case when exists(
      select 1 from public.rr_market_requirements_v9420 r join public.rr_fg_pi_v787 p on p.market_requirement_id=r.id
      where r.share_id=e.share_id and p.status='CI_FINAL'
    ) then 'CI_GENERATED'
    when exists(
      select 1 from public.rr_market_requirements_v9420 r join public.rr_fg_pi_v787 p on p.market_requirement_id=r.id
      where r.share_id=e.share_id and p.status<>'CANCELLED'
    ) then 'PI_GENERATED' else 'REQUIREMENT_RECEIVED' end,
    e.submitted_at,e.submitted_at
  from eligible e
  where e.chat_id is not null
    and not exists(select 1 from public.rr_collection_send_v9586 cs where cs.share_id=e.share_id)
    and not exists(select 1 from public.rr_collection_cycle_v9586 c where c.customer_id=e.customer_id and c.data_mode=upper(coalesce(e.data_mode,'TEST')) and c.collection_no=e.collection_no);

  insert into public.rr_collection_send_v9586(collection_cycle_id,share_id,send_seq,send_kind)
  select c.id,r.share_id,1,'FIRST'
  from (select distinct share_id,customer_id,collection_no from public.rr_market_requirements_v9420 where customer_id is not null) r
  join public.rr_market_share_v9420 s on s.id=r.share_id
  join public.rr_collection_cycle_v9586 c on c.customer_id=r.customer_id and c.data_mode=upper(coalesce(s.data_mode,'TEST')) and c.collection_no=r.collection_no
  where not exists(select 1 from public.rr_collection_send_v9586 x where x.share_id=r.share_id);

  update public.rr_market_requirements_v9420 r
  set collection_cycle_id=cs.collection_cycle_id,
      collection_no=c.collection_no,
      collection_display_no=c.display_no
  from public.rr_collection_send_v9586 cs
  join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id
  where cs.share_id=r.share_id and r.customer_id=c.customer_id;

  with missing as (
    select r.id,r.collection_cycle_id,
      row_number() over(partition by r.collection_cycle_id order by r.submitted_at,r.id)
      + coalesce((select max(l.requirement_seq) from public.rr_collection_requirement_link_v9586 l where l.collection_cycle_id=r.collection_cycle_id),0) seq
    from public.rr_market_requirements_v9420 r
    where r.collection_cycle_id is not null
      and not exists(select 1 from public.rr_collection_requirement_link_v9586 l where l.requirement_id=r.id)
  )
  insert into public.rr_collection_requirement_link_v9586(collection_cycle_id,requirement_id,requirement_seq,is_primary)
  select collection_cycle_id,id,seq,true from missing;

  with missing as (
    select r.*,
      row_number() over(partition by r.collection_cycle_id order by r.submitted_at,r.id)
      + coalesce((select max(a.update_no) from public.rr_collection_activity_v9633 a where a.collection_cycle_id=r.collection_cycle_id),0) activity_no
    from public.rr_market_requirements_v9420 r
    where r.collection_cycle_id is not null
      and not exists(select 1 from public.rr_collection_activity_v9633 a where a.reference_id=r.id and a.activity_kind in('REQUIREMENT','REQUIREMENT_UPDATE'))
  )
  insert into public.rr_collection_activity_v9633(collection_cycle_id,update_no,activity_kind,actor_kind,reference_id,payload,created_at)
  select collection_cycle_id,activity_no,
    case when requirement_update_no=0 then 'REQUIREMENT' else 'REQUIREMENT_UPDATE' end,
    'CUSTOMER',id,
    jsonb_build_object('legacy_backfill',true,'requirement_display_no',requirement_display_no,'requirement_update_no',requirement_update_no,'collection_display_no',collection_display_no),
    submitted_at
  from missing;
end;
$body$;

create or replace function public.rr_chat_requirement_detail_v9508(p_chat_id uuid,p_requirement_id uuid)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare r public.rr_market_requirements_v9420%rowtype; outj jsonb; pi jsonb;
begin
 perform public.rr_chat_internal_assert_v9495();
 if not exists(select 1 from public.rr_customer_chat_members_v9433 m join public.rr_user_profiles p on p.id=m.profile_id where m.chat_id=p_chat_id and m.is_active and p.auth_user_id=auth.uid()) then raise exception 'CHAT ACCESS DENIED'; end if;
 select q.* into r from public.rr_market_requirements_v9420 q join public.rr_customer_chat_v9433 c on c.customer_id=q.customer_id where q.id=p_requirement_id and c.id=p_chat_id;
 if not found then raise exception 'REQUIREMENT NOT FOUND IN THIS CHAT'; end if;
 select jsonb_build_object('id',p.id,'pi_no',p.pi_no,'ci_no',p.cpi_no,'status',p.status,'version_no',p.version_no) into pi
 from public.rr_fg_pi_v787 p where p.market_requirement_id=r.id order by p.created_at desc limit 1;
 select jsonb_build_object(
   'id',r.id,'requirement_no',coalesce(r.requirement_display_no,r.requirement_no),
   'requirement_display_no',coalesce(r.requirement_display_no,r.requirement_no),
   'requirement_update_no',coalesce(r.requirement_update_no,0),
   'collection_cycle_id',r.collection_cycle_id,'collection_no',r.collection_no,
   'collection_display_no',coalesce(r.collection_display_no,'COLLECTION'),
   'collection_update_no',coalesce(r.collection_update_no,0),
   'customer_name',r.customer_name,'mobile',r.mobile,'message',r.message,
   'status',coalesce(r.lifecycle_stage,r.status),'submitted_at',r.submitted_at,'share_id',r.share_id,
   'pi',pi,'can_prepare_pi',(pi is null and coalesce(r.lifecycle_stage,r.status) not in('SUPERSEDED','CI_FINAL')),
   'can_add_update',(pi is null and coalesce(r.lifecycle_stage,r.status) not in('SUPERSEDED','CI_FINAL')),
   'lines',coalesce(jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'requested_qty',l.requested_qty,'accepted_qty',l.accepted_qty,'max_available',l.max_available_at_submit,'card',to_jsonb(ca)) order by l.created_at),'[]'::jsonb)
 ) into outj
 from public.rr_market_requirement_lines_v9420 l
 left join lateral public.rr_web_window_cards_v9329(l.lot_no,null,null,'TEST',1,0) ca on true
 where l.requirement_id=r.id;
 return outj;
end $function$;

create or replace function public.rr_collection_current_state_v9633(p_token text)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare cyid uuid; cy public.rr_collection_cycle_v9586%rowtype; n integer; cn integer; rn integer;
begin
  cyid:=public.rr_collection_cycle_for_share_v9631(p_token);
  select * into cy from public.rr_collection_cycle_v9586 where id=cyid;
  select greatest(
    coalesce((select max(update_no) from public.rr_collection_activity_v9633 where collection_cycle_id=cyid),0),
    coalesce((select max(update_no) from public.rr_collection_update_request_v9630 where collection_cycle_id=cyid),0)
  ) into n;
  select greatest(coalesce(max(send_seq),1)-1,0) into cn
  from public.rr_collection_send_v9586 where collection_cycle_id=cyid;
  select coalesce(max(r.requirement_update_no),0) into rn
  from public.rr_market_requirements_v9420 r where r.collection_cycle_id=cyid;
  return jsonb_build_object('collection_cycle_id',cy.id,'collection_display_no',cy.display_no,
    'collection_status',cy.status,'update_no',n,'collection_update_no',cn,'requirement_update_no',rn);
end $function$;

create or replace function public.rr_market_link_requirement_pi_v9432(p_requirement_id uuid,p_pi_id uuid)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare r public.rr_market_requirements_v9420%rowtype; k text; advanced boolean:=false;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select * into r from public.rr_market_requirements_v9420 where id=p_requirement_id for update;
 if not found then raise exception 'REQUIREMENT NOT FOUND'; end if;
 update public.rr_fg_pi_v787 set market_requirement_id=p_requirement_id where id=p_pi_id;
 if not found then raise exception 'PI NOT FOUND'; end if;
 if r.pi_generated_at is null then
   update public.rr_market_requirements_v9420 set pi_generated_at=now(),status='PI_GENERATED',lifecycle_stage='PI_GENERATED' where id=p_requirement_id;
   update public.rr_collection_cycle_v9586 set status='PI_GENERATED' where id=r.collection_cycle_id and status not in('CI_GENERATED','CLOSED','CANCELLED');
   k:=public.rr_resolve_party_identity_v9543(r.customer_id,r.mobile,r.customer_name);
   if k is not null then
     insert into public.rr_party_requirement_sequence_v9543(identity_key,customer_id,mobile,party_name,current_no)
     values(k,r.customer_id,r.mobile,r.customer_name,2)
     on conflict(identity_key) do update set current_no=public.rr_party_requirement_sequence_v9543.current_no+1,updated_at=now();
   end if;
   advanced:=true;
 end if;
 return jsonb_build_object('linked',true,'requirement_id',p_requirement_id,
   'requirement_no',coalesce(r.requirement_display_no,r.requirement_no),'pi_id',p_pi_id,
   'lifecycle_stage','PI_GENERATED','next_requirement_advanced',advanced);
end $function$;

revoke all on function public.rr_chat_requirement_detail_v9508(uuid,uuid) from public;
grant execute on function public.rr_chat_requirement_detail_v9508(uuid,uuid) to authenticated,service_role;
revoke all on function public.rr_collection_current_state_v9633(text) from public;
grant execute on function public.rr_collection_current_state_v9633(text) to anon,authenticated,service_role;
revoke all on function public.rr_market_link_requirement_pi_v9432(uuid,uuid) from public;
grant execute on function public.rr_market_link_requirement_pi_v9432(uuid,uuid) to authenticated,service_role;
