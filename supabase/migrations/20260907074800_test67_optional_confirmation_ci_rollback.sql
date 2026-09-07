-- TEST67 unified optional-confirmation CI and reversible rollback lifecycle.
alter table public.rr_market_partner_customer_ci_v67
  add column if not exists revision_no integer not null default 1,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text;

create or replace function public.rr_market_staff_finalize_ci_v67(p_batch_id uuid,p_ci_ref text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_owner uuid;v_ref text;v_seq int;v_kind text;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select owner_customer_id,ci_ref,sequence_no,batch_kind into v_owner,v_ref,v_seq,v_kind
 from public.rr_market_partner_batch_v67
 where id=p_batch_id and data_mode='TEST'and status in('WAITING_CONFIRMATION','CONFIRMED','PARTIAL_CONFIRMED','CI_FINAL')for update;
 if v_owner is null then raise exception 'REDZED PI must exist before CI.';end if;
 v_ref:=coalesce(nullif(trim(p_ci_ref),''),v_ref,case when v_kind='CONSOLIDATED' then 'CONSOLIDATED CI ' else 'REDZED CI ' end||v_seq);
 update public.rr_market_partner_order_line_v67 l set
  confirmed_qty=coalesce(l.confirmed_qty,l.proposed_qty,l.requested_qty),updated_at=now()
 where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=l.order_id)
   and l.confirmation_status='WAITING';
 update public.rr_market_partner_batch_v67 set status='CI_FINAL',ci_ref=v_ref,updated_at=now()where id=p_batch_id;
 update public.rr_market_partner_order_v67 o set status=case when o.status='CANCELLED'then'CANCELLED'else'CI_FINAL'end,
  ci_ref=v_ref,customer_ci_visible=false,updated_at=now()
 where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=o.id);
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
 values(v_owner,p_batch_id,'REDZED_CI_SENT_TO_DISTRIBUTOR','STAFF',auth.uid(),jsonb_build_object(
  'ci_ref',v_ref,'batch_kind',v_kind,'confirmation_optional',true));
 return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

create or replace function public.rr_market_staff_cancel_ci_v67(p_batch_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_owner uuid;v_old_ci text;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 if nullif(trim(p_reason),'')is null then raise exception 'Cancellation reason is required.';end if;
 select owner_customer_id,ci_ref into v_owner,v_old_ci from public.rr_market_partner_batch_v67
 where id=p_batch_id and data_mode='TEST'and status='CI_FINAL'and ci_ref is not null for update;
 if v_owner is null then raise exception 'Only an active CI can be cancelled.';end if;
 update public.rr_market_partner_customer_ci_v67 ci set status='CANCELLED',cancelled_at=now(),cancellation_reason=trim(p_reason)
 where ci.status='FINAL'and exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=ci.source_order_id);
 update public.rr_market_partner_order_v67 o set status='PI_PROPOSED',ci_ref=null,customer_ci_ref=null,
  customer_ci_visible=false,customer_ci_pushed_at=null,updated_at=now()
 where o.status<>'CANCELLED'and exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=o.id);
 update public.rr_market_partner_batch_v67 set status='WAITING_CONFIRMATION',ci_ref=null,updated_at=now()where id=p_batch_id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,note,actor_kind,actor_id,payload)
 values(v_owner,p_batch_id,'REDZED_CI_CANCELLED_PI_RESTORED',trim(p_reason),'STAFF',auth.uid(),jsonb_build_object('cancelled_ci_ref',v_old_ci));
 return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

