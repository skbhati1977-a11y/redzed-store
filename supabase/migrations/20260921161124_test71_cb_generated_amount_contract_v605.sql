-- TEST71 CB Department V605: rr_cb_purchase_entries.amount is GENERATED ALWAYS.
-- Keep that canonical calculation and remove explicit amount writes from V600.

do $do$
declare
  v_def text;
  v_next text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='rr_cb_department_save_v600'
    and pg_get_function_identity_arguments(p.oid)='p_cb_id uuid, p_action_id uuid, p_confirm boolean, p_payload jsonb';
  if v_def is null then raise exception 'V600 CB save RPC unavailable'; end if;

  v_next:=replace(v_def,
    'allocation_scope,quantity,rate,amount,entry_notes,requirement_state,unit,cutting_blocking,client_key',
    'allocation_scope,quantity,rate,entry_notes,requirement_state,unit,cutting_blocking,client_key');
  if v_next=v_def then raise exception 'Regular Cloth generated amount column patch did not match'; end if;
  v_def:=v_next;

  v_next:=replace(v_def,
    $$'all',reg_qty,reg_rate,reg_amount,
      'Regular Cloth','CONFIRMED'$$,
    $$'all',reg_qty,reg_rate,
      'Regular Cloth','CONFIRMED'$$);
  if v_next=v_def then raise exception 'Regular Cloth generated amount value patch did not match'; end if;
  v_def:=v_next;

  v_next:=replace(v_def,'quantity=reg_qty,rate=reg_rate,amount=reg_amount,','quantity=reg_qty,rate=reg_rate,');
  if v_next=v_def then raise exception 'Regular Cloth generated amount update patch did not match'; end if;
  v_def:=v_next;

  v_next:=replace(v_def,
    'quantity,rate,amount,entry_notes,requirement_state,unit,cutting_blocking,client_key',
    'quantity,rate,entry_notes,requirement_state,unit,cutting_blocking,client_key');
  if v_next=v_def then raise exception 'Material generated amount column patch did not match'; end if;
  v_def:=v_next;

  v_next:=replace(v_def,
    $$nullif(entry_row->>'qty','')::numeric,nullif(entry_row->>'rate','')::numeric,nullif(entry_row->>'amount','')::numeric,
        'CB Material'$$,
    $$nullif(entry_row->>'qty','')::numeric,nullif(entry_row->>'rate','')::numeric,
        'CB Material'$$);
  if v_next=v_def then raise exception 'Material generated amount value patch did not match'; end if;
  v_def:=v_next;

  v_next:=replace(v_def,
    $$amount=nullif(entry_row->>'amount','')::numeric,requirement_state=req_state$$,
    $$requirement_state=req_state$$);
  if v_next=v_def then raise exception 'Material generated amount update patch did not match'; end if;
  v_def:=v_next;

  execute v_def;
end $do$;

comment on function public.rr_cb_department_save_v600(uuid,uuid,boolean,jsonb) is
  'Canonical same-CB Draft/Confirm/late-DUE mutation; purchase amount remains database-generated from Qty × Rate.';
