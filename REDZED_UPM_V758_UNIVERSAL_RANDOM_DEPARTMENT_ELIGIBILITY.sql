-- REDZED UPM V758
-- UNIVERSAL RANDOM COLOUR DEPARTMENT ELIGIBILITY
--
-- PURPOSE:
-- Every ACTIVE department may claim an OPEN Colour.
--
-- PRESERVED:
-- * Worker must still be actively mapped to the selected department.
-- * Colour/department duplicate locks remain.
-- * Quantity and Cutting validation remain.
-- * Existing assignment transaction logic remains.
--
-- This patch modifies only the hard-coded department eligibility rejection
-- inside rr_upm_claim_colours_v741.

begin;

create table if not exists public.rr_upm_function_backup_v758 (
  id bigserial primary key,
  function_identity text not null,
  version_tag text not null,
  function_definition text not null,
  backed_up_at timestamptz not null default now()
);

do $v758$
declare
  v_proc regprocedure;
  v_def text;
  v_new text;
  v_old_count integer;
  v_new_count integer;
begin
  v_proc := to_regprocedure(
    'public.rr_upm_claim_colours_v741(text,text,text,jsonb,text)'
  );

  if v_proc is null then
    raise exception
      'Function rr_upm_claim_colours_v741(text,text,text,jsonb,text) was not found.';
  end if;

  select pg_get_functiondef(v_proc::oid)
  into v_def;

  if v_def is null then
    raise exception 'Unable to read rr_upm_claim_colours_v741 definition.';
  end if;

  v_old_count :=
    case
      when position(
        'Department is not eligible for random Colour assignment'
        in v_def
      ) > 0 then 1
      else 0
    end;

  if v_old_count = 0 then
    raise exception
      'Expected eligibility gate text was not found. No function was changed.';
  end if;

  insert into public.rr_upm_function_backup_v758(
    function_identity,
    version_tag,
    function_definition
  )
  values(
    v_proc::text,
    'PRE_V758_UNIVERSAL_RANDOM_DEPARTMENT_ELIGIBILITY',
    v_def
  );

  /*
    Remove only this exact IF block:

      IF NOT <eligibility condition> THEN
        RAISE EXCEPTION
          'Department is not eligible for random Colour assignment.';
      END IF;

    No other validation block is touched.
  */
  v_new := regexp_replace(
    v_def,
    $rx$
      if[[:space:]]+not[[:space:]]+[^;]+
      then[[:space:]]+
      raise[[:space:]]+exception[[:space:]]+
      'Department is not eligible for random Colour assignment\.'
      (?:[[:space:]]+using[[:space:]]+[^;]+)?
      ;[[:space:]]*
      end[[:space:]]+if[[:space:]]*;
    $rx$,
    E'\n  null; -- V758: every active mapped department may claim OPEN Colours\n',
    'gix'
  );

  v_new_count :=
    case
      when position(
        'Department is not eligible for random Colour assignment'
        in v_new
      ) > 0 then 1
      else 0
    end;

  if v_new = v_def or v_new_count <> 0 then
    raise exception
      'V758 could not isolate the eligibility IF block. No function was changed.';
  end if;

  execute v_new;
end
$v758$;

grant execute on function public.rr_upm_claim_colours_v741(
  text,text,text,jsonb,text
) to authenticated;

commit;

-- Verification
select jsonb_build_object(
  'ok',
  position(
    'Department is not eligible for random Colour assignment'
    in pg_get_functiondef(
      'public.rr_upm_claim_colours_v741(text,text,text,jsonb,text)'::regprocedure
    )
  ) = 0,
  'version',
  'V758_UNIVERSAL_RANDOM_DEPARTMENT_ELIGIBILITY',
  'function',
  'rr_upm_claim_colours_v741(text,text,text,jsonb,text)',
  'rule',
  'Every active department may claim an OPEN Colour; worker mapping and all other locks remain enforced.'
) as rr_upm_v758_result;
