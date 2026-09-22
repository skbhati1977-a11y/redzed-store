-- TEST71 V609 · make the rollback-only CB duplicate proof recognize the
-- canonical creator's explicit business rejection as well as SQLSTATE 23505.
-- No business row, duplicate guard, or canonical save behavior is changed.

begin;

do $do$
declare
  v_def text;
  v_next text;
  v_marker text:=$marker$exception when unique_violation then
      v_natural_duplicate_blocked:=true;
    end;$marker$;
  v_replacement text:=$marker$exception
      when unique_violation then
        v_natural_duplicate_blocked:=true;
      when raise_exception then
        -- V609 natural duplicate proof: rr_create_cb_v713 deliberately raises
        -- P0001 before the unique index when the normalized CB already exists.
        if position(v_cb_no in sqlerrm)>0
           and lower(sqlerrm) like '%already exists%' then
          v_natural_duplicate_blocked:=true;
        else
          raise;
        end if;
    end;$marker$;
begin
  select pg_get_functiondef(
    'public.rr_test_cb_open_draft_invariants_v608()'::regprocedure
  ) into v_def;

  if position('V609 natural duplicate proof' in v_def)=0 then
    v_next:=replace(v_def,v_marker,v_replacement);
    if v_next=v_def then
      raise exception 'V608 rollback proof patch did not match';
    end if;
    execute v_next;
  end if;
end
$do$;

comment on function public.rr_test_cb_open_draft_invariants_v608() is
  'Rollback-only TEST71 proof for exact Qty/Rate/Value, Roll identity, action retry and canonical natural-identity duplicate rejection; V609.';

notify pgrst,'reload schema';
commit;
