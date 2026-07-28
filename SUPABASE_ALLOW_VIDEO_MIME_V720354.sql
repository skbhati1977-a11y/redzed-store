-- REDZED V720.35.4 — Allow common video proof MIME types in the existing redzed-media bucket.
-- Run once in Supabase SQL Editor.
-- Existing allowed MIME types stay unchanged. If the bucket already allows all MIME types (NULL), it stays unrestricted.

update storage.buckets
set allowed_mime_types = case
  when allowed_mime_types is null then null
  else (
    select array_agg(distinct mime_type order by mime_type)
    from unnest(
      allowed_mime_types
      || array['video/mp4','video/webm','video/quicktime','video/3gpp']::text[]
    ) as mime_type
  )
end
where id = 'redzed-media';
