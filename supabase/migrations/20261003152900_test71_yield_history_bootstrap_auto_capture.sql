-- TEST71: Bootstrap Yield Sheet from conservative released numeric lot history.
-- Future exact Cutting breakup/roll bindings continuously improve the same canonical Yield authority.

CREATE OR REPLACE FUNCTION public.rr_cutting_capture_yield_v1(p_cutting_lot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  l public.rr_cutting_lots_v3%rowtype;
  x record;
  n int:=0;
  v_category_code text;
begin
  select * into l
  from public.rr_cutting_lots_v3
  where id=p_cutting_lot_id;

  if not found then
    return jsonb_build_object('ok',true,'observations',0,'status','LOT_NOT_FOUND');
  end if;

  select lower(ac.category_code)
  into v_category_code
  from public.rr_art_master a
  left join public.rr_art_categories ac on ac.id=a.art_category_id
  where upper(trim(a.art_no))=upper(trim(l.art_no))
  order by coalesce(a.is_active,true) desc,a.updated_at desc nulls last
  limit 1;

  for x in
    select b.cb_colour_id,
           max(c.colour_name) colour_name,
           max(b.gsm) gsm,
           sum(b.selected_weight_kg) kg,
           coalesce((
             select sum(coalesce(br.actual_qty,br.planned_qty,0))
             from public.rr_cutting_breakup_v3 br
             where br.cutting_lot_id=l.id
               and br.colour_id=b.cb_colour_id
           ),0)::int pcs
    from public.rr_cutting_roll_lot_binding_v1 b
    join public.rr_cb_colours c on c.id=b.cb_colour_id
    where b.cutting_lot_id=l.id
      and b.status='ACTIVE'
    group by b.cb_colour_id
  loop
    if x.kg>0 and x.pcs>0 then
      insert into public.rr_cutting_yield_observation_v1(
        source_kind,cutting_lot_id,cb_id,cb_unit_id,cb_colour_id,
        lot_no,art_no,item_category,size_mix,sleeve_type,border_type,
        colour_name,gsm,fabric_weight_kg,good_cut_pcs,grams_per_piece,evidence_quality
      )
      values(
        'EXACT_ROLL_LOT',l.id,l.cb_id,l.cb_unit_id,x.cb_colour_id,
        l.lot_no,l.art_no,v_category_code,array_to_string(l.size_set,','),
        l.sleeve_type,l.border_type,x.colour_name,x.gsm,x.kg,x.pcs,
        round((x.kg*1000)/x.pcs,4),'EXACT_ROLL'
      )
      on conflict(source_kind,cutting_lot_id,cb_colour_id) do update set
        art_no=excluded.art_no,
        item_category=excluded.item_category,
        size_mix=excluded.size_mix,
        sleeve_type=excluded.sleeve_type,
        border_type=excluded.border_type,
        colour_name=excluded.colour_name,
        gsm=excluded.gsm,
        fabric_weight_kg=excluded.fabric_weight_kg,
        good_cut_pcs=excluded.good_cut_pcs,
        grams_per_piece=excluded.grams_per_piece,
        evidence_quality=excluded.evidence_quality;
      n:=n+1;
    end if;
  end loop;

  return jsonb_build_object('ok',true,'observations',n,'status','CAPTURED');
end $function$;


CREATE OR REPLACE FUNCTION public.rr_cutting_yield_bootstrap_history_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  n int:=0;
begin
  insert into public.rr_cutting_yield_observation_v1(
    source_kind,cutting_lot_id,cb_id,cb_unit_id,cb_colour_id,
    lot_no,art_no,item_category,size_mix,sleeve_type,border_type,
    fabric_name,colour_name,gsm,fabric_weight_kg,good_cut_pcs,
    grams_per_piece,evidence_quality,created_at
  )
  select
    'LEGACY_CONSOLIDATED',
    l.id,
    u.purchase_id,
    l.cb_unit_id,
    null,
    l.lot_no,
    l.art_no,
    lower(ac.category_code),
    array_to_string(l.size_set,','),
    l.sleeve_type,
    l.border_type,
    (
      select e.fabric_name
      from public.rr_cb_purchase_entries e
      where e.cb_id=u.purchase_id
        and lower(coalesce(e.entry_notes,''))='regular cloth'
      order by e.created_at
      limit 1
    ),
    'ALL COLOURS',
    null,
    l.fabric_used,
    coalesce(nullif(l.actual_pcs,0),l.planned_pcs),
    round((l.fabric_used*1000)/coalesce(nullif(l.actual_pcs,0),l.planned_pcs),4),
    'HISTORICAL_LOT_TOTAL',
    l.created_at
  from public.rr_cutting_lots_v3 l
  join public.rr_cb_units u on u.id=l.cb_unit_id
  left join lateral(
    select c.category_code
    from public.rr_art_master a
    left join public.rr_art_categories c on c.id=a.art_category_id
    where upper(trim(a.art_no))=upper(trim(l.art_no))
    order by coalesce(a.is_active,true) desc,a.updated_at desc nulls last
    limit 1
  ) ac on true
  where l.fabric_used>0
    and coalesce(nullif(l.actual_pcs,0),l.planned_pcs,0)>0
    and upper(coalesce(l.status,'')) in('RELEASED','COMPLETED','CLOSE','CLOSED')
    and l.lot_no ~ '^[0-9]+$'
    and not exists(
      select 1
      from public.rr_cutting_yield_observation_v1 o
      where o.source_kind='LEGACY_CONSOLIDATED'
        and o.cutting_lot_id=l.id
    );

  get diagnostics n=row_count;

  return jsonb_build_object('ok',true,'inserted',n,'source','NUMERIC_RELEASED_LOTS');
end $function$;


CREATE OR REPLACE FUNCTION public.rr_cutting_yield_refresh_exact_v1(p_cutting_lot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_cutting_lot_id is null then
    return jsonb_build_object('ok',true,'observations',0);
  end if;

  delete from public.rr_cutting_yield_observation_v1
  where source_kind='EXACT_ROLL_LOT'
    and cutting_lot_id=p_cutting_lot_id;

  return public.rr_cutting_capture_yield_v1(p_cutting_lot_id);
end $function$;


CREATE OR REPLACE FUNCTION public.rr_cutting_yield_source_refresh_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  old_lot uuid;
  new_lot uuid;
begin
  if tg_op<>'INSERT' then old_lot:=old.cutting_lot_id; end if;
  if tg_op<>'DELETE' then new_lot:=new.cutting_lot_id; end if;

  if old_lot is not null and old_lot is distinct from new_lot then
    perform public.rr_cutting_yield_refresh_exact_v1(old_lot);
  end if;

  if new_lot is not null then
    perform public.rr_cutting_yield_refresh_exact_v1(new_lot);
  end if;

  return coalesce(new,old);
exception when others then
  -- Yield learning must never block Cutting execution.
  return coalesce(new,old);
end $function$;


CREATE OR REPLACE FUNCTION public.rr_cutting_yield_estimate_v1(p_art_no text, p_gsm numeric, p_fabric_weight_kg numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_avg numeric;
  v_min numeric;
  v_max numeric;
  v_n int:=0;
  v_scope text;
  v_conf text;
  v_category_code text;
begin
  if coalesce(p_fabric_weight_kg,0)<=0 then
    return jsonb_build_object('available',false,'reason','Fabric weight required');
  end if;

  select lower(c.category_code)
  into v_category_code
  from public.rr_art_master a
  left join public.rr_art_categories c on c.id=a.art_category_id
  where upper(trim(a.art_no))=upper(trim(coalesce(p_art_no,'')))
  order by coalesce(a.is_active,true) desc,a.updated_at desc nulls last
  limit 1;

  select avg(grams_per_piece),min(grams_per_piece),max(grams_per_piece),count(*)
  into v_avg,v_min,v_max,v_n
  from public.rr_cutting_yield_observation_v1
  where good_cut_pcs>0
    and fabric_weight_kg>0
    and nullif(trim(coalesce(p_art_no,'')),'') is not null
    and upper(art_no)=upper(trim(p_art_no))
    and (p_gsm is null or gsm is null or abs(gsm-p_gsm)<=10);

  v_scope:='SAME_ART';
  v_conf:=case when v_n>=8 then 'HIGH' when v_n>=2 then 'MEDIUM' else 'LOW' end;

  if coalesce(v_n,0)<2 and v_category_code is not null then
    select avg(grams_per_piece),min(grams_per_piece),max(grams_per_piece),count(*)
    into v_avg,v_min,v_max,v_n
    from public.rr_cutting_yield_observation_v1
    where good_cut_pcs>0
      and fabric_weight_kg>0
      and lower(coalesce(item_category,''))=v_category_code
      and (p_gsm is null or gsm is null or abs(gsm-p_gsm)<=10);

    if coalesce(v_n,0)>0 then
      v_scope:='SAME_CATEGORY';
      v_conf:=case when v_n>=5 then 'MEDIUM' else 'LOW' end;
    end if;
  end if;

  if coalesce(v_n,0)=0 then
    select avg(grams_per_piece),min(grams_per_piece),max(grams_per_piece),count(*)
    into v_avg,v_min,v_max,v_n
    from public.rr_cutting_yield_observation_v1
    where good_cut_pcs>0
      and fabric_weight_kg>0
      and (p_gsm is null or gsm is null or abs(gsm-p_gsm)<=10);

    v_scope:='GENERAL_HISTORY';
    v_conf:='LOW';
  end if;

  if coalesce(v_n,0)=0 or coalesce(v_avg,0)<=0 then
    return jsonb_build_object(
      'available',false,
      'reason','Yield history अभी उपलब्ध नहीं है',
      'sample_count',0
    );
  end if;

  return jsonb_build_object(
    'available',true,
    'scope',v_scope,
    'sample_count',v_n,
    'avg_grams_per_piece',round(v_avg,2),
    'historical_min_grams',round(v_min,2),
    'historical_max_grams',round(v_max,2),
    'estimated_pcs',floor((p_fabric_weight_kg*1000)/v_avg),
    'confidence',v_conf
  );
end $function$;


drop trigger if exists rr_cutting_breakup_yield_refresh_v1 on public.rr_cutting_breakup_v3;
create trigger rr_cutting_breakup_yield_refresh_v1
after insert or update or delete
on public.rr_cutting_breakup_v3
for each row execute function public.rr_cutting_yield_source_refresh_trg_v1();

drop trigger if exists rr_cutting_binding_yield_refresh_v1 on public.rr_cutting_roll_lot_binding_v1;
create trigger rr_cutting_binding_yield_refresh_v1
after insert or update or delete
on public.rr_cutting_roll_lot_binding_v1
for each row execute function public.rr_cutting_yield_source_refresh_trg_v1();

revoke all on function public.rr_cutting_yield_bootstrap_history_v1() from public,anon,authenticated;
revoke all on function public.rr_cutting_yield_refresh_exact_v1(uuid) from public,anon,authenticated;
revoke all on function public.rr_cutting_yield_source_refresh_trg_v1() from public,anon,authenticated;

select public.rr_cutting_yield_bootstrap_history_v1();
