-- TEST67: a cancelled REDZED CI reopens the mapped PI as a new editable
-- revision.  Each revision can be sent once, then becomes immutable again.

alter table public.rr_market_partner_batch_v67
  add column if not exists pi_revision_no integer not null default 1,
  add column if not exists pi_revision_open boolean not null default false,
  add column if not exists pi_value_pct numeric(8,2) not null default 0,
  add column if not exists pi_freight numeric(14,2) not null default 0,
  add column if not exists pi_other numeric(14,2) not null default 0;

create table if not exists public.rr_market_partner_batch_pi_extra_line_v67(
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.rr_market_partner_batch_v67(id) on delete cascade,
  lot_no text not null,
  article_name text,
  category text,
  size_text text,
  image_url text,
  proposed_qty integer not null check(proposed_qty > 0),
  base_rate numeric(14,2) not null default 0,
  customer_rate numeric(14,2) not null default 0,
  available_qty integer not null default 0,
  stock_type text,
  pack_pcs_per_box integer not null default 0,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(batch_id,lot_no)
);

alter table public.rr_market_partner_batch_pi_extra_line_v67 enable row level security;
revoke all on table public.rr_market_partner_batch_pi_extra_line_v67 from public,anon,authenticated;

-- Existing batches that are currently at a genuine CI-cancel rollback event
-- must open immediately; ordinary already-sent PIs remain locked.
update public.rr_market_partner_batch_v67 b
set pi_revision_open=true,
    pi_revision_no=greatest(2,coalesce(b.pi_revision_no,1)+1),
    updated_at=now()
where b.data_mode='TEST'
  and b.status='WAITING_CONFIRMATION'
  and b.pi_ref is not null
  and b.ci_ref is null
  and exists(
    select 1 from public.rr_market_partner_event_v67 e
    where e.batch_id=b.id and e.event_type='REDZED_CI_CANCELLED_PI_RESTORED'
  );

