-- V9762: let authorized RCI roles complete the downstream Accounts reversal
-- without granting Sales general Accounts posting/view permission.
begin;

alter function public.rr_acct_can_view_v805() rename to rr_acct_can_view_base_v9762;

create function public.rr_acct_can_view_v805()
returns boolean language plpgsql stable security definer set search_path='public' as $function$
begin
 if current_setting('rr.trusted_account_bridge',true)='rci_reversal' then return true; end if;
 return public.rr_acct_can_view_base_v9762();
end $function$;

revoke all on function public.rr_acct_can_view_base_v9762(),public.rr_acct_can_view_v805() from public,anon,authenticated;
grant execute on function public.rr_acct_can_view_base_v9762(),public.rr_acct_can_view_v805() to service_role;

create or replace function public.rr_rci_accounts_status_trg_v9754()
returns trigger language plpgsql security definer set search_path='public' as $function$
begin
  if new.status='POSTED' and (tg_op='INSERT' or old.status is distinct from new.status) then
    perform public.rr_accounts_post_rci_v9754(new.id);
  elsif new.status='REVERSED' and old.status is distinct from new.status then
    perform set_config('rr.trusted_account_bridge','rci_reversal',true);
    perform public.rr_accounts_reverse_source_mirror_v806('RCI_V9740',new.id::text,new.data_mode,
      coalesce(new.reversal_reason,'RCI reversed'));
    perform set_config('rr.trusted_account_bridge','',true);
    update public.rr_rci_accounts_link_v9754 set status='REVERSED',message='RCI reversed in Accounts',updated_at=now()
     where rci_id=new.id;
  end if;
  return new;
end $function$;

revoke all on function public.rr_rci_accounts_status_trg_v9754() from public,anon,authenticated;
commit;
