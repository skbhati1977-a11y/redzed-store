-- REAL FACTORY V788 — AUTO-MAPPED PACKING LOT CARDS
-- Run after REAL_FACTORY_FINISHED_GOODS_V787.sql. TEST remains default.
begin;
create extension if not exists pgcrypto;

create table if not exists public.rr_fg_packing_assignments_v788(
  id uuid primary key default gen_random_uuid(),
  handover_no text not null,
  lot_no text not null,
  source_department text not null default 'PRESS' check(source_department='PRESS'),
  source_matrix jsonb not null,
  ready_qty int not null check(ready_qty>0),
  worker_user_id uuid not null,
  worker_name text not null,
  worker_code text,
  status text not null default 'ASSIGNED' check(status in('ASSIGNED','ACCEPTED','SUBMITTED','CANCELLED')),
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  assigned_by uuid not null default auth.uid(),
  assigned_at timestamptz not null default now(),
  accepted_by uuid,
  accepted_at timestamptz,
  pack_plan_id uuid references public.rr_fg_pack_plans_v787(id),
  submitted_by uuid,
  submitted_at timestamptz,
  unique(handover_no,data_mode)
);
create unique index if not exists rr_fg_one_active_pack_assignment_v788
on public.rr_fg_packing_assignments_v788(lot_no,data_mode)
where status in('ASSIGNED','ACCEPTED');

create or replace function public.rr_fg_is_pack_assigner_v788()
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from rr_user_profiles p where p.auth_user_id=auth.uid() and coalesce(p.is_active,false)
 and lower(coalesce(p.role_code,'')) in('owner','admin','manager'))
$$;

create or replace function public.rr_fg_packing_workers_v788()
returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object('user_id',u.user_id,'display_name',u.display_name,
 'worker_code',to_jsonb(u)->>'worker_code') order by u.display_name),'[]'::jsonb)
 from rr_user_assignments_v2 u where coalesce(u.is_active,false)
 and upper(coalesce(u.department_code,'')) in('PACK','PACKING')
$$;

create or replace function public.rr_fg_ready_packing_cards_v788(p_data_mode text default 'TEST')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare out_json jsonb;begin
 perform rr_fg_assert_user_v787();
 if p_data_mode not in('TEST','REAL') then raise exception 'Invalid data mode';end if;
 if to_regclass('public.rr_lot_process_actuals') is null then return '[]'::jsonb;end if;
 execute $q$
 with lots as(
   select distinct trim(lot_no) lot_no from rr_lot_process_actuals
   where nullif(trim(lot_no),'') is not null and upper(process_code)='PRESS'
 ), matrices as(
   select l.lot_no,public.rr_fg_packable_matrix_v787(l.lot_no,$1) matrix from lots l
 ), ready as(
   select m.lot_no,m.matrix,
     coalesce((select sum((z->>'qty')::int) from jsonb_array_elements(m.matrix) z),0)::int ready_qty,
     coalesce((select count(distinct z->>'colour_code') from jsonb_array_elements(m.matrix) z),0)::int colours,
     coalesce((select count(distinct z->>'size_code') from jsonb_array_elements(m.matrix) z),0)::int sizes
   from matrices m
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'lot_no',r.lot_no,'ready_qty',r.ready_qty,'colours',r.colours,'sizes',r.sizes,
   'assignment_id',a.id,'assignment_status',a.status,'worker_user_id',a.worker_user_id,
   'worker_name',a.worker_name,'is_mine',(a.worker_user_id=auth.uid()),
   'status_label',case when a.id is null then 'READY · TAP TO ASSIGN'
                       when a.worker_user_id=auth.uid() and a.status='ASSIGNED' then 'MY WORK · TAP TO ACCEPT'
                       when a.worker_user_id=auth.uid() and a.status='ACCEPTED' then 'MY WORK · TAP TO PACK'
                       else 'ASSIGNED' end
 ) order by r.lot_no),'[]'::jsonb)
 from ready r left join rr_fg_packing_assignments_v788 a
   on a.lot_no=r.lot_no and a.data_mode=$1 and a.status in('ASSIGNED','ACCEPTED')
 where r.ready_qty>0
 and not exists(select 1 from rr_fg_pack_plans_v787 p where p.lot_no=r.lot_no and p.data_mode=$1 and p.status='SUBMITTED')
 and (public.rr_fg_is_pack_assigner_v788() or a.worker_user_id=auth.uid())
 $q$ into out_json using p_data_mode;
 return coalesce(out_json,'[]'::jsonb);
end$$;

