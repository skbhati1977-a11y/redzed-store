-- REAL FACTORY ACCOUNTS V8076
-- MATERIAL ADD NEW: SPELL/SIMILARITY CHECK -> REQUEST -> SUPER ADMIN DECISION
-- Run after V805/V805.1 material backend.

begin;
create extension if not exists pg_trgm;

create or replace function public.rr_material_request_is_super_v8076()
returns boolean
language sql stable security definer set search_path=public
as $$
  select exists(
    select 1 from public.rr_user_profiles p
    where p.auth_user_id=auth.uid()
      and coalesce(p.is_active,false)
      and lower(coalesce(p.role_code,''))='owner'
  );
$$;

create or replace function public.rr_material_similarity_candidates_v8076(
  p_type_code text,
  p_requested_name text,
  p_data_mode text default 'TEST',
  p_limit integer default 8
)
returns table(
  source_type text, source_id text, existing_material_id uuid,
  display_name text, material_no text, similarity_score numeric, source_managed boolean
)
language plpgsql stable security definer set search_path=public
as $$
declare
  v_type text:=upper(trim(coalesce(p_type_code,'')));
  v_name text:=trim(coalesce(p_requested_name,''));
  v_norm text:=public.rr_name_normalize_v805(v_name);
begin
  if v_name='' then return; end if;

  if v_type='REGULAR_CLOTH' then
    return query
    select 'CB_REGULAR_CLOTH',min(e.id::text),null::uuid,e.fabric_name,null::text,
           greatest(similarity(lower(e.fabric_name),lower(v_name)),
                    case when public.rr_name_normalize_v805(e.fabric_name)=v_norm then 1 else 0 end)::numeric,
           true
    from public.rr_cb_purchase_entries e
    join public.rr_material_categories c on c.id=e.material_category_id
    where lower(c.category_code)='regular-cloth' and nullif(trim(e.fabric_name),'') is not null
    group by e.fabric_name
    having greatest(similarity(lower(e.fabric_name),lower(v_name)),
                    case when public.rr_name_normalize_v805(e.fabric_name)=v_norm then 1 else 0 end)>=0.45
    order by 6 desc,4
    limit greatest(1,least(coalesce(p_limit,8),20));
    return;
  elsif v_type='MATCHING_CLOTH' then
    return query
    select 'MATCHING_STOCK',
           coalesce(min(to_jsonb(s)->>'stock_item_id'),min(to_jsonb(s)->>'cb_id'),min(s.fabric_name))::text,
           null::uuid,s.fabric_name,null::text,
           greatest(similarity(lower(s.fabric_name),lower(v_name)),
                    case when public.rr_name_normalize_v805(s.fabric_name)=v_norm then 1 else 0 end)::numeric,
           true
    from public.rr_matching_stock_balance s
    where nullif(trim(s.fabric_name),'') is not null
    group by s.fabric_name
    having greatest(similarity(lower(s.fabric_name),lower(v_name)),
                    case when public.rr_name_normalize_v805(s.fabric_name)=v_norm then 1 else 0 end)>=0.45
    order by 6 desc,4
    limit greatest(1,least(coalesce(p_limit,8),20));
    return;
  elsif v_type='STICKER' then
    return query
    select 'STICKER_MASTER_V803',s.id::text,m.id,
           coalesce(nullif(trim(s.sticker_name),''),s.sticker_no),s.sticker_no,
           greatest(similarity(lower(coalesce(s.sticker_name,s.sticker_no,'')),lower(v_name)),
                    case when public.rr_name_normalize_v805(coalesce(s.sticker_name,s.sticker_no))=v_norm then 1 else 0 end)::numeric,
           true
    from public.rr_sticker_master_v803 s
    left join public.rr_material_master_v805 m on m.external_master_type='STICKER_MASTER_V803' and m.external_master_id=s.id::text and m.is_active
    where s.is_active
      and greatest(similarity(lower(coalesce(s.sticker_name,s.sticker_no,'')),lower(v_name)),
                   case when public.rr_name_normalize_v805(coalesce(s.sticker_name,s.sticker_no))=v_norm then 1 else 0 end)>=0.45
    order by 6 desc,4
    limit greatest(1,least(coalesce(p_limit,8),20));
    return;
  elsif v_type='METAL_ID' then
    return query
    select 'METAL_ID_MASTER_V803',s.id::text,m.id,
           coalesce(nullif(trim(s.metal_id_name),''),s.metal_id_no),s.metal_id_no,
           greatest(similarity(lower(coalesce(s.metal_id_name,s.metal_id_no,'')),lower(v_name)),
                    case when public.rr_name_normalize_v805(coalesce(s.metal_id_name,s.metal_id_no))=v_norm then 1 else 0 end)::numeric,
           true
    from public.rr_metal_id_master_v803 s
    left join public.rr_material_master_v805 m on m.external_master_type='METAL_ID_MASTER_V803' and m.external_master_id=s.id::text and m.is_active
    where s.is_active
      and greatest(similarity(lower(coalesce(s.metal_id_name,s.metal_id_no,'')),lower(v_name)),
                   case when public.rr_name_normalize_v805(coalesce(s.metal_id_name,s.metal_id_no))=v_norm then 1 else 0 end)>=0.45
    order by 6 desc,4
    limit greatest(1,least(coalesce(p_limit,8),20));
    return;
  else
    return query
    select coalesce(m.external_master_type,'MATERIAL_MASTER_V805'),coalesce(m.external_master_id,m.id::text),m.id,
           m.material_name,m.material_no,
           greatest(similarity(lower(m.material_name),lower(v_name)),
                    case when m.normalized_name=v_norm then 1 else 0 end)::numeric,
           false
    from public.rr_material_master_v805 m
    join public.rr_material_types_v805 t on t.id=m.material_type_id
    where m.is_active and t.type_code=v_type
      and greatest(similarity(lower(m.material_name),lower(v_name)),
                   case when m.normalized_name=v_norm then 1 else 0 end)>=0.45
    order by 6 desc,4
    limit greatest(1,least(coalesce(p_limit,8),20));
    return;
  end if;