create or replace function public.rr_market_staff_batch_detail_v67(p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_batch public.rr_market_partner_batch_v67%rowtype;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select * into v_batch from public.rr_market_partner_batch_v67 where id=p_batch_id and data_mode='TEST';
 if v_batch.id is null then raise exception 'TEST67 requirement not found.';end if;
 return jsonb_build_object('id',v_batch.id,'batch_ref',v_batch.batch_ref,'sequence_no',v_batch.sequence_no,
  'batch_kind',v_batch.batch_kind,'requirement_display_no',v_batch.requirement_display_no,'status',v_batch.status,
  'direct_customer_id',v_batch.owner_customer_id,
  'direct_customer_name',(select customer_name from public.rr_customers where id=v_batch.owner_customer_id),
  'pi_ref',v_batch.pi_ref,'ci_ref',v_batch.ci_ref,'pi_confirmation_required',false,
  'pi_revision_no',v_batch.pi_revision_no,'pi_revision_open',v_batch.pi_revision_open,
  'charges',jsonb_build_object('value_pct',v_batch.pi_value_pct,'freight',v_batch.pi_freight,'other',v_batch.pi_other,'tax_pct',0),
  'extra_lines',(select coalesce(jsonb_agg(jsonb_build_object(
    'id',x.id,'lot_no',x.lot_no,'article_name',x.article_name,'category',x.category,'size_text',x.size_text,
    'image_url',x.image_url,'requested_qty',0,'proposed_qty',x.proposed_qty,'base_rate',x.base_rate,
    'customer_rate',x.customer_rate,'final_customer_rate',x.customer_rate,'available_qty',x.available_qty,
    'stock_type',x.stock_type,'pack_pcs_per_box',x.pack_pcs_per_box,'is_extra',true
   )order by x.created_at,x.lot_no),'[]'::jsonb) from public.rr_market_partner_batch_pi_extra_line_v67 x where x.batch_id=v_batch.id),
  'orders',(select jsonb_agg(jsonb_build_object('id',o.id,'order_ref',o.order_ref,
   'requirement_display_no',o.requirement_display_no,'status',o.status,'customer_ref',c.customer_ref,
   'customer_pi_status',o.customer_pi_status,
   'lines',(select jsonb_agg(jsonb_build_object('id',l.id,'lot_no',l.lot_no,'article_name',l.article_name,
    'category',l.category,'size_text',l.size_text,'image_url',l.image_url,'requested_qty',l.requested_qty,
    'proposed_qty',l.proposed_qty,'confirmed_qty',l.confirmed_qty,'base_rate',l.base_rate,
    'customer_rate',l.customer_rate,'final_customer_rate',l.customer_rate,
    'confirmation_status',l.confirmation_status,'customer_pi_decision',l.customer_pi_decision,
    'customer_pi_qty',l.customer_pi_qty)order by l.lot_no)
    from public.rr_market_partner_order_line_v67 l where l.order_id=o.id))order by o.requirement_no,o.requirement_update_no)
   from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id
   join public.rr_market_partner_customer_v67 c on c.id=o.partner_customer_id where m.batch_id=v_batch.id),
  'consolidated',(select jsonb_agg(x order by x->>'lot_no')from(
   select jsonb_build_object('lot_no',l.lot_no,'article_name',max(l.article_name),'category',max(l.category),
    'size_text',max(l.size_text),'customer_count',count(distinct o.partner_customer_id),'order_count',count(distinct o.id),
    'total_requested_qty',sum(l.requested_qty),'total_proposed_qty',sum(coalesce(l.proposed_qty,l.requested_qty)),
    'total_confirmed_qty',sum(coalesce(l.confirmed_qty,0)))x
   from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id
   join public.rr_market_partner_order_line_v67 l on l.order_id=o.id where m.batch_id=v_batch.id group by l.lot_no
  )q));
end $$;

create or replace function public.rr_market_staff_pi_extra_lot_add_v67(
 p_batch_id uuid,p_lot_no text,p_qty integer
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_batch public.rr_market_partner_batch_v67%rowtype;v_context jsonb;v_name text;
 v_lot text;v_available integer;v_existing integer;v_rate numeric;v_stock text;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 v_lot:=upper(trim(coalesce(p_lot_no,'')));
 if v_lot=''or coalesce(p_qty,0)<=0 then raise exception 'Lot No. and positive Qty are required.';end if;
 select * into v_batch from public.rr_market_partner_batch_v67
 where id=p_batch_id and data_mode='TEST'and ci_ref is null
  and status in('SUBMITTED','PI_PROPOSED','WAITING_CONFIRMATION')
  and(pi_ref is null or pi_revision_open)for update;
 if v_batch.id is null then raise exception 'PI revision is locked. Rollback or open a revision before adding a lot.';end if;
 if exists(select 1 from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_line_v67 l on l.order_id=m.order_id
  where m.batch_id=p_batch_id and upper(trim(l.lot_no))=v_lot)then
  raise exception 'Lot % is already mapped in the source requirement. Edit its Working PI Qty instead.',v_lot;
 end if;
 select customer_name into v_name from public.rr_customers where id=v_batch.owner_customer_id;
 v_context:=public.rr_pi_replace_lot_context_v9553(v_lot,coalesce(v_name,''),'TEST');
 v_available:=coalesce((v_context->>'replace_available_qty')::integer,0);
 v_stock:=nullif(v_context->>'replace_stock_type','');
 v_rate:=coalesce(nullif(v_context->>'effective_rate','')::numeric,nullif(v_context->>'approved_rate','')::numeric,0);
 select coalesce(proposed_qty,0)into v_existing from public.rr_market_partner_batch_pi_extra_line_v67
 where batch_id=p_batch_id and upper(trim(lot_no))=v_lot;
 v_existing:=coalesce(v_existing,0);
 if v_stock is null or v_available<=0 then raise exception 'Lot % has no sellable stock.',v_lot;end if;
 if v_existing+p_qty>v_available then raise exception 'Lot % total PI Qty % exceeds available % stock %.',v_lot,v_existing+p_qty,v_stock,v_available;end if;
 insert into public.rr_market_partner_batch_pi_extra_line_v67(
  batch_id,lot_no,article_name,category,size_text,image_url,proposed_qty,base_rate,customer_rate,
  available_qty,stock_type,pack_pcs_per_box,created_by
 )values(
  p_batch_id,v_lot,coalesce(v_context->>'item_name',v_context->>'category',v_lot),v_context->>'category',
  v_context->>'size_text',v_context->>'image',p_qty,v_rate,v_rate,v_available,v_stock,
  coalesce(nullif(v_context->>'pack_pcs_per_box','')::integer,0),auth.uid()
 )on conflict(batch_id,lot_no)do update set proposed_qty=public.rr_market_partner_batch_pi_extra_line_v67.proposed_qty+excluded.proposed_qty,
  available_qty=excluded.available_qty,stock_type=excluded.stock_type,updated_at=now();
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
 values(v_batch.owner_customer_id,p_batch_id,'REDZED_PI_EXTRA_LOT_ADDED','STAFF',auth.uid(),jsonb_build_object('lot_no',v_lot,'qty',p_qty,'pi_revision_no',v_batch.pi_revision_no));
 return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

create or replace function public.rr_market_staff_pi_extra_lot_remove_v67(
 p_batch_id uuid,p_line_id uuid
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_owner uuid;v_lot text;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select owner_customer_id into v_owner from public.rr_market_partner_batch_v67
 where id=p_batch_id and data_mode='TEST'and ci_ref is null
  and status in('SUBMITTED','PI_PROPOSED','WAITING_CONFIRMATION')and(pi_ref is null or pi_revision_open)for update;
 if v_owner is null then raise exception 'PI revision is locked.';end if;
 delete from public.rr_market_partner_batch_pi_extra_line_v67 where id=p_line_id and batch_id=p_batch_id returning lot_no into v_lot;
 if v_lot is null then raise exception 'Extra PI line not found.';end if;
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
 values(v_owner,p_batch_id,'REDZED_PI_EXTRA_LOT_REMOVED','STAFF',auth.uid(),jsonb_build_object('lot_no',v_lot));
 return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

create or replace function public.rr_market_staff_save_pi_working_v67(
 p_batch_id uuid,p_line_proposals jsonb,p_value_pct numeric default 0,p_freight numeric default 0,
 p_other numeric default 0,p_send boolean default false
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_batch public.rr_market_partner_batch_v67%rowtype;v_line jsonb;v_line_id uuid;v_qty integer;
 v_ref text;v_expected integer;v_supplied integer;v_event text;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select * into v_batch from public.rr_market_partner_batch_v67 where id=p_batch_id and data_mode='TEST'for update;
 if v_batch.id is null then raise exception 'TEST67 requirement not found.';end if;
 if v_batch.ci_ref is not null or v_batch.status='CI_FINAL' then raise exception 'CI is final. Cancel CI to reopen the PI.';end if;
 if v_batch.pi_ref is not null and not v_batch.pi_revision_open then
  return public.rr_market_staff_batch_detail_v67(p_batch_id)||jsonb_build_object('already_sent',true);
 end if;
 if v_batch.status not in('SUBMITTED','PI_PROPOSED','WAITING_CONFIRMATION')then raise exception 'PI cannot be edited in the current status.';end if;
 if jsonb_typeof(p_line_proposals)<>'array'then raise exception 'PI quantities are required.';end if;
 if coalesce(p_value_pct,0)<-100 or coalesce(p_value_pct,0)>100 then raise exception 'Value Added/Less must be between -100 and 100.';end if;
 if coalesce(p_freight,0)<0 or coalesce(p_other,0)<0 then raise exception 'Charges cannot be negative.';end if;
 select count(*)+(select count(*)from public.rr_market_partner_batch_pi_extra_line_v67 x where x.batch_id=p_batch_id)
 into v_expected from public.rr_market_partner_order_line_v67 l
 where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=l.order_id);
 select count(distinct(value->>'line_id'))into v_supplied from jsonb_array_elements(p_line_proposals);
 if v_expected<>v_supplied or jsonb_array_length(p_line_proposals)<>v_expected then raise exception 'PI needs every mapped and add-on line exactly once.';end if;
 for v_line in select value from jsonb_array_elements(p_line_proposals)loop
  v_line_id:=(v_line->>'line_id')::uuid;v_qty:=coalesce((v_line->>'proposed_qty')::integer,0);
  if v_qty<0 then raise exception 'Proposed quantity cannot be negative.';end if;
  update public.rr_market_partner_order_line_v67 l set proposed_qty=v_qty,updated_at=now()
  where l.id=v_line_id and exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=l.order_id);
  if not found then
   if v_qty<=0 then raise exception 'Add-on lot quantity must remain positive or remove the row.';end if;
   update public.rr_market_partner_batch_pi_extra_line_v67 set proposed_qty=v_qty,updated_at=now()
   where id=v_line_id and batch_id=p_batch_id and v_qty<=available_qty;
   if not found then raise exception 'Add-on line is invalid or exceeds available stock.';end if;
  end if;
 end loop;
 update public.rr_market_partner_batch_v67 set pi_value_pct=coalesce(p_value_pct,0),pi_freight=coalesce(p_freight,0),
  pi_other=coalesce(p_other,0),updated_at=now()where id=p_batch_id;
 if not p_send then
  insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
  values(v_batch.owner_customer_id,p_batch_id,'REDZED_PI_REVISION_DRAFT_SAVED','STAFF',auth.uid(),jsonb_build_object('pi_revision_no',v_batch.pi_revision_no));
  return public.rr_market_staff_batch_detail_v67(p_batch_id)||jsonb_build_object('already_sent',false);
 end if;
 v_ref:=coalesce(v_batch.pi_ref,case when v_batch.batch_kind='CONSOLIDATED'then'CONSOLIDATED PI 'else'REDZED PI 'end||v_batch.sequence_no);
 update public.rr_market_partner_order_line_v67 l set confirmed_qty=null,confirmation_status='WAITING',
  customer_pi_decision='WAITING',customer_pi_qty=null,customer_pi_note=null,updated_at=now()
 where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=l.order_id);
 update public.rr_market_partner_order_v67 o set status='PI_PROPOSED',pi_ref=v_ref,customer_pi_visible=false,
  customer_pi_pushed_at=null,customer_pi_status='WAITING',customer_pi_note=null,customer_pi_responded_at=null,updated_at=now()
 where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=o.id);
 update public.rr_market_partner_batch_v67 set status='WAITING_CONFIRMATION',pi_ref=v_ref,pi_revision_open=false,updated_at=now()where id=p_batch_id;
 v_event:=case when v_batch.pi_ref is null then'REDZED_PI_SENT_TO_DISTRIBUTOR'else'REDZED_PI_REVISION_SENT_TO_DISTRIBUTOR'end;
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
 values(v_batch.owner_customer_id,p_batch_id,v_event,'STAFF',auth.uid(),jsonb_build_object('pi_ref',v_ref,'batch_kind',v_batch.batch_kind,'pi_revision_no',v_batch.pi_revision_no));
 return public.rr_market_staff_batch_detail_v67(p_batch_id)||jsonb_build_object('already_sent',false);