create or replace function public.rr_fg_assign_packing_v788(p_lot_no text,p_worker_user_id uuid,p_data_mode text default 'TEST')
returns jsonb language plpgsql security definer set search_path=public as $$
declare m jsonb;q int;n text;w record;a uuid;begin
 perform rr_fg_assert_user_v787();
 if not rr_fg_is_pack_assigner_v788() then raise exception 'Owner/Admin/Manager assignment required';end if;
 if p_data_mode not in('TEST','REAL') then raise exception 'Invalid data mode';end if;
 select u.display_name,to_jsonb(u)->>'worker_code' worker_code into w from rr_user_assignments_v2 u
 where u.user_id=p_worker_user_id and coalesce(u.is_active,false) and upper(coalesce(u.department_code,'')) in('PACK','PACKING');
 if not found then raise exception 'Active Packing Worker required';end if;
 m:=rr_fg_packable_matrix_v787(trim(p_lot_no),p_data_mode);
 select coalesce(sum((x->>'qty')::int),0) into q from jsonb_array_elements(m)x;
 if q<=0 then raise exception 'Press Ready quantity not found for Lot %',p_lot_no;end if;
 n:=rr_fg_next_no_v787('PACK_HANDOVER',p_data_mode,case when p_data_mode='TEST' then 'TPH' else 'PH' end);
 insert into rr_fg_packing_assignments_v788(handover_no,lot_no,source_matrix,ready_qty,worker_user_id,worker_name,worker_code,data_mode)
 values(n,trim(p_lot_no),m,q,p_worker_user_id,w.display_name,w.worker_code,p_data_mode)returning id into a;
 return jsonb_build_object('assignment_id',a,'handover_no',n,'lot_no',trim(p_lot_no),'ready_qty',q,'worker_name',w.display_name);
end$$;

create or replace function public.rr_fg_accept_packing_v788(p_assignment_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$declare a rr_fg_packing_assignments_v788%rowtype;begin
 perform rr_fg_assert_user_v787();select * into a from rr_fg_packing_assignments_v788 where id=p_assignment_id for update;
 if not found or a.status<>'ASSIGNED' then raise exception 'Open Packing assignment not found';end if;
 if a.worker_user_id<>auth.uid() then raise exception 'Only assigned Packing Worker can accept';end if;
 update rr_fg_packing_assignments_v788 set status='ACCEPTED',accepted_by=auth.uid(),accepted_at=now() where id=a.id;
 return jsonb_build_object('assignment_id',a.id,'accepted',true,'lot_no',a.lot_no);
end$$;

create or replace function public.rr_fg_generate_assigned_pack_v788(p_assignment_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$declare a rr_fg_packing_assignments_v788%rowtype;r jsonb;begin
 perform rr_fg_assert_user_v787();select * into a from rr_fg_packing_assignments_v788 where id=p_assignment_id for update;
 if not found or a.status<>'ACCEPTED' or a.worker_user_id<>auth.uid() then raise exception 'Accepted assigned Packing Work required';end if;
 r:=rr_fg_generate_pack_v787(a.lot_no,a.source_matrix,a.data_mode);
 update rr_fg_packing_assignments_v788 set pack_plan_id=(r->>'plan_id')::uuid where id=a.id;
 return r;
end$$;

create or replace function public.rr_fg_submit_assigned_pack_v788(p_assignment_id uuid,p_plan_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$declare a rr_fg_packing_assignments_v788%rowtype;r jsonb;begin
 perform rr_fg_assert_user_v787();select * into a from rr_fg_packing_assignments_v788 where id=p_assignment_id for update;
 if not found or a.status<>'ACCEPTED' or a.worker_user_id<>auth.uid() or a.pack_plan_id<>p_plan_id then raise exception 'Assigned accepted Packing Plan required';end if;
 r:=rr_fg_submit_pack_v787(p_plan_id);
 update rr_fg_packing_assignments_v788 set status='SUBMITTED',submitted_by=auth.uid(),submitted_at=now() where id=a.id;
 return r||jsonb_build_object('handover_no',a.handover_no,'lot_no',a.lot_no);
end$$;

alter table public.rr_fg_packing_assignments_v788 enable row level security;
drop policy if exists rr_fg_packing_assignments_v788_read on public.rr_fg_packing_assignments_v788;
create policy rr_fg_packing_assignments_v788_read on public.rr_fg_packing_assignments_v788 for select to authenticated
using(worker_user_id=auth.uid() or public.rr_fg_is_pack_assigner_v788());
grant select on public.rr_fg_packing_assignments_v788 to authenticated;
grant execute on function public.rr_fg_packing_workers_v788(),public.rr_fg_ready_packing_cards_v788(text),public.rr_fg_assign_packing_v788(text,uuid,text),public.rr_fg_accept_packing_v788(uuid),public.rr_fg_generate_assigned_pack_v788(uuid),public.rr_fg_submit_assigned_pack_v788(uuid,uuid) to authenticated;
commit;
