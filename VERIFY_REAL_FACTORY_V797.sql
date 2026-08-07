with fn as (
  select pg_get_functiondef('public.rr_upm_universal_form_v741(text,text)'::regprocedure) body
)
select jsonb_build_object(
  'result',case when body like '%V797_CURRENT_VISIBLE_LAST_SUBMIT_HIDDEN%'
                     and body like '%v_last_submitted_department%'
                     and body not like '%x.status=''COMPLETED'') into completed_here%'
                then 'PASS' else 'FAIL' end,
  'version','V797',
  'rule','CURRENT TARGET VISIBLE; ONLY LATEST SUBMITTED DEPARTMENT HIDDEN'
) as verification
from fn;
