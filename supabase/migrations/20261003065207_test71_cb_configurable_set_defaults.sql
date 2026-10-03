alter table public.rr_cb_construction_defaults_v1
  add column if not exists default_sleeve_finish text not null default 'PLAIN',
  add column if not exists default_size_family text not null default 'L,XL,XXL',
  add column if not exists default_border_pounchi text not null default 'WITHOUT_BORDER_POUNCHI';

update public.rr_cb_construction_defaults_v1
set default_sleeve_finish=coalesce(nullif(default_sleeve_finish,''),'PLAIN'),
    default_size_family=coalesce(nullif(default_size_family,''),'L,XL,XXL'),
    default_border_pounchi=coalesce(nullif(default_border_pounchi,''),'WITHOUT_BORDER_POUNCHI')
where id=true;

create or replace function public.rr_cb_construction_defaults_get_v2()
returns jsonb language sql stable security definer set search_path=public as $$
select jsonb_build_object(
  'default_sleeve_type',default_sleeve_type,
  'default_sleeve_finish',default_sleeve_finish,
  'default_size_family',default_size_family,
  'default_border_pounchi',default_border_pounchi,
  'size_families',jsonb_build_array('L,XL,XXL','2XL,3XL,4XL','3XL,4XL,5XL','M,L,XL,XXL','M,L,XL','L,XL','L,XXL','FREE SIZE')
) from public.rr_cb_construction_defaults_v1 where id=true
$$;

create or replace function public.rr_cb_construction_defaults_set_v2(p_sleeve_type text,p_sleeve_finish text,p_size_family text,p_border_pounchi text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 st text:=upper(trim(coalesce(p_sleeve_type,'')));
 sf text:=public.rr_cb_normalize_sleeve_finish_v1(p_sleeve_finish);
 sz text:=replace(upper(trim(coalesce(p_size_family,''))),' ','');
 bp text:=upper(trim(coalesce(p_border_pounchi,'')));
begin
 perform public.rr_cb_department_assert_authority_v600();
 if st not in('HALF','FULL') then raise exception 'Default Sleeve must be HALF or FULL.'; end if;
 if sf not in('PLAIN','CUFF','RIB') then raise exception 'Default Sleeve Finish must be PLAIN, CUFF or RIB.'; end if;
 if sz not in('L,XL,XXL','2XL,3XL,4XL','3XL,4XL,5XL','M,L,XL,XXL','M,L,XL','L,XL','L,XXL','FREE SIZE') then raise exception 'Choose Size from the approved Size list.'; end if;
 if bp not in('WITH_BORDER_POUNCHI','WITHOUT_BORDER_POUNCHI') then raise exception 'Default Border Pounchi must be WITH or WITHOUT.'; end if;
 update public.rr_cb_construction_defaults_v1
 set default_sleeve_type=st,default_sleeve_finish=sf,default_size_family=sz,default_border_pounchi=bp,updated_at=now(),updated_by=auth.uid()
 where id=true;
 return public.rr_cb_construction_defaults_get_v2();
end $$;

revoke all on function public.rr_cb_construction_defaults_get_v2() from public,anon;
revoke all on function public.rr_cb_construction_defaults_set_v2(text,text,text,text) from public,anon;
grant execute on function public.rr_cb_construction_defaults_get_v2() to authenticated;
grant execute on function public.rr_cb_construction_defaults_set_v2(text,text,text,text) to authenticated;
