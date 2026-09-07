-- TEST67: explicit REDZED single/consolidated requirement -> draft -> PI -> CI journey.

alter table public.rr_market_partner_batch_v67
  add column if not exists sequence_no integer,
  add column if not exists batch_kind text,
  add column if not exists requirement_display_no text;

with ranked as (
  select id,
         row_number() over (partition by owner_customer_id order by submitted_at,id)::integer as seq,
         (select count(*) from public.rr_market_partner_batch_member_v67 m where m.batch_id=b.id) as member_count
  from public.rr_market_partner_batch_v67 b
)
update public.rr_market_partner_batch_v67 b
set sequence_no=coalesce(b.sequence_no,r.seq),
    batch_kind=coalesce(b.batch_kind,case when r.member_count>1 then 'CONSOLIDATED' else 'SINGLE' end),
    requirement_display_no=coalesce(b.requirement_display_no,
      case when r.member_count>1 then 'CONSOLIDATED REQUIREMENT ' else 'REDZED REQUIREMENT ' end||r.seq)
from ranked r where r.id=b.id;

alter table public.rr_market_partner_batch_v67
  alter column sequence_no set not null,
  alter column batch_kind set not null,
  alter column requirement_display_no set not null;

alter table public.rr_market_partner_batch_v67 drop constraint if exists rr_market_partner_batch_v67_batch_kind_check;
alter table public.rr_market_partner_batch_v67 add constraint rr_market_partner_batch_v67_batch_kind_check
  check(batch_kind in('SINGLE','CONSOLIDATED'));
create unique index if not exists rr_market_partner_batch_sequence_v67_uq
  on public.rr_market_partner_batch_v67(owner_customer_id,sequence_no,data_mode);

create or replace function public.rr_market_partner_batch_submit_v67(
 p_session_token text,p_device_id text,p_order_ids uuid[]
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_batch uuid;v_batch_ref text;v_count int;v_refs jsonb;
 v_seq int;v_kind text;v_display text;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
 if not(v_ctx->>'send_collection_enabled')::boolean then raise exception 'Requirement push is disabled.';end if;
 v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select count(*)into v_count from public.rr_market_partner_order_v67
 where id=any(p_order_ids)and owner_customer_id=v_owner and status='READY'and customer_closed_at is not null;
 if coalesce(array_length(p_order_ids,1),0)=0 or v_count<>array_length(p_order_ids,1)then
  raise exception 'Only customer-closed requirements can be sent to REDZED.';
 end if;
 select jsonb_agg(requirement_display_no order by requirement_no,requirement_update_no)into v_refs
 from public.rr_market_partner_order_v67 where id=any(p_order_ids);
 perform pg_advisory_xact_lock(hashtext('rr_market_partner_batch:'||v_owner::text));
 select coalesce(max(sequence_no),0)+1 into v_seq from public.rr_market_partner_batch_v67
 where owner_customer_id=v_owner and data_mode='TEST';
 v_kind:=case when v_count>1 then 'CONSOLIDATED' else 'SINGLE' end;
 v_display:=case when v_count>1 then 'CONSOLIDATED REQUIREMENT ' else 'REDZED REQUIREMENT ' end||v_seq;
 v_batch_ref:='B-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.rr_market_partner_batch_v67(owner_customer_id,batch_ref,sequence_no,batch_kind,requirement_display_no)
 values(v_owner,v_batch_ref,v_seq,v_kind,v_display)returning id into v_batch;
 insert into public.rr_market_partner_batch_member_v67(batch_id,order_id)select v_batch,unnest(p_order_ids);
 update public.rr_market_partner_order_v67 set status='BATCHED',redzed_pushed_at=now(),updated_at=now()where id=any(p_order_ids);
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,payload)
 values(v_owner,v_batch,'CLOSED_REQUIREMENTS_PUSHED_TO_REDZED','DISTRIBUTOR',jsonb_build_object(
  'order_count',v_count,'requirements',coalesce(v_refs,'[]'::jsonb),'requirement_display_no',v_display,
  'batch_kind',v_kind,'destination','REDZED_STAFF_QUEUE'));
 return jsonb_build_object('batch_id',v_batch,'batch_ref',v_batch_ref,'sequence_no',v_seq,
  'batch_kind',v_kind,'requirement_display_no',v_display,'order_count',v_count,'status','SUBMITTED',
  'redzed_status','PUSHED','requirements',coalesce(v_refs,'[]'::jsonb));
