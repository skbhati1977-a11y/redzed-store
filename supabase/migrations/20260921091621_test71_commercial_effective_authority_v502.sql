-- Close Act As authority gaps in the pre-existing Sales and Accounts guards.
-- The effective identity, not the signed-in operator, owns commercial authority.
create or replace function public.rr_market_actor_role_v9420()
returns text language sql stable security definer set search_path=public as $$
  select upper(coalesce(public.rr_upm_effective_identity_v200()->>'resolved_role',
    public.rr_upm_effective_identity_v200()->>'role_code','WORKER'));
$$;

create or replace function public.rr_acct_can_view_v805()
returns boolean language plpgsql stable security definer set search_path=public as $$
declare identity_json jsonb; effective_role text;
begin
  if current_setting('rr.trusted_account_bridge',true)='rci_reversal' then return true; end if;
  if auth.uid() is null then return public.rr_acct_can_view_base_v9762(); end if;
  identity_json:=public.rr_upm_effective_identity_v200();
  effective_role:=upper(coalesce(identity_json->>'resolved_role',identity_json->>'role_code','WORKER'));
  if effective_role not in('OWNER','SUPER_ADMIN','ADMIN','ACCOUNT','ACCOUNTS') then return false; end if;
  return public.rr_acct_can_view_base_v9762();
end $$;

create or replace function public.rr_sales_real_chat_queue_v500(p_status text default 'OPEN',p_search text default null,p_data_mode text default 'TEST')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare s text:=upper(coalesce(p_status,'OPEN')); rows_json jsonb;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  if s not in('OPEN','WORKING','CLOSE') then raise exception 'OPEN / WORKING / CLOSE required.'; end if;
  if s='OPEN' then
    with req as (
      select coalesce(r.root_requirement_id,r.id) root_id,max(r.requirement_display_no) requirement_no,
        sum(coalesce(l.accepted_qty,0)) present_qty,max(r.submitted_at) last_update,max(r.pi_generated_at) pi_generated_at,
        max(r.customer_name) customer_name,max(r.collection_display_no) collection_display_no,max(r.lifecycle_stage) lifecycle_stage
      from public.rr_market_requirements_v9420 r left join public.rr_market_requirement_lines_v9420 l on l.requirement_id=r.id
      group by coalesce(r.root_requirement_id,r.id)
    ), cy as (
      select c.id,c.display_no collection_no,c.status,c.created_at,c.chat_id,ch.customer_name,
        coalesce(max(cs.send_seq)-1,0) update_no,max(cs.sent_at) last_update,
        coalesce((select sum(q.present_qty) from req q join public.rr_collection_requirement_link_v9586 rl on rl.requirement_id=q.root_id where rl.collection_cycle_id=c.id),0) present_qty,
        (select max(q.requirement_no) from req q join public.rr_collection_requirement_link_v9586 rl on rl.requirement_id=q.root_id where rl.collection_cycle_id=c.id) requirement_no,
        (select max(q.pi_generated_at) from req q join public.rr_collection_requirement_link_v9586 rl on rl.requirement_id=q.root_id where rl.collection_cycle_id=c.id) pi_generated_at
      from public.rr_collection_cycle_v9586 c left join public.rr_customer_chat_v9433 ch on ch.id=c.chat_id
      left join public.rr_collection_send_v9586 cs on cs.collection_cycle_id=c.id
      where c.data_mode=upper(p_data_mode) group by c.id,ch.customer_name
    )
    select coalesce(jsonb_agg(jsonb_build_object('id',cy.id,'card_type','COLLECTION_FOLLOWUP','customer',cy.customer_name,
      'collection_no',cy.collection_no,'collection_update_no',cy.update_no,'requirement_no',cy.requirement_no,'present_qty',cy.present_qty,
      'present_amount',0,'all_qty',cy.present_qty,'all_amount',0,'last_update',coalesce(cy.last_update,cy.created_at),
      'current_status',case when cy.pi_generated_at is not null then 'COMPLETE' else cy.status end,'chat_id',cy.chat_id)
      order by coalesce(cy.last_update,cy.created_at) desc),'[]'::jsonb) into rows_json
    from cy where cy.pi_generated_at is null and cy.status not in('CLOSED','CLOSED_NO_RESPONSE','CANCELLED')
      and (nullif(trim(p_search),'') is null or concat_ws(' ',cy.customer_name,cy.collection_no,cy.requirement_no) ilike '%'||trim(p_search)||'%');
  elsif s='WORKING' then
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'card_type','PI_CI_READY','customer',p.buyer_snapshot->>'buyer_name',
      'pi_no',p.pi_no,'date',p.created_at::date,'qty',coalesce(x.qty,0),'amount',p.grand_total,'salesman',u.full_name,
      'current_status','CI READY','market_requirement_id',p.market_requirement_id) order by p.updated_at desc),'[]'::jsonb) into rows_json
    from public.rr_fg_pi_v787 p left join lateral(select sum(qty) qty from public.rr_fg_pi_lines_v787 where pi_id=p.id)x on true
    left join public.rr_user_profiles u on u.auth_user_id=p.created_by
    where p.data_mode=upper(p_data_mode) and p.status='DRAFT'
      and (nullif(trim(p_search),'') is null or concat_ws(' ',p.pi_no,p.buyer_snapshot->>'buyer_name') ilike '%'||trim(p_search)||'%');
  else
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'card_type','CI_HISTORY','customer',p.buyer_snapshot->>'buyer_name',
      'ci_no',p.cpi_no,'pi_no',p.pi_no,'date',p.finalized_at::date,'qty',coalesce(x.qty,0),'amount',p.grand_total,
      'current_status','CLOSE','rci_count',coalesce(r.rci_count,0),'rci_amount',coalesce(r.rci_amount,0),'payment_status','LEDGER')
      order by p.finalized_at desc),'[]'::jsonb) into rows_json
    from public.rr_fg_pi_v787 p left join lateral(select sum(qty) qty from public.rr_fg_pi_lines_v787 where pi_id=p.id)x on true
    left join lateral(select count(*) rci_count,sum(total_amount) rci_amount from public.rr_rci_v9740 where linked_ci_id=p.id and status='POSTED')r on true
    where p.data_mode=upper(p_data_mode) and p.status in('CI_FINAL','CPI_FINAL')
      and (nullif(trim(p_search),'') is null or concat_ws(' ',p.pi_no,p.cpi_no,p.buyer_snapshot->>'buyer_name') ilike '%'||trim(p_search)||'%');
  end if;
  return jsonb_build_object('version','V502_CANONICAL_SALES_CHAT','status',s,'cards',rows_json,
    'market_window','real-web-window-v9329.html','direct_pi','real-web-window-v9329.html?share_mode=direct_pi',
    'direct_ci','real-finished-goods-v787.html?view=sale&direct_ci=1','rci','real-rci-v9740.html');
end $$;
