-- Readymade Real Chat adapts the existing purchase, stock, costing and Market engines.
alter table public.rr_rm_purchase_lines_v849_2c6 add column if not exists chat_details_test71 jsonb not null default '{}'::jsonb;

create or replace function public.rr_rm_chat_save_test71(p_purchase_id uuid,p_supplier_name text,p_bill_no text,p_purchase_date date,p_lines jsonb,p_post boolean default false)
returns jsonb language plpgsql security definer set search_path=public as $$
declare j jsonb;pid uuid;x jsonb;s record;costj jsonb;notes jsonb:='[]'::jsonb;h record;rate numeric;
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
  select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=p_purchase_id;
  if h.status='POSTED' then return jsonb_build_object('ok',true,'purchase_id',p_purchase_id,'status','POSTED','duplicate_blocked',true);end if;
 end if;
 j:=public.rr_rm_purchase_save_test71(p_purchase_id,p_supplier_name,p_bill_no,p_purchase_date,p_lines,false);
 pid:=(j->>'purchase_id')::uuid;
 for x in select value from jsonb_array_elements(p_lines) loop
  update public.rr_rm_purchase_lines_v849_2c6 set chat_details_test71=jsonb_build_object('category',trim(x->>'category'),'size_text',trim(x->>'size_text'),'colours_text',trim(x->>'colours_text'),'cloth_name',trim(x->>'cloth_name'),'art_no',trim(x->>'art_no'),'caption_note',trim(x->>'caption_note'),'final_rate',nullif(x->>'final_rate','')::numeric) where purchase_id=pid and lot_no=trim(x->>'lot_no');
 end loop;
 if p_post then
  j:=public.rr_rm_purchase_post_v849_2c6(pid);
  for s in select st.*,l.chat_details_test71 details from public.rr_rm_stock_v849_2c6 st join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=st.source_purchase_line_id where st.source_purchase_id=pid loop
   insert into public.rr_web_window_lot_profile_v9329(data_mode,lot_no,item_name,category,size_text,cloth_name,art_no)
   values('TEST',s.lot_no,s.item_name,s.details->>'category',s.details->>'size_text',s.details->>'cloth_name',s.details->>'art_no')
   on conflict(data_mode,lot_no) do update set item_name=excluded.item_name,category=excluded.category,size_text=excluded.size_text,cloth_name=excluded.cloth_name,art_no=excluded.art_no,updated_at=now();
   update public.rr_fg_products_v787 set size_text=s.details->>'size_text' where lot_no=s.lot_no;
   rate:=nullif(s.details->>'final_rate','')::numeric;
   if rate is not null then
    costj:=public.rr_rm_costing_test71(s.lot_no,'TEST');
    if coalesce((costj->>'costing_complete')::boolean,false) and coalesce(public.rr_costing_user_scope_v760(null)->>'effective_role','') in('OWNER','SUPER_ADMIN') then
     perform public.rr_rm_approve_rate_test71(s.lot_no,rate,'Readymade Real Chat purchase final rate');
    else notes:=notes||jsonb_build_array(s.lot_no||': final rate awaiting complete costing / Owner approval');end if;
   end if;
  end loop;
 end if;
 return j||jsonb_build_object('purchase_id',pid,'rate_notes',notes);
end $$;
revoke all on function public.rr_rm_chat_save_test71(uuid,text,text,date,jsonb,boolean) from public,anon;
grant execute on function public.rr_rm_chat_save_test71(uuid,text,text,date,jsonb,boolean) to authenticated;

create or replace function public.rr_rm_chat_queue_test71(p_search text default '',p_category text default '') returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare scope jsonb;role text;purchase_ok boolean;drafts jsonb:='[]';cards jsonb;filtered jsonb;categories jsonb;open_count integer;working_count integer;
begin
 perform public.rr_fg_assert_user_v787();scope:=public.rr_costing_user_scope_v760(null);role:=scope->>'effective_role';
 if role not in('OWNER','SUPER_ADMIN','ADMIN','ACCOUNTS','SALES','MANAGER') or role is null then raise exception 'Readymade access requires purchase, Sales or management role.';end if;
 purchase_ok:=role in('OWNER','SUPER_ADMIN','ADMIN','ACCOUNTS');
 if purchase_ok then
  select coalesce(jsonb_agg(d.value||jsonb_build_object('lines',(select jsonb_agg(to_jsonb(l)-'created_by'||l.chat_details_test71 order by l.lot_no) from public.rr_rm_purchase_lines_v849_2c6 l where l.purchase_id=(d.value->>'purchase_id')::uuid))),'[]') into drafts from jsonb_array_elements(public.rr_rm_purchase_drafts_test71()) d;
 end if;
 select coalesce(jsonb_agg(c.value||jsonb_build_object('category',coalesce(w.category,l.chat_details_test71->>'category','Uncategorised'),'size_text',coalesce(w.size_text,l.chat_details_test71->>'size_text'),'cloth_name',coalesce(w.cloth_name,l.chat_details_test71->>'cloth_name'),'art_no',coalesce(w.art_no,l.chat_details_test71->>'art_no'),'colours_text',l.chat_details_test71->>'colours_text','caption_note',l.chat_details_test71->>'caption_note','requested_rate',case when role in('OWNER','SUPER_ADMIN','ADMIN') then l.chat_details_test71->'final_rate' else null end) order by c.value->>'lot_no'),'[]') into cards
 from jsonb_array_elements(public.rr_rm_cards_test71('')) c join public.rr_rm_stock_v849_2c6 s on s.stock_id=(c.value->>'stock_id')::uuid
 join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=s.source_purchase_line_id left join public.rr_web_window_lot_profile_v9329 w on w.lot_no=s.lot_no and w.data_mode='TEST';
 working_count:=jsonb_array_length(cards);open_count:=case when purchase_ok then 1+jsonb_array_length(drafts) else 0 end;
 select coalesce(jsonb_agg(cat order by cat),'[]') into categories from (select distinct value->>'category' cat from jsonb_array_elements(cards)) a;
 select coalesce(jsonb_agg(value),'[]') into filtered from jsonb_array_elements(cards)
 where (coalesce(p_search,'')='' or concat_ws(' ',value->>'lot_no',value->>'item_name',value->>'category',value->>'art_no',value->>'colours_text') ilike '%'||p_search||'%') and (coalesce(p_category,'')='' or lower(value->>'category')=lower(p_category));
 select coalesce(jsonb_agg(value),'[]') into drafts from jsonb_array_elements(drafts) where coalesce(p_search,'')='' or concat_ws(' ',value->>'purchase_no',value->>'supplier_name',value->>'bill_no',value->'lines') ilike '%'||p_search||'%';
 return jsonb_build_object('role',role,'can_purchase',purchase_ok,'can_approve',role in('OWNER','SUPER_ADMIN','ADMIN'),'cards',filtered,'drafts',drafts,'categories',categories,'counts',jsonb_build_object('OPEN',open_count,'WORKING',working_count));
end $$;
revoke all on function public.rr_rm_chat_queue_test71(text,text) from public,anon;
grant execute on function public.rr_rm_chat_queue_test71(text,text) to authenticated;
