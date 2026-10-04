-- TEST71: CB requirement WhatsApp manual contact share with JPEG/PDF and named thumbnails.
-- No mapped phone is required. Share context exposes item/profile media for native Web Share.

create or replace function public.rr_cb_requirement_share_context_v1(
  p_cb_id uuid,
  p_requirement_type text,
  p_source_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_type text:=upper(trim(coalesce(p_requirement_type,'')));
  v_cb_no text;
  v_item_no text;
  v_item_name text;
  v_unit text;
  v_fulfil text;
  v_appx numeric:=0;
  v_cutting numeric:=0;
  v_required numeric:=0;
  v_supplier_name text;
  v_revision integer:=1;
  v_profiles text[];
  v_attachments jsonb:='[]'::jsonb;
begin
  perform public.rr_cb_department_assert_authority_v600();

  if v_type not in('MATERIAL','STICKER','METAL_ID') then
    raise exception 'Requirement type invalid.';
  end if;

  select cb_no into v_cb_no
  from public.rr_fabric_purchases
  where id=p_cb_id;

  if v_cb_no is null then raise exception 'CB not found.'; end if;

  select max(r.item_no),max(r.item_name),max(r.unit),max(r.fulfilment_method),
         sum(coalesce(r.appx_pcs,case when r.basis='YIELD' then r.basis_pcs else 0 end)),
         sum(coalesce(r.cutting_pcs,case when r.basis='CUTTING_ACTUAL' then r.basis_pcs else 0 end)),
         sum(r.required_qty),max(r.supplier_name),max(r.revision_no),
         array_agg(distinct r.profile_label order by r.profile_label)
  into v_item_no,v_item_name,v_unit,v_fulfil,v_appx,v_cutting,v_required,
       v_supplier_name,v_revision,v_profiles
  from public.rr_cb_derived_requirement_v1 r
  where r.cb_id=p_cb_id
    and r.active
    and r.requirement_type=v_type
    and r.source_id=p_source_id
    and r.required_qty>0;

  if v_item_name is null then raise exception 'Active requirement not found.'; end if;

  with req as (
    select distinct r.cb_unit_id,r.profile_label,r.root_set_no
    from public.rr_cb_derived_requirement_v1 r
    where r.cb_id=p_cb_id
      and r.active
      and r.requirement_type=v_type
      and r.source_id=p_source_id
      and r.required_qty>0
  ),
  art_rows as (
    select 20 sort_group,q.root_set_no,coalesce(q.profile_label,'') profile_label,
           'ART' kind,
           coalesce(q.profile_label||' · ','')||'ART '||coalesce(am.art_no,'')||
             case when nullif(am.item_name,'') is not null then ' · '||am.item_name else '' end label,
           med.file_url
    from req q
    join public.rr_cb_art_assignments ca on ca.cb_id=q.cb_unit_id
    join public.rr_art_master am on am.id=ca.art_id
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='art'
        and m.entity_id=am.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where med.file_url is not null
  ),
  print_rows as (
    select 30 sort_group,q.root_set_no,coalesce(q.profile_label,'') profile_label,
           'PRINT' kind,
           coalesce(q.profile_label||' · ','')||'PRINT '||coalesce(pm.print_no,'')||
             case when nullif(pm.print_name,'') is not null then ' · '||pm.print_name else '' end label,
           coalesce(nullif(pm.garment_preview_url,''),nullif(pm.artwork_url,''),med.file_url) file_url
    from req q
    join public.rr_cb_art_assignments ca on ca.cb_id=q.cb_unit_id
    join public.rr_cb_print_assignments pa on pa.assignment_id=ca.id
    join public.rr_print_master pm on pm.id=pa.print_id
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='printing'
        and m.entity_id=pm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where coalesce(nullif(pm.garment_preview_url,''),nullif(pm.artwork_url,''),med.file_url) is not null
  ),
  item_rows as (
    select 10 sort_group,0 root_set_no,'' profile_label,
           'STICKER' kind,
           'STICKER '||coalesce(sm.sticker_no,'')||
             case when nullif(sm.sticker_name,'') is not null then ' · '||sm.sticker_name else '' end label,
           med.file_url
    from public.rr_sticker_master_v803 sm
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='sticker_master_v803'
        and m.entity_id=sm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where v_type='STICKER' and sm.id=p_source_id and med.file_url is not null

    union all

    select 10,0,'','METAL ID',
           'METAL ID '||coalesce(mm.metal_id_no,'')||
             case when nullif(mm.metal_id_name,'') is not null then ' · '||mm.metal_id_name else '' end,
           med.file_url
    from public.rr_metal_id_master_v803 mm
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='metal_id_master_v803'
        and m.entity_id=mm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where v_type='METAL_ID' and mm.id=p_source_id and med.file_url is not null
  ),
  colour_rows as (
    select 40 sort_group,c.col_no root_set_no,'' profile_label,
           'COLOUR' kind,
           'COLOUR '||c.col_no||case when nullif(c.colour_name,'') is not null then ' · '||c.colour_name else '' end label,
           c.image_url file_url
    from public.rr_cb_colours c
    where c.cb_id=p_cb_id and nullif(c.image_url,'') is not null
  ),
  all_rows as (
    select * from item_rows
    union all select * from art_rows
    union all select * from print_rows
    union all select * from colour_rows
  ),
  dedup as (
    select distinct on (file_url)
           sort_group,root_set_no,profile_label,kind,label,file_url
    from all_rows
    where nullif(file_url,'') is not null
    order by file_url,sort_group,root_set_no,label
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'kind',kind,
        'label',label,
        'profile_label',nullif(profile_label,''),
        'url',file_url
      )
      order by sort_group,root_set_no,label
    ),
    '[]'::jsonb
  )
  into v_attachments
  from dedup;

  return jsonb_build_object(
    'ok',true,
    'cb_id',p_cb_id,
    'cb_no',v_cb_no,
    'requirement_type',v_type,
    'source_id',p_source_id,
    'item_no',v_item_no,
    'item_name',v_item_name,
    'unit',v_unit,
    'fulfilment_method',v_fulfil,
    'appx_pcs',coalesce(v_appx,0),
    'cutting_pcs',coalesce(v_cutting,0),
    'required_qty',coalesce(v_required,0),
    'supplier_name',v_supplier_name,
    'revision_no',v_revision,
    'profile_labels',to_jsonb(coalesce(v_profiles,'{}'::text[])),
    'attachments',coalesce(v_attachments,'[]'::jsonb)
  );
