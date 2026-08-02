-- ============================================================
-- REDZED V776.7 — DUPLICATE WORKER NAME GUARD
-- ============================================================
--
-- Same normalized Worker Name cannot be saved twice in the same
-- Primary Department.
--
-- Equivalent names:
-- Ahmed
-- AHMED
-- " Ahmed "
-- "Ahmed   "
--
-- Existing duplicate historical rows are not deleted.
-- Future INSERT/UPDATE duplicates are blocked.
-- ============================================================

begin;

create or replace function public.rr_normalize_worker_name_v776_7(
  p_worker_name text
)
returns text
language sql
immutable
as $$
  select lower(
    regexp_replace(
      trim(coalesce(p_worker_name,'')),
      '\s+',
      ' ',
      'g'
    )
  )
$$;

grant execute on function public.rr_normalize_worker_name_v776_7(text)
to authenticated;

create or replace function public.rr_worker_duplicate_name_guard_v776_7()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_normalized_name text;
  v_department text;
  v_base_name text;
  v_suggestion text;
  v_suffix integer:=2;
  v_existing record;
begin
  v_normalized_name:=
    public.rr_normalize_worker_name_v776_7(new.worker_name);
  v_department:=lower(trim(coalesce(new.department_code,'')));
  v_base_name:=regexp_replace(trim(coalesce(new.worker_name,'')),'\s+',' ','g');

  if v_normalized_name='' then
    raise exception 'Worker Name required hai.';
  end if;

  if v_department='' then
    raise exception 'Primary Department required hai.';
  end if;

  select
    w.worker_id,
    w.worker_name,
    w.worker_code
  into v_existing
  from public.rr_worker_directory_unified_v1 w
  where w.worker_id<>new.id
    and lower(trim(coalesce(w.department_code,'')))=v_department
    and public.rr_normalize_worker_name_v776_7(w.worker_name)
        =v_normalized_name
  limit 1;

  if found then
    loop
      v_suggestion:=v_base_name||' '||v_suffix::text;

      exit when not exists(
        select 1
        from public.rr_worker_directory_unified_v1 w
        where w.worker_id<>new.id
          and lower(trim(coalesce(w.department_code,'')))=v_department
          and public.rr_normalize_worker_name_v776_7(w.worker_name)
              =public.rr_normalize_worker_name_v776_7(v_suggestion)
      );

      v_suffix:=v_suffix+1;
    end loop;

    raise exception
      'Same Department me Worker "%" pehle se maujood hai (%). Naye Worker ke naam me suffix use karein, jaise "%".',
      v_existing.worker_name,
      coalesce(v_existing.worker_code,v_existing.worker_id::text),
      v_suggestion;
  end if;

  new.worker_name:=v_base_name;
  return new;
end $$;

drop trigger if exists rr_worker_duplicate_name_guard_v776_7
on public.rr_worker_directory_v1;

create trigger rr_worker_duplicate_name_guard_v776_7
before insert or update of worker_name,department_code
on public.rr_worker_directory_v1
for each row
execute function public.rr_worker_duplicate_name_guard_v776_7();

commit;

select jsonb_build_object(
  'ok',true,
  'version','V776_7_DUPLICATE_WORKER_NAME_GUARD',
  'scope','SAME_PRIMARY_DEPARTMENT',
  'case_insensitive',true,
  'space_normalized',true,
  'existing_records_deleted',false,
  'future_duplicate_insert_update_blocked',true,
  'suffix_suggestion_enabled',true
) as rr_upm_v776_7_result;