end $$;

create or replace function public.rr_market_staff_save_batch_draft_v67(p_batch_id uuid,p_line_proposals jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_batch public.rr_market_partner_batch_v67%rowtype;
begin
 select * into v_batch from public.rr_market_partner_batch_v67 where id=p_batch_id;
 return public.rr_market_staff_save_pi_working_v67(p_batch_id,p_line_proposals,v_batch.pi_value_pct,v_batch.pi_freight,v_batch.pi_other,false);
end $$;

create or replace function public.rr_market_staff_propose_batch_v67(p_batch_id uuid,p_line_proposals jsonb,p_pi_ref text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_batch public.rr_market_partner_batch_v67%rowtype;
begin
 select * into v_batch from public.rr_market_partner_batch_v67 where id=p_batch_id;
 return public.rr_market_staff_save_pi_working_v67(p_batch_id,p_line_proposals,v_batch.pi_value_pct,v_batch.pi_freight,v_batch.pi_other,true);
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
 update public.rr_market_partner_order_v67 o set status='PI_PROPOSED',ci_ref=null,customer_ci_visible=false,customer_ci_pushed_at=null,updated_at=now()
 where o.status<>'CANCELLED'and exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=o.id);
 update public.rr_market_partner_batch_v67 set status='WAITING_CONFIRMATION',ci_ref=null,pi_revision_open=true,
  pi_revision_no=greatest(1,pi_revision_no)+1,updated_at=now()where id=p_batch_id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,note,actor_kind,actor_id,payload)
 values(v_owner,p_batch_id,'REDZED_CI_CANCELLED_PI_RESTORED',trim(p_reason),'STAFF',auth.uid(),jsonb_build_object('cancelled_ci_ref',v_old_ci));
 return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

