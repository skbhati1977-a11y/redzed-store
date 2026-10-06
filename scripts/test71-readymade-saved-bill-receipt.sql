create or replace function public.rr_rm_saved_bill_test71(p_supplier_name text,p_bill_no text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare h record;draft jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 if nullif(trim(p_supplier_name),'') is null or nullif(trim(p_bill_no),'') is null then raise exception 'Supplier and bill number required.';end if;
 select * into h from public.rr_rm_purchase_header_v849_2c6 where data_mode='TEST' and public.rr_name_normalize_v805(supplier_name)=public.rr_name_normalize_v805(p_supplier_name) and bill_no_test71=trim(p_bill_no);
 if not found then return jsonb_build_object('found',false);end if;
 if h.status='POSTED' then return jsonb_build_object('found',true,'status','POSTED','purchase_id',h.purchase_id,'receipt',public.rr_rm_receipt_summary_test71(h.purchase_id));end if;
 if h.status='DRAFT' then
 select d into draft from jsonb_array_elements(public.rr_rm_purchase_drafts_test71()) d where d->>'purchase_id'=h.purchase_id::text;
 select draft||jsonb_build_object('lines',coalesce(jsonb_agg((to_jsonb(l)-'created_by'-'markup_per_pc'-'markup_mode'-'target_sale_rate'-'minimum_allowed_sale_rate'-'max_customer_discount_per_pc')||l.chat_details_test71 order by l.lot_no),'[]'::jsonb)) into draft from public.rr_rm_purchase_lines_v849_2c6 l where l.purchase_id=h.purchase_id;
 return jsonb_build_object('found',true,'status','DRAFT','purchase_id',h.purchase_id,'draft',draft);
 end if;
 return jsonb_build_object('found',true,'status',h.status,'purchase_id',h.purchase_id);
end $$;
revoke all on function public.rr_rm_saved_bill_test71(text,text) from public,anon;
grant execute on function public.rr_rm_saved_bill_test71(text,text) to authenticated;
