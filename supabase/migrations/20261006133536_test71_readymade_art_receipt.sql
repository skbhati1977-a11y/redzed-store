-- Readymade TEST Art defaults are append-only purchase snapshots, not a new stock/Accounts engine.
create table if not exists public.rr_rm_art_versions_test71(
 art_key text not null, revision bigint not null, art_no text not null, defaults jsonb not null,
 effective_from timestamptz not null default clock_timestamp(),
 source_line_id uuid references public.rr_rm_purchase_lines_v849_2c6(purchase_line_id),
 created_by uuid references auth.users(id), data_mode text not null default 'TEST' check(data_mode='TEST'),
 primary key(art_key,revision)
);
alter table public.rr_rm_art_versions_test71 enable row level security;
revoke all on public.rr_rm_art_versions_test71 from public,anon,authenticated;
create table if not exists public.rr_rm_receipt_assets_test71(
 purchase_id uuid primary key references public.rr_rm_purchase_header_v849_2c6(purchase_id),
 snapshot jsonb not null, files jsonb, prepared_at timestamptz not null default now(),
 share_events jsonb not null default '[]', last_shared_at timestamptz,
 data_mode text not null default 'TEST' check(data_mode='TEST'),created_by uuid references auth.users(id)
);
alter table public.rr_rm_receipt_assets_test71 enable row level security;
revoke all on public.rr_rm_receipt_assets_test71 from public,anon,authenticated;

create or replace function public.rr_rm_art_register_test71(p_line_id uuid,p_sale_only numeric default null)
returns bigint language plpgsql security definer set search_path=public as $$
declare line_row record;current_row record;key text;details jsonb;rev bigint;
begin
 perform public.rr_rm_assert_operator_test71();
 select l.*,h.status,h.data_mode into line_row from public.rr_rm_purchase_lines_v849_2c6 l join public.rr_rm_purchase_header_v849_2c6 h on h.purchase_id=l.purchase_id where l.purchase_line_id=p_line_id;
 if not found or line_row.data_mode<>'TEST' or line_row.status<>'POSTED' then raise exception 'Confirmed TEST purchase required for Art mapping.';end if;
 key:=upper(trim(line_row.chat_details_test71->>'art_no'));if coalesce(key,'')='' then return null;end if;
 perform pg_advisory_xact_lock(hashtextextended('RM-ART:TEST:'||key,0));
 select * into current_row from public.rr_rm_art_versions_test71 where art_key=key order by revision desc limit 1;
 details:=jsonb_build_object('item_name',line_row.item_name,'category',line_row.chat_details_test71->>'category','size_text',line_row.chat_details_test71->>'size_text',
 'colours_text',line_row.chat_details_test71->>'colours_text','cloth_name',line_row.chat_details_test71->>'cloth_name','caption_note',line_row.chat_details_test71->>'caption_note',
 'final_image_url',line_row.final_image_url,'purchase_rate',line_row.purchase_rate,'final_rate',line_row.chat_details_test71->'final_rate');
 if p_sale_only is not null then details:=coalesce(current_row.defaults,details)||jsonb_build_object('final_rate',p_sale_only);end if;
 if current_row.revision is not null and current_row.defaults=details then return current_row.revision;end if;
 rev:=coalesce(current_row.revision,0)+1;
 insert into public.rr_rm_art_versions_test71(art_key,revision,art_no,defaults,source_line_id,created_by)
 values(key,rev,trim(line_row.chat_details_test71->>'art_no'),details,p_line_id,auth.uid());
 return rev;
end $$;
revoke all on function public.rr_rm_art_register_test71(uuid,numeric) from public,anon,authenticated;

-- Bootstrap latest confirmed Readymade values only. Manufacturing Art records stay separate.
insert into public.rr_rm_art_versions_test71(art_key,revision,art_no,defaults,source_line_id,created_by,effective_from)
select distinct on(upper(trim(l.chat_details_test71->>'art_no'))) upper(trim(l.chat_details_test71->>'art_no')),1,trim(l.chat_details_test71->>'art_no'),
 jsonb_build_object('item_name',l.item_name,'category',l.chat_details_test71->>'category','size_text',l.chat_details_test71->>'size_text',
 'colours_text',l.chat_details_test71->>'colours_text','cloth_name',l.chat_details_test71->>'cloth_name','caption_note',l.chat_details_test71->>'caption_note',
 'final_image_url',l.final_image_url,'purchase_rate',l.purchase_rate,'final_rate',coalesce(to_jsonb(q.final_sale_rate),l.chat_details_test71->'final_rate')),
 l.purchase_line_id,l.created_by,coalesce(h.posted_at,h.updated_at,h.created_at)
