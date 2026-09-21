-- TEST71 V606: one canonical Material Unit Master for Material Master, CB,
-- consumption and costing consumers. Existing material/unit values are kept;
-- only future selectable values resolve through this master.
begin;

create extension if not exists pg_trgm;

create table if not exists public.rr_unit_master_v606(
  id uuid primary key default gen_random_uuid(),
  unit_code text not null,
  unit_name text not null,
  normalized_name text not null,
  aliases text[] not null default '{}'::text[],
  display_order integer not null default 100,
  is_active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rr_unit_master_v606_code_chk check(unit_code=upper(unit_code) and unit_code~'^[A-Z][A-Z0-9_]{0,31}$')
);
create unique index if not exists rr_unit_master_v606_code_uq on public.rr_unit_master_v606(lower(unit_code));
create unique index if not exists rr_unit_master_v606_name_uq on public.rr_unit_master_v606(normalized_name);
alter table public.rr_unit_master_v606 enable row level security;
revoke all on public.rr_unit_master_v606 from public,anon,authenticated;
grant all on public.rr_unit_master_v606 to service_role;

insert into public.rr_unit_master_v606(unit_code,unit_name,normalized_name,aliases,display_order)
values
 ('PCS','Pieces','pieces',array['PC','PIECE','PIECES'],10),
 ('KG','Kilogram','kilogram',array['KGS','KILOGRAM','KILOGRAMS'],20),
 ('MTR','Meter','meter',array['METER','METERS','METRE','METRES'],30),
 ('ROLL','Roll','roll',array['ROLLS'],40),
 ('BOX','Box','box',array['BOXES'],50),
 ('PACKET','Packet','packet',array['PACKETS'],60),
 ('PKT','Pkt','pkt',array['PKTS'],61),
 ('GADDI','Gaddi','gaddi',array['GADDIS'],70),
 ('SET','Set','set',array['SETS'],80),
 ('CONE','Cone','cone',array['CONES'],90)
on conflict do nothing;

create or replace function public.rr_unit_normalize_v606(p_value text)
returns text language sql immutable parallel safe set search_path='public' as $function$
  select lower(regexp_replace(trim(coalesce(p_value,'')),'[^a-zA-Z0-9]+','','g'))
$function$;

create or replace function public.rr_unit_master_assert_authority_v606()
returns jsonb language plpgsql stable security definer set search_path='public' as $function$
declare ident jsonb:=public.rr_upm_effective_identity_v200(); r text;
begin
  perform public.rr_assert_active_user_v1();
  r:=upper(coalesce(ident->>'role_code',ident->>'resolved_role',''));
  if r not in('OWNER','SUPER_ADMIN') then
    raise exception 'Super Admin Unit Master authority required.' using errcode='42501';
  end if;
  return ident;
end $function$;
revoke all on function public.rr_unit_master_assert_authority_v606() from public,anon,authenticated;
grant execute on function public.rr_unit_master_assert_authority_v606() to service_role;

create or replace function public.rr_unit_master_list_v606()
returns jsonb language plpgsql stable security definer set search_path='public' as $function$
begin
  perform public.rr_assert_active_user_v1();
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',u.id,'unit_code',u.unit_code,'unit_name',u.unit_name,'aliases',u.aliases
  ) order by u.display_order,u.unit_code) from public.rr_unit_master_v606 u where u.is_active),'[]'::jsonb);
end $function$;
revoke all on function public.rr_unit_master_list_v606() from public,anon;
grant execute on function public.rr_unit_master_list_v606() to authenticated,service_role;

create or replace function public.rr_unit_resolve_code_v606(p_value text)
returns text language plpgsql stable security definer set search_path='public' as $function$
declare v text:=public.rr_unit_normalize_v606(p_value); c text;
begin
  if v='' then return null; end if;
  select u.unit_code into c
  from public.rr_unit_master_v606 u
  where u.is_active and (
    public.rr_unit_normalize_v606(u.unit_code)=v
    or u.normalized_name=v
    or exists(select 1 from unnest(u.aliases)a where public.rr_unit_normalize_v606(a)=v)
  )
  order by (public.rr_unit_normalize_v606(u.unit_code)=v) desc,u.display_order,u.unit_code
  limit 1;
  return c;
