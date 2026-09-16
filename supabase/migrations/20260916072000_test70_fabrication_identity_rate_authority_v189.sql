-- TEST70 V189: truthful Fabrication identities, Nasim upstream management,
-- and one audited multi-department Actual Rate entry using the App rate engine.
begin;

-- Balli is a Metal ID worker, not a Fabrication line manager.
insert into public.rr_departments(code,name,sequence_no,entry_mode,is_factory,is_active)
values('metal_id','Metal ID',40,'PIECE_RATE',true,true)
on conflict(code) do nothing;

update public.rr_user_profiles
set department_code='metal_id',role_code='worker',updated_at=now()
where auth_user_id='1a2b08fc-18d3-481d-b376-916bd31a3721'::uuid
  and is_active;

update public.rr_worker_directory_v1
set department_code='metal_id',role_code='id kariger',updated_at=now()
where linked_auth_user_id='1a2b08fc-18d3-481d-b376-916bd31a3721'::uuid
  and is_active;

update public.rr_real_chat_department_membership_v70
set is_active=false,source_rule='TRUTHFUL_METAL_ID_WORKER_V189',updated_at=now()
where worker_id='1a2b08fc-18d3-481d-b376-916bd31a3721'::uuid
  and not (upper(department_code)='METAL_ID' and membership_side='WORKER');

insert into public.rr_real_chat_department_membership_v70(
  department_code,worker_id,membership_side,source_rule,is_active,
  membership_scope,manual_lock,created_at,updated_at
) values (
  'METAL_ID','1a2b08fc-18d3-481d-b376-916bd31a3721'::uuid,'WORKER',
  'TRUTHFUL_METAL_ID_WORKER_V189',true,'DEPARTMENT',false,now(),now()
)
on conflict(department_code,worker_id,membership_side) do update
set is_active=true,source_rule=excluded.source_rule,membership_scope='DEPARTMENT',
    manual_lock=false,updated_at=now();

-- Sanju is a Printing worker only; remove the legacy named global-staff fan-out.
update public.rr_real_chat_department_membership_v70
set is_active=false,source_rule='TRUTHFUL_PRINT_WORKER_V189',updated_at=now()
where worker_id='8f6f2fb5-3e15-4d59-8385-1ac54b55f646'::uuid
  and membership_side='STAFF';

insert into public.rr_real_chat_department_membership_v70(
  department_code,worker_id,membership_side,source_rule,is_active,
  membership_scope,manual_lock,created_at,updated_at
) values (
  'PRINTING','8f6f2fb5-3e15-4d59-8385-1ac54b55f646'::uuid,'WORKER',
  'TRUTHFUL_PRINT_WORKER_V189',true,'DEPARTMENT',false,now(),now()
)
on conflict(department_code,worker_id,membership_side) do update
set is_active=true,source_rule=excluded.source_rule,membership_scope='DEPARTMENT',
    manual_lock=false,updated_at=now();

-- Nasim is the Fabrication Manager for the complete Cut-to-Despatch path.
update public.rr_real_chat_department_membership_v70
set is_active=false,source_rule='FABRICATION_MANAGER_STAFF_V189',updated_at=now()
where worker_id='688bc76c-3f66-4084-b3da-fc3d54220a28'::uuid
  and membership_side='WORKER';

with departments(code) as (values
  ('CUTTING'),('PRINTING'),('STICKER'),('METAL_ID'),('STITCHING'),
  ('OVERLOCK'),('FOLDING'),('KAAJ_BUTTON'),('TEAK_TANKI'),('THREAD_CUT'),
  ('QC'),('PRESS'),('PACKING'),('DISPATCH'),('FABRICATION')
)
insert into public.rr_real_chat_department_membership_v70(
  department_code,worker_id,membership_side,source_rule,is_active,
  membership_scope,manual_lock,created_at,updated_at
)
select code,'688bc76c-3f66-4084-b3da-fc3d54220a28'::uuid,'STAFF',
  'FABRICATION_MANAGER_CUT_TO_DESPATCH_V189',true,'MULTI_DEPARTMENT',
  false,now(),now()
from departments
on conflict(department_code,worker_id,membership_side) do update
set is_active=true,source_rule=excluded.source_rule,
    membership_scope='MULTI_DEPARTMENT',manual_lock=false,updated_at=now();

