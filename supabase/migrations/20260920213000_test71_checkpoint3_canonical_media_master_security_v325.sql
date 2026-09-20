-- TEST71 Checkpoint 3: extend the existing canonical media map and harden master access.
create or replace function public.rr_real_chat_media_map_v1()
returns jsonb language sql security definer set search_path='public','pg_temp' as $$
with units as (
 select u.id cb_unit_id,u.purchase_id,u.cb_code,u.cb_base_no,a.id assignment_id,a.art_id,am.art_no
 from public.rr_cb_units u left join public.rr_cb_art_assignments a on a.cb_id=u.id
 left join public.rr_art_master am on am.id=a.art_id where auth.uid() is not null
), combined as (
 select null::text lot_no,u.cb_code cb_no,u.cb_unit_id,u.purchase_id,u.art_no,u.assignment_id,u.art_id,
        '[]'::jsonb art_image_urls,'[]'::jsonb print_image_urls from units u
 union all
 select l.lot_no,l.cb_no,coalesce(nullif(l.metadata->>'cb_unit_id','')::uuid,u.cb_unit_id),u.purchase_id,
        coalesce(nullif(l.art_no,''),u.art_no),u.assignment_id,u.art_id,
        coalesce(l.art_image_urls,'[]'::jsonb),coalesce(l.print_image_urls,'[]'::jsonb)
 from public.rr_upm_lot_registry l left join units u on upper(trim(u.cb_code))=upper(trim(l.cb_no))
)
select coalesce(jsonb_agg(jsonb_build_object(
 'lot_no',c.lot_no,'cb_no',c.cb_no,'cb_unit_id',c.cb_unit_id,'art_no',c.art_no,
 'art_images',coalesce(nullif(c.art_image_urls,'[]'::jsonb),ar.images,'[]'::jsonb),
 'print_images',coalesce(nullif(c.print_image_urls,'[]'::jsonb),pr.images,'[]'::jsonb),
 'sticker_images',coalesce(st.images,'[]'::jsonb),'metal_id_images',coalesce(mi.images,'[]'::jsonb),
 'colour_images',coalesce(ci.images,'[]'::jsonb)
)),'[]'::jsonb)
from combined c
left join lateral (
 select jsonb_agg(jsonb_build_object('url',x.url,'caption','Art '||coalesce(c.art_no,'')) order by x.sort_order,x.created_at) images
 from (
  select m.file_url url,m.sort_order,m.created_at from public.rr_media m
   where lower(m.entity_type)='art' and m.entity_id=c.art_id::text and nullif(trim(m.file_url),'') is not null
  union all
  select p.image_url,100,p.created_at from public.products p
   where upper(trim(p.art_no))=upper(trim(c.art_no)) and nullif(trim(p.image_url),'') is not null
 ) x
) ar on true
left join lateral (
 select jsonb_agg(jsonb_build_object('url',x.url,'caption','Print '||x.print_no) order by x.seq,x.created_at) images
 from (
  select distinct coalesce(nullif(m.file_url,''),nullif(pm.artwork_url,''),nullif(pm.garment_preview_url,'')) url,
         pm.print_no,ca.sequence_no seq,coalesce(m.created_at,pm.created_at) created_at
  from public.rr_cb_print_assignments ca join public.rr_print_master pm on pm.id=ca.print_id
  left join public.rr_media m on lower(m.entity_type)='printing' and m.entity_id=pm.id::text
  where ca.assignment_id=c.assignment_id
 ) x where x.url is not null
) pr on true
left join lateral (
 select jsonb_agg(jsonb_build_object('url',coalesce(nullif(m.file_url,''),sm.image_url),
        'caption','Sticker '||sm.sticker_no) order by ca.sequence_no) images
 from public.rr_cb_sticker_assignments ca join public.rr_art_sticker_instructions i on i.id=ca.sticker_instruction_id
 join public.rr_sticker_master_library_v803 sm on sm.id=i.sticker_master_id
 left join public.rr_media m on lower(m.entity_type)='sticker_master_v803' and m.entity_id=sm.id::text
 where ca.assignment_id=c.assignment_id and coalesce(nullif(trim(m.file_url),''),nullif(trim(sm.image_url),'')) is not null
) st on true
left join lateral (
 select jsonb_agg(jsonb_build_object('url',coalesce(nullif(rm.file_url,''),mm.image_url),'caption','Metal ID '||mm.metal_id_no)
 order by ca.sequence_no) images
 from public.rr_cb_metal_id_assignments_v801 ca join public.rr_art_metal_id_instructions_v801 i on i.id=ca.metal_id_instruction_id
 join public.rr_metal_id_master_library_v803 mm on mm.id=i.metal_id_master_id
 left join public.rr_media rm on lower(rm.entity_type)='metal_id_master_v803' and rm.entity_id=mm.id::text
 where ca.assignment_id=c.assignment_id and coalesce(nullif(trim(rm.file_url),''),nullif(trim(mm.image_url),'')) is not null
) mi on true
left join lateral (
 select jsonb_agg(jsonb_build_object('url',cc.image_url,'caption','Colour '||coalesce(nullif(cc.colour_name,''),'C'||cc.col_no),
        'colour_code',coalesce(nullif(upper(trim(cc.colour_name)),''),'C'||cc.col_no),'colour_name',cc.colour_name)
        order by coalesce(cc.colour_order,cc.col_no),cc.created_at) images
 from public.rr_cb_colours cc
 where cc.cb_id=c.purchase_id and nullif(trim(cc.image_url),'') is not null
) ci on true
$$;

revoke all on function public.rr_real_chat_media_map_v1() from public,anon;
grant execute on function public.rr_real_chat_media_map_v1() to authenticated;

-- Existing master mutation RPCs already enforce owner/admin internally. Remove their
-- unnecessary anonymous execute path; canonical authenticated behavior is unchanged.
revoke execute on function public.rr_accessory_master_list_v804(text,text) from anon;
revoke execute on function public.rr_upsert_sticker_master_v804(uuid,text,text,text,boolean) from anon;
revoke execute on function public.rr_upsert_metal_id_master_v804(uuid,text,text,text,boolean) from anon;

-- Art No duplicate protection must be case/whitespace insensitive, like other masters.
create unique index if not exists rr_art_master_art_no_normalized_uq
on public.rr_art_master (upper(trim(art_no)));
