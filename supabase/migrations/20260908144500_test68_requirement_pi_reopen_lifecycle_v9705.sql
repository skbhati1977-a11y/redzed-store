create or replace function public.rr_pi_requirement_editor_v9705(p_requirement_id uuid)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare r public.rr_market_requirements_v9420%rowtype; p public.rr_fg_pi_v787%rowtype; ls jsonb;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  select * into r from public.rr_market_requirements_v9420 where id=p_requirement_id;
  if not found then raise exception 'REQUIREMENT NOT FOUND'; end if;
  select * into p from public.rr_fg_pi_v787 where market_requirement_id=r.id and status in('DRAFT','CI_FINAL')
    order by case when status='CI_FINAL' then 0 else 1 end,updated_at desc limit 1;
  if p.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'qty',l.qty,'category',l.short_item_name,
      'stock_type',l.stock_type,'rate',coalesce(l.gross_rate,l.original_rate,l.final_rate),
      'discount',coalesce(l.party_discount_per_piece,0),'serial_no',l.serial_no)
      order by coalesce(l.serial_no,2147483647),l.id),'[]'::jsonb)
    into ls from public.rr_fg_pi_lines_v787 l where l.pi_id=p.id;
  else
    select coalesce(jsonb_agg(jsonb_build_object('lot_no',l.lot_no,
      'qty',coalesce(l.accepted_qty,l.requested_qty),'requested_qty',l.requested_qty,
      'available_at_submit',l.max_available_at_submit,'category',coalesce(u.item_name,u.style_name,''),
      'size_text',coalesce(u.metadata->>'size_text',u.metadata->>'sizes',''),
      'image',coalesce(nullif(u.art_image_urls->>0,''),nullif(u.print_image_urls->>0,''))) order by l.created_at),'[]'::jsonb)
    into ls from public.rr_market_requirement_lines_v9420 l
    left join lateral(select * from public.rr_upm_lot_registry u where upper(trim(u.lot_no))=upper(trim(l.lot_no))
      order by u.updated_at desc limit 1)u on true where l.requirement_id=r.id;
  end if;
  return jsonb_build_object('requirement_id',r.id,'requirement_no',coalesce(r.requirement_display_no,r.requirement_no),
    'requirement_status',r.status,'customer_id',r.customer_id,'customer_name',r.customer_name,'mobile',r.mobile,
    'message',r.message,'lines',ls,'pi_id',p.id,'pi_no',p.pi_no,'ci_no',p.cpi_no,'pi_status',p.status,
    'dispatch_details',p.dispatch_details,'value_added_pct',coalesce(p.value_added_pct,0),
    'freight_amount',coalesce(p.freight_amount,0),'packing_other',coalesce(p.packing_other,0));
end $function$;
revoke all on function public.rr_pi_requirement_editor_v9705(uuid) from public,anon;
grant execute on function public.rr_pi_requirement_editor_v9705(uuid) to authenticated,service_role;

create or replace function public.rr_market_mark_requirement_ci_v9705(p_requirement_id uuid,p_pi_id uuid)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare r public.rr_market_requirements_v9420%rowtype; p public.rr_fg_pi_v787%rowtype;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  select * into r from public.rr_market_requirements_v9420 where id=p_requirement_id for update;
  if not found then raise exception 'REQUIREMENT NOT FOUND'; end if;
  select * into p from public.rr_fg_pi_v787 where id=p_pi_id and market_requirement_id=p_requirement_id for update;
  if not found then raise exception 'LINKED PI NOT FOUND'; end if;
  if p.status<>'CI_FINAL' then raise exception 'CI IS NOT CONFIRMED'; end if;
  update public.rr_market_requirements_v9420 set status='CI_FINAL',lifecycle_stage='CI_FINAL' where id=r.id;
  update public.rr_collection_cycle_v9586 set status='CI_GENERATED'
    where id=r.collection_cycle_id and status not in('CLOSED','CANCELLED');
  return jsonb_build_object('requirement_id',r.id,'pi_id',p.id,'pi_no',p.pi_no,'ci_no',p.cpi_no,'status','CI_FINAL');
