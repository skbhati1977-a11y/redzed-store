-- REAL FACTORY ACCOUNTS V8078
-- FIELD-WISE ADD NEW: PARTY / MATERIAL TYPE / MATERIAL / LEDGER
-- Uses existing rr_name_creation_requests_v805 and V8076 material approval functions when present.

begin;
create extension if not exists pg_trgm;

create or replace function public.rr_master_is_super_v8078()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.rr_user_profiles p
    where p.auth_user_id=auth.uid()
      and coalesce(p.is_active,false)
      and lower(coalesce(p.role_code,''))='owner'
  )
$$;

create or replace function public.rr_master_name_candidates_v8078(
  p_entity_type text,p_search text,p_limit integer default 20
)
returns table(id text,display_name text,code text,detail text,similarity_score numeric)
language plpgsql stable security definer set search_path=public as $$
declare e text:=upper(trim(coalesce(p_entity_type,''))); q text:=trim(coalesce(p_search,''));
begin
  if q='' then return; end if;

  if e in('PARTY','LEDGER') then
    return query
    select l.id::text,l.ledger_name,l.ledger_code,l.ledger_kind,
           greatest(similarity(lower(l.ledger_name),lower(q)),
             case when public.rr_name_normalize_v805(l.ledger_name)=public.rr_name_normalize_v805(q) then 1 else 0 end)::numeric
    from public.rr_ledgers_v805 l
    where l.is_active
      and greatest(similarity(lower(l.ledger_name),lower(q)),
        case when public.rr_name_normalize_v805(l.ledger_name)=public.rr_name_normalize_v805(q) then 1 else 0 end)>=0.35
    order by 5 desc,2 limit greatest(1,least(coalesce(p_limit,20),50));
  elsif e='MATERIAL_TYPE' then
    return query
    select t.id::text,t.type_name,t.type_code,t.material_category,
           greatest(similarity(lower(t.type_name),lower(q)),
             case when public.rr_name_normalize_v805(t.type_name)=public.rr_name_normalize_v805(q) then 1 else 0 end)::numeric
    from public.rr_material_types_v805 t
    where t.is_active
      and greatest(similarity(lower(t.type_name),lower(q)),
        case when public.rr_name_normalize_v805(t.type_name)=public.rr_name_normalize_v805(q) then 1 else 0 end)>=0.35
    order by 5 desc,2 limit greatest(1,least(coalesce(p_limit,20),50));
  end if;
end $$;

create or replace function public.rr_master_name_request_v8078(
  p_entity_type text,p_requested_name text,p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  e text:=upper(trim(coalesce(p_entity_type,'')));
  n text:=trim(coalesce(p_requested_name,''));
  nn text:=public.rr_name_normalize_v805(n);
  ms jsonb:='[]'::jsonb;
  blocked boolean:=false;
  rid uuid;
  typecode text;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if e not in('PARTY','LEDGER','MATERIAL_TYPE','MATERIAL') then raise exception 'Unsupported master entity type.'; end if;
  if n='' then raise exception 'Name required.'; end if;

  if e='MATERIAL' then
    typecode:=upper(coalesce(p_payload->>'type_code',''));
    if typecode='' then raise exception 'Material Type required.'; end if;
    if to_regprocedure('public.rr_material_similarity_candidates_v8076(text,text,text,integer)') is not null then
      execute $q$
        select coalesce(jsonb_agg(jsonb_build_object(
          'id',x.source_id,'display_name',x.display_name,'code',x.material_no,
          'detail',x.source_type,'similarity_score',x.similarity_score
        ) order by x.similarity_score desc),'[]'::jsonb),
        coalesce(bool_or(x.similarity_score>=0.72),false)
        from public.rr_material_similarity_candidates_v8076($1,$2,coalesce($3,'TEST'),8) x
      $q$ into ms,blocked using typecode,n,p_payload->>'data_mode';
    end if;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',x.id,'display_name',x.display_name,'code',x.code,'detail',x.detail,'similarity_score',x.similarity_score
    ) order by x.similarity_score desc),'[]'::jsonb),
    coalesce(bool_or(x.similarity_score>=0.72),false)
    into ms,blocked
    from public.rr_master_name_candidates_v8078(e,n,8) x;
  end if;

  if blocked then
    return jsonb_build_object('ok',false,'blocked_by_match',true,'suggested_matches',ms,
      'message','Similar existing name found. Use existing master instead of creating duplicate.');
  end if;

  if exists(
    select 1 from public.rr_name_creation_requests_v805 r
    where r.entity_type=e and r.normalized_requested_name=nn and r.status='PENDING'
  ) then raise exception 'Same new-name request is already pending.'; end if;

  insert into public.rr_name_creation_requests_v805(
    entity_type,requested_name,normalized_requested_name,requested_payload,suggested_matches,status,requested_by
  ) values(e,n,nn,coalesce(p_payload,'{}'::jsonb),ms,'PENDING',auth.uid())
  returning id into rid;

  return jsonb_build_object('ok',true,'request_id',rid,'status','PENDING','suggested_matches',ms,'blocked_by_match',false);
end $$;

