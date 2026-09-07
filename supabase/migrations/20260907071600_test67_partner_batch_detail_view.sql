-- TEST67: let the owning distributor review the exact line mapping sent to REDZED.
create or replace function public.rr_market_partner_batches_v67(p_session_token text,p_device_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'id',b.id,'batch_ref',b.batch_ref,'sequence_no',b.sequence_no,'batch_kind',b.batch_kind,
  'requirement_display_no',b.requirement_display_no,'status',b.status,'pi_ref',b.pi_ref,'ci_ref',b.ci_ref,
  'submitted_at',b.submitted_at,'order_count',(select count(*) from public.rr_market_partner_batch_member_v67 m where m.batch_id=b.id),
  'requirements',(select jsonb_agg(jsonb_build_object('id',o.id,'requirement_display_no',o.requirement_display_no,
    'status',o.status,'lines',(select coalesce(jsonb_agg(jsonb_build_object(
      'id',l.id,'lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,
      'requested_qty',l.requested_qty,'proposed_qty',l.proposed_qty) order by l.lot_no),'[]'::jsonb)
      from public.rr_market_partner_order_line_v67 l where l.order_id=o.id)) order by o.requirement_no,o.requirement_update_no)
   from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id where m.batch_id=b.id)
 ) order by b.submitted_at desc) from public.rr_market_partner_batch_v67 b
 where b.owner_customer_id=v_owner and b.data_mode='TEST'),'[]'::jsonb);
end $$;

revoke all on function public.rr_market_partner_batches_v67(text,text) from public,anon;
grant execute on function public.rr_market_partner_batches_v67(text,text) to authenticated,service_role;
