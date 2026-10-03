create or replace function public.rr_cb_variance_report_v1(
  p_purchase_entry_id uuid,
  p_variance_qty numeric,
  p_variance_type text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  p public.rr_cb_purchase_entries%rowtype;
  cb public.rr_fabric_purchases%rowtype;
  a public.rr_user_profiles%rowtype;
  r public.rr_cb_shortage_reports_v1%rowtype;
  v_type text:=upper(trim(p_variance_type));
  msg text;
  smsg text;
  v_link text;
  bill_qty numeric:=0;
  physical_qty numeric:=0;
begin
  perform public.rr_product_require_admin_v1();

  if v_type not in('SHORT','EXCESS') then
    raise exception 'Variance Type must be SHORT or EXCESS.';
  end if;
  if coalesce(p_variance_qty,0)<=0 then
    raise exception 'Variance Qty must be greater than zero.';
  end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Variance reason required.';
  end if;

  select * into p
  from public.rr_cb_purchase_entries
  where id=p_purchase_entry_id;
  if not found then raise exception 'CB purchase entry not found.'; end if;

  select * into cb
  from public.rr_fabric_purchases
  where id=p.cb_id;

  bill_qty:=coalesce(p.original_quantity,p.quantity,0);

  select coalesce(sum(coalesce(r.quantity,0)),0)
  into physical_qty
  from public.rr_cb_purchase_rolls r
  where r.purchase_entry_id=p.id
    and coalesce(r.operation_status,'ACTIVE')<>'REVERSED';

  v_link:='real-cb-new-v9130-loader.html?cb_id='||p.cb_id::text||'&from=CB_VARIANCE';

  select * into a
  from public.rr_user_profiles
  where is_active=true and upper(role_code) in('SUPER_ADMIN','OWNER','ADMIN')
  order by case upper(role_code) when 'SUPER_ADMIN' then 1 when 'OWNER' then 2 else 3 end,
           updated_at desc nulls last,created_at
  limit 1;

  msg:=concat(
    'REDZED · CB ',v_type,' REPORT',E'\n',
    'CB No.: ',coalesce(cb.cb_no,'—'),E'\n',
    'Supplier: ',coalesce(p.vendor_name,'—'),E'\n',
    'Bill No.: ',coalesce(p.vendor_bill_no,'—'),E'\n',
    'Material: ',coalesce(p.fabric_name,'Regular Cloth'),E'\n',
    'Party Bill Qty: ',to_char(bill_qty,'FM999999990.000'),' KG',E'\n',
    'Physical Roll / Stock-In Qty: ',to_char(physical_qty,'FM999999990.000'),' KG',E'\n',
    'Difference: ',v_type,' ',to_char(round(p_variance_qty,3),'FM999999990.000'),' KG',E'\n',
    'Reason: ',trim(p_reason),E'\n\n',
    'Action: Please review and forward this report to the Supplier.'
  );

  smsg:=concat(
    'REDZED · CB ',coalesce(cb.cb_no,'—'),' · ',v_type,' AGAINST BILL',E'\n',
    'Bill No.: ',coalesce(p.vendor_bill_no,'—'),E'\n',
    'Material: ',coalesce(p.fabric_name,'Regular Cloth'),E'\n',
    'Party Bill Qty: ',to_char(bill_qty,'FM999999990.000'),' KG',E'\n',
    'Physical Received Qty: ',to_char(physical_qty,'FM999999990.000'),' KG',E'\n',
    v_type,' Qty: ',to_char(round(p_variance_qty,3),'FM999999990.000'),' KG',E'\n',
    'Reason: ',trim(p_reason),E'\n',
    'Please review and confirm.'
  );

  insert into public.rr_cb_shortage_reports_v1(
    purchase_entry_id,shortage_qty,variance_type,reason,admin_user_id,admin_message,supplier_message
  )
  values(
    p.id,round(p_variance_qty,3),v_type,trim(p_reason),a.auth_user_id,msg,smsg
  )
  returning * into r;

  if a.auth_user_id is not null then
    insert into public.rr_real_chat_message_bridge_v70(
      data_mode,canonical_key,source_module,source_record_id,source_event_type,
      department_code,sender_user_id,receiver_user_id,action_code,action_label,
      personal_payload,group_payload,deep_link,projection_type
    )
    values(
      'TEST','CB_VARIANCE:'||r.id::text,'CB_VARIANCE',r.id::text,v_type||'_REPORTED',
      'PURCHASE',auth.uid(),a.auth_user_id,'CB_VARIANCE_FORWARD','FORWARD TO SUPPLIER',
      jsonb_build_object(
        'title','CB '||v_type,
        'message',msg,
        'variance_report_id',r.id,
        'variance_type',v_type,
        'supplier_message',smsg,
        'cb_no',cb.cb_no,
        'party_bill_qty',bill_qty,
        'physical_roll_qty',physical_qty,
        'variance_qty',round(p_variance_qty,3)
      ),
      jsonb_build_object(
        'title','CB '||v_type,
        'message',msg,
        'cb_no',cb.cb_no,
        'party_bill_qty',bill_qty,
        'physical_roll_qty',physical_qty,
        'variance_qty',round(p_variance_qty,3)
      ),
      v_link,'ACTION'
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'report',to_jsonb(r),
    'admin_message',msg,
    'supplier_message',smsg,
    'admin_user_id',a.auth_user_id,
    'deep_link',v_link,
    'cb_no',cb.cb_no,
    'party_bill_qty',bill_qty,
    'physical_roll_qty',physical_qty,
    'variance_qty',round(p_variance_qty,3)
  );
end
$$;

revoke all on function public.rr_cb_variance_report_v1(uuid,numeric,text,text) from public,anon;
grant execute on function public.rr_cb_variance_report_v1(uuid,numeric,text,text) to authenticated;
