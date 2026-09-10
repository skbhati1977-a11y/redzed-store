-- V9757: bind requirement PI/CI to its source and complete report classification.
begin;

insert into public.rr_account_report_map_v806(category_code,report_type,report_section,normal_side,display_order,is_active)
values
 ('CHIT_CONTRIBUTION_ASSET','BALANCE_SHEET','ASSET','DR',150,true),
 ('CHIT_FUTURE_LIABILITY','BALANCE_SHEET','LIABILITY','CR',250,true),
 ('CHIT_AUCTION_LOSS','PROFIT_LOSS','EXPENSE','DR',450,true),
 ('CHIT_DIVIDEND_INCOME','PROFIT_LOSS','INCOME','CR',160,true),
 ('ROUND_OFF','PROFIT_LOSS','INCOME','CR',190,true)
on conflict(category_code) do update set report_type=excluded.report_type,
 report_section=excluded.report_section,normal_side=excluded.normal_side,
 display_order=excluded.display_order,is_active=true,updated_at=now();

create or replace function public.rr_fg_save_pi_requirement_safe_signed_v9563(
 p_pi_id uuid,p_requirement_id uuid,p_customer_name text,p_dispatch_details text,p_lines jsonb,
 p_party_discount numeric,p_value_added_pct numeric default 0,p_freight_amount numeric default 0,
 p_packing_other numeric default 0,p_gst_pct numeric default 0,p_finalize boolean default false,
 p_data_mode text default 'TEST') returns jsonb
language plpgsql security definer set search_path='public' as $function$
declare v_pid uuid:=p_pi_id;v_existing uuid;v_status text;v_count int:=0;v_res jsonb;v_saved_id uuid;
 v_sub numeric;v_va numeric;v_taxable numeric;v_gst numeric;v_raw numeric;v_grand numeric;v_round numeric;
begin
 perform public.rr_fg_assert_user_v787();
 if upper(coalesce(p_data_mode,''))<>'TEST' then raise exception 'V9563 signed Value Added wrapper locked to TEST.'; end if;
 if coalesce(p_freight_amount,0)<0 or coalesce(p_packing_other,0)<0 or coalesce(p_gst_pct,0)<0 then
  raise exception 'Invalid commercial charges.'; end if;
 if p_requirement_id is not null then
  perform pg_advisory_xact_lock(hashtextextended(p_requirement_id::text,0));
  select count(*) into v_count from public.rr_fg_pi_v787 where market_requirement_id=p_requirement_id;
  if exists(select 1 from public.rr_fg_pi_v787 where market_requirement_id=p_requirement_id and status='CI_FINAL') then
   raise exception 'CI FINAL: this requirement is locked.'; end if;
  if v_pid is not null then
   select status into v_status from public.rr_fg_pi_v787 where id=v_pid and market_requirement_id=p_requirement_id;
   if not found then raise exception 'PI does not belong to this requirement.'; end if;
   if v_status<>'DRAFT' then raise exception 'Editable PI not found.'; end if;
  else
   select id into v_existing from public.rr_fg_pi_v787 where market_requirement_id=p_requirement_id and status='DRAFT'
    order by created_at asc limit 1 for update;
   if v_existing is not null then v_pid:=v_existing; end if;
  end if;
 end if;
 v_res:=public.rr_fg_save_pi_party_discount_v9557(v_pid,p_customer_name,p_dispatch_details,p_lines,
  p_party_discount,coalesce(p_freight_amount,0),coalesce(p_packing_other,0),coalesce(p_gst_pct,0),p_finalize,'TEST');
 v_saved_id:=nullif(v_res->>'pi_id','')::uuid;
 if v_saved_id is null then raise exception 'PI save failed.'; end if;
 -- Permanent source binding: requirement/distributor CI shares the canonical FG CI engine.
 if p_requirement_id is not null then
  update public.rr_fg_pi_v787 set market_requirement_id=p_requirement_id,updated_at=now()
   where id=v_saved_id and (market_requirement_id is null or market_requirement_id=p_requirement_id);
  if not found then raise exception 'Requirement PI binding conflict.'; end if;
 end if;
 select coalesce(sub_total,0) into v_sub from public.rr_fg_pi_v787 where id=v_saved_id for update;
 v_va:=v_sub*coalesce(p_value_added_pct,0)/100;
 v_taxable:=v_sub+v_va+coalesce(p_packing_other,0)+coalesce(p_freight_amount,0);
 if v_taxable<0 then raise exception 'Value Added adjustment makes PI total negative.'; end if;
 v_gst:=round(v_taxable*coalesce(p_gst_pct,0)/100,2);v_raw:=v_taxable+v_gst;
 v_grand:=round(v_raw/10)*10;v_round:=v_grand-v_raw;
 update public.rr_fg_pi_v787 set value_added_pct=coalesce(p_value_added_pct,0),taxable_amount=v_taxable,
  gst_pct=coalesce(p_gst_pct,0),gst_amount=v_gst,round_off=v_round,grand_total=v_grand,updated_at=now()
 where id=v_saved_id;
 return v_res||jsonb_build_object('requirement_id',p_requirement_id,'requirement_bound',p_requirement_id is null or
  exists(select 1 from public.rr_fg_pi_v787 where id=v_saved_id and market_requirement_id=p_requirement_id),
  'reused_existing_pi',v_pid is not null,'existing_requirement_pi_count_before',v_count,
  'value_added_pct',coalesce(p_value_added_pct,0),'value_added_amount',v_va,'taxable_amount',v_taxable,
  'gst_amount',v_gst,'round_off',v_round,'grand_total',v_grand);
end $function$;

revoke all on function public.rr_fg_save_pi_requirement_safe_signed_v9563(uuid,uuid,text,text,jsonb,numeric,numeric,numeric,numeric,numeric,boolean,text)
 from public,anon;
grant execute on function public.rr_fg_save_pi_requirement_safe_signed_v9563(uuid,uuid,text,text,jsonb,numeric,numeric,numeric,numeric,numeric,boolean,text)
 to authenticated,service_role;
commit;

