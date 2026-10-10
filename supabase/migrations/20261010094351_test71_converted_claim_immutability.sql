BEGIN;
CREATE OR REPLACE FUNCTION public.rr_payroll_alter_reserve_v800(p_source_id text, p_worker_id text, p_worker_name text, p_canonical_lot_id text, p_lot_no text, p_department_code text, p_assignment_id text, p_colour_code text, p_size_code text, p_qty numeric, p_frozen_rate numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_amount numeric := greatest(coalesce(p_qty,0),0) * greatest(coalesce(p_frozen_rate,0),0);
 v_existing public.rr_payroll_claim_reserve_v800%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended('ALTER_RESERVE|'||coalesce(p_source_id,''),0));
  select * into v_existing from public.rr_payroll_claim_reserve_v800
   where reserve_type='ALTER' and source_id=p_source_id for update;
  if found then
    if v_existing.worker_id is distinct from p_worker_id
       or v_existing.canonical_lot_id is distinct from p_canonical_lot_id
       or v_existing.department_code is distinct from upper(p_department_code) then
      raise exception 'Alter reserve source identity cannot change.';
    end if;
    if v_existing.status='CONVERTED_TO_FINAL_DEBIT' then
      if v_existing.qty is distinct from greatest(coalesce(p_qty,0),0)
         or v_existing.frozen_rate is distinct from greatest(coalesce(p_frozen_rate,0),0) then
        raise exception 'Finalized Alter claim is immutable; approved correction required.';
      end if;
      return jsonb_build_object('ok',true,'reserve_type','ALTER','reserve_amount',v_existing.reserve_amount,'already_finalized',true);
    end if;
  end if;
  insert into public.rr_payroll_claim_reserve_v800(
    reserve_code,worker_id,worker_name,reserve_type,source_id,canonical_lot_id,
    lot_no,department_code,assignment_id,colour_code,size_code,qty,frozen_rate,
    reserve_amount,status
  )
  values(
    public.rr_v800_code('RSV'),p_worker_id,p_worker_name,'ALTER',p_source_id,p_canonical_lot_id,
    p_lot_no,upper(p_department_code),p_assignment_id,upper(p_colour_code),upper(p_size_code),
    greatest(coalesce(p_qty,0),0),greatest(coalesce(p_frozen_rate,0),0),v_amount,'HELD'
  )
  on conflict (reserve_type,source_id)
  do update set
    qty=excluded.qty,frozen_rate=excluded.frozen_rate,reserve_amount=excluded.reserve_amount,
    status=case when public.rr_payroll_claim_reserve_v800.status='CONVERTED_TO_FINAL_DEBIT'
                then public.rr_payroll_claim_reserve_v800.status else 'HELD' end;

  return jsonb_build_object('ok',true,'reserve_type','ALTER','reserve_amount',v_amount);
end;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rr_payroll_alter_reserve_v800(text,text,text,text,text,text,text,text,text,numeric,numeric) FROM PUBLIC,anon,authenticated;
COMMIT;