end $function$;
revoke all on function public.rr_unit_resolve_code_v606(text) from public,anon;
grant execute on function public.rr_unit_resolve_code_v606(text) to authenticated,service_role;

create or replace function public.rr_unit_require_code_v606(p_value text)
returns text language plpgsql stable security definer set search_path='public' as $function$
declare c text:=public.rr_unit_resolve_code_v606(p_value);
begin
  if c is null then raise exception 'Select an active canonical Unit from Unit Master.'; end if;
  return c;
end $function$;
revoke all on function public.rr_unit_require_code_v606(text) from public,anon;
grant execute on function public.rr_unit_require_code_v606(text) to authenticated,service_role;

create or replace function public.rr_unit_master_create_v606(p_unit_name text,p_unit_code text)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare
  ident jsonb:=public.rr_unit_master_assert_authority_v606();
  n text:=nullif(trim(p_unit_name),'');
  c text:=upper(regexp_replace(trim(coalesce(p_unit_code,'')),'[^A-Za-z0-9]+','_','g'));
  norm text:=public.rr_unit_normalize_v606(p_unit_name);
  synonym text;
  found_row public.rr_unit_master_v606%rowtype;
begin
  if n is null then raise exception 'Unit Name required.'; end if;
  c:=trim(both '_' from c);
  if c='' then raise exception 'Unit Code required.'; end if;
  if c!~'^[A-Z][A-Z0-9_]{0,31}$' then raise exception 'Unit Code must start with A-Z and use only A-Z, 0-9 or underscore.'; end if;
  if norm='' then raise exception 'Unit Name required.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('RR_UNIT:'||least(c,norm),0));

  synonym:=case
    when norm in('pc','pcs','piece','pieces') or public.rr_unit_normalize_v606(c) in('pc','pcs','piece','pieces') then 'PCS'
    when norm in('mtr','meter','meters','metre','metres') or public.rr_unit_normalize_v606(c) in('mtr','meter','meters','metre','metres') then 'MTR'
    when norm in('kg','kgs','kilogram','kilograms') or public.rr_unit_normalize_v606(c) in('kg','kgs','kilogram','kilograms') then 'KG'
    else null end;

  select * into found_row from public.rr_unit_master_v606 u
  where u.is_active and (
    lower(u.unit_code)=lower(c) or u.normalized_name=norm
    or public.rr_unit_normalize_v606(u.unit_name)=public.rr_unit_normalize_v606(c)
    or exists(select 1 from unnest(u.aliases)a where public.rr_unit_normalize_v606(a) in(norm,public.rr_unit_normalize_v606(c)))
    or (synonym is not null and u.unit_code=synonym)
    or similarity(u.normalized_name,norm)>=0.78
  ) order by (lower(u.unit_code)=lower(c)) desc,(u.normalized_name=norm) desc,u.display_order limit 1;
  if found then
    return jsonb_build_object('ok',true,'created',false,'existing_match',true,'message','Existing canonical Unit selected.','unit',to_jsonb(found_row));
  end if;

  insert into public.rr_unit_master_v606(unit_code,unit_name,normalized_name,created_by)
  values(c,n,norm,auth.uid()) returning * into found_row;
  return jsonb_build_object('ok',true,'created',true,'existing_match',false,'message','New Unit saved.','unit',to_jsonb(found_row));
exception when unique_violation then
  select * into found_row from public.rr_unit_master_v606 u where lower(u.unit_code)=lower(c) or u.normalized_name=norm limit 1;
  return jsonb_build_object('ok',true,'created',false,'existing_match',true,'message','Existing canonical Unit selected.','unit',to_jsonb(found_row));
end $function$;
revoke all on function public.rr_unit_master_create_v606(text,text) from public,anon;
grant execute on function public.rr_unit_master_create_v606(text,text) to authenticated,service_role;

-- CB material options remain the existing category rows, now explicitly linked
-- to the canonical Material Master rather than becoming another material engine.
alter table public.rr_material_categories add column if not exists material_master_id uuid references public.rr_material_master_v805(id) on delete restrict;
create unique index if not exists rr_material_categories_material_master_uq
  on public.rr_material_categories(material_master_id) where material_master_id is not null;