-- Home directory: managers/admins remain staff, not home workers.
create or replace function public.rr_real_chat_directory_v85()
returns jsonb language plpgsql volatile security definer set search_path=''
as $function$
declare v_result jsonb;v_departments jsonb;
begin
  v_result:=public.rr_real_chat_directory_v84();
  select coalesce(jsonb_agg(
    jsonb_set(jsonb_set(dep,'{workers}',coalesce(home.workers,'[]'::jsonb),true),
      '{worker_count}',to_jsonb(coalesce(home.worker_count,0)),true)
    order by (dep->>'sort_order')::integer
  ),'[]'::jsonb) into v_departments
  from jsonb_array_elements(coalesce(v_result->'departments','[]'::jsonb)) dep
  left join lateral (
    select count(*)::integer worker_count,
      jsonb_agg(jsonb_build_object(
        'worker_id',d.worker_id,'worker_code',d.worker_code,
        'worker_name',d.worker_name,'role_code',d.role_code,
        'home_department_code',public.rr_upm_core_department_v9077(d.department_code),
        'linked_login',d.linked_auth_user_id is not null,
        'membership_side','WORKER','membership_active',coalesce(m.is_active,false),
        'manual_lock',coalesce(m.manual_lock,false),'inactive_reason',m.inactive_reason,
        'source_rule',m.source_rule
      ) order by d.worker_name) workers
    from public.rr_worker_directory_unified_v1 d
    left join public.rr_real_chat_department_membership_v70 m
      on m.worker_id=d.worker_id and m.department_code=dep->>'department_code'
     and m.membership_side='WORKER'
    where coalesce(d.is_active,false)
      and upper(coalesce(d.access_status,'ACTIVE'))='ACTIVE'
      and public.rr_upm_core_department_v9077(d.department_code)=dep->>'department_code'
      and upper(coalesce(d.role_code,'WORKER')) not in
        ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','ACCOUNT','ACCOUNTS','ACCOUNTANT','DEPARTMENT_HEAD')
  ) home on true;
  v_result:=jsonb_set(v_result,'{departments}',v_departments,true);
  return jsonb_set(v_result,'{version}',to_jsonb('TEST70_REAL_CHAT_DIRECTORY_V85_TRUTHFUL_HOME_V189'::text),true);
end $function$;
revoke all on function public.rr_real_chat_directory_v85() from public,anon;
grant execute on function public.rr_real_chat_directory_v85() to authenticated;

create or replace function public.rr_upm_bulk_set_department_rates_v189(
  p_canonical_lot_id text,p_rates jsonb,p_reason text default null
)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_profile public.rr_user_profiles%rowtype;v_item jsonb;v_dept text;v_rate numeric;
  v_reason text:=nullif(trim(coalesce(p_reason,'')),'');v_saved jsonb:='[]'::jsonb;
  v_skipped jsonb:='[]'::jsonb;v_result jsonb;v_salaried numeric;
  v_allowed constant text[]:=array['CUTTING','PRINTING','STICKER','METAL_ID',
    'STITCHING','OVERLOCK','FOLDING','KAAJ_BUTTON','TEAK_TANKI','THREAD_CUT',
    'QC','PRESS','PACKING','DISPATCH'];
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  select * into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  order by updated_at desc nulls last limit 1;
  if not found then raise exception 'Active User Directory profile required.';end if;
  if not (
    lower(coalesce(v_profile.role_code,'')) in ('owner','super_admin','admin')
    or (lower(coalesce(v_profile.role_code,''))='manager'
      and upper(coalesce(v_profile.department_code,''))='FABRICATION'
      and lower(trim(coalesce(v_profile.full_name,'')))='nasim')
  ) then raise exception 'Actual Rate bulk entry permission denied.';end if;
  if coalesce(jsonb_typeof(p_rates),'')<>'array' or jsonb_array_length(p_rates)=0
    then raise exception 'At least one Department rate required.';end if;
  if v_reason is null or length(v_reason)<5 then
    raise exception 'Rate save reason minimum 5 characters required.';end if;

  for v_item in select value from jsonb_array_elements(p_rates)
  loop
    v_dept:=public.rr_upm_core_department_v9077(v_item->>'department_code');
    v_rate:=nullif(v_item->>'actual_rate','')::numeric;
    if not (v_dept=any(v_allowed)) then
      v_skipped:=v_skipped||jsonb_build_array(jsonb_build_object(
        'department_code',v_dept,'reason','OUTSIDE_CUT_TO_DESPATCH_SCOPE'));
      continue;
    end if;
    if coalesce(v_rate,0)<=0 then
      v_skipped:=v_skipped||jsonb_build_array(jsonb_build_object(
        'department_code',v_dept,'reason','RATE_REQUIRED'));
      continue;
    end if;
    select coalesce(max(salaried_labor_cost),0) into v_salaried
    from public.rr_upm_department_labor_cost_v9160
    where canonical_lot_id=p_canonical_lot_id
      and public.rr_upm_core_department_v9077(department_code)=v_dept;
    if coalesce(v_salaried,0)>0 then
      v_skipped:=v_skipped||jsonb_build_array(jsonb_build_object(
        'department_code',v_dept,'reason','SALARIED_WEIGHTED_COST_AUTO',
        'weighted_cost',v_salaried));
      continue;
    end if;
    v_result:=public.rr_upm_set_department_rate_v760(
      p_canonical_lot_id,v_dept,v_rate,null
    );
    v_saved:=v_saved||jsonb_build_array(v_result);
  end loop;
  return jsonb_build_object('ok',true,'version','V189',
    'canonical_lot_id',p_canonical_lot_id,'saved',v_saved,'skipped',v_skipped,
    'saved_count',jsonb_array_length(v_saved),'skipped_count',jsonb_array_length(v_skipped));
