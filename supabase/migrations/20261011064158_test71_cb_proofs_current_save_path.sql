-- TEST-only proofs must exercise the same batched save authority as the CB editor.
-- Preserve signatures, grants, validation, idempotency and rollback assertions.
do $migration$
declare signature text; definition text;
begin
  foreach signature in array array[
    'public.rr_test_cb_department_flow_v600()',
    'public.rr_test_cb_material_unit_v610()',
    'public.rr_test_cb_open_draft_invariants_v608()',
    'public.rr_test_cb_ui_fixture_v619(text,uuid)',
    'public.rr_test_cb_working_art_v611()',
    'public.rr_test_cb_working_projection_v618()',
    'public.rr_test_cutting_department_lifecycle_v615()',
    'public.rr_test_cutting_department_lifecycle_v632()'
  ] loop
    select pg_get_functiondef(signature::regprocedure) into definition;
    if position('public.rr_cb_department_save_v600(' in definition)>0 then
      execute replace(definition,'public.rr_cb_department_save_v600(','public.rr_cb_department_save_v601(');
    elsif position('public.rr_cb_department_save_v601(' in definition)=0 then
      raise exception 'Expected CB save authority missing in %',signature;
    end if;
  end loop;
end $migration$;