end $$;

create or replace function public.rr_material_name_request_v8076(
  p_type_code text,
  p_requested_name text,
  p_material_no text default null,
  p_purchase_unit text default 'PCS',
  p_stock_unit text default 'PCS',
  p_consumption_unit text default 'PCS',
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_type text:=upper(trim(coalesce(p_type_code,'')));
  v_name text:=trim(coalesce(p_requested_name,''));
  v_norm text:=public.rr_name_normalize_v805(v_name);
  v_matches jsonb;
  v_block boolean:=false;
  v_id uuid;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if v_name='' then raise exception 'Material Name required.'; end if;
  if not exists(select 1 from public.rr_material_types_v805 where type_code=v_type and is_active) then
    raise exception 'Active Material Type not found.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'source_type',x.source_type,'source_id',x.source_id,'existing_material_id',x.existing_material_id,
    'display_name',x.display_name,'material_no',x.material_no,'similarity_score',x.similarity_score,
    'source_managed',x.source_managed
  ) order by x.similarity_score desc),'[]'::jsonb),
  coalesce(bool_or(x.similarity_score>=0.72),false)
  into v_matches,v_block
  from public.rr_material_similarity_candidates_v8076(v_type,v_name,p_data_mode,8) x;

  if v_block then
    return jsonb_build_object('ok',false,'blocked_by_match',true,'suggested_matches',v_matches,
                              'message','Similar existing Material found. Select existing instead of Add New.');
  end if;

  if exists(
    select 1 from public.rr_name_creation_requests_v805 r
    where r.entity_type='MATERIAL'
      and (r.requested_payload->>'type_code')=v_type
      and r.normalized_requested_name=v_norm
      and r.status='PENDING'
  ) then
    raise exception 'Same Material request is already pending for Super Admin approval.';
  end if;

  insert into public.rr_name_creation_requests_v805(
    entity_type,requested_name,normalized_requested_name,requested_payload,suggested_matches,status,requested_by
  ) values(
    'MATERIAL',v_name,v_norm,
    jsonb_build_object('type_code',v_type,'material_no',nullif(trim(p_material_no),''),
      'purchase_unit',upper(trim(coalesce(p_purchase_unit,'PCS'))),
      'stock_unit',upper(trim(coalesce(p_stock_unit,'PCS'))),
      'consumption_unit',upper(trim(coalesce(p_consumption_unit,'PCS'))),
      'data_mode',upper(trim(coalesce(p_data_mode,'TEST')))),
    v_matches,'PENDING',auth.uid()
  ) returning id into v_id;

  return jsonb_build_object('ok',true,'blocked_by_match',false,'request_id',v_id,'suggested_matches',v_matches,'status','PENDING');
end $$;

create or replace function public.rr_material_name_requests_v8076(
  p_status text default null,
  p_limit integer default 100
)
returns jsonb
language sql stable security definer set search_path=public
as $$
  select coalesce(jsonb_agg(to_jsonb(q) order by q.requested_at desc),'[]'::jsonb)
  from (
    select r.id,r.requested_at,r.entity_type,r.requested_name,r.requested_payload->>'type_code' type_code,
           r.requested_payload,r.suggested_matches,r.status,r.super_admin_remark,r.mapped_existing_id,r.created_entity_id
    from public.rr_name_creation_requests_v805 r
    where r.entity_type='MATERIAL'
      and (p_status is null or upper(r.status)=upper(p_status))
      and (r.requested_by=auth.uid() or public.rr_material_request_is_super_v8076())
    order by r.requested_at desc
    limit greatest(1,least(coalesce(p_limit,100),500))
  ) q
$$;