from public.rr_rm_purchase_lines_v849_2c6 l join public.rr_rm_purchase_header_v849_2c6 h on h.purchase_id=l.purchase_id
left join public.rrq_lot_rates_v9300 q on q.lot_no=l.lot_no and q.data_mode='TEST' and q.dispatch_ready
where h.data_mode='TEST' and h.status='POSTED' and nullif(trim(l.chat_details_test71->>'art_no'),'') is not null
order by upper(trim(l.chat_details_test71->>'art_no')),h.posted_at desc nulls last,h.updated_at desc,l.purchase_line_id
on conflict(art_key,revision) do nothing;

create or replace function public.rr_rm_art_catalog_test71(p_art_no text default null) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare rows jsonb;items jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 with latest as(select distinct on(art_key) * from public.rr_rm_art_versions_test71 where coalesce(trim(p_art_no),'')='' or art_key=upper(trim(p_art_no)) order by art_key,revision desc),
 balances as(select upper(trim(l.chat_details_test71->>'art_no')) art_key,sum(s.available_qty) available_qty from public.rr_rm_stock_v849_2c6 s join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=s.source_purchase_line_id where s.data_mode='TEST' group by 1)
 select coalesce(jsonb_agg(v.defaults||jsonb_build_object('art_no',v.art_no,'art_revision',v.revision,'effective_from',v.effective_from,'available_qty',coalesce(b.available_qty,0)) order by v.art_key),'[]') into rows from latest v left join balances b on b.art_key=v.art_key;
 select coalesce(jsonb_agg(item order by item),'[]') into items from(select distinct defaults->>'item_name' item from public.rr_rm_art_versions_test71 where nullif(trim(defaults->>'item_name'),'') is not null) a;
 return jsonb_build_object('rows',rows,'items',items,'as_of',clock_timestamp());
end $$;
revoke all on function public.rr_rm_art_catalog_test71(text) from public,anon;
grant execute on function public.rr_rm_art_catalog_test71(text) to authenticated;

