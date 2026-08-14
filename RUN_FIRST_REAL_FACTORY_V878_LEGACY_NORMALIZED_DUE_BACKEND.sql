-- REAL FACTORY V878
-- Backend-first legacy normalization for UPM Assign Due / Submit Due.
-- Goal: legacy lots react like new batches without mutating old production data.
-- Safe layer only: creates wrapper/helper RPCs. Existing v741/v740 functions remain unchanged.

begin;

do $$
begin
  if to_regprocedure('public.rr_upm_universal_form_v741(text,text)') is null then
    raise exception 'Required function rr_upm_universal_form_v741(text,text) is missing.';
  end if;
  if to_regclass('public.rr_upm_departments') is null then
    raise exception 'Required table rr_upm_departments is missing.';
  end if;
end $$;

create or replace function public.rr_upm_canonical_department_v878(p_code text)
returns text
language sql immutable
as $$
select case
  when upper(trim(coalesce(p_code,''))) in ('CUTTING','CUT') then 'CUTTING'
  when upper(trim(coalesce(p_code,''))) in ('PRINTING','PRINT','PRINTER') then 'PRINTING'
  when upper(trim(coalesce(p_code,''))) in ('STICKER','STICKER_WORK') then 'STICKER'
  when upper(trim(coalesce(p_code,''))) in ('ID','ID_WORK','IDENTITY','METAL_ID','METAL ID','METAL') then 'ID'
  when upper(trim(coalesce(p_code,''))) in ('KR','KARIGAR','STITCHING','KARIGAR / STITCHING') then 'KR'
  when upper(trim(coalesce(p_code,''))) in ('OVERLOCK','OV') then 'OVERLOCK'
  when upper(trim(coalesce(p_code,''))) in ('FOLDING','FLD','FLATLOCK') then 'FOLDING'
  when upper(trim(coalesce(p_code,''))) in ('KAAJ_BUTTON','KAAJ','KAJ','BUTTON','BTN','KAAJ BUTTON') then 'KAAJ_BUTTON'
  when upper(trim(coalesce(p_code,''))) in ('TEAK_TANKI','TEAK','TACK','TANKI','TEAK TANKI') then 'TEAK_TANKI'
  when upper(trim(coalesce(p_code,''))) in ('THREAD_CUT','THREAD_CUTTING','TH_CUT','THREAD CUT') then 'THREAD_CUT'
  when upper(trim(coalesce(p_code,''))) in ('QC','CHECKING','QUALITY_CHECK') then 'QC'
  when upper(trim(coalesce(p_code,''))) in ('PRESS','FINISHING') then 'PRESS'
  when upper(trim(coalesce(p_code,''))) in ('PACKING','PACK') then 'PACKING'
  when upper(trim(coalesce(p_code,''))) in ('DESPATCH','DISPATCH') then 'DESPATCH'
  else upper(trim(coalesce(p_code,'')))
end;
$$;

grant execute on function public.rr_upm_canonical_department_v878(text) to authenticated;

create or replace function public.rr_upm_department_candidates_v878(p_department_code text)
returns table(department_code text, canonical_code text, source_rank int)
language sql stable security definer set search_path=public
as $$
with wanted as (
  select public.rr_upm_canonical_department_v878(p_department_code) canonical_code
), raw(code, rank_no) as (
  values
    (upper(trim(coalesce(p_department_code,''))), 1),
    ((select canonical_code from wanted), 2)
), aliases(code, canonical_code, rank_no) as (
  values
    ('CUTTING','CUTTING',10),('CUT','CUTTING',11),
    ('PRINTING','PRINTING',10),('PRINT','PRINTING',11),('PRINTER','PRINTING',12),
    ('STICKER','STICKER',10),('STICKER_WORK','STICKER',11),
    ('ID','ID',10),('ID_WORK','ID',11),('IDENTITY','ID',12),('METAL_ID','ID',13),('METAL','ID',14),
    ('KR','KR',10),('KARIGAR','KR',11),('STITCHING','KR',12),
    ('OVERLOCK','OVERLOCK',10),('OV','OVERLOCK',11),
    ('FOLDING','FOLDING',10),('FLD','FOLDING',11),('FLATLOCK','FOLDING',12),
    ('KAAJ_BUTTON','KAAJ_BUTTON',10),('KAAJ','KAAJ_BUTTON',11),('KAJ','KAAJ_BUTTON',12),('BUTTON','KAAJ_BUTTON',13),('BTN','KAAJ_BUTTON',14),
    ('TEAK_TANKI','TEAK_TANKI',10),('TEAK','TEAK_TANKI',11),('TACK','TEAK_TANKI',12),('TANKI','TEAK_TANKI',13),
    ('THREAD_CUT','THREAD_CUT',10),('THREAD_CUTTING','THREAD_CUT',11),('TH_CUT','THREAD_CUT',12),
    ('QC','QC',10),('CHECKING','QC',11),('QUALITY_CHECK','QC',12),
    ('PRESS','PRESS',10),('FINISHING','PRESS',11),
    ('PACKING','PACKING',10),('PACK','PACKING',11),
    ('DESPATCH','DESPATCH',10),('DISPATCH','DESPATCH',11)
), dept_rows as (
  select d.department_code::text code,
         public.rr_upm_canonical_department_v878(coalesce(d.department_code,d.department_name)) canonical_code,
         30 rank_no
  from public.rr_upm_departments d, wanted w
  where public.rr_upm_canonical_department_v878(coalesce(d.department_code,d.department_name)) = w.canonical_code
     or public.rr_upm_canonical_department_v878(d.department_name) = w.canonical_code
), all_codes as (
  select code, public.rr_upm_canonical_department_v878(code) canonical_code, rank_no from raw where coalesce(code,'') <> ''
  union all
  select a.code, a.canonical_code, a.rank_no from aliases a join wanted w on a.canonical_code=w.canonical_code
  union all
  select code, canonical_code, rank_no from dept_rows
)
select distinct on (upper(code)) code, canonical_code, rank_no
from all_codes
where coalesce(code,'') <> ''
order by upper(code), rank_no;
$$;