end $function$;
revoke all on function public.rr_market_mark_requirement_ci_v9705(uuid,uuid) from public,anon;
grant execute on function public.rr_market_mark_requirement_ci_v9705(uuid,uuid) to authenticated,service_role;

create or replace function public.rr_market_cancel_requirement_ci_v9705(p_requirement_id uuid,p_pi_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare r public.rr_market_requirements_v9420%rowtype; p public.rr_fg_pi_v787%rowtype; l record;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'CI cancellation reason required.'; end if;
  select * into r from public.rr_market_requirements_v9420 where id=p_requirement_id for update;
  if not found then raise exception 'REQUIREMENT NOT FOUND'; end if;
  select * into p from public.rr_fg_pi_v787 where id=p_pi_id and market_requirement_id=p_requirement_id for update;
  if not found or p.status<>'CI_FINAL' then raise exception 'CONFIRMED CI NOT FOUND'; end if;
  if exists(select 1 from public.rr_account_source_links_v806 where source_module='FG_CPI_V787'
      and source_record_id=p.id::text and data_mode=p.data_mode and status='ACTIVE') then
    perform public.rr_accounts_reverse_source_mirror_v806('FG_CPI_V787',p.id::text,p.data_mode,trim(p_reason));
  end if;
  for l in select * from public.rr_fg_pi_lines_v787 where pi_id=p.id loop
    if not exists(select 1 from public.rr_fg_stock_ledger_v787 s where s.txn_type='CI_CANCEL'
      and s.ref_type='CI_CANCEL_LINE' and s.ref_id=l.id and s.data_mode=p.data_mode) then
      insert into public.rr_fg_stock_ledger_v787(txn_type,ref_type,ref_id,lot_no,stock_type,location_code,
        qty_delta,rate,data_mode,created_by,meta)
      values('CI_CANCEL','CI_CANCEL_LINE',l.id,l.lot_no,l.stock_type,null,l.qty,l.final_rate,p.data_mode,auth.uid(),
        jsonb_build_object('pi_id',p.id,'cancelled_ci_no',p.cpi_no,'reason',trim(p_reason)));
    end if;
  end loop;
  update public.rr_fg_pi_v787 set status='DRAFT',cpi_no=null,finalized_by=null,finalized_at=null,updated_at=now() where id=p.id;
  update public.rr_market_requirements_v9420 set status='PI_GENERATED',lifecycle_stage='PI_GENERATED' where id=r.id;
  update public.rr_collection_cycle_v9586 set status='PI_GENERATED'
    where id=r.collection_cycle_id and status not in('CLOSED','CANCELLED');
  update public.rr_cpi_accounts_link_v847 set status='REVERSED',message='CI cancelled · accounts reversed',updated_at=now()
    where cpi_id=p.id;
  return jsonb_build_object('requirement_id',r.id,'pi_id',p.id,'pi_no',p.pi_no,'status','DRAFT','rolled_back',true);
end $function$;
revoke all on function public.rr_market_cancel_requirement_ci_v9705(uuid,uuid,text) from public,anon;
grant execute on function public.rr_market_cancel_requirement_ci_v9705(uuid,uuid,text) to authenticated,service_role;

do $fix$
declare v_pi uuid:='33e2fd0f-8731-4149-98e4-824ce9593dc4'; v_req uuid:='af644709-abf7-494e-a7ab-7223f733b3da';
begin
  if exists(select 1 from public.rr_fg_pi_v787 where id=v_pi and pi_no='09/001' and status='DRAFT')
     and exists(select 1 from public.rr_market_requirements_v9420 where id=v_req and requirement_display_no='RZ REQUIREMENT 11') then
    update public.rr_fg_pi_v787 set market_requirement_id=v_req,updated_at=now() where id=v_pi;
    update public.rr_market_requirements_v9420 set status='PI_GENERATED',lifecycle_stage='PI_GENERATED',
      pi_generated_at=coalesce(pi_generated_at,now()) where id=v_req;
    update public.rr_collection_cycle_v9586 c set status='PI_GENERATED'
      from public.rr_market_requirements_v9420 r where r.id=v_req and c.id=r.collection_cycle_id
      and c.status not in('CI_GENERATED','CLOSED','CANCELLED');
  end if;
end $fix$;
