-- TEST71 Checkpoint 3: scoped Product Master authorization.
-- Do not broaden the legacy global helper; only Product Master surfaces gain SUPER_ADMIN.
create or replace function public.rr_can_manage_product_masters_v327()
returns boolean language sql stable security definer set search_path='public' as $$
 select coalesce(public.rr_current_role() in ('owner','admin','super_admin'),false)
$$;
revoke all on function public.rr_can_manage_product_masters_v327() from public,anon;
grant execute on function public.rr_can_manage_product_masters_v327() to authenticated;

drop policy if exists rr_owner_admin_all on public.rr_art_master;
create policy rr_owner_admin_all on public.rr_art_master for all to authenticated
using (public.rr_can_manage_product_masters_v327()) with check (public.rr_can_manage_product_masters_v327());

drop policy if exists rr_owner_admin_all on public.rr_media;
create policy rr_owner_admin_all on public.rr_media for all to authenticated
using (public.rr_can_manage_product_masters_v327()) with check (public.rr_can_manage_product_masters_v327());

drop policy if exists rr_print_frames_owner_admin on public.rr_print_frames;
create policy rr_print_frames_owner_admin on public.rr_print_frames for all to authenticated
using (public.rr_can_manage_product_masters_v327()) with check (public.rr_can_manage_product_masters_v327());

drop policy if exists rr_print_master_owner_admin_select on public.rr_print_master;
drop policy if exists rr_print_master_owner_admin_insert on public.rr_print_master;
drop policy if exists rr_print_master_owner_admin_update on public.rr_print_master;
drop policy if exists rr_print_master_owner_admin_delete on public.rr_print_master;
create policy rr_print_master_owner_admin_select on public.rr_print_master for select to authenticated using (public.rr_can_manage_product_masters_v327());
create policy rr_print_master_owner_admin_insert on public.rr_print_master for insert to authenticated with check (public.rr_can_manage_product_masters_v327());
create policy rr_print_master_owner_admin_update on public.rr_print_master for update to authenticated using (public.rr_can_manage_product_masters_v327()) with check (public.rr_can_manage_product_masters_v327());
create policy rr_print_master_owner_admin_delete on public.rr_print_master for delete to authenticated using (public.rr_can_manage_product_masters_v327());

create or replace function public.rr_upsert_sticker_master_v804(
 p_id uuid default null,p_sticker_no text default null,p_sticker_name text default null,
 p_sticker_quality text default null,p_is_active boolean default true
) returns uuid language plpgsql security definer set search_path='public' as $$
declare v_id uuid;v_no text:=nullif(trim(p_sticker_no),'');v_quality text:=upper(trim(coalesce(p_sticker_quality,'')));
begin
 if not public.rr_can_manage_product_masters_v327() then raise exception 'Owner/Admin permission required.';end if;
 if v_no is null then raise exception 'Sticker No required.';end if;
 if v_quality not in('HD','DTF','VINYL','OTHER')then raise exception 'Sticker Quality must be HD, DTF, VINYL or OTHER.';end if;
 if p_id is null then
  insert into public.rr_sticker_master_v803(sticker_no,sticker_name,sticker_quality,is_active,updated_at)
  values(v_no,nullif(trim(p_sticker_name),''),v_quality,coalesce(p_is_active,true),now()) returning id into v_id;
 else
  update public.rr_sticker_master_v803 set sticker_no=v_no,sticker_name=nullif(trim(p_sticker_name),''),sticker_quality=v_quality,is_active=coalesce(p_is_active,true),updated_at=now()
  where id=p_id returning id into v_id;
  if v_id is null then raise exception 'Sticker Master item not found.';end if;
 end if;return v_id;
end$$;

create or replace function public.rr_upsert_metal_id_master_v804(
 p_id uuid default null,p_metal_id_no text default null,p_metal_id_name text default null,
 p_id_size text default null,p_is_active boolean default true
) returns uuid language plpgsql security definer set search_path='public' as $$
declare v_id uuid;v_no text:=nullif(trim(p_metal_id_no),'');v_size text:=upper(trim(coalesce(p_id_size,'')));
begin
 if not public.rr_can_manage_product_masters_v327() then raise exception 'Owner/Admin permission required.';end if;
 if v_no is null then raise exception 'Metal ID No required.';end if;
 if v_size not in('SMALL','MEDIUM','BIG')then raise exception 'ID Size must be SMALL, MEDIUM or BIG.';end if;
 if p_id is null then
  insert into public.rr_metal_id_master_v803(metal_id_no,metal_id_name,id_size,is_active,updated_at)
  values(v_no,nullif(trim(p_metal_id_name),''),v_size,coalesce(p_is_active,true),now()) returning id into v_id;
 else
  update public.rr_metal_id_master_v803 set metal_id_no=v_no,metal_id_name=nullif(trim(p_metal_id_name),''),id_size=v_size,is_active=coalesce(p_is_active,true),updated_at=now()
  where id=p_id returning id into v_id;
  if v_id is null then raise exception 'Metal ID Master item not found.';end if;
 end if;return v_id;
end$$;

revoke all on function public.rr_upsert_sticker_master_v804(uuid,text,text,text,boolean) from public,anon;
revoke all on function public.rr_upsert_metal_id_master_v804(uuid,text,text,text,boolean) from public,anon;
grant execute on function public.rr_upsert_sticker_master_v804(uuid,text,text,text,boolean) to authenticated;
grant execute on function public.rr_upsert_metal_id_master_v804(uuid,text,text,text,boolean) to authenticated;