create or replace function public.rr_market_partner_convert_customer_ci_v67(p_session_token text,p_device_id text,p_order_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_order public.rr_market_partner_order_v67%rowtype;
 v_prefix text;v_no bigint;v_ci_ref text;v_ci uuid;v_revision int:=1;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
 if not(v_ctx->>'ci_convert_enabled')::boolean then raise exception 'Customer CI conversion is disabled.';end if;
 v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select * into v_order from public.rr_market_partner_order_v67 where id=p_order_id and owner_customer_id=v_owner and status='CI_FINAL'for update;
 if v_order.id is null or v_order.ci_ref is null then raise exception 'Final upstream CI allocation not found.';end if;
 select id,customer_ci_ref,revision_no into v_ci,v_ci_ref,v_revision from public.rr_market_partner_customer_ci_v67
 where source_order_id=p_order_id for update;
 if v_ci is not null and exists(select 1 from public.rr_market_partner_customer_ci_v67 where id=v_ci and status='FINAL')then
  return jsonb_build_object('customer_ci_id',v_ci,'customer_ci_ref',v_ci_ref,'source_upstream_ci_ref',v_order.ci_ref,'status','FINAL','revision_no',v_revision);
 end if;
 if v_ci is null then
  select prefix into v_prefix from public.rr_market_owner_sequence_v67 where owner_key='CUSTOMER:'||v_owner::text and data_mode='TEST';
  select coalesce(max((regexp_match(customer_ci_ref,'([0-9]+)$'))[1]::bigint),0)+1 into v_no from public.rr_market_partner_customer_ci_v67 where owner_customer_id=v_owner;
  v_ci_ref:=v_prefix||'-CI-'||lpad(v_no::text,4,'0');
  insert into public.rr_market_partner_customer_ci_v67(owner_customer_id,partner_customer_id,source_order_id,source_upstream_ci_ref,customer_ci_ref)
  values(v_owner,v_order.partner_customer_id,p_order_id,v_order.ci_ref,v_ci_ref)returning id into v_ci;
 else
  v_revision:=v_revision+1;
  update public.rr_market_partner_customer_ci_v67 set status='FINAL',source_upstream_ci_ref=v_order.ci_ref,
   revision_no=v_revision,cancelled_at=null,cancellation_reason=null,created_at=now()where id=v_ci;
  delete from public.rr_market_partner_customer_ci_line_v67 where customer_ci_id=v_ci;
 end if;
 insert into public.rr_market_partner_customer_ci_line_v67(customer_ci_id,source_order_line_id,lot_no,article_name,quantity,customer_rate)
 select v_ci,id,lot_no,article_name,greatest(0,coalesce(distributor_pi_qty,confirmed_qty,proposed_qty,requested_qty)),customer_rate
 from public.rr_market_partner_order_line_v67 where order_id=p_order_id
   and greatest(0,coalesce(distributor_pi_qty,confirmed_qty,proposed_qty,requested_qty))>0;
 if not found then raise exception 'Customer CI needs at least one positive PI quantity.';end if;
 update public.rr_market_partner_order_v67 set status='CLOSED',customer_ci_ref=v_ci_ref,customer_ci_visible=true,customer_ci_pushed_at=now(),updated_at=now()where id=p_order_id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,actor_kind,payload)
 values(v_owner,p_order_id,'CUSTOMER_CI_CREATED','DISTRIBUTOR',jsonb_build_object('customer_ci_ref',v_ci_ref,'upstream_ci_ref',v_order.ci_ref,'revision_no',v_revision,'confirmation_optional',true));
 return jsonb_build_object('customer_ci_id',v_ci,'customer_ci_ref',v_ci_ref,'source_upstream_ci_ref',v_order.ci_ref,'status','FINAL','revision_no',v_revision);
end $$;