end $$;

create or replace function public.rr_market_staff_save_batch_draft_v67(
 p_batch_id uuid,p_line_proposals jsonb
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_line jsonb;v_line_id uuid;v_qty int;v_owner uuid;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select owner_customer_id into v_owner from public.rr_market_partner_batch_v67
 where id=p_batch_id and data_mode='TEST'and status='SUBMITTED' for update;
 if v_owner is null then raise exception 'Only a submitted requirement can be saved as draft.';end if;
 if jsonb_typeof(p_line_proposals)<>'array' then raise exception 'Draft quantities are required.';end if;
 for v_line in select value from jsonb_array_elements(p_line_proposals) loop
  v_line_id:=(v_line->>'line_id')::uuid;v_qty:=greatest(0,coalesce((v_line->>'proposed_qty')::int,0));
  update public.rr_market_partner_order_line_v67 l set proposed_qty=v_qty,updated_at=now()
  where l.id=v_line_id and exists(select 1 from public.rr_market_partner_batch_member_v67 m
    where m.batch_id=p_batch_id and m.order_id=l.order_id);
  if not found then raise exception 'Draft line does not belong to this requirement.';end if;
 end loop;
 update public.rr_market_partner_batch_v67 set updated_at=now() where id=p_batch_id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
 values(v_owner,p_batch_id,'REDZED_REQUIREMENT_DRAFT_SAVED','STAFF',auth.uid(),jsonb_build_object('line_count',jsonb_array_length(p_line_proposals)));
 return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

create or replace function public.rr_market_staff_propose_batch_v67(
 p_batch_id uuid,p_line_proposals jsonb,p_pi_ref text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_line jsonb;v_line_id uuid;v_qty int;v_owner uuid;v_ref text;v_seq int;v_kind text;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select owner_customer_id,sequence_no,batch_kind,pi_ref into v_owner,v_seq,v_kind,v_ref
 from public.rr_market_partner_batch_v67
 where id=p_batch_id and data_mode='TEST'and status in('SUBMITTED','PI_PROPOSED','WAITING_CONFIRMATION')for update;
 if v_owner is null then raise exception 'Requirement cannot receive a PI proposal.';end if;
 v_ref:=coalesce(nullif(trim(p_pi_ref),''),v_ref,
   case when v_kind='CONSOLIDATED' then 'CONSOLIDATED PI ' else 'REDZED PI ' end||v_seq);
 for v_line in select value from jsonb_array_elements(p_line_proposals)loop
  v_line_id:=(v_line->>'line_id')::uuid;v_qty:=(v_line->>'proposed_qty')::int;
  if v_qty<0 then raise exception 'Proposed quantity cannot be negative.';end if;
  update public.rr_market_partner_order_line_v67 l set proposed_qty=v_qty,confirmed_qty=null,
   confirmation_status='WAITING',customer_pi_decision='WAITING',customer_pi_qty=null,customer_pi_note=null,updated_at=now()
  where l.id=v_line_id and exists(select 1 from public.rr_market_partner_batch_member_v67 m
   where m.batch_id=p_batch_id and m.order_id=l.order_id);
  if not found then raise exception 'Proposal line does not belong to requirement.';end if;
 end loop;
 update public.rr_market_partner_order_v67 o set status='PI_PROPOSED',pi_ref=v_ref,
  customer_pi_visible=false,customer_pi_pushed_at=null,customer_pi_status='WAITING',customer_pi_note=null,
  customer_pi_responded_at=null,updated_at=now()
 where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=o.id);
 update public.rr_market_partner_batch_v67 set status='WAITING_CONFIRMATION',pi_ref=v_ref,updated_at=now()where id=p_batch_id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
 values(v_owner,p_batch_id,'REDZED_PI_SENT_TO_DISTRIBUTOR','STAFF',auth.uid(),jsonb_build_object('pi_ref',v_ref,'batch_kind',v_kind));
 return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

create or replace function public.rr_market_staff_finalize_ci_v67(p_batch_id uuid,p_ci_ref text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_owner uuid;v_ref text;v_seq int;v_kind text;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select owner_customer_id,ci_ref,sequence_no,batch_kind into v_owner,v_ref,v_seq,v_kind
 from public.rr_market_partner_batch_v67
 where id=p_batch_id and data_mode='TEST'and status in('WAITING_CONFIRMATION','CONFIRMED','PARTIAL_CONFIRMED','CI_FINAL')for update;
 if v_owner is null then raise exception 'REDZED PI must exist before CI.';end if;
 v_ref:=coalesce(nullif(trim(p_ci_ref),''),v_ref,
   case when v_kind='CONSOLIDATED' then 'CONSOLIDATED CI ' else 'REDZED CI ' end||v_seq);
 update public.rr_market_partner_batch_v67 set status='CI_FINAL',ci_ref=v_ref,updated_at=now()where id=p_batch_id;
 update public.rr_market_partner_order_v67 o set status=case when o.status='CANCELLED'then'CANCELLED'else'CI_FINAL'end,
  ci_ref=v_ref,customer_ci_visible=false,updated_at=now()
 where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=o.id);
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
 values(v_owner,p_batch_id,'REDZED_CI_SENT_TO_DISTRIBUTOR','STAFF',auth.uid(),jsonb_build_object(
  'ci_ref',v_ref,'batch_kind',v_kind,'pi_confirmation_required',false));
 return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

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
  'orders',(select jsonb_agg(jsonb_build_object('id',o.id,'order_ref',o.order_ref,
   'requirement_display_no',o.requirement_display_no,'status',o.status,'customer_ref',c.customer_ref,
   'customer_pi_status',o.customer_pi_status,
   'lines',(select jsonb_agg(jsonb_build_object('id',l.id,'lot_no',l.lot_no,'article_name',l.article_name,
    'category',l.category,'size_text',l.size_text,'image_url',l.image_url,'requested_qty',l.requested_qty,
    'proposed_qty',l.proposed_qty,'confirmed_qty',l.confirmed_qty,'base_rate',l.base_rate,
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
    'status',o.status) order by o.requirement_no,o.requirement_update_no)
   from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id where m.batch_id=b.id)
 ) order by b.submitted_at desc) from public.rr_market_partner_batch_v67 b
 where b.owner_customer_id=v_owner and b.data_mode='TEST'),'[]'::jsonb);
