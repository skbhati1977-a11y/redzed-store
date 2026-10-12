create table if not exists public.rr_operational_import_row_log_test71 (
  id bigint generated always as identity primary key,
  source_app text not null,
  source_module text not null,
  source_id text not null,
  target_table text,
  target_id uuid,
  status text not null,
  reason text,
  payload_sha256 text,
  source_reference text not null,
  raw_values jsonb not null,
  canonical_values jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.rr_operational_source_identity_test71 enable row level security;
alter table public.rr_operational_import_row_log_test71 enable row level security;
revoke all on public.rr_operational_source_identity_test71, public.rr_operational_import_row_log_test71 from public, anon, authenticated;
grant all on public.rr_operational_source_identity_test71, public.rr_operational_import_row_log_test71 to service_role;
create or replace function public.rr_import_redzed_art_batch_test71(
  p_source_app text,
  p_source_reference text,
  p_source_sha256 text,
  p_environment text,
  p_mode text,
  p_backup_reference text,
  p_records jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $function$
declare
  v_row jsonb;
  v_source_id text;
  v_art_no text;
  v_item_name text;
  v_image_url text;
  v_target_id uuid;
  v_media_id uuid;
  v_media_ids uuid[];
  v_prior public.rr_operational_source_identity_test71%rowtype;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
begin
  if p_source_app <> 'Redzed Clothing' then raise exception 'Unsupported source application.'; end if;
  if nullif(trim(p_source_reference),'') is null or p_source_sha256 !~ '^[a-f0-9]{64}$' then
    raise exception 'Source reference and SHA-256 are required.';
  end if;
  if p_environment <> 'TEST' then raise exception 'Operational legacy import is TEST-only.'; end if;
  if p_mode not in ('DRY_RUN','APPLY') then raise exception 'Unsupported import mode.'; end if;
  if p_mode='APPLY' and nullif(trim(p_backup_reference),'') is null then
    raise exception 'APPLY requires a verified target backup reference.';
  end if;
  if jsonb_typeof(p_records) <> 'array' then raise exception 'p_records must be a JSON array.'; end if;

  for v_row in select value from jsonb_array_elements(p_records)
  loop
    v_source_id := nullif(trim(v_row->>'source_id'),'');
    if v_source_id is null or jsonb_typeof(v_row->'raw') <> 'object'
       or jsonb_typeof(v_row->'canonical') <> 'object' then
      raise exception 'Every import row requires source_id, raw and canonical objects.';
    end if;
    if v_row->>'classification' <> 'READY_TO_IMPORT' then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'module',v_row->>'module','source_id',v_source_id,'status',v_row->>'classification'));
      continue;
    end if;
    if v_row->>'module' <> 'ART' then raise exception 'This first operational writer supports ART rows only.'; end if;
    if v_row->>'payload_sha256' !~ '^[a-f0-9]{64}$' then raise exception 'Invalid row payload SHA-256.'; end if;
    v_art_no := nullif(trim(v_row->'canonical'->>'art_no'),'');
    v_item_name := nullif(trim(v_row->'canonical'->>'item_name'),'');
    v_image_url := nullif(trim(v_row->'canonical'->>'source_image_url'),'');
    if v_art_no is null or v_item_name is null then
      raise exception 'ART row requires verified Art No and Item Name.';
    end if;
    if v_row->'raw'->>'ID' <> v_source_id
       or v_row->'raw'->>'art_no' <> v_art_no
       or v_row->'raw'->>'art_status' <> 'NAME_CODE_MASTER_ID_AGREES' then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'module','ART','source_id',v_source_id,'status','REVIEW_REQUIRED','reason','SOURCE_ART_ID_MAPPING_NOT_VERIFIED'));
      continue;
    end if;
    if v_image_url is null or v_image_url !~ '^https://redzedclothing\.in/uploads/[^[:space:]]+$' then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'module','ART','source_id',v_source_id,'status','BLOCKED','reason','SOURCE_IMAGE_URL_NOT_VERIFIED'));
      continue;
    end if;

    select * into v_prior from public.rr_operational_source_identity_test71
     where source_app=p_source_app and source_module='ART' and source_id=v_source_id for update;
    if found then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'module','ART','source_id',v_source_id,
        'status',case when v_prior.payload_sha256=v_row->>'payload_sha256' then 'SKIPPED_DUPLICATE' else 'REVIEW_REQUIRED' end,
        'reason',case when v_prior.payload_sha256=v_row->>'payload_sha256' then 'SOURCE_ID_ALREADY_LINKED' else 'SOURCE_ID_PAYLOAD_CHANGED' end,
        'target_id',v_prior.target_id));
      continue;
    end if;
    select id into v_target_id from public.rr_art_master_core_v402 where art_no=v_art_no limit 1;
    if found then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'module','ART','source_id',v_source_id,'status','REVIEW_REQUIRED',
        'reason','TARGET_ART_NO_CONFLICT','conflicting_target_id',v_target_id));
      continue;
    end if;
    if exists(select 1 from public.rr_media where entity_type='art' and file_url=v_image_url) then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'module','ART','source_id',v_source_id,'status','REVIEW_REQUIRED','reason','TARGET_IMAGE_URL_ALREADY_LINKED'));
      continue;
    end if;
    if p_mode='DRY_RUN' then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'module','ART','source_id',v_source_id,'status','READY_TO_IMPORT',
        'target_table','public.rr_art_master_core_v402','image_reference','external_source_url',
        'write_performed',false));
      continue;
    end if;

    insert into public.rr_art_master_core_v402 (art_no,item_name,product_name,category)
    values (v_art_no,v_item_name,v_item_name,nullif(trim(v_row->'canonical'->>'category'),''))
    returning id into v_target_id;
    insert into public.rr_media (
      entity_type,entity_id,media_category,file_url,file_name,mime_type,caption,
      source_type,is_cover,sort_order,visibility_scope,storage_path
    ) values (
      'art',v_target_id::text,'reference',v_image_url,
      split_part(v_image_url,'/',array_length(string_to_array(v_image_url,'/'),1)),
      case when lower(v_image_url) like '%.png' then 'image/png' else 'image/jpeg' end,
      'Redzed Clothing source image reference · Art '||v_art_no,
      'gallery',true,0,'factory',null
    ) returning id into v_media_id;
    v_media_ids := array[v_media_id];
    insert into public.rr_operational_source_identity_test71 (
      source_app,source_module,source_id,target_table,target_id,target_media_ids,
      payload_sha256,source_reference,raw_values,canonical_values
    ) values (
      p_source_app,'ART',v_source_id,'public.rr_art_master_core_v402',v_target_id,v_media_ids,
      v_row->>'payload_sha256',p_source_reference,v_row->'raw',v_row->'canonical'
    );
    insert into public.rr_operational_import_row_log_test71 (
      source_app,source_module,source_id,target_table,target_id,status,reason,
      payload_sha256,source_reference,raw_values,canonical_values
    ) values (
      p_source_app,'ART',v_source_id,'public.rr_art_master_core_v402',v_target_id,
      'IMPORTED_PENDING_VERIFY','INSERT_ONLY_ART_AND_EXTERNAL_IMAGE_REFERENCE',
      v_row->>'payload_sha256',p_source_reference,v_row->'raw',v_row->'canonical'
    );
    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'module','ART','source_id',v_source_id,'status','IMPORTED_PENDING_VERIFY',
      'target_id',v_target_id,'media_id',v_media_id,'target_table','public.rr_art_master_core_v402'));
  end loop;
  return jsonb_build_object('mode',p_mode,'environment',p_environment,
    'source_reference',p_source_reference,'source_sha256',p_source_sha256,'results',v_results);
end
$function$;
revoke all on function public.rr_import_redzed_art_batch_test71(text,text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.rr_import_redzed_art_batch_test71(text,text,text,text,text,text,jsonb) to service_role;