grant execute on function public.rr_upm_department_candidates_v878(text) to authenticated;

create or replace function public.rr_upm_universal_form_normalized_v878(
  p_canonical_lot_id text,
  p_department_code text
) returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  c record;
  ctx jsonb;
  best jsonb := null;
  best_assign int := -1;
  best_submit int := -1;
  assign_count int;
  submit_count int;
  canonical text := public.rr_upm_canonical_department_v878(p_department_code);
begin
  for c in
    select * from public.rr_upm_department_candidates_v878(p_department_code)
    order by source_rank
  loop
    begin
      ctx := public.rr_upm_universal_form_v741(p_canonical_lot_id, c.department_code);

      select count(distinct upper(coalesce(r->>'colour_code', r->>'colour_id', r->>'colour_name')))
      into assign_count
      from jsonb_array_elements(coalesce(ctx->'rows','[]'::jsonb)) r
      where coalesce((r->>'can_assign')::boolean,false)
        and not coalesce((r->>'is_locked')::boolean,false)
        and not coalesce((r->>'is_completed_here')::boolean,false);

      select count(distinct upper(coalesce(r->>'colour_code', r->>'colour_id', r->>'colour_name')))
      into submit_count
      from jsonb_array_elements(coalesce(ctx->'rows','[]'::jsonb)) r
      where coalesce((r->>'is_locked')::boolean,false)
        and not coalesce((r->>'is_completed_here')::boolean,false);

      if assign_count > best_assign or submit_count > best_submit then
        best := ctx
          || jsonb_build_object(
            'requested_department_code', p_department_code,
            'resolved_department_code', c.department_code,
            'canonical_department_code', canonical,
            'assign_due_count', assign_count,
            'submit_due_count', submit_count,
            'normalizer_version', 'V878'
          );
        best_assign := greatest(assign_count, best_assign);
        best_submit := greatest(submit_count, best_submit);
      end if;

      if assign_count > 0 or submit_count > 0 then
        return best;
      end if;
    exception when others then
      -- Try the next legacy alias/code without blocking the frontend.
      null;
    end;
  end loop;

  return coalesce(best, jsonb_build_object(
    'rows','[]'::jsonb,
    'requested_department_code', p_department_code,
    'canonical_department_code', canonical,
    'assign_due_count', 0,
    'submit_due_count', 0,
    'normalizer_version', 'V878',
    'warning', 'No legacy/new department alias returned rows'
  ));
end;
$$;

grant execute on function public.rr_upm_universal_form_normalized_v878(text,text) to authenticated;

create or replace function public.rr_upm_due_lot_summary_v878(p_department_code text)
returns table(
  canonical_lot_id text,
  lot_no text,
  canonical_department_code text,
  resolved_department_code text,
  assign_due_count int,
  submit_due_count int,
  assign_due_codes text[],
  submit_due_codes text[]
)
language plpgsql security definer set search_path=public
as $$
declare
  lot record;
  ctx jsonb;
begin
  for lot in
    select b.canonical_lot_id::text, b.lot_no::text
    from public.rr_upm_lot_board_v1 b
    order by b.board_updated_at desc nulls last
  loop
    ctx := public.rr_upm_universal_form_normalized_v878(lot.canonical_lot_id, p_department_code);
    return query
    with rows as (
      select r
      from jsonb_array_elements(coalesce(ctx->'rows','[]'::jsonb)) r
    ), agg as (
      select
        array_agg(distinct upper(coalesce(r->>'colour_code', r->>'colour_id', r->>'colour_name')))
          filter (where coalesce((r->>'can_assign')::boolean,false)
                    and not coalesce((r->>'is_locked')::boolean,false)
                    and not coalesce((r->>'is_completed_here')::boolean,false)) assign_codes,
        array_agg(distinct upper(coalesce(r->>'colour_code', r->>'colour_id', r->>'colour_name')))
          filter (where coalesce((r->>'is_locked')::boolean,false)
                    and not coalesce((r->>'is_completed_here')::boolean,false)) submit_codes
      from rows
    )
    select
      lot.canonical_lot_id,
      lot.lot_no,
      ctx->>'canonical_department_code',
      ctx->>'resolved_department_code',
      coalesce(cardinality(assign_codes),0),
      coalesce(cardinality(submit_codes),0),
      coalesce(assign_codes, array[]::text[]),
      coalesce(submit_codes, array[]::text[])
    from agg
    where coalesce(cardinality(assign_codes),0) > 0
       or coalesce(cardinality(submit_codes),0) > 0;
  end loop;
end;
$$;

grant execute on function public.rr_upm_due_lot_summary_v878(text) to authenticated;

commit;

select jsonb_build_object(
  'ok', true,
  'version', 'REAL_FACTORY_V878_LEGACY_NORMALIZED_DUE_BACKEND',
  'created', jsonb_build_array(
    'rr_upm_canonical_department_v878(text)',
    'rr_upm_department_candidates_v878(text)',
    'rr_upm_universal_form_normalized_v878(text,text)',
    'rr_upm_due_lot_summary_v878(text)'
  ),
  'rules', jsonb_build_object(
    'legacy_lots','normalized like new batches',
    'assign_due','only selected department can_assign open colour rows',
    'submit_due','only selected department is_locked and not completed rows',
    'bulk_dropdown','untouched'
  )
) as real_factory_v878_backend_result;