create or replace function public.rr_sync_material_category_unit_v606()
returns trigger language plpgsql security definer set search_path='public' as $function$
declare t text; code text;
begin
  select type_code into t from public.rr_material_types_v805 where id=new.material_type_id;
  if t in('REGULAR_CLOTH','MATCHING_CLOTH','STICKER','METAL_ID') then return new; end if;
  code:='material-'||replace(new.id::text,'-','');
  insert into public.rr_material_categories(category_code,category_name,costing_mode,is_active,sort_order,unit,material_master_id)
  values(left(code,48),new.material_name,'division',new.is_active,95,public.rr_unit_require_code_v606(new.purchase_unit),new.id)
  on conflict(material_master_id) where material_master_id is not null do update set
    category_name=excluded.category_name,unit=excluded.unit,is_active=excluded.is_active,updated_at=now();
  return new;
end $function$;
drop trigger if exists rr_material_category_unit_sync_v606 on public.rr_material_master_v805;
create trigger rr_material_category_unit_sync_v606 after insert or update of material_name,purchase_unit,is_active
on public.rr_material_master_v805 for each row execute function public.rr_sync_material_category_unit_v606();

create or replace function public.rr_validate_canonical_unit_v606()
returns trigger language plpgsql set search_path='public' as $function$
begin
  if tg_table_name='rr_material_master_v805' then
    new.purchase_unit:=public.rr_unit_require_code_v606(new.purchase_unit);
    new.base_stock_unit:=public.rr_unit_require_code_v606(new.base_stock_unit);
    new.consumption_unit:=public.rr_unit_require_code_v606(new.consumption_unit);
  elsif tg_table_name='rr_material_categories' then
    new.unit:=public.rr_unit_require_code_v606(new.unit);
  elsif tg_table_name='rr_cb_purchase_entries' and new.unit is not null then
    new.unit:=public.rr_unit_require_code_v606(new.unit);
  end if;
  return new;
end $function$;
drop trigger if exists rr_material_master_unit_guard_v606 on public.rr_material_master_v805;
create trigger rr_material_master_unit_guard_v606 before insert or update of purchase_unit,base_stock_unit,consumption_unit
on public.rr_material_master_v805 for each row execute function public.rr_validate_canonical_unit_v606();
drop trigger if exists rr_material_category_unit_guard_v606 on public.rr_material_categories;
create trigger rr_material_category_unit_guard_v606 before insert or update of unit
on public.rr_material_categories for each row execute function public.rr_validate_canonical_unit_v606();
alter table public.rr_cb_purchase_entries drop constraint if exists rr_cb_purchase_entries_unit_chk;
drop trigger if exists rr_cb_purchase_entry_unit_guard_v606 on public.rr_cb_purchase_entries;
create trigger rr_cb_purchase_entry_unit_guard_v606 before insert or update of unit
on public.rr_cb_purchase_entries for each row execute function public.rr_validate_canonical_unit_v606();

