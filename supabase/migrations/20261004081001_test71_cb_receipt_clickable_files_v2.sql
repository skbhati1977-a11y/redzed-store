-- TEST71 receipt presentation only. Existing quantities, allocations and accounts are untouched.
alter table public.rr_cb_requirement_send_log_v1
  add column if not exists share_event_id uuid,
  add column if not exists share_channel text,
  add column if not exists receipt_no text,
  add column if not exists attachment_manifest jsonb,
  add column if not exists receipt_snapshot jsonb;
create unique index if not exists rr_cb_receipt_share_event_v2_idx
  on public.rr_cb_requirement_send_log_v1(share_event_id) where share_event_id is not null;

create or replace function public.rr_cb_requirement_receipt_context_v2(
  p_cb_id uuid,p_requirement_type text,p_source_id uuid
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $fn$
declare
  d jsonb; rows_json jsonb; assets jsonb; n integer; last_rev integer;
  typ text:=upper(trim(p_requirement_type));
begin
  perform public.rr_cb_department_assert_authority_v600();
  d:=public.rr_cb_requirement_share_context_v1(p_cb_id,typ,p_source_id);
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'cb_unit_id',r.cb_unit_id,'profile_label',r.profile_label,
    'appx_pcs',r.appx_pcs,'cutting_pcs',r.cutting_pcs,'required_qty',r.required_qty,
    'revision_no',r.revision_no,'art_no',am.art_no,'category',ac.category_name,
    'sleeves',sr.sleeve_type,'sizes',sr.size_family,'cuff',sr.sleeve_finish
  ) order by r.root_set_no,r.profile_label),'[]'::jsonb)
  into rows_json
  from public.rr_cb_derived_requirement_v1 r
  left join public.rr_cb_art_assignments ca on ca.cb_id=r.cb_unit_id
  left join public.rr_art_master am on am.id=ca.art_id
  left join public.rr_art_categories ac on ac.id=am.art_category_id
  left join public.rr_cb_set_requirement_v1 sr on sr.cb_unit_id=r.cb_unit_id
  where r.cb_id=p_cb_id and r.active and r.requirement_type=typ
    and r.source_id=p_source_id and r.required_qty>0;

  with profiles as (
    select distinct ca.id assignment_id,ca.art_id,r.profile_label,r.root_set_no,
      ca.print_due,ca.print_not_applicable,ca.sticker_due,ca.sticker_not_applicable,
      ca.metal_id_due,ca.metal_id_not_applicable
    from public.rr_cb_derived_requirement_v1 r
    join public.rr_cb_art_assignments ca on ca.cb_id=r.cb_unit_id
    where r.cb_id=p_cb_id and r.active and r.requirement_type=typ
      and r.source_id=p_source_id and r.required_qty>0
  ), entities as (
    select 20 ord,'ART' kind,'art' entity_type,a.id::text entity_id,
      a.art_no code,coalesce(a.item_name,a.product_name,'') name,p.profile_label
    from profiles p join public.rr_art_master a on a.id=p.art_id
    union all
    select 30,'PRINT','printing',a.id::text,a.print_no,coalesce(a.print_name,''),p.profile_label
    from profiles p join public.rr_cb_print_assignments x on x.assignment_id=p.assignment_id
    join public.rr_print_master a on a.id=x.print_id
    where not coalesce(p.print_due,false) and not coalesce(p.print_not_applicable,false)
    union all
    select case when typ='STICKER' and a.id=p_source_id then 10 else 40 end,
      'STICKER','sticker_master_v803',a.id::text,a.sticker_no,coalesce(a.sticker_name,''),p.profile_label
    from profiles p join public.rr_cb_sticker_assignments x on x.assignment_id=p.assignment_id
    join public.rr_art_sticker_instructions i on i.id=x.sticker_instruction_id and i.is_active
    join public.rr_sticker_master_v803 a on a.id=i.sticker_master_id and a.is_active
    where not coalesce(p.sticker_due,false) and not coalesce(p.sticker_not_applicable,false)
    union all
    select case when typ='METAL_ID' and a.id=p_source_id then 10 else 50 end,
      'METAL ID','metal_id_master_v803',a.id::text,a.metal_id_no,coalesce(a.metal_id_name,''),p.profile_label
    from profiles p join public.rr_cb_metal_id_assignments_v801 x on x.assignment_id=p.assignment_id
    join public.rr_art_metal_id_instructions_v801 i on i.id=x.metal_id_instruction_id and i.is_active
    join public.rr_metal_id_master_v803 a on a.id=i.metal_id_master_id and a.is_active
    where not coalesce(p.metal_id_due,false) and not coalesce(p.metal_id_not_applicable,false)
    union all
    select 10,'MATERIAL','material_master_v805',m.id::text,m.material_no,m.material_name,''
    from public.rr_material_categories c join public.rr_material_master_v805 m on m.id=c.material_master_id
    where typ='MATERIAL' and c.id=p_source_id
  ), media_rows as (
    select e.ord,e.kind,e.code,e.name,e.profile_label,m.file_url url,
      coalesce(m.mime_type,'') mime_type,coalesce(m.sort_order,999) media_order
    from entities e join public.rr_media m on m.entity_type=e.entity_type and m.entity_id=e.entity_id
    where nullif(trim(m.file_url),'') is not null
      and (coalesce(m.mime_type,'')='' or m.mime_type like 'image/%' or m.mime_type='application/pdf')
    union all
    select e.ord,e.kind,e.code,e.name,e.profile_label,x.url,'',0
    from entities e join public.rr_print_master pm on pm.id::text=e.entity_id and e.kind='PRINT'
    cross join lateral (values(pm.artwork_url),(pm.garment_preview_url)) x(url)
    where nullif(trim(x.url),'') is not null
    union all
    select 60,'COLOUR','C'||c.col_no,coalesce(c.colour_name,''),'',c.image_url,'',c.col_no
    from public.rr_cb_colours c where c.cb_id=p_cb_id and nullif(trim(c.image_url),'') is not null
  ), merged as (
    select url,min(ord) ord,min(media_order) media_order,
      (array_agg(kind order by ord,code))[1] kind,
      string_agg(distinct code,', ' order by code) code,
      string_agg(distinct name,' / ' order by name) name,
      string_agg(distinct nullif(profile_label,''),', ' order by nullif(profile_label,'')) profile_label,
      max(mime_type) mime_type
    from media_rows where url ~ '^https://' group by url
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind',kind,'code',code,'name',name,'profile_label',profile_label,
    'label',concat_ws(' · ',kind,code,nullif(name,''),profile_label),
    'url',url,'mime_type',mime_type
  ) order by ord,media_order,code,url),'[]'::jsonb) into assets from merged;

  select count(*),max(revision_no) into n,last_rev
  from public.rr_cb_requirement_send_log_v1
  where cb_id=p_cb_id and requirement_type=typ and source_id=p_source_id;
  d:=d||jsonb_build_object('rows',rows_json,'attachments',assets,
    'receipt_no','CB'||(d->>'cb_no')||'-'||case typ when 'MATERIAL' then 'MAT' when 'STICKER' then 'STK' else 'MID' end||'-'||left(p_source_id::text,8)||'-R'||(d->>'revision_no'),
    'send_kind',case when n=0 then 'FIRST' when coalesce(last_rev,0)<(d->>'revision_no')::integer then 'REVISED' else 'RESEND' end,
    'send_count',n,'generated_at',now(),'version','RECEIPT_V2');
  -- Fingerprint only semantic data. Retry timing / send count cannot invalidate a prepared slip.
  return d||jsonb_build_object('snapshot_token',md5((d-'generated_at'-'send_kind'-'send_count')::text));
