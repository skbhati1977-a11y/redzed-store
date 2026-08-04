-- Use only if V766 must be removed.
begin;

do $rollback$
begin
  if to_regprocedure(
       'public.rr_upm_alter_stage_v740_core(text,text,text,jsonb,jsonb,boolean,uuid,text)'
     ) is not null then
    if to_regprocedure(
         'public.rr_upm_alter_stage_v740(text,text,text,jsonb,jsonb,boolean,uuid,text)'
       ) is not null then
      execute 'drop function public.rr_upm_alter_stage_v740(text,text,text,jsonb,jsonb,boolean,uuid,text)';
    end if;

    execute 'alter function public.rr_upm_alter_stage_v740_core(text,text,text,jsonb,jsonb,boolean,uuid,text) rename to rr_upm_alter_stage_v740';
    execute 'grant execute on function public.rr_upm_alter_stage_v740(text,text,text,jsonb,jsonb,boolean,uuid,text) to authenticated';
  end if;
end
$rollback$;

commit;