-- Patch existing canonical creators in place so no second Material/Type engine is introduced.
do $do$
declare d text; n text;
begin
  select pg_get_functiondef('public.rr_material_create_v805_31(text,text,text,text,text,numeric,text,numeric,text,numeric,text,uuid,jsonb)'::regprocedure) into d;
  n:=replace(d,'upper(trim(p_purchase_unit)),upper(trim(p_stock_unit)),upper(trim(p_consumption_unit)),',
    'public.rr_unit_require_code_v606(p_purchase_unit),public.rr_unit_require_code_v606(p_stock_unit),public.rr_unit_require_code_v606(p_consumption_unit),');
  if n=d then raise exception 'Material creator Unit patch did not match'; end if;
  execute n;

  select pg_get_functiondef('public.rr_material_type_create_v805_31(text,text,text,text)'::regprocedure) into d;
  n:=replace(d,
    $$upper(coalesce(nullif(trim(p_default_purchase_unit),''),'PCS')),upper(coalesce(nullif(trim(p_default_consumption_unit),''),'PCS'))$$,
    $$public.rr_unit_require_code_v606(coalesce(nullif(trim(p_default_purchase_unit),''),'PCS')),public.rr_unit_require_code_v606(coalesce(nullif(trim(p_default_consumption_unit),''),'PCS'))$$);
  if n=d then raise exception 'Material Type Unit patch did not match'; end if;
  execute n;

  select pg_get_functiondef('public.rr_material_name_request_v8076(text,text,text,text,text,text,text)'::regprocedure) into d;
  n:=replace(d,$$upper(trim(coalesce(p_purchase_unit,'PCS')))$$,$$public.rr_unit_require_code_v606(coalesce(p_purchase_unit,'PCS'))$$);
  n:=replace(n,$$upper(trim(coalesce(p_stock_unit,'PCS')))$$,$$public.rr_unit_require_code_v606(coalesce(p_stock_unit,'PCS'))$$);
  n:=replace(n,$$upper(trim(coalesce(p_consumption_unit,'PCS')))$$,$$public.rr_unit_require_code_v606(coalesce(p_consumption_unit,'PCS'))$$);
  if n=d then raise exception 'Material request Unit patch did not match'; end if;
  execute n;

  select pg_get_functiondef('public.rr_material_name_decide_v8076(uuid,text,text,text)'::regprocedure) into d;
  n:=replace(d,$$v_pu:=upper(coalesce(nullif(r.requested_payload->>'purchase_unit',''),'PCS'));$$,
    $$v_pu:=public.rr_unit_require_code_v606(coalesce(nullif(r.requested_payload->>'purchase_unit',''),'PCS'));$$);
  n:=replace(n,$$v_su:=upper(coalesce(nullif(r.requested_payload->>'stock_unit',''),v_pu));$$,
    $$v_su:=public.rr_unit_require_code_v606(coalesce(nullif(r.requested_payload->>'stock_unit',''),v_pu));$$);
  n:=replace(n,$$v_cu:=upper(coalesce(nullif(r.requested_payload->>'consumption_unit',''),v_su));$$,
    $$v_cu:=public.rr_unit_require_code_v606(coalesce(nullif(r.requested_payload->>'consumption_unit',''),v_su));$$);
  if n=d then raise exception 'Material approval Unit patch did not match'; end if;
  execute n;

  select pg_get_functiondef('public.rr_cb_department_save_v600(uuid,uuid,boolean,jsonb)'::regprocedure) into d;
  n:=replace(d,
    $$if unit_code is null or unit_code not in('KG','PCS','ROLL','CONE','MTR','SET','BOX') then$$,
    $$if unit_code is null or public.rr_unit_resolve_code_v606(unit_code) is null then$$);
  if n=d then raise exception 'CB dynamic Unit Master patch did not match'; end if;
  execute n;
end $do$;

-- Reversible TEST-only cleanup for the deployment E2E namespace.
create or replace function public.rr_test_material_unit_cleanup_v606(p_material_name text,p_unit_code text)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare mid uuid; uid uuid;
begin
  perform public.rr_unit_master_assert_authority_v606();
  if p_material_name not like 'TEST71 Rope Unit %' or upper(p_unit_code) not like 'TEST71_BUNDLE_%' then
    raise exception 'Only TEST71 material/unit fixtures may be cleaned.';
  end if;
  select m.id into mid from public.rr_material_master_v805 m where m.material_name=p_material_name;
  if mid is not null then
    if exists(select 1 from public.rr_material_purchases_v805 where material_id=mid)
       or exists(select 1 from public.rr_material_consumption_v805 where material_id=mid) then
      raise exception 'TEST fixture has ledger history and cannot be deleted.';
    end if;
    delete from public.rr_material_categories where material_master_id=mid;
    delete from public.rr_material_master_v805 where id=mid;
  end if;
  select id into uid from public.rr_unit_master_v606 where unit_code=upper(p_unit_code);
  if uid is not null and not exists(
    select 1 from public.rr_material_master_v805 where purchase_unit=upper(p_unit_code) or base_stock_unit=upper(p_unit_code) or consumption_unit=upper(p_unit_code)
  ) then delete from public.rr_unit_master_v606 where id=uid; end if;
  return jsonb_build_object('ok',true,'material_removed',mid is not null,'unit_removed',uid is not null);
end $function$;
revoke all on function public.rr_test_material_unit_cleanup_v606(text,text) from public,anon;
grant execute on function public.rr_test_material_unit_cleanup_v606(text,text) to authenticated,service_role;

comment on table public.rr_unit_master_v606 is 'Canonical selectable Unit Master shared by Material Master, CB, consumption and costing mappings.';
comment on function public.rr_unit_master_create_v606(text,text) is 'Super Admin-only idempotent Unit creation with alias/similarity duplicate protection.';
notify pgrst,'reload schema';
commit;