end
$function$;

grant execute on function public.rr_cb_requirement_share_context_v1(uuid,text,uuid) to authenticated;

create or replace function public.rr_cb_requirement_whatsapp_send_v1(
  p_cb_id uuid,
  p_requirement_type text,
  p_source_id uuid,
  p_supplier_ledger_id uuid default null,
  p_supplier_name text default null,
  p_supplier_mobile text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_type text:=upper(trim(coalesce(p_requirement_type,'')));
  v_cb_no text;
  v_item_no text;
  v_item_name text;
  v_unit text;
  v_fulfil text;
  v_supplier_ledger uuid;
  v_supplier_name text;
  v_supplier_mobile text;
  v_revision integer:=1;
  v_total_qty numeric:=0;
  v_appx_pcs numeric:=0;
  v_cutting_pcs numeric:=0;
  v_basis text:='YIELD';
  v_lines text:='';
  v_send_count integer:=0;
  v_last_sent_revision integer;
  v_template_kind text;
  v_header text;
  v_message text;
  v_sequence integer;
  x record;
begin
  perform public.rr_cb_department_assert_authority_v600();

  if v_type not in('MATERIAL','STICKER','METAL_ID') then
    raise exception 'Requirement type invalid.';
  end if;

  select cb_no into v_cb_no
  from public.rr_fabric_purchases
  where id=p_cb_id;

  if v_cb_no is null then raise exception 'CB not found.'; end if;

  select
    max(r.item_no),max(r.item_name),max(r.unit),max(r.fulfilment_method),
    max(r.revision_no),sum(r.required_qty),
    sum(coalesce(r.appx_pcs,case when r.basis='YIELD' then r.basis_pcs else 0 end)),
    sum(coalesce(r.cutting_pcs,case when r.basis='CUTTING_ACTUAL' then r.basis_pcs else 0 end)),
    case when bool_or(r.basis='CUTTING_ACTUAL') then 'CUTTING_ACTUAL' else 'YIELD' end,
    min(r.supplier_ledger_id::text)::uuid,max(r.supplier_name),max(r.supplier_mobile)
  into
    v_item_no,v_item_name,v_unit,v_fulfil,v_revision,v_total_qty,
    v_appx_pcs,v_cutting_pcs,v_basis,
    v_supplier_ledger,v_supplier_name,v_supplier_mobile
  from public.rr_cb_derived_requirement_v1 r
  where r.cb_id=p_cb_id
    and r.active
    and r.requirement_type=v_type
    and r.source_id=p_source_id
    and r.required_qty>0;

  if v_item_name is null then raise exception 'Active requirement not found.'; end if;

  v_supplier_ledger:=coalesce(p_supplier_ledger_id,v_supplier_ledger);
  v_supplier_name:=coalesce(nullif(trim(coalesce(p_supplier_name,'')),''),v_supplier_name);
  v_supplier_mobile:=coalesce(
    nullif(regexp_replace(coalesce(p_supplier_mobile,''),'[^0-9]','','g'),''),
    nullif(regexp_replace(coalesce(v_supplier_mobile,''),'[^0-9]','','g'),'')
  );

  if v_supplier_ledger is not null then
    select coalesce(l.ledger_name,v_supplier_name),
           coalesce(nullif(regexp_replace(l.mobile,'[^0-9]','','g'),''),v_supplier_mobile)
    into v_supplier_name,v_supplier_mobile
    from public.rr_ledgers_v805 l
    where l.id=v_supplier_ledger;
  end if;

  select count(*),max(l.revision_no)
  into v_send_count,v_last_sent_revision
  from public.rr_cb_requirement_send_log_v1 l
  where l.cb_id=p_cb_id
    and l.requirement_type=v_type
    and l.source_id=p_source_id;

  if v_send_count=0 then
    v_template_kind:='FIRST';
    v_header:=case when v_fulfil='MAKING'
      then 'REDZED MAKING REQUIREMENT'
      else 'REDZED PURCHASE ORDER / REQUIREMENT' end;
  elsif coalesce(v_last_sent_revision,0)<v_revision then
    v_template_kind:='REVISED';
    v_header:=case when v_fulfil='MAKING'
      then 'REVISED MAKING REQUIREMENT'
      else 'REVISED PURCHASE ORDER / REQUIREMENT' end;
  else
    v_template_kind:='RESEND';
    v_header:=case when v_fulfil='MAKING'
      then 'REMINDER · REQUIREMENT STILL PENDING · RESENDING MAKING REQUIREMENT'
      else 'REMINDER · REQUIREMENT STILL PENDING · RESENDING PURCHASE ORDER' end;
  end if;

  v_sequence:=v_send_count+1;

  for x in
    select profile_label,
           coalesce(appx_pcs,case when basis='YIELD' then basis_pcs else 0 end) appx_pcs,
           coalesce(cutting_pcs,case when basis='CUTTING_ACTUAL' then basis_pcs else 0 end) cutting_pcs,
           required_qty,revision_no
    from public.rr_cb_derived_requirement_v1
    where cb_id=p_cb_id
      and active
      and requirement_type=v_type
      and source_id=p_source_id
      and required_qty>0
    order by root_set_no,profile_label
  loop
    v_lines:=v_lines||E'\n• '||x.profile_label||
      ' · Appx '||trim(to_char(coalesce(x.appx_pcs,0),'FM999999990.###'))||' pcs'||
      ' · Cutting '||case when coalesce(x.cutting_pcs,0)>0
          then trim(to_char(x.cutting_pcs,'FM999999990.###')) else '—' end||' pcs'||
      ' · Required '||trim(to_char(x.required_qty,'FM999999990.###'))||' '||v_unit;
  end loop;

  v_message:=
    v_header||
    E'\nCB: '||v_cb_no||
    E'\nItem: '||coalesce(v_item_no||' · ','')||v_item_name||
    E'\nMode: '||coalesce(v_fulfil,'PURCHASE')||
    E'\nAppx PCS: '||trim(to_char(coalesce(v_appx_pcs,0),'FM999999990.###'))||
    E'\nCutting PCS: '||case when coalesce(v_cutting_pcs,0)>0
      then trim(to_char(v_cutting_pcs,'FM999999990.###')) else '—' end||
    E'\nTotal Required: '||trim(to_char(v_total_qty,'FM999999990.###'))||' '||v_unit||
    case when v_supplier_name is not null then E'\nMapped Supplier: '||v_supplier_name else '' end||
    E'\nDetails:'||v_lines||
    E'\nRevision: '||v_revision||
    case when v_template_kind='RESEND' then E'\nResend No: '||v_sequence else '' end||
    E'\nPlease confirm availability / making status.';

  insert into public.rr_cb_requirement_send_log_v1(
    cb_id,requirement_type,source_id,supplier_ledger_id,supplier_name,supplier_mobile,
    revision_no,send_sequence,template_kind,message_text
  )
  values(
    p_cb_id,v_type,p_source_id,v_supplier_ledger,v_supplier_name,v_supplier_mobile,
    v_revision,v_sequence,v_template_kind,v_message
  );

  update public.rr_cb_derived_requirement_v1 r
  set supplier_ledger_id=coalesce(r.supplier_ledger_id,v_supplier_ledger),
      supplier_name=coalesce(r.supplier_name,v_supplier_name),
      supplier_mobile=coalesce(r.supplier_mobile,v_supplier_mobile),
      status=case when v_template_kind='RESEND' then 'RESENT' else 'SENT' end,
      last_sent_at=now(),
      last_sent_revision=v_revision,
      updated_at=now()
  where r.cb_id=p_cb_id
    and r.active
    and r.requirement_type=v_type
    and r.source_id=p_source_id;

  return jsonb_build_object(
    'ok',true,
    'cb_id',p_cb_id,
    'cb_no',v_cb_no,
    'requirement_type',v_type,
    'source_id',p_source_id,
    'supplier_ledger_id',v_supplier_ledger,
    'supplier_name',v_supplier_name,
    'supplier_mobile',v_supplier_mobile,
    'revision_no',v_revision,
    'send_sequence',v_sequence,
    'template_kind',v_template_kind,
    'message',v_message
  );
end
$function$;
