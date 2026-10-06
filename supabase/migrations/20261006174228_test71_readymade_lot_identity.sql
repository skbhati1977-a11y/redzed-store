CREATE OR REPLACE FUNCTION public.rr_rm_purchase_save_test71(p_purchase_id uuid, p_supplier_name text, p_bill_no text, p_purchase_date date, p_lines jsonb, p_post boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pid uuid;res jsonb;h record;x jsonb; lot_key text;
begin
 perform public.rr_rm_assert_operator_test71();
 if nullif(trim(p_supplier_name),'') is null or p_purchase_date is null then raise exception 'Supplier and Bill Date required.';end if;
 if nullif(trim(p_bill_no),'') is null then raise exception 'Supplier Bill No. required.';end if;

 if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one garment required.';end if;
 if exists(select 1 from jsonb_array_elements(p_lines) a group by upper(trim(a->>'lot_no')) having count(*)>1) then raise exception 'Each purchase line needs a different Lot No.';end if;
 for lot_key in select upper(trim(value->>'lot_no')) from jsonb_array_elements(p_lines) order by 1 loop
  perform pg_advisory_xact_lock(hashtextextended('READYMADE-LOT:'||lot_key,0));
  if lot_key !~ '^RM[0-9]+$' and not exists(select 1 from rr_rm_purchase_lines_v849_2c6 where purchase_id=p_purchase_id and upper(trim(lot_no))=lot_key) then raise exception 'New Readymade Lot must use RM followed by numbers, for example RM00001.';end if;
  if exists(select 1 from rr_rm_purchase_lines_v849_2c6 l where upper(trim(l.lot_no))=lot_key and l.purchase_id is distinct from p_purchase_id) then raise exception 'Lot % already belongs to another purchase. Choose the next Readymade Lot.',lot_key;end if;
  if (exists(select 1 from rr_fg_products_v787 where upper(trim(lot_no))=lot_key) or exists(select 1 from rr_lots where upper(trim(lot_no))=lot_key)) and not exists(select 1 from rr_rm_purchase_lines_v849_2c6 where purchase_id=p_purchase_id and upper(trim(lot_no))=lot_key) then raise exception 'Lot % already exists. Choose another Readymade Lot.',lot_key;end if;
 end loop;

 if p_purchase_id is null then
 perform pg_advisory_xact_lock(hashtextextended('RM-BILL:'||public.rr_name_normalize_v805(p_supplier_name)||':'||trim(p_bill_no),0));
 select purchase_id into pid from public.rr_rm_purchase_header_v849_2c6 where public.rr_name_normalize_v805(supplier_name)=public.rr_name_normalize_v805(p_supplier_name) and bill_no_test71=trim(p_bill_no) and data_mode='TEST';
 if found then raise exception 'Supplier bill already exists. Open its saved purchase.';end if;
 res:=public.rr_rm_purchase_create_v849_2c6(p_supplier_name,p_purchase_date,null);pid:=(res->>'purchase_id')::uuid;
 else pid:=p_purchase_id;end if;
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=pid for update;
 if h.status='POSTED' then return jsonb_build_object('ok',true,'purchase_id',pid,'status','POSTED','duplicate_blocked',true);end if;
 if h.status<>'DRAFT' or h.data_mode<>'TEST' then raise exception 'TEST Readymade draft required.';end if;
 update public.rr_rm_purchase_header_v849_2c6 set supplier_name=trim(p_supplier_name),bill_no_test71=trim(p_bill_no),purchase_date=p_purchase_date where purchase_id=pid;
 res:=public.rr_rm_purchase_replace_lines_v849_2c6(pid,p_lines);
 if p_post then res:=public.rr_rm_purchase_post_v849_2c6(pid);end if;
 return res||jsonb_build_object('purchase_id',pid);
end $function$
;
create or replace function public.rr_rm_lot_hint_test71() returns jsonb language plpgsql security definer set search_path=public as $$
declare previous text;n bigint;candidate text;
begin
 perform public.rr_rm_assert_operator_test71();
 select l.lot_no into previous from rr_rm_purchase_lines_v849_2c6 l join rr_rm_purchase_header_v849_2c6 h using(purchase_id) where h.data_mode='TEST' order by l.created_at desc,l.lot_no desc limit 1;
 select coalesce(max(substring(upper(trim(l.lot_no)) from 3)::bigint),0)+1 into n from rr_rm_purchase_lines_v849_2c6 l where upper(trim(l.lot_no)) ~ '^RM[0-9]{1,12}$';
 loop candidate:='RM'||lpad(n::text,greatest(5,length(n::text)),'0');exit when not exists(select 1 from rr_fg_products_v787 where upper(trim(lot_no))=candidate) and not exists(select 1 from rr_lots where upper(trim(lot_no))=candidate) and not exists(select 1 from rr_rm_purchase_lines_v849_2c6 where upper(trim(lot_no))=candidate);n:=n+1;end loop;
 return jsonb_build_object('previous_lot',previous,'suggested_lot',candidate);
end $$;
revoke all on function public.rr_rm_lot_hint_test71() from public,anon;
grant execute on function public.rr_rm_lot_hint_test71() to authenticated;
