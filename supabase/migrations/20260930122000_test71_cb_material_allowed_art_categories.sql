-- TEST71: per-material allowed Art categories, enforced per allocated CB child.
alter table public.rr_cb_purchase_entries add column if not exists allowed_art_category_ids uuid[] not null default '{}'::uuid[];
comment on column public.rr_cb_purchase_entries.allowed_art_category_ids is 'Allowed rr_art_categories IDs for Art Decision on divisions allocated to this material entry. Empty means no Art-category restriction.';
create or replace function public.rr_validate_cb_art_category_v1()
returns trigger language plpgsql security invoker set search_path=public as $$
declare v_cat uuid; v_allowed uuid[];
begin
 select art_category_id into v_cat from public.rr_art_master where id=new.art_id;
 select array_agg(distinct x) into v_allowed from (
   select unnest(e.allowed_art_category_ids) x
   from public.rr_cb_material_allocations a join public.rr_cb_purchase_entries e on e.id=a.purchase_entry_id
   where a.division_id=new.cb_id and cardinality(e.allowed_art_category_ids)>0
 ) q;
 if cardinality(coalesce(v_allowed,'{}'::uuid[]))>0 and (v_cat is null or not (v_cat=any(v_allowed))) then
   raise exception using errcode='23514',message='Selected Art category is not allowed for this S division material mapping.';
 end if;
 return new;
end $$;
drop trigger if exists rr_cb_art_category_gate_v1 on public.rr_cb_art_assignments;
create trigger rr_cb_art_category_gate_v1 before insert or update of art_id,cb_id on public.rr_cb_art_assignments for each row execute function public.rr_validate_cb_art_category_v1();
revoke all on function public.rr_validate_cb_art_category_v1() from public,anon,authenticated;
