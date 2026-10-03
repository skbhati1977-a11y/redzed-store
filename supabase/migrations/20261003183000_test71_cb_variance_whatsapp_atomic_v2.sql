-- TEST71: make CB SHORT/EXCESS WhatsApp preparation atomic.
-- One RPC creates the variance report, prepares the Super Admin delivery,
-- marks it SENT per the product rule, and returns the phone/message for immediate navigation.

create or replace function public.rr_cb_variance_whatsapp_prepare_v2(
  p_purchase_entry_id uuid,
  p_variance_qty numeric,
  p_variance_type text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=public
set statement_timeout='15s'
as $$
declare
  v_report jsonb;
  v_prepare jsonb;
  v_confirm jsonb;
  v_report_id uuid;
  v_delivery_id uuid;
begin
  perform public.rr_product_require_admin_v1();

  v_report:=public.rr_cb_variance_report_v1(
    p_purchase_entry_id,
    p_variance_qty,
    p_variance_type,
    p_reason
  );

  v_report_id:=nullif(v_report#>>'{report,id}','')::uuid;
  if v_report_id is null then
    raise exception 'CB variance report was not created.';
  end if;

  v_prepare:=public.rr_report_send_superadmin_prepare_v1('CB_VARIANCE',v_report_id);
  v_delivery_id:=nullif(v_prepare->>'delivery_id','')::uuid;
  if v_delivery_id is null then
    raise exception 'Super Admin WhatsApp delivery was not prepared.';
  end if;

  v_confirm:=public.rr_report_send_superadmin_confirm_v1(v_delivery_id);

  return v_report || jsonb_build_object(
    'delivery_id',v_delivery_id,
    'delivery_state',coalesce(v_confirm->>'state','SENT'),
    'recipient_name',v_prepare->>'recipient_name',
    'recipient_phone',v_prepare->>'recipient_phone',
    'message',v_prepare->>'message'
  );
end
$$;

revoke all on function public.rr_cb_variance_whatsapp_prepare_v2(uuid,numeric,text,text)
from public,anon;

grant execute on function public.rr_cb_variance_whatsapp_prepare_v2(uuid,numeric,text,text)
to authenticated;
