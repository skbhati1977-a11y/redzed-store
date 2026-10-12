create table if not exists public.rr_operational_source_identity_test71 (
  source_app text not null,
  source_module text not null,
  source_id text not null,
  target_table text not null,
  target_id uuid not null,
  target_media_ids uuid[] not null default '{}',
  payload_sha256 text not null check (payload_sha256 ~ '^[a-f0-9]{64}$'),
  source_reference text not null,
  raw_values jsonb not null,
  canonical_values jsonb not null,
  status text not null default 'IMPORTED_PENDING_VERIFY'
    check (status in ('IMPORTED_PENDING_VERIFY','IMPORTED_VERIFIED')),
  created_at timestamptz not null default now(),
  primary key (source_app, source_module, source_id),
  unique (target_table, target_id)
);
