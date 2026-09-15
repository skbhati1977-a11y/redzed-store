-- TEST70 V176: explicit, expiring Super Admin on-behalf context for role-by-role testing.
begin;

update public.rr_worker_directory_v1
set role_code='sales',department_code='sales',updated_at=now()
where id='e1966884-f998-4775-81a6-ec33e4e5eb37'::uuid
  and lower(worker_name)='lukman';

insert into public.rr_worker_department_map_v1(worker_id,department_code,is_primary,is_active,created_at,updated_at)
values('e1966884-f998-4775-81a6-ec33e4e5eb37'::uuid,'sales',true,true,now(),now())
on conflict(worker_id,department_code) do update set is_primary=true,is_active=true,updated_at=now();

update public.rr_real_chat_department_membership_v70
set membership_side='STAFF',membership_scope='DEPARTMENT',source_rule='SALES_HEAD',is_active=true,updated_at=now()
where worker_id='e1966884-f998-4775-81a6-ec33e4e5eb37'::uuid and upper(department_code)='SALES';

create table if not exists public.rr_test_on_behalf_context_v176(
 operator_user_id uuid primary key references auth.users(id) on delete cascade,
 target_worker_id uuid not null,
 target_name text not null,
 target_role text not null,
 department_codes text[] not null default '{}',
 is_active boolean not null default true,
 selected_at timestamptz not null default now(),
 expires_at timestamptz not null default(now()+interval '8 hours')
);
alter table public.rr_test_on_behalf_context_v176 enable row level security;
revoke all on public.rr_test_on_behalf_context_v176 from public,anon,authenticated;

create or replace function public.rr_test_set_on_behalf_context_v176(p_worker_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_operator_role text;v_target record;v_departments text[];
begin
 select upper(role_code) into v_operator_role from public.rr_user_profiles
 where auth_user_id=auth.uid() and is_active order by updated_at desc nulls last limit 1;
 if v_operator_role not in('OWNER','SUPER_ADMIN')then raise exception 'Super Admin test delegation required';end if;
 select worker_id,worker_name,upper(coalesce(role_code,'WORKER')) role_code,upper(coalesce(department_code,'')) department_code
 into v_target from public.rr_worker_directory_unified_v1 where worker_id=p_worker_id and is_active limit 1;
 if not found then raise exception 'Selected mapped person is inactive or unavailable';end if;
 select array_agg(distinct d) into v_departments from(
  select v_target.department_code d where v_target.department_code<>''
  union select upper(department_code) from public.rr_worker_department_map_v1 where worker_id=p_worker_id and is_active
 )s;
 insert into public.rr_test_on_behalf_context_v176(operator_user_id,target_worker_id,target_name,target_role,department_codes,is_active,selected_at,expires_at)
 values(auth.uid(),p_worker_id,v_target.worker_name,v_target.role_code,coalesce(v_departments,'{}'),true,now(),now()+interval '8 hours')
 on conflict(operator_user_id)do update set target_worker_id=excluded.target_worker_id,target_name=excluded.target_name,
  target_role=excluded.target_role,department_codes=excluded.department_codes,is_active=true,selected_at=now(),expires_at=now()+interval '8 hours';
 return jsonb_build_object('ok',true,'worker_id',p_worker_id,'name',v_target.worker_name,'role_code',v_target.role_code,'department_codes',coalesce(v_departments,'{}'));
end $$;

create or replace function public.rr_test_clear_on_behalf_context_v176()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin delete from public.rr_test_on_behalf_context_v176 where operator_user_id=auth.uid();return jsonb_build_object('ok',true);end $$;

create or replace function public.rr_real_chat_test_behalf_context_v176()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare c record;v_role text;
begin
 if upper(coalesce(new.data_mode,''))<>'TEST' or new.sender_user_id is null then return new;end if;
 select upper(role_code) into v_role from public.rr_user_profiles where auth_user_id=new.sender_user_id and is_active order by updated_at desc nulls last limit 1;
 if v_role not in('OWNER','SUPER_ADMIN')then return new;end if;
 select * into c from public.rr_test_on_behalf_context_v176 where operator_user_id=new.sender_user_id and is_active and expires_at>now();
 if not found then return new;end if;
 new.personal_payload:=coalesce(new.personal_payload,'{}')||jsonb_build_object('delegation_requested',true,'on_behalf_worker_id',c.target_worker_id,
  'on_behalf_of_name',c.target_name,'on_behalf_role',c.target_role,'on_behalf_departments',c.department_codes);
 new.group_payload:=coalesce(new.group_payload,'{}')||jsonb_build_object('delegation_requested',true,'on_behalf_worker_id',c.target_worker_id,
  'on_behalf_of_name',c.target_name,'on_behalf_role',c.target_role,'on_behalf_departments',c.department_codes);
 return new;
end $$;

drop trigger if exists zzzy_rr_test_behalf_context_v176 on public.rr_real_chat_message_bridge_v70;
create trigger zzzy_rr_test_behalf_context_v176 before insert or update on public.rr_real_chat_message_bridge_v70
for each row execute function public.rr_real_chat_test_behalf_context_v176();

revoke all on function public.rr_test_set_on_behalf_context_v176(uuid) from public,anon;
revoke all on function public.rr_test_clear_on_behalf_context_v176() from public,anon;
revoke all on function public.rr_real_chat_test_behalf_context_v176() from public,anon,authenticated;
grant execute on function public.rr_test_set_on_behalf_context_v176(uuid) to authenticated;
grant execute on function public.rr_test_clear_on_behalf_context_v176() to authenticated;

commit;
