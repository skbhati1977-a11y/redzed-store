-- TEST-mode Art writes reconcile once after the complete canonical decision.
-- Accessory-free fixtures explicitly select the self-collar Art; no gates are bypassed.
do $patch$
declare d text; name text;
begin
 foreach name in array array['rr_real_chat_dynamic_lifecycle_trigger_v101','rr_real_chat_cb_close_trigger_v103','rr_real_chat_purchase_next_actions_trigger_v104','rr_real_chat_cutting_trigger_v113'] loop
 select pg_get_functiondef(to_regprocedure('public.'||name||'()')) into d;
 if position('redzed.cb_art_batch_test71' in d)=0 then
 d:=replace(d,E'begin\n',E'begin\n if current_setting(''redzed.cb_art_batch_test71'',true)=''on'' then return null; end if;\n');
 execute d;
 end if;
 end loop;
 select pg_get_functiondef('public.rr_pm_save_decision_bundle_v804(uuid,uuid,text,uuid[],text,uuid[],text,uuid[],text)'::regprocedure) into d;
 if position('redzed.cb_art_batch_test71' in d)>0 then raise exception 'Art batch already patched; inspect existing state'; end if;
 d:=replace(d,'  i integer:=0;',E'  i integer:=0;\n  batch_old text:=coalesce(current_setting(''redzed.cb_save_batch'',true),''off'');\n  art_batch_old text:=coalesce(current_setting(''redzed.cb_art_batch_test71'',true),''off'');\n  batch_test boolean:=false;');
 d:=replace(d,'  v_result:=public.rr_pm_save_decision_bundle_v802_2(',E'  select purchase_id into v_cb_id from public.rr_cb_units where id=p_cb_unit_id;\n  batch_test:=v_mode=''TEST'';\n  if coalesce(batch_test,false) then\n    perform set_config(''redzed.cb_save_batch'',''on'',true);\n    perform set_config(''redzed.cb_art_batch_test71'',''on'',true);\n  end if;\n  v_result:=public.rr_pm_save_decision_bundle_v802_2(');
 d:=replace(d,'  return coalesce(v_result',E'  if coalesce(batch_test,false) then\n    perform set_config(''redzed.cb_save_batch'',batch_old,true);\n    perform set_config(''redzed.cb_art_batch_test71'',art_batch_old,true);\n    if batch_old<>''on'' and art_batch_old<>''on'' then\n      perform public.rr_real_chat_reconcile_dynamic_lifecycle_v101();\n      perform public.rr_real_chat_reconcile_cb_close_v103();\n      perform public.rr_real_chat_purchase_next_actions_v104();\n      perform public.rr_real_chat_reconcile_cutting_v113();\n      perform public.rr_real_chat_reconcile_cutting_v628();\n      perform public.rr_real_chat_reconcile_cb_children_v105();\n      perform public.rr_real_chat_reconcile_cb_parent_v618();\n      perform public.rr_real_chat_reconcile_cb_slice_v96();\n      perform public.rr_real_chat_bind_art_superadmin_v99();\n    end if;\n  end if;\n  return coalesce(v_result');
 execute d;
end $patch$;
do $fixture$
declare d text; fn text;
begin
 foreach fn in array array['rr_test_cb_working_art_v611()','rr_test_cb_working_projection_v618()','rr_test_cutting_department_lifecycle_v632()','rr_test_cb_ui_fixture_v619(text,uuid)'] loop
 select pg_get_functiondef(('public.'||fn)::regprocedure) into d;
 d:=regexp_replace(d,'from public\.rr_art_master[[:space:]]+where is_active[[:space:]]+order by created_at,id[[:space:]]+limit 1',
 'from public.rr_art_master where is_active and art_category_id in (select id from public.rr_art_categories where category_code=''self-collar'' and is_active) order by created_at,id limit 1','g');
 if position('category_code=''self-collar''' in d)=0 then raise exception 'Accessory-free fixture Art selection not found: %',fn; end if;
 execute d;
 end loop;
end $fixture$;
do $queue$ declare d text; begin
select pg_get_functiondef('public.rr_chat_cutting_queue_test71(text)'::regprocedure) into d;
if position($old$cards:=coalesce(public.rr_real_chat_work_search_v10(s,null,'CUTTING',500)->'cards','[]');$old$ in d)=0 then raise exception 'Expected Cutting legacy queue missing'; end if;
d:=replace(d,$old$cards:=coalesce(public.rr_real_chat_work_search_v10(s,null,'CUTTING',500)->'cards','[]');$old$,$new$cards:=coalesce((select jsonb_agg(c) from jsonb_array_elements(coalesce(public.rr_real_chat_work_search_v317(s,null,'CUTTING',500)->'cards','[]')) c where upper(c->>'department_code')='CUTTING'),'[]');$new$);
execute d;
end $queue$;
do $handoff$ declare d text; begin
select pg_get_functiondef('public.rr_test_cutting_department_lifecycle_v632()'::regprocedure) into d;
if position($old$v_mirror:=public.rr_real_chat_work_search_v317('OPEN',v_lot,'FABRICATION',100);$old$ in d)=0 then raise exception 'Expected legacy Fabrication projection missing'; end if;
d:=replace(d,$old$v_mirror:=public.rr_real_chat_work_search_v317('OPEN',v_lot,'FABRICATION',100);$old$,$new$v_mirror:=public.rr_chat_department_projection_test71('FABRICATION','OPEN');$new$);
d:=replace(d,$old$array['PRINTING','STITCHING','OVERLOCK','THREAD_CUTTING','CHECKING','PRESS','FOLDING','PACKING']$old$,$new$array['STITCHING','OVERLOCK','THREAD_CUTTING','CHECKING','PRESS','FOLDING','PACKING']$new$);
d:=replace(d,$old$public.rr_real_chat_work_search_v317('WORKING',v_lot,'CUTTING',100)$old$,$new$public.rr_chat_cutting_queue_test71('WORKING')$new$);
d:=replace(d,$old$public.rr_real_chat_work_search_v317('CLOSE',v_lot,'CUTTING',100)$old$,$new$public.rr_chat_cutting_queue_test71('CLOSE')$new$);
execute d;
end $handoff$;
notify pgrst, 'reload schema';

