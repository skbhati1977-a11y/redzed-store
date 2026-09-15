-- Fix the directory RPC version field: a backslash-escaped SQL string is not
-- valid JSON when standard_conforming_strings is enabled.
create or replace function public.rr_real_chat_directory_v84()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  perform public.rr_real_chat_auto_inactive_v136();
  v_result := public.rr_real_chat_directory_v83();

  return jsonb_set(
    v_result,
    '{version}',
    to_jsonb('TEST70_REAL_CHAT_DIRECTORY_V84_STAFF_LIFECYCLE'::text),
    true
  );
end
$function$;

revoke all on function public.rr_real_chat_directory_v84() from public, anon;
grant execute on function public.rr_real_chat_directory_v84() to authenticated;
