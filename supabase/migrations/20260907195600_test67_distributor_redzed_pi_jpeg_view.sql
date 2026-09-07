-- TEST67: safe read-only REDZED PI/CI view for its mapped distributor.
create or replace function public.rr_market_partner_batch_invoice_view_v67(p_session_token text,p_device_id text,p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_batch public.rr_market_partner_batch_v67%rowtype;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select * into v_batch from public.rr_market_partner_batch_v67 where id=p_batch_id and owner_customer_id=v_owner and data_mode='TEST';
 if v_batch.id is null then raise exception 'Mapped REDZED document is unavailable.';end if;
 if v_batch.pi_ref is null then raise exception 'REDZED PI has not been sent yet.';end if;
 return jsonb_build_object('kind',case when v_batch.ci_ref is not null then'CI'else'PI'end,'ref',coalesce(v_batch.ci_ref,v_batch.pi_ref),'status',v_batch.status,'created_at',coalesce(v_batch.updated_at,v_batch.submitted_at),'requirement_display_no',v_batch.requirement_display_no,
  'collection_display_no',case when v_batch.batch_kind='CONSOLIDATED'then'CONSOLIDATED · '||(select count(*)::text from public.rr_market_partner_batch_member_v67 m where m.batch_id=v_batch.id)||' SOURCE REQUIREMENTS'else coalesce((select o.requirement_display_no from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id where m.batch_id=v_batch.id order by o.created_at limit 1),'1 SOURCE REQUIREMENT')end,
  'party_name',(select customer_name from public.rr_customers where id=v_owner),'charges',jsonb_build_object('value_pct',v_batch.pi_value_pct,'freight',v_batch.pi_freight,'other',v_batch.pi_other,'tax_pct',0),
  'lines',coalesce((select jsonb_agg(line order by line->>'lot_no')from(
   select jsonb_build_object('id',l.id,'lot_no',l.lot_no,'article_name',l.article_name,'category',l.category,'size_text',l.size_text,'image_url',l.image_url,'requested_qty',l.requested_qty,'proposed_qty',coalesce(l.proposed_qty,l.requested_qty),'base_rate',l.base_rate,'customer_rate',l.customer_rate,'final_customer_rate',l.customer_rate,'is_extra',false)line from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_line_v67 l on l.order_id=m.order_id where m.batch_id=v_batch.id
   union all select jsonb_build_object('id',x.id,'lot_no',x.lot_no,'article_name',x.article_name,'category',x.category,'size_text',x.size_text,'image_url',x.image_url,'requested_qty',0,'proposed_qty',x.proposed_qty,'base_rate',x.base_rate,'customer_rate',x.customer_rate,'final_customer_rate',x.customer_rate,'is_extra',true)line from public.rr_market_partner_batch_pi_extra_line_v67 x where x.batch_id=v_batch.id
  )q),'[]'::jsonb));
end $$;
revoke all on function public.rr_market_partner_batch_invoice_view_v67(text,text,uuid)from public,anon;
grant execute on function public.rr_market_partner_batch_invoice_view_v67(text,text,uuid)to anon,authenticated,service_role;