end $$;

revoke all on function public.rr_market_staff_save_batch_draft_v67(uuid,jsonb) from public,anon;
revoke all on function public.rr_market_partner_batches_v67(text,text) from public;
grant execute on function public.rr_market_staff_save_batch_draft_v67(uuid,jsonb) to authenticated,service_role;
grant execute on function public.rr_market_partner_batches_v67(text,text) to anon,authenticated,service_role;

create or replace function public.rr_market_redzed_staff_distributor_relations_v83()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  perform public.rr_market_assert_sales_actor_v9420();
  return coalesce((select jsonb_agg(jsonb_build_object(
    'chat_id',r.chat_id,'owner_customer_id',r.owner_customer_id,'distributor_name',c.customer_name,
    'batches',coalesce((select jsonb_agg(jsonb_build_object(
      'id',b.id,'batch_ref',b.batch_ref,'sequence_no',b.sequence_no,'batch_kind',b.batch_kind,
      'requirement_display_no',b.requirement_display_no,'status',b.status,'pi_ref',b.pi_ref,'ci_ref',b.ci_ref,
      'order_count',(select count(*) from public.rr_market_partner_batch_member_v67 bm where bm.batch_id=b.id),
      'submitted_at',b.submitted_at) order by b.submitted_at desc)
      from public.rr_market_partner_batch_v67 b where b.owner_customer_id=r.owner_customer_id and b.data_mode='TEST'),'[]'::jsonb)
    ) order by c.customer_name)
    from public.rr_market_partner_relation_chat_v67 r join public.rr_customers c on c.id=r.owner_customer_id
    where r.relation_kind='DISTRIBUTOR_REDZED' and r.status='ACTIVE' and c.is_active),'[]'::jsonb);
end $$;