end $function$;
revoke all on function public.rr_upm_bulk_set_department_rates_v189(text,jsonb,text) from public,anon;
grant execute on function public.rr_upm_bulk_set_department_rates_v189(text,jsonb,text) to authenticated;

-- Fabrication is the virtual group; cards still display their truthful source work.
create or replace function public.rr_real_chat_work_inbox_v81(
  p_status text default 'WORKING',p_search text default null,
  p_department_code text default null,p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare v_base jsonb;v_cards jsonb;v_counts jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  v_base:=public.rr_real_chat_work_inbox_v80(p_status,p_search,p_department_code,p_limit);
  select coalesce(jsonb_agg(
    case when upper(coalesce(card->>'department_code',''))='FABRICATION'
      and nullif(card->>'source_department_code','') is not null
    then card||jsonb_build_object(
      'operational_group_name','Fabrication / Line Man',
      'department_name',public.rr_costing_department_display_v760(card->>'source_department_code'),
      'message',concat('Source ',public.rr_costing_department_display_v760(card->>'source_department_code'),
        ' · ',coalesce(card->>'message','Lineman operational journey'))
    ) else card end order by ord
  ),'[]'::jsonb) into v_cards
  from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) with ordinality x(card,ord);
  select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb) into v_counts
  from(select coalesce(nullif(x->>'department_code',''),'UNKNOWN') department_code,count(*) cnt
    from jsonb_array_elements(v_cards)x group by 1)s;
  return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}',
    to_jsonb('TEST70_REAL_CHAT_WORK_V81_TRUTHFUL_FABRICATION'::text),true),
    '{cards}',v_cards,true),'{department_counts}',v_counts,true);
end $function$;
revoke all on function public.rr_real_chat_work_inbox_v81(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_inbox_v81(text,text,text,integer) to authenticated;

create or replace function public.rr_real_chat_work_search_v8(
  p_status text default 'WORKING',p_search text default null,
  p_department_code text default null,p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare v_base jsonb;v_find text:=lower(trim(coalesce(p_search,'')));
  v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');
  v_cards jsonb;v_counts jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  v_base:=public.rr_real_chat_work_inbox_v81(p_status,null,p_department_code,p_limit);
  if v_find='' then return v_base;end if;
  select coalesce(jsonb_agg(card order by ord),'[]'::jsonb) into v_cards
  from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(card,ord)
  where lower(card::text)like'%'||v_find||'%'
    or(v_key<>''and regexp_replace(lower(card::text),'[^a-z0-9]','','g')like'%'||v_key||'%');
  select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb)into v_counts
  from(select coalesce(nullif(card->>'department_code',''),'UNKNOWN')department_code,
    count(*)card_count from jsonb_array_elements(v_cards)x(card)group by 1)c;
  return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end $function$;
revoke all on function public.rr_real_chat_work_search_v8(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_search_v8(text,text,text,integer) to authenticated;

commit;
