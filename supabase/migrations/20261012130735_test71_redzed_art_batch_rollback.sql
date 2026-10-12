create or replace function public.rr_rollback_redzed_art_import_test71(
  p_source_id text,
  p_expected_target_id uuid
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $function$
declare
  v_map public.rr_operational_source_identity_test71%rowtype;
begin
  select * into v_map from public.rr_operational_source_identity_test71
   where source_app='Redzed Clothing' and source_module='ART' and source_id=p_source_id for update;
  if not found or v_map.target_id<>p_expected_target_id then raise exception 'Source identity mapping mismatch; rollback refused.'; end if;
  delete from public.rr_media where id=any(v_map.target_media_ids);
  delete from public.rr_art_master_core_v402 where id=v_map.target_id;
  update public.rr_operational_import_row_log_test71
     set status='ROLLED_BACK',reason='AUTHORIZED_TEST_BATCH_ROLLBACK'
   where source_app='Redzed Clothing' and source_module='ART' and source_id=p_source_id
     and target_id=p_expected_target_id and status in ('IMPORTED_PENDING_VERIFY','IMPORTED_VERIFIED');
  delete from public.rr_operational_source_identity_test71
   where source_app='Redzed Clothing' and source_module='ART' and source_id=p_source_id;
  return jsonb_build_object('source_id',p_source_id,'target_id',p_expected_target_id,'status','ROLLED_BACK');
end
$function$;
revoke all on function public.rr_rollback_redzed_art_import_test71(text,uuid) from public,anon,authenticated;
grant execute on function public.rr_rollback_redzed_art_import_test71(text,uuid) to service_role;
