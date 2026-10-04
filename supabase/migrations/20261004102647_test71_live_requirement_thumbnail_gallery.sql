create or replace function public.rr_cb_requirement_media_projection_v1(p_cb_id uuid,p_requirement_type text,p_source_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $media$
declare v_type text:=upper(p_requirement_type);v_item_name text;v_attachments jsonb;
begin
select max(item_name) into v_item_name from public.rr_cb_derived_requirement_v1 where cb_id=p_cb_id and active and requirement_type=v_type and source_id=p_source_id;
  with req as (
    select distinct r.cb_unit_id,r.profile_label,r.root_set_no
    from public.rr_cb_derived_requirement_v1 r
    where r.cb_id=p_cb_id
      and r.active
      and r.requirement_type=v_type
      and r.source_id=p_source_id
      and r.required_qty>0
  ),
  requirement_item_rows as (
    select 10 sort_group,0 root_set_no,'' profile_label,
           'ITEM' kind,
           'ITEM · '||coalesce(mc.category_name,v_item_name) label,
           med.file_url
    from public.rr_material_categories mc
    left join public.rr_material_master_v805 mm on mm.id=mc.material_master_id
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='material_master_v805'
        and m.entity_id=mm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where v_type='MATERIAL' and mc.id=p_source_id and med.file_url is not null

    union all

    select 10,0,'','STICKER',
           'STICKER · '||coalesce(sm.sticker_no,'')||
             case when nullif(sm.sticker_name,'') is not null then ' · '||sm.sticker_name else '' end,
           coalesce(med.file_url,nullif(sm.image_url,''))
    from public.rr_sticker_master_library_v803 sm
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='sticker_master_v803'
        and m.entity_id=sm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where v_type='STICKER' and sm.id=p_source_id
      and coalesce(med.file_url,nullif(sm.image_url,'')) is not null

    union all

    select 10,0,'','METAL ID',
           'METAL ID · '||coalesce(mm.metal_id_no,'')||
             case when nullif(mm.metal_id_name,'') is not null then ' · '||mm.metal_id_name else '' end,
           coalesce(med.file_url,nullif(mm.image_url,''))
    from public.rr_metal_id_master_library_v803 mm
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='metal_id_master_v803'
        and m.entity_id=mm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where v_type='METAL_ID' and mm.id=p_source_id
      and coalesce(med.file_url,nullif(mm.image_url,'')) is not null
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
      select x.file_url
      from (
        select m.file_url,0 source_rank,coalesce(m.is_cover,false) is_cover,
               coalesce(m.sort_order,999) sort_order,m.created_at
        from public.rr_media m
        where m.entity_type='art'
          and m.entity_id=am.id::text
          and nullif(m.file_url,'') is not null
        union all
        select p.image_url,1,false,999,p.created_at
        from public.products p
        where upper(trim(p.art_no))=upper(trim(am.art_no))
          and nullif(p.image_url,'') is not null
      ) x
      order by x.source_rank,x.is_cover desc,x.sort_order,x.created_at
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
  linked_sticker_rows as (
    select 40 sort_group,q.root_set_no,coalesce(q.profile_label,'') profile_label,
           'STICKER' kind,
           coalesce(q.profile_label||' · ','')||'STICKER '||coalesce(sm.sticker_no,'')||
             case when nullif(sm.sticker_name,'') is not null then ' · '||sm.sticker_name else '' end label,
           coalesce(med.file_url,nullif(sm.image_url,'')) file_url
    from req q
    join public.rr_cb_art_assignments ca on ca.cb_id=q.cb_unit_id
    join public.rr_cb_sticker_assignments sa on sa.assignment_id=ca.id
    join public.rr_art_sticker_instructions si on si.id=sa.sticker_instruction_id and si.is_active
    join public.rr_sticker_master_library_v803 sm on sm.id=si.sticker_master_id
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='sticker_master_v803'
        and m.entity_id=sm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where coalesce(med.file_url,nullif(sm.image_url,'')) is not null
  ),
  linked_metal_rows as (
    select 50 sort_group,q.root_set_no,coalesce(q.profile_label,'') profile_label,
           'METAL ID' kind,
           coalesce(q.profile_label||' · ','')||'METAL ID '||coalesce(mm.metal_id_no,'')||
             case when nullif(mm.metal_id_name,'') is not null then ' · '||mm.metal_id_name else '' end label,
           coalesce(med.file_url,nullif(mm.image_url,'')) file_url
    from req q
    join public.rr_cb_art_assignments ca on ca.cb_id=q.cb_unit_id
    join public.rr_cb_metal_id_assignments_v801 ma on ma.assignment_id=ca.id
    join public.rr_art_metal_id_instructions_v801 mi on mi.id=ma.metal_id_instruction_id and mi.is_active
    join public.rr_metal_id_master_library_v803 mm on mm.id=mi.metal_id_master_id
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='metal_id_master_v803'
        and m.entity_id=mm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where coalesce(med.file_url,nullif(mm.image_url,'')) is not null
  ),
  colour_rows as (
    select 60 sort_group,c.col_no root_set_no,'' profile_label,
           'ITEM / COLOUR' kind,
           'ITEM / COLOUR '||c.col_no||
             case when nullif(c.colour_name,'') is not null then ' · '||c.colour_name else '' end label,
           c.image_url file_url
    from public.rr_cb_colours c
    where c.cb_id=p_cb_id and nullif(c.image_url,'') is not null
  ),
  all_rows as (
    select * from requirement_item_rows
    union all select * from art_rows
    union all select * from print_rows
    union all select * from linked_sticker_rows
    union all select * from linked_metal_rows
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


return coalesce(v_attachments,'[]'::jsonb);
end $media$;
revoke all on function public.rr_cb_requirement_media_projection_v1(uuid,text,uuid) from public,anon,authenticated;

create or replace function public.rr_cb_requirement_live_projection_v1(p_short_code text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_link public.rr_cb_requirement_live_link_v1%rowtype;
  v_result jsonb;
  v_colour jsonb;
  v_fulfilment jsonb;
  v_required numeric:=0;
  v_unit text;
  v_closed boolean:=false;
begin
  select * into v_link
  from public.rr_cb_requirement_live_link_v1 l
  where l.short_code=upper(trim(coalesce(p_short_code,'')))
    and l.is_active and l.revoked_at is null;

  if v_link.id is null then raise exception 'LIVE UPDATE link unavailable.'; end if;

  v_colour:=public.rr_cb_requirement_colour_projection_v1(
    v_link.cb_id,v_link.requirement_type,v_link.source_id
  );

  select jsonb_build_object(
    'ok',true,
    'cb_no',max(fp.cb_no),
    'requirement_type',v_link.requirement_type,
    'item_no',max(r.item_no),
    'item_name',max(r.item_name),
    'profile_labels',to_jsonb(array_agg(distinct r.profile_label order by r.profile_label)),
    'appx_pcs',coalesce((v_colour#>>'{totals,appx_pcs}')::numeric,0),
    'cutting_pcs',coalesce((v_colour#>>'{totals,actual_pcs}')::numeric,0),
    'required_qty',coalesce((v_colour#>>'{totals,effective_required_qty}')::numeric,sum(r.required_qty),0),
    'appx_required_qty',coalesce((v_colour#>>'{totals,appx_required_qty}')::numeric,0),
    'difference_qty',coalesce((v_colour#>>'{totals,difference_qty}')::numeric,0),
    'unit',max(r.unit),
    'revision_no',max(r.revision_no),
    'mode',max(r.fulfilment_method),
    'supplier_name',max(r.supplier_name),
    'short_note',coalesce(v_link.share_note,'Please confirm availability and expected delivery.'),
    'projection_mode',coalesce(v_colour->>'mode','APPX'),
    'colour_projection',coalesce(v_colour,'{}'::jsonb),
    'updated_at',greatest(max(r.updated_at),max(fp.updated_at)),
    'receipt_no','CB'||max(fp.cb_no)||'-'||case v_link.requirement_type
      when 'MATERIAL' then 'MAT' when 'STICKER' then 'STK' else 'MID' end||
      '-'||left(v_link.source_id::text,8)||'-R'||max(r.revision_no)
  ) into v_result
  from public.rr_cb_derived_requirement_v1 r
  join public.rr_fabric_purchases fp on fp.id=r.cb_id
  where r.cb_id=v_link.cb_id and r.active
    and r.requirement_type=v_link.requirement_type
    and r.source_id=v_link.source_id and r.required_qty>0;

  if v_result->>'cb_no' is null then raise exception 'Requirement is no longer available.'; end if;

  v_required:=coalesce((v_result->>'required_qty')::numeric,0);
  v_unit:=coalesce(v_result->>'unit','PCS');
  v_fulfilment:=public.rr_cb_requirement_fulfilment_projection_v1(
    v_link.cb_id,v_link.requirement_type,v_link.source_id,v_required,v_unit
  );
  v_closed:=coalesce((v_fulfilment->>'fully_received_confirmed')::boolean,false);
  v_result:=v_result||jsonb_build_object(
    'live',not v_closed,
    'closed',v_closed,
    'label',case when v_closed then 'CLOSE REQUIREMENT' else 'LIVE UPDATE' end,
    'link_state',case when v_closed then 'CLOSED' else 'LIVE_UPDATE' end,
    'fulfilment',v_fulfilment
  );

  update public.rr_cb_requirement_live_link_v1
  set last_opened_at=now(),
      last_status=case when v_closed then 'CLOSED' else 'LIVE_UPDATE' end,
      retired_at=case
        when v_closed then coalesce(retired_at,now())
        else null
      end,
      updated_at=case when last_status is distinct from
        (case when v_closed then 'CLOSED' else 'LIVE_UPDATE' end)
        then now() else updated_at end
  where id=v_link.id;

  return v_result||jsonb_build_object('attachments',public.rr_cb_requirement_media_projection_v1(v_link.cb_id,v_link.requirement_type,v_link.source_id));
end
$function$;


notify pgrst,'reload schema';