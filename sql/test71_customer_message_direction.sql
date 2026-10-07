-- Keep session validation, hidden-message filtering and the existing RPC signature.
-- Ownership comes from trusted database columns, not names or client payloads.
CREATE OR REPLACE FUNCTION public.rr_chat_customer_messages_session_v9593(
  p_session_token text, p_device_id text, p_channel text DEFAULT 'GROUP', p_limit integer DEFAULT 100
)
RETURNS TABLE(id uuid, channel text, sender_name text, message_type text, body text,
  payload jsonb, reply_to_message_id uuid, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE x jsonb; chn text:=upper(coalesce(p_channel,'GROUP')); ch uuid; cust uuid;
BEGIN
  x:=public.rr_customer_session_validate_v9590(p_session_token,p_device_id);
  ch:=(x->>'chat_id')::uuid; cust:=(x->>'customer_id')::uuid;
  RETURN QUERY
  SELECT m.id,m.channel,m.sender_name,m.message_type,m.body,
    (coalesce(m.payload,'{}'::jsonb)-'thumb_base64') || jsonb_build_object(
      'rr_customer_is_own', coalesce(m.sender_kind='CUSTOMER' AND m.sender_customer_id=cust,false)
    ), m.reply_to_message_id,m.created_at
  FROM public.rr_customer_chat_messages_v9433 m
  WHERE m.chat_id=ch AND m.channel=chn AND m.archived_at IS NULL
    AND NOT EXISTS (SELECT 1 FROM public.rr_chat_message_hidden_v9712 h
      WHERE h.message_id=m.id AND h.viewer_kind='CUSTOMER' AND h.viewer_id=cust)
  ORDER BY m.created_at DESC LIMIT least(greatest(coalesce(p_limit,100),1),200);
END $function$;