create or replace function public.rr_material_name_decide_v8076(
  p_request_id uuid,
  p_decision text,
  p_existing_source_id text default null,
  p_remark text default null
)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  r public.rr_name_creation_requests_v805%rowtype;
  v_dec text:=upper(trim(coalesce(p_decision,'')));
  v_type text;
  v_name text;
  v_material_no text;
  v_pu text;v_su text;v_cu text;
  v_type_id uuid;
  v_new_id uuid;
begin
  if not public.rr_material_request_is_super_v8076() then raise exception 'Super Admin permission required.'; end if;
  select * into r from public.rr_name_creation_requests_v805 where id=p_request_id and entity_type='MATERIAL' for update;
  if not found then raise exception 'Material request not found.'; end if;
  if r.status<>'PENDING' then raise exception 'Request already decided.'; end if;

  v_type:=upper(r.requested_payload->>'type_code');
  v_name:=coalesce(r.corrected_name,r.requested_name);
  v_material_no:=nullif(trim(r.requested_payload->>'material_no'),'');
  v_pu:=upper(coalesce(nullif(r.requested_payload->>'purchase_unit',''),'PCS'));
  v_su:=upper(coalesce(nullif(r.requested_payload->>'stock_unit',''),v_pu));
  v_cu:=upper(coalesce(nullif(r.requested_payload->>'consumption_unit',''),v_su));

  if v_dec='REJECT' then
    update public.rr_name_creation_requests_v805
      set status='REJECTED',super_admin_remark=nullif(trim(p_remark),''),decided_by=auth.uid(),decided_at=now()
      where id=r.id;
    return jsonb_build_object('ok',true,'status','REJECTED','message','Request rejected.');
  elsif v_dec='MAP_EXISTING' then
    if nullif(trim(p_existing_source_id),'') is null then raise exception 'Existing source id required.'; end if;
    update public.rr_name_creation_requests_v805
      set status='MAPPED_EXISTING',mapped_existing_id=trim(p_existing_source_id),super_admin_remark=nullif(trim(p_remark),''),
          decided_by=auth.uid(),decided_at=now()
      where id=r.id;
    return jsonb_build_object('ok',true,'status','MAPPED_EXISTING','message','Request mapped to existing Material.');
  elsif v_dec<>'APPROVE_NEW' then
    raise exception 'Decision must be APPROVE_NEW, MAP_EXISTING or REJECT.';
  end if;

  -- Source-managed types cannot be duplicated into generic material master.
  if v_type in('REGULAR_CLOTH','MATCHING_CLOTH','STICKER','METAL_ID') then
    update public.rr_name_creation_requests_v805
      set status='APPROVED_SOURCE_CREATE_REQUIRED',super_admin_remark=coalesce(nullif(trim(p_remark),''),'Approved. Create in canonical source master, then map.'),
          decided_by=auth.uid(),decided_at=now()
      where id=r.id;
    return jsonb_build_object('ok',true,'status','APPROVED_SOURCE_CREATE_REQUIRED',
      'message',replace(v_type,'_',' ')||' is source-managed. Approval recorded; create it in its canonical source master and it will then appear in mapped search.');
  end if;

  select id into v_type_id from public.rr_material_types_v805 where type_code=v_type and is_active limit 1;
  if v_type_id is null then raise exception 'Active Material Type not found.'; end if;

  if exists(select 1 from public.rr_material_master_v805 where material_type_id=v_type_id and normalized_name=public.rr_name_normalize_v805(v_name) and is_active) then
    raise exception 'Same normalized Material already exists. Map existing instead.';
  end if;

  insert into public.rr_material_master_v805(
    material_no,material_type_id,material_name,normalized_name,purchase_unit,base_stock_unit,consumption_unit,
    purchase_to_base,consumption_to_base,estimated_consumption_per_good_piece,consumption_basis,applicable_to,
    is_active,created_by,approved_by,created_at,updated_at
  ) values(
    v_material_no,v_type_id,v_name,public.rr_name_normalize_v805(v_name),v_pu,v_su,v_cu,
    1,1,0,'AUTO_STANDARD','{}'::jsonb,true,r.requested_by,auth.uid(),now(),now()
  ) returning id into v_new_id;

  update public.rr_name_creation_requests_v805
    set status='APPROVED',created_entity_id=v_new_id::text,super_admin_remark=nullif(trim(p_remark),''),
        decided_by=auth.uid(),decided_at=now()
    where id=r.id;

  return jsonb_build_object('ok',true,'status','APPROVED','created_entity_id',v_new_id,'message','New Material approved and created.');
end $$;

grant execute on function public.rr_material_similarity_candidates_v8076(text,text,text,integer) to authenticated;
grant execute on function public.rr_material_name_request_v8076(text,text,text,text,text,text,text) to authenticated;
grant execute on function public.rr_material_name_requests_v8076(text,integer) to authenticated;
grant execute on function public.rr_material_name_decide_v8076(uuid,text,text,text) to authenticated;

notify pgrst,'reload schema';
commit;
