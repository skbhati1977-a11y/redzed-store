-- TEST71: customer-only PI/CI receipt snapshots, atomic attachment send and content-idempotent delivery.
create table public.rr_pi_chat_deliveries_test71 (
 pi_id uuid not null references public.rr_fg_pi_v787(id),
 chat_id uuid not null references public.rr_customer_chat_v9433(id),
 fingerprint text not null,
 message_ids uuid[] not null,
 sent_by uuid not null,
 sent_at timestamptz not null default now(),
 primary key(pi_id,chat_id,fingerprint)
);
alter table public.rr_pi_chat_deliveries_test71 enable row level security;
revoke all on public.rr_pi_chat_deliveries_test71 from public,anon,authenticated;

create or replace function public.rr_pi_customer_document_test71(p_pi_id uuid,p_chat_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare p public.rr_fg_pi_v787%rowtype; a public.rr_user_profiles%rowtype; cid uuid; chat uuid; doc jsonb; items jsonb; fp text; delivery public.rr_pi_chat_deliveries_test71%rowtype;
begin
 perform public.rr_fg_assert_user_v787();
 a:=public.rr_chat_actor_profile_v9433();
 if lower(trim(a.role_code)) not in ('owner','super_admin','superadmin','admin','sales','salesman') then raise exception 'Sales/Admin/Super Admin required.'; end if;
 select * into p from public.rr_fg_pi_v787 where id=p_pi_id and data_mode='TEST';
 if not found then raise exception 'Saved TEST PI required.'; end if;
 cid:=nullif(p.buyer_snapshot->>'contact_customer_id','')::uuid;
 if cid is null then raise exception 'PI customer mapping required.'; end if;
 select c.id into chat from public.rr_customer_chat_v9433 c
 where c.customer_id=cid and c.data_mode='TEST' and c.relation_kind='DIRECT_CUSTOMER'
 and (p_chat_id is null or c.id=p_chat_id)
 and exists(select 1 from public.rr_customer_chat_members_v9433 m where m.chat_id=c.id and m.profile_id=a.id and m.is_active)
 order by c.updated_at desc,c.id limit 1;
 if chat is null then raise exception 'Matching party chat and active group membership required.'; end if;
 if p.market_requirement_id is not null and not exists(
 select 1 from public.rr_market_requirements_v9420 r where r.id=p.market_requirement_id and r.customer_id=cid)
 then raise exception 'PI requirement belongs to another customer.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
 'lot_no',l.lot_no,'item_name',l.short_item_name,'qty',l.qty,'gross_rate',coalesce(l.gross_rate,l.original_rate),
 'discount',coalesce(l.party_discount_per_piece,l.discount_amount,0),'net_rate',l.final_rate,'amount',l.amount)
 order by l.serial_no,l.lot_no,l.stock_type),'[]'::jsonb) into items from public.rr_fg_pi_lines_v787 l where l.pi_id=p.id;
 if jsonb_array_length(items)=0 then raise exception 'Saved PI items required.'; end if;
 doc:=jsonb_build_object('pi_id',p.id,'document_kind',case when p.status='CI_FINAL' then 'CI' else 'PI' end,
 'document_no',case when p.status='CI_FINAL' then coalesce(p.cpi_no,p.pi_no) else p.pi_no end,
 'customer_name',coalesce(p.buyer_snapshot->>'customer_name',p.buyer_snapshot->>'buyer_name'),
 'mobile',p.buyer_snapshot->>'mobile','address',p.buyer_snapshot->>'address','gstin',p.buyer_snapshot->>'gstin',
 'dispatch_details',p.dispatch_details,'lines',items,'sub_total',p.sub_total,'value_added_pct',p.value_added_pct,
 'value_added_amount',p.sub_total*coalesce(p.value_added_pct,0)/100,'freight_amount',p.freight_amount,
 'other_charges',p.packing_other,'gst_amount',p.gst_amount,'round_off',p.round_off,'grand_total',p.grand_total,
 'total_qty',(select sum(l.qty) from public.rr_fg_pi_lines_v787 l where l.pi_id=p.id));
 fp:=md5(doc::text);
 select * into delivery from public.rr_pi_chat_deliveries_test71 where pi_id=p.id and chat_id=chat and fingerprint=fp;
 return jsonb_build_object('chat_id',chat,'fingerprint',fp,'document',doc,
 'already_sent',delivery.pi_id is not null,'message_ids',to_jsonb(delivery.message_ids));