create or replace function public.rr_rm_receipt_prepare_test71(p_purchase_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare row_record record;receipt jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 select * into row_record from public.rr_rm_purchase_header_v849_2c6 where purchase_id=p_purchase_id for update;
 if not found or row_record.data_mode<>'TEST' or row_record.status<>'POSTED' then raise exception 'Save & Confirm Purchase before preparing the supplier receipt.';end if;
 receipt:=public.rr_rm_receipt_summary_test71(p_purchase_id);
 insert into public.rr_rm_receipt_assets_test71(purchase_id,snapshot,created_by) values(p_purchase_id,receipt,auth.uid()) on conflict(purchase_id) do nothing;
 return (select snapshot||jsonb_build_object('files',files,'prepared_at',prepared_at,'last_shared_at',last_shared_at) from public.rr_rm_receipt_assets_test71 where purchase_id=p_purchase_id);
end $$;
revoke all on function public.rr_rm_receipt_prepare_test71(uuid) from public,anon;
grant execute on function public.rr_rm_receipt_prepare_test71(uuid) to authenticated;

create or replace function public.rr_rm_receipt_files_save_test71(p_purchase_id uuid,p_files jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare f jsonb;receipt_row record;
begin
 perform public.rr_rm_assert_operator_test71();
 select * into receipt_row from public.rr_rm_receipt_assets_test71 where purchase_id=p_purchase_id and data_mode='TEST' for update;
 if not found then raise exception 'Prepare the receipt first.';end if;
 if receipt_row.files is not null then return receipt_row.snapshot||jsonb_build_object('files',receipt_row.files,'prepared_at',receipt_row.prepared_at,'last_shared_at',receipt_row.last_shared_at);end if;
 if jsonb_typeof(p_files) is distinct from 'array' or jsonb_array_length(p_files) not between 1 and 30 then raise exception 'Receipt JPG files required.';end if;
 for f in select value from jsonb_array_elements(p_files) loop
  if coalesce(f->>'name','') !~ '^[a-zA-Z0-9_-]+\.jpg$' or coalesce(f->>'sha256','') !~ '^[a-f0-9]{64}$'
   or left(coalesce(f->>'path',''),length('readymade/test71/receipts/'||p_purchase_id||'/'))<>'readymade/test71/receipts/'||p_purchase_id||'/'
   or not exists(select 1 from storage.objects o where o.bucket_id='redzed-media' and o.name=f->>'path' and o.owner_id=auth.uid()::text) then
   raise exception 'Upload valid receipt JPG files before saving the receipt.';
  end if;
 end loop;
 update public.rr_rm_receipt_assets_test71 set files=p_files where purchase_id=p_purchase_id;
 return receipt_row.snapshot||jsonb_build_object('files',p_files,'prepared_at',receipt_row.prepared_at,'last_shared_at',receipt_row.last_shared_at);
end $$;
revoke all on function public.rr_rm_receipt_files_save_test71(uuid,jsonb) from public,anon;
grant execute on function public.rr_rm_receipt_files_save_test71(uuid,jsonb) to authenticated;

create or replace function public.rr_rm_receipt_share_record_test71(p_purchase_id uuid,p_event_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare receipt_row record;
begin
 perform public.rr_rm_assert_operator_test71();
 select * into receipt_row from public.rr_rm_receipt_assets_test71 where purchase_id=p_purchase_id and data_mode='TEST' for update;
 if not found or receipt_row.files is null then raise exception 'Prepared JPG receipt required.';end if;
 if not exists(select 1 from jsonb_array_elements(receipt_row.share_events) e where e->>'event_id'=p_event_id::text) then
  update public.rr_rm_receipt_assets_test71 set share_events=share_events||jsonb_build_array(jsonb_build_object('event_id',p_event_id,'shared_at',clock_timestamp(),'by',auth.uid())),last_shared_at=clock_timestamp() where purchase_id=p_purchase_id;
 end if;
 return jsonb_build_object('ok',true,'delivery_confirmed',false,'state','HANDED_TO_SHARE_APP');
end $$;
revoke all on function public.rr_rm_receipt_share_record_test71(uuid,uuid) from public,anon;
grant execute on function public.rr_rm_receipt_share_record_test71(uuid,uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.rr_rm_receipt_summary_test71(p_purchase_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h record;outj jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=p_purchase_id;
 if not found or h.data_mode<>'TEST' then raise exception 'TEST Readymade purchase required.';end if;
 select coalesce(jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'item_name',l.item_name,'art_no',l.chat_details_test71->>'art_no','category',l.chat_details_test71->>'category','size_text',l.chat_details_test71->>'size_text','colours_text',l.chat_details_test71->>'colours_text','image_url',l.final_image_url,'bill_qty',coalesce(l.bill_qty_test71,l.qty),'received_qty',l.qty,
  'difference_qty',l.qty-coalesce(l.bill_qty_test71,l.qty),'purchase_rate',l.purchase_rate,
  'bill_value',round(coalesce(l.bill_qty_test71,l.qty)*l.purchase_rate,2),'received_value',round(l.qty*l.purchase_rate,2),
  'note_type',case when l.qty<coalesce(l.bill_qty_test71,l.qty) then 'DEBIT_NOTE' when l.qty>coalesce(l.bill_qty_test71,l.qty) then 'CREDIT_NOTE' else 'MATCHED' end,
  'note_amount',abs(round(l.qty*l.purchase_rate,2)-round(coalesce(l.bill_qty_test71,l.qty)*l.purchase_rate,2)),
  'account_transaction_id',l.receipt_note_transaction_id_test71,'voucher_no',t.voucher_no) order by l.lot_no),'[]') into outj
 from public.rr_rm_purchase_lines_v849_2c6 l left join public.rr_account_transactions_v805 t on t.id=l.receipt_note_transaction_id_test71 where l.purchase_id=p_purchase_id;
 return jsonb_build_object('purchase_id',p_purchase_id,'bill_no',h.bill_no_test71,'purchase_no',h.purchase_no,'supplier_name',h.supplier_name,'purchase_date',h.purchase_date,'status',h.status,'lines',outj,'bill_value',h.total_purchase_amount,'received_value',(select sum(round(qty*purchase_rate,2)) from public.rr_rm_purchase_lines_v849_2c6 where purchase_id=p_purchase_id));
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_rm_chat_save_test71(p_purchase_id uuid, p_supplier_name text, p_bill_no text, p_purchase_date date, p_lines jsonb, p_post boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j jsonb;pid uuid;x jsonb;s record;costj jsonb;notes jsonb:='[]'::jsonb;h record;rate numeric;art_row record;rev bigint;art_key text;
begin
 perform public.rr_rm_assert_operator_test71();
 if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one garment required.';end if;
 for x in select value from jsonb_array_elements(p_lines) loop
  if nullif(trim(x->>'category'),'') is null then raise exception 'Garment category required.';end if;
  if coalesce(x->>'final_image_url','') !~ '^https?://' then raise exception 'Final garment image required.';end if;
  if (x->>'qty')::numeric::text in ('NaN','Infinity','-Infinity') or (x->>'purchase_rate')::numeric::text in ('NaN','Infinity','-Infinity') then raise exception 'Valid quantity and purchase rate required.';end if;
  rate:=nullif(x->>'final_rate','')::numeric;
  if rate is not null and (rate<0 or rate::text in ('NaN','Infinity','-Infinity')) then raise exception 'Valid final sales rate required.';end if;
 end loop;
 if p_purchase_id is not null then
  select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=p_purchase_id for update;
  if h.status='POSTED' then return jsonb_build_object('ok',true,'purchase_id',p_purchase_id,'status','POSTED','duplicate_blocked',true,'receipt',public.rr_rm_receipt_summary_test71(p_purchase_id));end if;
 end if;

 -- Lock all Art keys in order and reject stale mapped drafts before altering stock/Accounts.
 for art_key in select distinct upper(trim(value->>'art_no')) from jsonb_array_elements(p_lines) where nullif(trim(value->>'art_no'),'') is not null order by 1 loop
  perform pg_advisory_xact_lock(hashtextextended('RM-ART:TEST:'||art_key,0));
 end loop;
 for x in select value from jsonb_array_elements(p_lines) loop
  if nullif(trim(x->>'art_no'),'') is not null and x ? 'art_revision' then
   select * into art_row from public.rr_rm_art_versions_test71 where rr_rm_art_versions_test71.art_key=upper(trim(x->>'art_no')) order by revision desc limit 1;
   if coalesce(nullif(x->>'art_revision','')::bigint,0)<>coalesce(art_row.revision,0) then raise exception 'Art details changed after this form was loaded. Reload Art defaults and review the current rates before confirming.';end if;
  end if;
 end loop;
 j:=public.rr_rm_purchase_save_test71(p_purchase_id,p_supplier_name,p_bill_no,p_purchase_date,p_lines,false);
 pid:=(j->>'purchase_id')::uuid;
 for x in select value from jsonb_array_elements(p_lines) loop
  update public.rr_rm_purchase_lines_v849_2c6 set chat_details_test71=jsonb_build_object('category',trim(x->>'category'),'size_text',trim(x->>'size_text'),'colours_text',trim(x->>'colours_text'),'cloth_name',trim(x->>'cloth_name'),'art_no',trim(x->>'art_no'),'caption_note',trim(x->>'caption_note'),'final_rate',nullif(x->>'final_rate','')::numeric,'art_revision',nullif(x->>'art_revision','')::bigint) where purchase_id=pid and lot_no=trim(x->>'lot_no');
 end loop;
 if p_post then
  j:=public.rr_rm_purchase_post_v849_2c6(pid);
  for s in select st.*,l.chat_details_test71 details from public.rr_rm_stock_v849_2c6 st join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=st.source_purchase_line_id where st.source_purchase_id=pid loop
   insert into public.rr_web_window_lot_profile_v9329(data_mode,lot_no,item_name,category,size_text,cloth_name,art_no)
   values('TEST',s.lot_no,s.item_name,s.details->>'category',s.details->>'size_text',s.details->>'cloth_name',s.details->>'art_no')
   on conflict(data_mode,lot_no) do update set item_name=excluded.item_name,category=excluded.category,size_text=excluded.size_text,cloth_name=excluded.cloth_name,art_no=excluded.art_no,updated_at=now();
   update public.rr_fg_products_v787 set size_text=s.details->>'size_text' where lot_no=s.lot_no;
   rev:=public.rr_rm_art_register_test71(s.source_purchase_line_id);
   update public.rr_rm_purchase_lines_v849_2c6 set chat_details_test71=chat_details_test71||jsonb_build_object('art_revision',rev) where purchase_line_id=s.source_purchase_line_id;
   rate:=nullif(s.details->>'final_rate','')::numeric;
   if rate is not null then
    costj:=public.rr_rm_costing_test71(s.lot_no,'TEST');
    if coalesce((costj->>'costing_complete')::boolean,false) and coalesce(public.rr_costing_user_scope_v760(null)->>'effective_role','') in('OWNER','SUPER_ADMIN') then
     perform public.rr_rm_approve_rate_test71(s.lot_no,rate,'Readymade Real Chat purchase final rate');
    else notes:=notes||jsonb_build_array(s.lot_no||': final rate awaiting complete costing / Owner approval');end if;
   end if;
  end loop;
 end if;
 return j||jsonb_build_object('purchase_id',pid,'rate_notes',notes,'receipt',public.rr_rm_receipt_summary_test71(pid));
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_rm_approve_rate_test71(p_lot_no text, p_final_rate numeric, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s record;j jsonb;r jsonb;art_lock_key text;
begin
 perform public.rr_rm_assert_operator_test71();
 if p_final_rate is null or p_final_rate<=0 or p_final_rate::text in('NaN','Infinity','-Infinity') then raise exception 'Positive final sale rate required.';end if;
 if not coalesce((public.rr_rm_market_readiness_test71(p_lot_no)->>'mapping_ready')::boolean,false) then raise exception 'Complete garment mapping in Readymade Working before approving final rate.';end if;
 if lower(public.rr_costing_user_scope_v760(null)->>'effective_role') not in('owner','super_admin','superadmin','admin') then raise exception 'Owner / Admin rate approval required.';end if;
 select upper(trim(l.chat_details_test71->>'art_no')) into art_lock_key from public.rr_rm_stock_v849_2c6 st join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=st.source_purchase_line_id where upper(trim(st.lot_no))=upper(trim(p_lot_no)) and st.data_mode='TEST';
 if coalesce(art_lock_key,'')<>'' then perform pg_advisory_xact_lock(hashtextextended('RM-ART:TEST:'||art_lock_key,0));end if;
 perform pg_advisory_xact_lock(hashtextextended('RM:'||upper(trim(p_lot_no))||':TEST',0));
 select * into s from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode='TEST' for update;
 if not found then raise exception 'Readymade lot not found.';end if;
 if s.sale_ready and exists(select 1 from public.rrq_lot_rates_v9300 q where q.lot_no=s.lot_no and q.data_mode='TEST' and q.dispatch_ready and q.final_sale_rate>0) then raise exception 'Final rate already approved; read only.';end if;
 -- Freeze full private costing under owner scope; Admin can approve but cannot read it.
 if s.costing_snapshot_test71 is null then
 if lower(public.rr_costing_user_scope_v760(null)->>'effective_role') not in('owner','super_admin','superadmin') then raise exception 'Owner must finalize Readymade costing first.';end if;
 j:=public.rr_rm_costing_test71(s.lot_no,'TEST');
 if not coalesce((j->>'costing_complete')::boolean,false) then raise exception 'Monthly weighted allocation is pending.';end if;
 update public.rr_rm_stock_v849_2c6 set costing_snapshot_test71=j||jsonb_build_object('frozen',true,'frozen_at',now()) where stock_id=s.stock_id;
 end if;
 r:=public.rrq_apply_packing_rate_core_test71(s.lot_no,p_final_rate,'TEST',p_reason);
 update public.rr_rm_stock_v849_2c6 set target_sale_rate=p_final_rate,minimum_allowed_sale_rate=greatest(0,p_final_rate-max_customer_discount_per_pc),markup_mode='DEFAULT_22',markup_per_pc=22,sale_ready=true where stock_id=s.stock_id;
 perform public.rr_rm_art_register_test71(s.source_purchase_line_id,p_final_rate);
 return r;
end $function$
;
