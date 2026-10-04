-- TEST71-only receipt endpoint. Existing RPCs, table grants and business rows remain unchanged.
create schema if not exists test71_private;
revoke all on schema test71_private from public;
grant usage on schema test71_private to authenticated;

create or replace function test71_private.cb_requirement_receipt_context_v1(
 p_cb_id uuid, p_requirement_type text, p_source_id uuid
) returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_base jsonb; v_images jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 perform public.rr_cb_department_assert_authority_v600();
 v_base:=public.rr_cb_requirement_share_context_v1(p_cb_id,p_requirement_type,p_source_id);
 with req as (
  select distinct r.cb_unit_id,r.profile_label
  from public.rr_cb_derived_requirement_v1 r
  where r.cb_id=p_cb_id and r.active and r.required_qty>0
    and r.requirement_type=upper(trim(p_requirement_type)) and r.source_id=p_source_id
 ), assigned as (
  select a.id,q.profile_label from req q
  join public.rr_cb_art_assignments a on a.cb_id=q.cb_unit_id
 ), candidates as (
  select x.value as image,x.ordinality::bigint*10 as rank
  from jsonb_array_elements(coalesce(v_base->'attachments','[]'::jsonb)) with ordinality x(value,ordinality)
  union all
  select jsonb_build_object('kind','ITEM','label',concat_ws(' · ',v_base->>'item_no',v_base->>'item_name'),'url',m.file_url),1::bigint
  from public.rr_material_categories c
  join lateral (
   select file_url from public.rr_media m
   where m.entity_type='material_master_v805' and m.entity_id=c.material_master_id::text
     and m.media_category='reference' and nullif(m.file_url,'') is not null
   order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at limit 1
  ) m on true
  where upper(trim(p_requirement_type))='MATERIAL' and c.id=p_source_id
  union all
  select jsonb_build_object('kind','STICKER','profile_label',a.profile_label,
   'label',concat_ws(' · ',a.profile_label,'STICKER '||sm.sticker_no,sm.sticker_name),'url',m.file_url),1001::bigint
  from assigned a
  join public.rr_cb_sticker_assignments s on s.assignment_id=a.id
  join public.rr_art_sticker_instructions i on i.id=s.sticker_instruction_id
  join public.rr_sticker_master_v803 sm on sm.id=i.sticker_master_id
  join lateral (
   select file_url from public.rr_media m
   where m.entity_type='sticker_master_v803' and m.entity_id=sm.id::text and nullif(m.file_url,'') is not null
   order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at limit 1
  ) m on true
  union all
  select jsonb_build_object('kind','METAL ID','profile_label',a.profile_label,
   'label',concat_ws(' · ',a.profile_label,'METAL ID '||mm.metal_id_no,mm.metal_id_name),'url',m.file_url),1002::bigint
  from assigned a
  join public.rr_cb_metal_id_assignments_v801 s on s.assignment_id=a.id
  join public.rr_art_metal_id_instructions_v801 i on i.id=s.metal_id_instruction_id
  join public.rr_metal_id_master_v803 mm on mm.id=i.metal_id_master_id
  join lateral (
   select file_url from public.rr_media m
   where m.entity_type='metal_id_master_v803' and m.entity_id=mm.id::text and nullif(m.file_url,'') is not null
   order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at limit 1
  ) m on true
 ), dedup as (
  select distinct on (image->>'url') image,rank from candidates
  where nullif(image->>'url','') is not null
  order by image->>'url',rank,image->>'label'
 ) select coalesce(jsonb_agg(image order by rank,image->>'label'),'[]'::jsonb) into v_images from dedup;
 return v_base||jsonb_build_object('attachments',v_images,'receipt_context_version','TEST71-1');
end
$function$;
revoke all on function test71_private.cb_requirement_receipt_context_v1(uuid,text,uuid) from public,anon;
grant execute on function test71_private.cb_requirement_receipt_context_v1(uuid,text,uuid) to authenticated;

create or replace function public.rr_cb_requirement_receipt_context_test71(
 p_cb_id uuid,p_requirement_type text,p_source_id uuid
) returns jsonb language sql stable security invoker set search_path = ''
as $function$
 select test71_private.cb_requirement_receipt_context_v1(p_cb_id,p_requirement_type,p_source_id)
$function$;
revoke all on function public.rr_cb_requirement_receipt_context_test71(uuid,text,uuid) from public,anon;
grant execute on function public.rr_cb_requirement_receipt_context_test71(uuid,text,uuid) to authenticated;
notify pgrst,'reload schema';