create or replace function public.rr_master_name_requests_v8078(
  p_status text default null,p_limit integer default 100
)
returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(q) order by q.requested_at desc),'[]'::jsonb)
  from(
    select r.id,r.requested_at,r.entity_type,r.requested_name,r.requested_payload,
           r.suggested_matches,r.status,r.super_admin_remark,r.mapped_existing_id,r.created_entity_id
    from public.rr_name_creation_requests_v805 r
    where r.entity_type in('PARTY','LEDGER','MATERIAL_TYPE','MATERIAL')
      and (p_status is null or upper(r.status)=upper(p_status))
      and (r.requested_by=auth.uid() or public.rr_master_is_super_v8078())
    order by r.requested_at desc
    limit greatest(1,least(coalesce(p_limit,100),500))
  ) q
$$;

create or replace function public.rr_master_name_decide_v8078(
  p_request_id uuid,p_decision text,p_remark text default null
)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  r public.rr_name_creation_requests_v805%rowtype;
  d text:=upper(trim(coalesce(p_decision,'')));
  new_id uuid;
  cat uuid;
  kind text;
  code text;
  unit text;
  type_id uuid;
begin
  if not public.rr_master_is_super_v8078() then raise exception 'Super Admin permission required.'; end if;
  select * into r from public.rr_name_creation_requests_v805 where id=p_request_id for update;
  if not found then raise exception 'Request not found.'; end if;
  if r.status<>'PENDING' then raise exception 'Request already decided.'; end if;

  if d='REJECT' then
    update public.rr_name_creation_requests_v805 set status='REJECTED',super_admin_remark=nullif(trim(p_remark),''),
      decided_by=auth.uid(),decided_at=now() where id=r.id;
    return jsonb_build_object('ok',true,'status','REJECTED','message','Request rejected.');
  elsif d<>'APPROVE_NEW' then
    raise exception 'Decision must be APPROVE_NEW or REJECT.';
  end if;

  if r.entity_type='MATERIAL' then
    -- Reuse the installed material-specific decision logic so source-managed types remain protected.
    if to_regprocedure('public.rr_material_name_decide_v8076(uuid,text,text,text)') is null then
      raise exception 'Material approval backend V8076 is required.';
    end if;
    return public.rr_material_name_decide_v8076(r.id,'APPROVE_NEW',null,p_remark);
  elsif r.entity_type='MATERIAL_TYPE' then
    code:=upper(coalesce(nullif(trim(r.requested_payload->>'code_no'),''),regexp_replace(r.requested_name,'[^A-Za-z0-9]+','_','g')));
    unit:=upper(coalesce(nullif(trim(r.requested_payload->>'default_unit'),''),'PCS'));
    if exists(select 1 from public.rr_material_types_v805 where type_code=code or public.rr_name_normalize_v805(type_name)=r.normalized_requested_name) then
      raise exception 'Same Material Type already exists.';
    end if;
    insert into public.rr_material_types_v805(type_code,type_name,material_category,default_purchase_unit,default_consumption_unit,display_order,is_active)
    values(code,r.requested_name,'OTHER',unit,unit,100,true) returning id into new_id;
  elsif r.entity_type in('PARTY','LEDGER') then
    cat:=nullif(r.requested_payload->>'category_id','')::uuid;
    kind:=upper(coalesce(nullif(trim(r.requested_payload->>'ledger_kind'),''),case when r.entity_type='PARTY' then 'SUPPLIER' else 'GENERAL' end));
    code:=nullif(trim(r.requested_payload->>'code_no'),'');
    if cat is null then
      if kind in('SUPPLIER','PARTY') then select id into cat from public.rr_account_categories_v805 where category_code='SUPPLIER_PAYABLE' and is_active limit 1;
      elsif kind='CASH' then select id into cat from public.rr_account_categories_v805 where category_code='CASH' and is_active limit 1;
      elsif kind='BANK' then select id into cat from public.rr_account_categories_v805 where category_code='BANK' and is_active limit 1;
      else select id into cat from public.rr_account_categories_v805 where is_active order by display_order,category_name limit 1;
      end if;
    end if;
    if cat is null then raise exception 'Ledger Category required.'; end if;
    if exists(select 1 from public.rr_ledgers_v805 where normalized_name=r.normalized_requested_name and is_active) then
      raise exception 'Same Ledger / Party already exists.';
    end if;
    insert into public.rr_ledgers_v805(
      ledger_code,ledger_name,normalized_name,category_id,ledger_kind,is_active,approved_by,created_by
    ) values(code,r.requested_name,r.normalized_requested_name,cat,kind,true,auth.uid(),r.requested_by)
    returning id into new_id;
  else
    raise exception 'Unsupported entity type.';
  end if;

  update public.rr_name_creation_requests_v805
  set status='APPROVED',created_entity_id=new_id::text,super_admin_remark=nullif(trim(p_remark),''),
      decided_by=auth.uid(),decided_at=now()
  where id=r.id;

  return jsonb_build_object('ok',true,'status','APPROVED','created_entity_id',new_id,
    'message',replace(r.entity_type,'_',' ')||' approved and created.');
end $$;

grant execute on function public.rr_master_name_candidates_v8078(text,text,integer) to authenticated;
grant execute on function public.rr_master_name_request_v8078(text,text,jsonb) to authenticated;
grant execute on function public.rr_master_name_requests_v8078(text,integer) to authenticated;
grant execute on function public.rr_master_name_decide_v8078(uuid,text,text) to authenticated;

notify pgrst,'reload schema';
commit;
