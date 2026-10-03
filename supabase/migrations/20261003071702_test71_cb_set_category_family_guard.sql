create or replace function public.rr_cb_set_art_category_allowed_v1(p_cb_unit_id uuid,p_category_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
select case
  when u.division_index=1 then lower(c.category_code)='self-collar'
  when u.division_index in(2,3) then lower(c.category_code) in('crew-neck','drop-shoulder')
  when u.division_index=4 then lower(c.category_code)='flat-polo'
  else true
end
from public.rr_cb_units u
join public.rr_art_categories c on c.id=p_category_id
where u.id=p_cb_unit_id
$$;

create or replace function public.rr_sync_cb_mapping_from_art_v3(p_cb_unit_id uuid,p_art_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  a record;
  u public.rr_cb_units%rowtype;
  req public.rr_cb_set_requirement_v1%rowtype;
  st text; sf text; unit_finish text; sz text; arr text[]; bp text;
begin
  perform public.rr_cb_department_assert_authority_v600();
  select * into u from public.rr_cb_units where id=p_cb_unit_id;
  if u.id is null then raise exception 'CB child not found.'; end if;
  select id,art_category_id into a from public.rr_art_master where id=p_art_id;
  if a.id is null then raise exception 'Art not found.'; end if;
  if a.art_category_id is null then raise exception 'Art Category required.'; end if;
  if not coalesce(public.rr_cb_set_art_category_allowed_v1(p_cb_unit_id,a.art_category_id),false) then
    raise exception 'Selected Art Category is not allowed for this Set.';
  end if;

  select * into req from public.rr_cb_set_requirement_v1 where cb_unit_id=p_cb_unit_id;
  st:=coalesce(nullif(upper(req.sleeve_type),''),nullif(upper(u.sleeve_type),''),'HALF');
  sf:=public.rr_cb_normalize_sleeve_finish_v1(coalesce(req.sleeve_finish,u.sleeve_finish,'PLAIN'));
  sz:=replace(coalesce(nullif(upper(req.size_family),''),nullif(upper(u.size_family),''),'L,XL,XXL'),' ','');
  if sz not in('L,XL,XXL','2XL,3XL,4XL','3XL,4XL,5XL','M,L,XL,XXL','M,L,XL','L,XL','L,XXL','FREE SIZE') then sz:='L,XL,XXL'; end if;
  arr:=case when sz='FREE SIZE' then array['FREE SIZE']::text[] else string_to_array(sz,',') end;
  bp:=case when upper(coalesce(req.border_pounchi,u.border_pounchi,'WITHOUT_BORDER_POUNCHI'))='WITH_BORDER_POUNCHI' then 'WITH_BORDER_POUNCHI' else 'WITHOUT_BORDER_POUNCHI' end;
  unit_finish:=case sf when 'CUFF' then 'WITH_CUFF' when 'RIB' then 'RIB' else 'WITHOUT_CUFF' end;

  update public.rr_cb_units
  set garment_category_id=a.art_category_id,sleeve_type=st,sleeve_finish=unit_finish,border_pounchi=bp,size_family=sz,size_set=arr,
      material_decision=case
        when exists(select 1 from public.rr_art_categories c where c.id=a.art_category_id and lower(c.category_code)='self-collar') then 'NOT_APPLICABLE'
        when material_decision='NOT_APPLICABLE' then 'DUE'
        else material_decision end,
      updated_at=now()
  where id=p_cb_unit_id;

  insert into public.rr_cb_set_requirement_v1
    (cb_unit_id,art_id,art_category_id,sleeve_type,size_family,sleeve_finish,border_pounchi,updated_at)
  values(p_cb_unit_id,p_art_id,a.art_category_id,st,sz,sf,bp,now())
  on conflict(cb_unit_id) do update set
    art_id=excluded.art_id,art_category_id=excluded.art_category_id,sleeve_type=excluded.sleeve_type,size_family=excluded.size_family,
    sleeve_finish=excluded.sleeve_finish,border_pounchi=excluded.border_pounchi,updated_at=now();

  return jsonb_build_object('ok',true,'source','ART','art_id',p_art_id,'category_id',a.art_category_id,'sleeve_type',st,'sleeve_finish',sf,'border_pounchi',bp,'size_family',sz);
end $$;

create or replace function public.rr_cb_set_requirement_sync_v5(p_cb_id uuid,p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  r jsonb; u public.rr_cb_units%rowtype; a public.rr_cb_art_assignments%rowtype; am record;
  di int; n int:=0; st text; sf text; sz text; bp text; cat uuid; art uuid; arr text[]; unit_finish text; cat_code text;
begin
  perform public.rr_cb_department_assert_authority_v600();
  for r in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    di:=(r->>'set_no')::int;
    st:=coalesce(nullif(upper(r->>'sleeve_type'),''),'HALF');
    sf:=public.rr_cb_normalize_sleeve_finish_v1(r->>'sleeve_finish');
    sz:=replace(coalesce(nullif(upper(r->>'size_family'),''),'L,XL,XXL'),' ','');
    bp:=case when upper(coalesce(r->>'border_pounchi','WITHOUT_BORDER_POUNCHI'))='WITH_BORDER_POUNCHI' then 'WITH_BORDER_POUNCHI' else 'WITHOUT_BORDER_POUNCHI' end;
    cat:=nullif(r->>'art_category_id','')::uuid;
    art:=nullif(r->>'art_id','')::uuid;
    if sz not in('L,XL,XXL','2XL,3XL,4XL','3XL,4XL,5XL','M,L,XL,XXL','M,L,XL','L,XL','L,XXL','FREE SIZE') then raise exception 'Choose Size from the approved Size list.'; end if;

    select * into u from public.rr_cb_units where purchase_id=p_cb_id and division_index=di and coalesce(is_final,true) order by created_at limit 1;
    if u.id is null then continue; end if;

    if art is not null then
      select id,art_category_id into am from public.rr_art_master where id=art;
      if am.id is null or am.art_category_id is null then raise exception 'Selected Art Category required.'; end if;
      cat:=am.art_category_id;
    end if;

    if cat is not null and not coalesce(public.rr_cb_set_art_category_allowed_v1(u.id,cat),false) then
      raise exception 'S%: selected Category is not allowed for this Set.',di;
    end if;

    if art is not null then
      insert into public.rr_cb_art_assignments(cb_id,art_id) values(u.id,art)
      on conflict(cb_id) do update set art_id=excluded.art_id,updated_at=now();
    else
      select * into a from public.rr_cb_art_assignments where cb_id=u.id;
      if a.id is not null then
        select id,art_category_id into am from public.rr_art_master where id=a.art_id;
        if cat is null or am.art_category_id is distinct from cat then delete from public.rr_cb_art_assignments where id=a.id; else art:=a.art_id; end if;
      end if;
    end if;

    select lower(category_code) into cat_code from public.rr_art_categories where id=cat;
    arr:=case when sz='FREE SIZE' then array['FREE SIZE']::text[] else string_to_array(sz,',') end;
    unit_finish:=case sf when 'CUFF' then 'WITH_CUFF' when 'RIB' then 'RIB' else 'WITHOUT_CUFF' end;

    insert into public.rr_cb_set_requirement_v1
      (cb_unit_id,art_id,art_category_id,sleeve_type,size_family,sleeve_finish,border_pounchi,updated_at)
    values(u.id,art,cat,st,sz,sf,bp,now())
    on conflict(cb_unit_id) do update set
      art_id=excluded.art_id,art_category_id=excluded.art_category_id,sleeve_type=excluded.sleeve_type,size_family=excluded.size_family,
      sleeve_finish=excluded.sleeve_finish,border_pounchi=excluded.border_pounchi,updated_at=now();

    update public.rr_cb_units
    set garment_category_id=cat,sleeve_type=st,sleeve_finish=unit_finish,border_pounchi=bp,size_family=sz,size_set=arr,
        material_decision=case when cat_code='self-collar' then 'NOT_APPLICABLE' when material_decision='NOT_APPLICABLE' then 'DUE' else material_decision end,
        updated_at=now()
    where id=u.id;
    n:=n+1;
  end loop;
  return jsonb_build_object('ok',true,'synced',n);
end $$;

revoke all on function public.rr_cb_set_art_category_allowed_v1(uuid,uuid) from public,anon;
grant execute on function public.rr_cb_set_art_category_allowed_v1(uuid,uuid) to authenticated;
