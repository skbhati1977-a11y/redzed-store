create or replace function public.rr_rci_post_standalone_internal_v9746(
  p_buyer_id uuid,
  p_lines jsonb,
  p_reason text,
  p_idempotency_key text,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  d jsonb;
  v_existing public.rr_rci_v9740%rowtype;
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));
  v_key text:=nullif(btrim(p_idempotency_key),'');
begin
  if v_key is null then raise exception 'RCI idempotency key required.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_mode||'|'||v_key,0));

  select * into v_existing
  from public.rr_rci_v9740
  where data_mode=v_mode and idempotency_key=v_key;

  if v_existing.id is not null then
    return jsonb_build_object(
      'rci_id',v_existing.id,
      'rci_no',v_existing.rci_no,
      'status',v_existing.status,
      'total_qty',v_existing.total_qty,
      'total_amount',v_existing.total_amount,
      'idempotent_replay',true
    );
  end if;

  d:=public.rr_rci_save_draft_v9740(null,null,p_buyer_id,'STANDALONE',p_lines,p_reason,v_key,v_mode);
  return public.rr_rci_finalize_v9740((d->>'rci_id')::uuid);
end
$function$;
