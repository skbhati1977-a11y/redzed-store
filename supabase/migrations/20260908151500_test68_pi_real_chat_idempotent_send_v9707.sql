create or replace function public.rr_chat_staff_upload_once_v9707(p_chat_id uuid,p_file_name text,p_mime_type text,p_base64 text,p_body text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare k text:=nullif(trim(coalesce(p_payload->>'dedupe_key','')),''); old_id uuid; result jsonb;
begin
  perform public.rr_assert_active_user_v1();
  if k is null then raise exception 'Document dedupe key required.'; end if;
  perform pg_advisory_xact_lock(hashtext(p_chat_id::text||':'||k));
  select id into old_id from public.rr_customer_chat_messages_v9433 where chat_id=p_chat_id and channel='GROUP' and payload->>'dedupe_key'=k order by created_at desc limit 1;
  if old_id is not null then return jsonb_build_object('message_id',old_id,'already_sent',true); end if;
  result:=public.rr_chat_staff_upload_v9479(p_chat_id,'GROUP',p_file_name,p_mime_type,p_base64,p_body,null,p_payload);
  return result||jsonb_build_object('already_sent',false);
end $function$;
revoke all on function public.rr_chat_staff_upload_once_v9707(uuid,text,text,text,text,jsonb) from public,anon;
grant execute on function public.rr_chat_staff_upload_once_v9707(uuid,text,text,text,text,jsonb) to authenticated,service_role;