create or replace function public.rr_market_partner_cancel_customer_ci_v67(p_session_token text,p_device_id text,p_order_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_ci public.rr_market_partner_customer_ci_v67%rowtype;v_pi text;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 if nullif(trim(p_reason),'')is null then raise exception 'Cancellation reason is required.';end if;
 select * into v_ci from public.rr_market_partner_customer_ci_v67 where source_order_id=p_order_id and owner_customer_id=v_owner and status='FINAL'for update;
 if v_ci.id is null then raise exception 'Only an active customer CI can be cancelled.';end if;
 update public.rr_market_partner_customer_ci_v67 set status='CANCELLED',cancelled_at=now(),cancellation_reason=trim(p_reason)where id=v_ci.id;
 update public.rr_market_partner_order_v67 set status='CI_FINAL',customer_ci_ref=null,customer_ci_visible=false,customer_ci_pushed_at=null,updated_at=now()
 where id=p_order_id and owner_customer_id=v_owner returning distributor_pi_ref into v_pi;
 insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,note,actor_kind,payload)
 values(v_owner,p_order_id,'CUSTOMER_CI_CANCELLED_PI_RESTORED',trim(p_reason),'DISTRIBUTOR',jsonb_build_object('cancelled_ci_ref',v_ci.customer_ci_ref,'restored_pi_ref',v_pi));
 return jsonb_build_object('ok',true,'status','CI_FINAL','cancelled_ci_ref',v_ci.customer_ci_ref,'distributor_pi_ref',v_pi,'revision_no',v_ci.revision_no);
end $$;

revoke all on function public.rr_market_staff_cancel_ci_v67(uuid,text)from public,anon;
revoke all on function public.rr_market_partner_cancel_customer_ci_v67(text,text,uuid,text)from public;
grant execute on function public.rr_market_staff_cancel_ci_v67(uuid,text)to authenticated,service_role;
grant execute on function public.rr_market_partner_cancel_customer_ci_v67(text,text,uuid,text)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_convert_customer_ci_v67(text,text,uuid)to anon,authenticated,service_role;

-- Keep the distributor's customer PI editable after upstream CI allocation;
-- lock it only while an active downstream customer CI exists.
create or replace function public.rr_market_partner_make_customer_pi_v67(
 p_session_token text,p_device_id text,p_order_id uuid,p_lines jsonb,p_note text default null
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_order public.rr_market_partner_order_v67%rowtype;
 v_line public.rr_market_partner_order_line_v67%rowtype;v_input jsonb;v_qty int;v_limit int;
 v_ref text;v_expected int;v_supplied int;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select * into v_order from public.rr_market_partner_order_v67 o
 where o.id=p_order_id and o.owner_customer_id=v_owner and o.data_mode='TEST'and o.status<>'CANCELLED'
  and not exists(select 1 from public.rr_market_partner_customer_ci_v67 ci where ci.source_order_id=o.id and ci.status='FINAL')for update;
 if v_order.id is null then raise exception 'PI is locked only while an active customer CI exists, or requirement is unavailable.';end if;
 if jsonb_typeof(p_lines)<>'array'or jsonb_array_length(p_lines)=0 then raise exception 'PI needs every requirement line.';end if;
 select count(*)into v_expected from public.rr_market_partner_order_line_v67 where order_id=v_order.id;
 select count(distinct(value->>'line_id'))into v_supplied from jsonb_array_elements(p_lines);
 if v_supplied<>v_expected or jsonb_array_length(p_lines)<>v_expected then raise exception 'PI needs every requirement line exactly once.';end if;
 for v_input in select value from jsonb_array_elements(p_lines)loop
  begin v_qty:=(v_input->>'qty')::int;exception when others then raise exception 'PI quantity must be a whole number.';end;
  if v_qty is null or v_qty<0 then raise exception 'PI quantity cannot be negative or empty.';end if;
  select * into v_line from public.rr_market_partner_order_line_v67 where id=(v_input->>'line_id')::uuid and order_id=v_order.id for update;
  if v_line.id is null then raise exception 'PI line does not belong to this requirement.';end if;
  v_limit:=case when v_order.ci_ref is not null then coalesce(v_line.confirmed_qty,v_line.proposed_qty,v_line.requested_qty)else v_line.requested_qty end;
  if v_qty>coalesce(v_limit,0)then raise exception 'Customer PI quantity cannot exceed REDZED allocation for lot %.',v_line.lot_no;end if;
  update public.rr_market_partner_order_line_v67 set distributor_pi_qty=v_qty,distributor_pi_decision='WAITING',
   distributor_pi_customer_qty=null,distributor_pi_note=null,updated_at=now()where id=v_line.id;
 end loop;
 v_ref:=coalesce(v_order.distributor_pi_ref,public.rr_market_partner_next_distributor_pi_v67());
 update public.rr_market_partner_order_v67 set distributor_pi_ref=v_ref,
  distributor_pi_created_at=coalesce(distributor_pi_created_at,now()),distributor_pi_visible=true,
  distributor_pi_pushed_at=now(),distributor_pi_status='WAITING',distributor_pi_note=nullif(trim(p_note),''),
  distributor_pi_responded_at=null,status=case when status='DRAFT'then'READY'else status end,
  customer_closed_at=case when status='DRAFT'then coalesce(customer_closed_at,now())else customer_closed_at end,updated_at=now()
 where id=v_order.id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,note,actor_kind,payload)
 values(v_owner,v_order.id,'DISTRIBUTOR_PI_SENT_TO_CUSTOMER',nullif(trim(p_note),''),'DISTRIBUTOR',jsonb_build_object(
  'distributor_pi_ref',v_ref,'requirement_display_no',v_order.requirement_display_no,'confirmation_optional',true,
  'reconciled_with_redzed',v_order.ci_ref is not null,'pi_revision',v_order.distributor_pi_ref is not null));
 return jsonb_build_object('ok',true,'order_id',v_order.id,'distributor_pi_ref',v_ref,'distributor_pi_status','WAITING',
  'requirement_status',case when v_order.status='DRAFT'then'READY'else v_order.status end,'sent_to','DISTRIBUTOR_CUSTOMER');
