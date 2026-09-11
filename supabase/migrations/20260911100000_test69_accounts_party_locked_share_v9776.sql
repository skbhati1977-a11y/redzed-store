-- V9776: account summaries and ledger-originated shares can only reach the ledger party.
begin;

create or replace function public.rr_accounts_party_chat_v9776(p_ledger_id uuid)
returns jsonb language plpgsql stable security definer set search_path='public' as $function$
declare l public.rr_ledgers_v805%rowtype; target record;
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  select * into l from public.rr_ledgers_v805 where id=p_ledger_id and is_active;
  if l.id is null then raise exception 'Ledger not found.'; end if;
  if upper(coalesce(l.ledger_kind,''))<>'CUSTOMER'
     or upper(coalesce(l.linked_entity_type,''))<>'CUSTOMER'
     or coalesce(l.linked_entity_id,'') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  then raise exception '% does not have a direct-customer Real Chat mapping.',l.ledger_name; end if;

  select i.* into target
  from public.rr_customer_sales_map_v9745 m
  join public.rr_chat_staff_inbox_v9704() i on i.customer_id=m.customer_id
  where m.buyer_id=l.linked_entity_id::uuid and m.customer_id is not null and m.is_active
    and i.relation_kind='DIRECT_CUSTOMER'
  order by i.last_message_at desc nulls last limit 1;
  if target.chat_id is null then
    raise exception '% की Real Chat mapping उपलब्ध नहीं है। पहले party mapping पूरी करें।',l.ledger_name;
  end if;
  return jsonb_build_object('chat_id',target.chat_id,'customer_id',target.customer_id,
    'customer_name',target.customer_name,'mobile',target.mobile,'ledger_id',l.id,
    'ledger_name',l.ledger_name,'relation_kind',target.relation_kind,'locked',true);
end $function$;

create or replace function public.rr_accounts_party_upload_v9776(
  p_ledger_id uuid,p_chat_id uuid,p_file_name text,p_mime_type text,p_base64 text,p_body text
) returns jsonb language plpgsql security definer set search_path='public' as $function$
declare target jsonb; locked_chat uuid; result jsonb;
begin
  target:=public.rr_accounts_party_chat_v9776(p_ledger_id);
  locked_chat:=(target->>'chat_id')::uuid;
  if p_chat_id is distinct from locked_chat then
    raise exception 'Account privacy lock: this ledger can only be shared with %.',target->>'customer_name';
  end if;
  result:=public.rr_chat_staff_upload_v9434(locked_chat,'GROUP',p_file_name,p_mime_type,p_base64,p_body,null);
  return result||jsonb_build_object('party_locked',true,'ledger_id',p_ledger_id);
end $function$;

revoke all on function public.rr_accounts_party_chat_v9776(uuid),
  public.rr_accounts_party_upload_v9776(uuid,uuid,text,text,text,text) from public,anon;
grant execute on function public.rr_accounts_party_chat_v9776(uuid),
  public.rr_accounts_party_upload_v9776(uuid,uuid,text,text,text,text) to authenticated,service_role;

commit;