end $fn$;
revoke all on function public.rr_cb_requirement_receipt_context_v2(uuid,text,uuid) from public,anon;
grant execute on function public.rr_cb_requirement_receipt_context_v2(uuid,text,uuid) to authenticated;

create or replace function public.rr_cb_requirement_receipt_record_v2(
  p_cb_id uuid,p_requirement_type text,p_source_id uuid,p_share_event_id uuid,
  p_snapshot_token text,p_format text,p_caption text,p_files jsonb
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $fn$
declare d jsonb; n integer; old_log public.rr_cb_requirement_send_log_v1%rowtype;
begin
  perform public.rr_cb_department_assert_authority_v600();
  if p_share_event_id is null or p_format is null or p_format not in ('JPG','PDF','IMAGES') then
    raise exception 'Valid file-share receipt required.';
  end if;
  if jsonb_typeof(p_files) is distinct from 'array' or jsonb_array_length(p_files)=0
     or length(coalesce(p_caption,''))>8000 then raise exception 'Receipt attachment required.'; end if;
  if exists(select 1 from jsonb_array_elements(p_files) f
    where coalesce(f->>'type','') not in('image/jpeg','application/pdf')
       or coalesce((f->>'size')::bigint,0)<=0) then raise exception 'Valid JPG/PDF attachment required.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('CB_RECEIPT:'||p_cb_id::text||':'||p_requirement_type||':'||p_source_id::text,2));
  select * into old_log from public.rr_cb_requirement_send_log_v1 where share_event_id=p_share_event_id;
  if found then
    if old_log.cb_id<>p_cb_id or old_log.source_id<>p_source_id or old_log.requirement_type<>upper(p_requirement_type)
      then raise exception 'Share event does not match this receipt.'; end if;
    return jsonb_build_object('ok',true,'duplicate',true,'recorded',true,'receipt_no',old_log.receipt_no);
  end if;
  d:=public.rr_cb_requirement_receipt_context_v2(p_cb_id,p_requirement_type,p_source_id);
  if d->>'snapshot_token' is distinct from p_snapshot_token then
    return jsonb_build_object('ok',true,'recorded',false,'reason','REQUIREMENT_CHANGED');
  end if;
  n:=coalesce((d->>'send_count')::integer,0)+1;
  insert into public.rr_cb_requirement_send_log_v1(
    cb_id,requirement_type,source_id,revision_no,send_sequence,template_kind,message_text,
    supplier_name,share_event_id,share_channel,receipt_no,attachment_manifest,receipt_snapshot
  ) values(p_cb_id,upper(p_requirement_type),p_source_id,(d->>'revision_no')::integer,n,
    d->>'send_kind',p_caption,d->>'supplier_name',p_share_event_id,'NATIVE_FILES_'||p_format,
    d->>'receipt_no',p_files,d);
  -- Recipient is chosen in WhatsApp; never invent a phone or overwrite supplier mapping.
  update public.rr_cb_derived_requirement_v1 r
  set status=case when d->>'send_kind'='RESEND' then 'RESENT' else 'SENT' end,
    last_sent_at=now(),last_sent_revision=r.revision_no,updated_at=now()
  where r.cb_id=p_cb_id and r.requirement_type=upper(p_requirement_type)
    and r.source_id=p_source_id and r.active and r.required_qty>0;
  return jsonb_build_object('ok',true,'recorded',true,'receipt_no',d->>'receipt_no',
    'send_sequence',n,'handoff_only',true);
end $fn$;
revoke all on function public.rr_cb_requirement_receipt_record_v2(uuid,text,uuid,uuid,text,text,text,jsonb) from public,anon;
grant execute on function public.rr_cb_requirement_receipt_record_v2(uuid,text,uuid,uuid,text,text,text,jsonb) to authenticated;