end $fn$;

create or replace function public.rr_pi_customer_document_send_test71(p_pi_id uuid,p_chat_id uuid,p_fingerprint text,p_pages jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare context jsonb; doc jsonb; a public.rr_user_profiles%rowtype; page jsonb; raw bytea; mid uuid; aid uuid;
 ids uuid[]:='{}'; num integer:=0; body text; fname text;
begin
 perform public.rr_fg_assert_user_v787();
 -- Serializes double taps/retries across tabs/devices and prevents sending a superseded snapshot.
 perform 1 from public.rr_fg_pi_v787 where id=p_pi_id and data_mode='TEST' for update;
 if not found then raise exception 'Saved TEST PI required.'; end if;
 context:=public.rr_pi_customer_document_test71(p_pi_id,p_chat_id);
 if context->>'fingerprint' is distinct from p_fingerprint then raise exception 'PI changed. Retry to send the latest saved bill.'; end if;
 if (context->>'already_sent')::boolean then
 return jsonb_build_object('sent',true,'already_sent',true,'message_ids',context->'message_ids'); end if;
 if jsonb_typeof(p_pages) is distinct from 'array' or jsonb_array_length(p_pages)<1 or jsonb_array_length(p_pages)>20 then raise exception '1 to 20 JPG receipt pages required.'; end if;
 a:=public.rr_chat_actor_profile_v9433(); doc:=context->'document';
 body:=concat(doc->>'document_kind',' ',doc->>'document_no',' · ',doc->>'customer_name',
 ' · ',doc->>'total_qty',' PCS · ₹',doc->>'grand_total',' · JPG receipt');
 for page in select value from jsonb_array_elements(p_pages) loop
 num:=num+1; raw:=decode(page->>'base64','base64');
 if raw is null or octet_length(raw)<4 or octet_length(raw)>6291456 or substring(raw from 1 for 2)<>decode('ffd8','hex') or substring(raw from octet_length(raw)-1 for 2)<>decode('ffd9','hex') then
 raise exception 'Valid JPG page up to 6 MB required.'; end if;
 mid:=gen_random_uuid(); aid:=gen_random_uuid();
 fname:=regexp_replace(doc->>'document_no','[^a-zA-Z0-9_-]','_','g')||'-'||num||'.jpg';
 insert into public.rr_customer_chat_messages_v9433(id,chat_id,channel,sender_kind,sender_profile_id,sender_name,message_type,body,payload)
 values(mid,(context->>'chat_id')::uuid,'GROUP','STAFF',a.id,a.full_name,'ATTACHMENT',
 body||case when jsonb_array_length(p_pages)>1 then concat(' · Page ',num,'/',jsonb_array_length(p_pages)) else '' end,
 jsonb_build_object('source','DIRECT_PI_DOCUMENT_TEST71','pi_id',p_pi_id,'document_kind',doc->>'document_kind',
 'document_no',doc->>'document_no','fingerprint',p_fingerprint,'document_page',num,'document_pages',jsonb_array_length(p_pages),
 'attachment_id',aid,'file_name',fname,'mime_type','image/jpeg','byte_size',octet_length(raw),
 'invoice_details',case when num=1 then doc else null end));
 insert into public.rr_customer_chat_attachments_v9434(id,message_id,chat_id,file_name,mime_type,byte_size,file_data)
 values(aid,mid,(context->>'chat_id')::uuid,fname,'image/jpeg',octet_length(raw),raw);
 ids:=array_append(ids,mid);
 end loop;
 insert into public.rr_pi_chat_deliveries_test71(pi_id,chat_id,fingerprint,message_ids,sent_by)
 values(p_pi_id,(context->>'chat_id')::uuid,p_fingerprint,ids,auth.uid());
 return jsonb_build_object('sent',true,'already_sent',false,'message_ids',to_jsonb(ids),'chat_id',context->>'chat_id');
end $fn$;
revoke all on function public.rr_pi_customer_document_test71(uuid,uuid) from public,anon;
revoke all on function public.rr_pi_customer_document_send_test71(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.rr_pi_customer_document_test71(uuid,uuid),public.rr_pi_customer_document_send_test71(uuid,uuid,text,jsonb) to authenticated,service_role;
CREATE OR REPLACE FUNCTION public.rr_chat_push_enqueue_v61()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_name text; v_target text; v_cycle uuid; v_update integer;
begin
 -- One bill notification even if its JPG receipt spans multiple chat attachments.
 if new.payload->>'source'='DIRECT_PI_DOCUMENT_TEST71' and coalesce((new.payload->>'document_page')::integer,1)>1 then return new; end if;
 if new.channel<>'GROUP' or new.archived_at is not null then return new; end if;
 if tg_op='UPDATE' then
  if not exists(select 1 from public.rr_customer_chat_v9433 c where c.id=new.chat_id and c.relation_kind='DIRECT_CUSTOMER' and c.data_mode='TEST') then return new; end if;
  if new.body is not distinct from old.body
   and (select jsonb_object_agg(k,new.payload->k) from unnest(array['collection_update_no','requirement_update_no','revision_no','status','pi_no','ci_no','rci_no','attachment_id','url']) k) is not distinct from
       (select jsonb_object_agg(k,old.payload->k) from unnest(array['collection_update_no','requirement_update_no','revision_no','status','pi_no','ci_no','rci_no','attachment_id','url']) k)
  then return new; end if;
 end if;
 if new.sender_kind='STAFF' and new.payload->>'source'='DIRECT_MARKET_WINDOW' then
  v_target:=new.payload->>'url';
  if v_target like 'https://redzed-customer-collection.jggfab2011.chatgpt.site/s.html?%' or v_target ~ '^https://[a-z0-9.-]+\.(vercel\.app|github\.io)/s\.html\?' then
   v_target:=regexp_replace(v_target,'^https://[^/]+','https://redzed-customer-collection.jggfab2011.chatgpt.site');
   v_target:=v_target||'&open=collection';
   v_cycle:=nullif(new.payload->>'direct_collection_cycle_id','')::uuid;
   v_update:=coalesce(nullif(new.payload->>'collection_update_no','')::integer,0);
  else v_target:=null; end if;
 end if;
 select coalesce(nullif(new.sender_name,''),c.customer_name,'REDZED Chat') into v_name from public.rr_customer_chat_v9433 c where c.id=new.chat_id;
 if tg_op='UPDATE' then
  insert into public.rr_chat_push_outbox_v61(message_id,chat_id,customer_name,preview,target_url,collection_cycle_id,collection_update_no)
  values(new.id,new.chat_id,coalesce(v_name,'REDZED Chat'),new.body,v_target,v_cycle,v_update)
  on conflict(message_id) do update set preview=excluded.preview,target_url=excluded.target_url,
   collection_cycle_id=excluded.collection_cycle_id,collection_update_no=excluded.collection_update_no,
   processed_at=null,dispatch_token=gen_random_uuid(),created_at=now();
 else
  insert into public.rr_chat_push_outbox_v61(message_id,chat_id,customer_name,preview,target_url,collection_cycle_id,collection_update_no)
  values(new.id,new.chat_id,coalesce(v_name,'REDZED Chat'),coalesce(nullif(new.body,''),new.message_type,'New message'),v_target,v_cycle,v_update)
  on conflict(message_id) do nothing;
 end if;
 return new;
end $function$
;
