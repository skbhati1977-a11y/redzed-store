alter table public.rr_cb_material_allocations add column if not exists allowed_art_category_ids uuid[] not null default '{}'::uuid[];
comment on column public.rr_cb_material_allocations.allowed_art_category_ids is 'Set-specific allowed Art categories for this material allocation.';
create or replace function public.rr_validate_cb_art_category_v1()
returns trigger language plpgsql security invoker set search_path=public as $$
declare v_cat uuid; v_allowed uuid[];
begin
 select art_category_id into v_cat from public.rr_art_master where id=new.art_id;
 select array_agg(distinct x) into v_allowed from (select unnest(a.allowed_art_category_ids) x from public.rr_cb_material_allocations a where a.division_id=new.cb_id and cardinality(a.allowed_art_category_ids)>0) q;
 if cardinality(coalesce(v_allowed,'{}'::uuid[]))>0 and (v_cat is null or not (v_cat=any(v_allowed))) then raise exception using errcode='23514',message='Selected Art category is not allowed for this S division material mapping.'; end if;
 return new;
end $$;