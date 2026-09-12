-- TEST70 V100: final receiver guard. The legacy Product Master role-queue
-- decorator runs before this trigger and must not clear an exact Art authority.
begin;

create or replace function public.rr_real_chat_preserve_art_superadmin_v100()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $function$
declare v_user uuid; v_worker uuid; v_name text; v_role text;
begin
  if new.source_event_type<>'ART_DECIDE_PENDING' or new.action_code<>'ART_DECIDE_SUBMIT' then
    return new;
  end if;
  select p.auth_user_id,d.worker_id,coalesce(d.worker_name,p.full_name),upper(coalesce(p.role_code,''))
    into v_user,v_worker,v_name,v_role
  from public.rr_user_profiles p
  left join public.rr_worker_directory_unified_v1 d
    on d.linked_auth_user_id=p.auth_user_id and coalesce(d.is_active,false)
  where coalesce(p.is_active,false) and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
    and regexp_replace(upper(coalesce(p.role_code,'')),'[^A-Z]','','g') in ('SUPERADMIN','OWNER')
  order by case when regexp_replace(upper(coalesce(p.role_code,'')),'[^A-Z]','','g')='SUPERADMIN' then 0 else 1 end,
    p.updated_at desc nulls last,d.worker_id
  limit 1;
  if v_user is null then return new; end if;
  new.receiver_user_id:=v_user;
  new.receiver_worker_id:=v_worker;
  new.action_label:='DECIDE ART / PRINT / STICKER / METAL ID';
  new.personal_payload:=coalesce(new.personal_payload,'{}'::jsonb)||jsonb_build_object(
    'receiver_name',v_name,'receiver_role',case when regexp_replace(v_role,'[^A-Z]','','g')='SUPERADMIN' then 'SUPER_ADMIN' else 'OWNER_SUPERADMIN_AUTHORITY' end,
    'receiver_rule','EXACT_SUPERADMIN_THEN_OWNER','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN'),
    'message','Art, Print, Sticker और Metal ID Superadmin को decide करना है');
  new.group_payload:=coalesce(new.group_payload,'{}'::jsonb)||jsonb_build_object(
    'receiver_name',v_name,'receiver_role',case when regexp_replace(v_role,'[^A-Z]','','g')='SUPERADMIN' then 'SUPER_ADMIN' else 'OWNER_SUPERADMIN_AUTHORITY' end,
    'receiver_rule','EXACT_SUPERADMIN_THEN_OWNER','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN'),
    'message','Art, Print, Sticker और Metal ID Superadmin को decide करना है');
  return new;
end $function$;
revoke all on function public.rr_real_chat_preserve_art_superadmin_v100() from public,anon,authenticated;

drop trigger if exists zzzzzz_rr_art_superadmin_receiver_v100 on public.rr_real_chat_message_bridge_v70;
create trigger zzzzzz_rr_art_superadmin_receiver_v100
before insert or update on public.rr_real_chat_message_bridge_v70
for each row execute function public.rr_real_chat_preserve_art_superadmin_v100();

select public.rr_real_chat_bind_art_superadmin_v99();
commit;
