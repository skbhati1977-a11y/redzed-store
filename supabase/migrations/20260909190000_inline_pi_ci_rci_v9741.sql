begin;

create or replace function public.rr_rci_post_linked_final_v9741(p_rci_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  h public.rr_rci_v9740%rowtype;
begin
  perform public.rr_fg_assert_user_v787();
  select * into h from public.rr_rci_v9740 where id=p_rci_id for update;
  if h.id is null then raise exception 'Linked RCI not found.'; end if;
  if h.flow_type<>'COMBINED' or h.linked_ci_id is null then
    raise exception 'Combined PI/CI linked RCI required.';
  end if;
  if not exists(
    select 1 from public.rr_fg_pi_v787 p
    where p.id=h.linked_ci_id and p.status='CI_FINAL' and p.buyer_id=h.buyer_id and p.data_mode=h.data_mode
  ) then raise exception 'Linked CI must be final before RCI posting.'; end if;
  return public.rr_rci_finalize_v9740(h.id);
end
$function$;

revoke all on function public.rr_rci_post_linked_final_v9741(uuid) from public,anon;
grant execute on function public.rr_rci_post_linked_final_v9741(uuid) to authenticated;

commit;