create or replace function public.rr_market_staff_finalize_ci_v67(p_batch_id uuid,p_ci_ref text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_owner uuid;v_ref text;v_seq int;v_kind text;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select owner_customer_id,ci_ref,sequence_no,batch_kind into v_owner,v_ref,v_seq,v_kind
 from public.rr_market_partner_batch_v67 where id=p_batch_id and data_mode='TEST'
  and status in('WAITING_CONFIRMATION','CONFIRMED','PARTIAL_CONFIRMED','CI_FINAL')and pi_ref is not null and not pi_revision_open for update;
 if v_owner is null then raise exception 'Save and send the current PI revision before creating CI.';end if;
 v_ref:=coalesce(nullif(trim(p_ci_ref),''),v_ref,case when v_kind='CONSOLIDATED'then'CONSOLIDATED CI 'else'REDZED CI 'end||v_seq);
 update public.rr_market_partner_order_line_v67 l set confirmed_qty=coalesce(l.confirmed_qty,l.proposed_qty,l.requested_qty),updated_at=now()
 where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=l.order_id)and l.confirmation_status='WAITING';
 update public.rr_market_partner_batch_v67 set status='CI_FINAL',ci_ref=v_ref,updated_at=now()where id=p_batch_id;
 update public.rr_market_partner_order_v67 o set status=case when o.status='CANCELLED'then'CANCELLED'else'CI_FINAL'end,
  ci_ref=v_ref,customer_ci_visible=false,updated_at=now()
 where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=o.id);
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
 values(v_owner,p_batch_id,'REDZED_CI_SENT_TO_DISTRIBUTOR','STAFF',auth.uid(),jsonb_build_object('ci_ref',v_ref,'batch_kind',v_kind,'confirmation_optional',true));
 return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

