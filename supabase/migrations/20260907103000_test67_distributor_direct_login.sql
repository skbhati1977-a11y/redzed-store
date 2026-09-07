-- TEST67: independent distributor login by exact configured name + mobile.
create or replace function public.rr_market_partner_login_issue_v67(
  p_name text,p_mobile text,p_device_id text
) returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare
  v_name text:=lower(trim(coalesce(p_name,'')));
  v_mobile text:=regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g');
  v_device text:=trim(coalesce(p_device_id,''));
  v_customer public.rr_customers%rowtype;
  v_share public.rr_market_share_v9420%rowtype;
  v_boot jsonb;v_raw text;v_hash text;v_device_hash text;
begin
  if v_name='' or length(v_mobile)<10 or v_device='' then raise exception 'Distributor name, mobile and trusted device are required.';end if;
  select c.* into v_customer from public.rr_customers c
  join public.rr_market_workspace_access_v61 a on a.subject_kind='CUSTOMER' and a.subject_id=c.id
  where c.is_active and a.menu_enabled and a.seller_workspace_enabled
    and lower(trim(c.customer_name))=v_name
    and right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10)=right(v_mobile,10)
  limit 1;
  if v_customer.id is null then raise exception 'Distributor name or mobile does not match an enabled workspace.';end if;
  select s.* into v_share from public.rr_market_share_v9420 s
  where s.customer_id=v_customer.id and s.status='ACTIVE' and s.data_mode='TEST'
  order by s.created_at desc limit 1;
  if v_share.id is null then raise exception 'Distributor TEST67 access link is unavailable.';end if;
  v_boot:=public.rr_chat_customer_bootstrap_v9434(v_share.token,v_customer.customer_name,v_customer.mobile);
  v_raw:=encode(extensions.gen_random_bytes(32),'hex');
  v_hash:=encode(extensions.digest(v_raw,'sha256'),'hex');
  v_device_hash:=encode(extensions.digest(v_device,'sha256'),'hex');
  insert into public.rr_customer_session_v9590(session_token_hash,customer_id,chat_id,share_id,data_mode,device_id_hash)
  values(v_hash,v_customer.id,(v_boot->>'chat_id')::uuid,v_share.id,'TEST',v_device_hash);
  return jsonb_build_object('session_token',v_raw,'owner_name',v_customer.customer_name,'expires_in_seconds',2592000);
end $$;

revoke all on function public.rr_market_partner_login_issue_v67(text,text,text) from public;
grant execute on function public.rr_market_partner_login_issue_v67(text,text,text) to anon,authenticated,service_role;