end $$;

create or replace function public.rr_market_partner_customer_pi_charges_v67(
 p_session_token text,p_device_id text,p_order_id uuid,p_value_pct numeric default 0,
 p_freight numeric default 0,p_other numeric default 0,p_tax_pct numeric default 0
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_order public.rr_market_partner_order_v67%rowtype;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 if coalesce(p_value_pct,0)<-100 or coalesce(p_value_pct,0)>100 then raise exception 'Value Added/Less must be between -100 and 100.';end if;
 if coalesce(p_freight,0)<0 or coalesce(p_other,0)<0 or coalesce(p_tax_pct,0)<0 then raise exception 'Charges cannot be negative.';end if;
 update public.rr_market_partner_order_v67 o set distributor_pi_value_pct=coalesce(p_value_pct,0),
  distributor_pi_freight=coalesce(p_freight,0),distributor_pi_other=coalesce(p_other,0),
  distributor_pi_tax_pct=coalesce(p_tax_pct,0),updated_at=now()
 where o.id=p_order_id and o.owner_customer_id=v_owner and o.data_mode='TEST'and o.status<>'CANCELLED'
  and not exists(select 1 from public.rr_market_partner_customer_ci_v67 ci where ci.source_order_id=o.id and ci.status='FINAL')returning * into v_order;
 if v_order.id is null then raise exception 'PI charges are locked only while an active customer CI exists, or requirement is unavailable.';end if;
 return jsonb_build_object('value_pct',v_order.distributor_pi_value_pct,'freight',v_order.distributor_pi_freight,'other',v_order.distributor_pi_other,'tax_pct',v_order.distributor_pi_tax_pct);
end $$;

revoke all on function public.rr_market_partner_make_customer_pi_v67(text,text,uuid,jsonb,text)from public;
revoke all on function public.rr_market_partner_customer_pi_charges_v67(text,text,uuid,numeric,numeric,numeric,numeric)from public;
grant execute on function public.rr_market_partner_make_customer_pi_v67(text,text,uuid,jsonb,text)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_pi_charges_v67(text,text,uuid,numeric,numeric,numeric,numeric)to anon,authenticated,service_role;