revoke all on function public.rr_market_staff_pi_extra_lot_add_v67(uuid,text,integer)from public,anon;
revoke all on function public.rr_market_staff_pi_extra_lot_remove_v67(uuid,uuid)from public,anon;
revoke all on function public.rr_market_staff_save_pi_working_v67(uuid,jsonb,numeric,numeric,numeric,boolean)from public,anon;
revoke all on function public.rr_market_staff_save_batch_draft_v67(uuid,jsonb)from public,anon;
revoke all on function public.rr_market_staff_propose_batch_v67(uuid,jsonb,text)from public,anon;
revoke all on function public.rr_market_staff_cancel_ci_v67(uuid,text)from public,anon;
revoke all on function public.rr_market_staff_finalize_ci_v67(uuid,text)from public,anon;
grant execute on function public.rr_market_staff_pi_extra_lot_add_v67(uuid,text,integer)to authenticated,service_role;
grant execute on function public.rr_market_staff_pi_extra_lot_remove_v67(uuid,uuid)to authenticated,service_role;
grant execute on function public.rr_market_staff_save_pi_working_v67(uuid,jsonb,numeric,numeric,numeric,boolean)to authenticated,service_role;
grant execute on function public.rr_market_staff_save_batch_draft_v67(uuid,jsonb)to authenticated,service_role;
grant execute on function public.rr_market_staff_propose_batch_v67(uuid,jsonb,text)to authenticated,service_role;
grant execute on function public.rr_market_staff_cancel_ci_v67(uuid,text)to authenticated,service_role;
grant execute on function public.rr_market_staff_finalize_ci_v67(uuid,text)to authenticated,service_role;
