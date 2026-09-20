-- TEST71 Checkpoint 6 follow-up: make the existing Finished Goods Packing
-- engine honour the canonical effective Act As identity.  This does not add a
-- second Packing workflow; it repairs the legacy auth.uid()-only gates used by
-- the V788 canonical functions.

begin;

create or replace function public.rr_fg_effective_packing_access_v334(
  p_assigned_worker_user_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_identity jsonb;
  v_role text;
  v_effective_auth_id uuid;
  v_worker_id uuid;
  v_is_assigned_worker boolean;
begin
  perform public.rr_fg_assert_user_v787();
  v_identity:=public.rr_upm_effective_identity_v200();
  v_role:=upper(coalesce(v_identity->>'role_code',v_identity->>'resolved_role',''));
  v_effective_auth_id:=nullif(v_identity->>'effective_auth_user_id','')::uuid;
  v_worker_id:=nullif(v_identity->>'worker_id','')::uuid;
  v_is_assigned_worker:=p_assigned_worker_user_id is not null and (
    coalesce(p_assigned_worker_user_id=v_effective_auth_id,false)
    or coalesce(p_assigned_worker_user_id=v_worker_id,false)
  );

  return jsonb_build_object(
    'role_code',v_role,
    'can_manage',v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER'),
    'is_assigned_worker',v_is_assigned_worker,
    'effective_auth_user_id',v_effective_auth_id,
    'worker_id',v_worker_id,
    'on_behalf',coalesce((v_identity->>'on_behalf')::boolean,false),
    'operator_user_id',auth.uid()
  );
end $$;

revoke all on function public.rr_fg_effective_packing_access_v334(uuid)
  from public,anon,authenticated;

create or replace function public.rr_fg_is_pack_assigner_v788()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select coalesce(
    (public.rr_fg_effective_packing_access_v334(null)->>'can_manage')::boolean,
    false
  )
$$;

create or replace function public.rr_fg_ready_packing_cards_v788(
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  out_json jsonb;
  v_access jsonb;
  v_effective_auth_id uuid;
  v_worker_id uuid;
  v_manager boolean;
begin
  perform public.rr_fg_assert_user_v787();
  v_access:=public.rr_fg_effective_packing_access_v334(null);
  v_effective_auth_id:=nullif(v_access->>'effective_auth_user_id','')::uuid;
  v_worker_id:=nullif(v_access->>'worker_id','')::uuid;
  v_manager:=coalesce((v_access->>'can_manage')::boolean,false);

  if p_data_mode not in ('TEST','REAL') then
    raise exception 'Invalid data mode';
  end if;
  if to_regclass('public.rr_lot_process_actuals') is null then
    return '[]'::jsonb;
  end if;

  execute $q$
    with lots as (
      select distinct trim(lot_no) as lot_no
      from rr_lot_process_actuals
      where nullif(trim(lot_no),'') is not null
        and upper(process_code) in ('PRESS','PACKING')
    ),
    matrices as (
      select l.lot_no, public.rr_fg_packable_matrix_v787(l.lot_no,$1) as matrix
      from lots l
    ),
    ready as (
      select
        m.lot_no,
        m.matrix,
        coalesce((select sum((z->>'qty')::int) from jsonb_array_elements(m.matrix) z),0)::int as ready_qty,
        coalesce((select count(distinct z->>'colour_code') from jsonb_array_elements(m.matrix) z),0)::int as colours,
        coalesce((select count(distinct z->>'size_code') from jsonb_array_elements(m.matrix) z),0)::int as sizes
      from matrices m
    ),
    latest_assignment as (
      select distinct on (a.lot_no) a.*
      from rr_fg_packing_assignments_v788 a
      where a.data_mode=$1
        and a.status in ('ASSIGNED','ACCEPTED','SUBMITTED')
      order by a.lot_no,coalesce(a.submitted_at,a.accepted_at,a.assigned_at) desc nulls last
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'lot_no',r.lot_no,
      'ready_qty',r.ready_qty,
      'colours',r.colours,
      'sizes',r.sizes,
      'assignment_id',a.id,
      'assignment_status',a.status,
      'pack_plan_id',a.pack_plan_id,
      'worker_user_id',a.worker_user_id,
      'worker_name',a.worker_name,
      'is_mine',(
        coalesce(a.worker_user_id=$2,false)
        or coalesce(a.worker_user_id=$3,false)
      ),
      'status_label',case
        when a.pack_plan_id is not null then 'ALGORITHM READY · TAP TO VIEW'
        when a.id is null then 'READY · TAP TO ASSIGN'
        when (coalesce(a.worker_user_id=$2,false) or coalesce(a.worker_user_id=$3,false)) and a.status='ASSIGNED' then 'MY WORK · TAP TO ACCEPT'
        when (coalesce(a.worker_user_id=$2,false) or coalesce(a.worker_user_id=$3,false)) and a.status='ACCEPTED' then 'MY WORK · RUN ALGORITHM'
        when $4 and a.status='ASSIGNED' then 'ASSIGNED · MANAGER CAN ACCEPT'
        when $4 and a.status='ACCEPTED' then 'ACCEPTED · RUN ALGORITHM'
        else 'ASSIGNED'
      end
    ) order by r.lot_no),'[]'::jsonb)
    from ready r
    left join latest_assignment a on a.lot_no=r.lot_no
    where r.ready_qty>0
      and coalesce(a.status,'')<>'SUBMITTED'
      and (
        $4
        or coalesce(a.worker_user_id=$2,false)
        or coalesce(a.worker_user_id=$3,false)
      )
  $q$
  into out_json
  using p_data_mode,v_effective_auth_id,v_worker_id,v_manager;

  return coalesce(out_json,'[]'::jsonb);
end $$;

create or replace function public.rr_fg_accept_packing_v788(
  p_assignment_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  a public.rr_fg_packing_assignments_v788%rowtype;
  v_access jsonb;
  v_manager boolean;
  v_worker boolean;
begin
  perform public.rr_fg_assert_user_v787();
  select * into a from public.rr_fg_packing_assignments_v788 where id=p_assignment_id for update;
  if not found then raise exception 'Open Packing assignment not found'; end if;
  v_access:=public.rr_fg_effective_packing_access_v334(a.worker_user_id);
  v_manager:=coalesce((v_access->>'can_manage')::boolean,false);
  v_worker:=coalesce((v_access->>'is_assigned_worker')::boolean,false);
  if not v_manager and not v_worker then
    raise exception 'Only assigned Packing Worker or Owner/Admin/Manager can accept';
  end if;
  if a.status='ACCEPTED' then
    return jsonb_build_object(
      'assignment_id',a.id,'accepted',true,'already_accepted',true,'lot_no',a.lot_no,
      'manager_behalf',v_manager and not v_worker,'performed_by',auth.uid(),
      'act_as_worker_id',v_access->>'worker_id'
    );
  end if;
  if a.status<>'ASSIGNED' then raise exception 'Open Packing assignment not found'; end if;
  update public.rr_fg_packing_assignments_v788
  set status='ACCEPTED',accepted_by=auth.uid(),accepted_at=now()
  where id=a.id;
  return jsonb_build_object(
    'assignment_id',a.id,'accepted',true,'lot_no',a.lot_no,
    'manager_behalf',v_manager and not v_worker,'performed_by',auth.uid(),
    'act_as_worker_id',v_access->>'worker_id'
  );
end $$;

create or replace function public.rr_fg_generate_assigned_pack_v788(
  p_assignment_id uuid,
  p_pcs_per_box integer default 18
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  a public.rr_fg_packing_assignments_v788%rowtype;
  r jsonb;
  v_access jsonb;
  v_manager boolean;
  v_worker boolean;
begin
  perform public.rr_fg_assert_user_v787();
  select * into a from public.rr_fg_packing_assignments_v788 where id=p_assignment_id for update;
  if not found or a.status<>'ACCEPTED' then
    raise exception 'Accepted assigned Packing Work required';
  end if;
  v_access:=public.rr_fg_effective_packing_access_v334(a.worker_user_id);
  v_manager:=coalesce((v_access->>'can_manage')::boolean,false);
  v_worker:=coalesce((v_access->>'is_assigned_worker')::boolean,false);
  if not v_manager and not v_worker then
    raise exception 'Only assigned Packing Worker or Owner/Admin/Manager can run packing algorithm';
  end if;
  r:=public.rr_fg_generate_pack_v787(a.lot_no,a.source_matrix,a.data_mode,p_pcs_per_box);
  update public.rr_fg_packing_assignments_v788
  set pack_plan_id=(r->>'plan_id')::uuid where id=a.id;
  return r||jsonb_build_object(
    'manager_behalf',v_manager and not v_worker,'performed_by',auth.uid(),
    'act_as_worker_id',v_access->>'worker_id'
  );
end $$;

create or replace function public.rr_fg_reset_equal_pack_plan_v9317(
  p_assignment_id uuid,
  p_pcs_per_box integer default 18
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  a public.rr_fg_packing_assignments_v788%rowtype;
  old_plan uuid;
  old_status text;
  r jsonb;
  v_access jsonb;
  v_manager boolean;
  v_worker boolean;
begin
  perform public.rr_fg_assert_user_v787();
  select * into a from public.rr_fg_packing_assignments_v788 where id=p_assignment_id for update;
  if not found then raise exception 'Packing assignment not found'; end if;
  v_access:=public.rr_fg_effective_packing_access_v334(a.worker_user_id);
  v_manager:=coalesce((v_access->>'can_manage')::boolean,false);
  v_worker:=coalesce((v_access->>'is_assigned_worker')::boolean,false);
  if not v_manager and not v_worker then
    raise exception 'Only assigned Packing Worker or Owner/Admin/Manager can reset packing algorithm';
  end if;
  old_plan:=a.pack_plan_id;
  if old_plan is not null then
    select status into old_status from public.rr_fg_pack_plans_v787 where id=old_plan;
    if exists(
      select 1 from public.rr_fg_despatch_boxes_v787 db
      join public.rr_fg_boxes_v787 b on b.id=db.box_id
      where b.plan_id=old_plan
    ) then raise exception 'Despatched packing cannot be reset'; end if;
    if old_status='SUBMITTED' then
      raise exception 'Submitted packing cannot be reset. Despatch/return flow ke liye locked hai.';
    end if;
    update public.rr_fg_pack_plans_v787 set status='CANCELLED'
    where id=old_plan and status='DRAFT';
  end if;
  update public.rr_fg_packing_assignments_v788
  set status='ACCEPTED',pack_plan_id=null,submitted_by=null,submitted_at=null
  where id=a.id;
  r:=public.rr_fg_generate_pack_v787(a.lot_no,a.source_matrix,a.data_mode,p_pcs_per_box);
  update public.rr_fg_packing_assignments_v788
  set pack_plan_id=(r->>'plan_id')::uuid,status='ACCEPTED'
  where id=a.id;
  return r||jsonb_build_object(
    'assignment_id',a.id,'lot_no',a.lot_no,'reset',true,
    'old_plan_id',old_plan,'pcs_per_box',(r->>'pcs_per_box')::int,
    'manager_behalf',v_manager and not v_worker,'performed_by',auth.uid(),
    'act_as_worker_id',v_access->>'worker_id'
  );
end $$;

create or replace function public.rr_fg_submit_assigned_pack_v788(
  p_assignment_id uuid,
  p_plan_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  a public.rr_fg_packing_assignments_v788%rowtype;
  r jsonb;
  v_access jsonb;
  v_manager boolean;
  v_worker boolean;
  v_camera int:=0;
  v_ai_final int:=0;
  v_rate_status text;
begin
  perform public.rr_fg_assert_user_v787();
  select * into a from public.rr_fg_packing_assignments_v788 where id=p_assignment_id for update;
  if not found or a.status<>'ACCEPTED' or a.pack_plan_id<>p_plan_id then
    raise exception 'Assigned accepted Packing Plan required';
  end if;
  v_access:=public.rr_fg_effective_packing_access_v334(a.worker_user_id);
  v_manager:=coalesce((v_access->>'can_manage')::boolean,false);
  v_worker:=coalesce((v_access->>'is_assigned_worker')::boolean,false);
  if not v_manager and not v_worker then
    raise exception 'Only assigned Packing Worker or Owner/Admin/Manager can submit packing plan';
  end if;
  select status into v_rate_status
  from public.rr_pack_rate_approval_v9340
  where data_mode=a.data_mode and upper(trim(lot_no))=upper(trim(a.lot_no));
  if coalesce(v_rate_status,'')<>'APPROVED' then
    raise exception 'Packing submit blocked: Final Rate Approval pending';
  end if;
  select least(3,count(*) filter(
    where coalesce(variant_no,0) between 1 and 99 or caption ilike '[CAMERA]%'
  )) into v_camera
  from public.rr_fg_webstore_media_v808
  where data_mode=a.data_mode and upper(trim(lot_no))=upper(trim(a.lot_no));
  if coalesce(v_camera,0)<>3 then
    raise exception 'Packing submit blocked: 3 final camera/gallery pics mandatory. Current: %/3',coalesce(v_camera,0);
  end if;
  select count(distinct style_no) into v_ai_final
  from public.rr_pack_ai_candidates_v9340
  where data_mode=a.data_mode and upper(trim(lot_no))=upper(trim(a.lot_no))
    and is_final=true and style_no in (1,2,3);
  r:=public.rr_fg_submit_pack_v787(p_plan_id);
  update public.rr_fg_packing_assignments_v788
  set status='SUBMITTED',submitted_by=auth.uid(),submitted_at=now()
  where id=a.id;
  return r||jsonb_build_object(
    'handover_no',a.handover_no,'lot_no',a.lot_no,
    'manager_behalf',v_manager and not v_worker,'camera_pics',v_camera,
    'ai_final_styles',v_ai_final,'performed_by',auth.uid(),
    'act_as_worker_id',v_access->>'worker_id'
  );
end $$;

grant execute on function public.rr_fg_is_pack_assigner_v788() to authenticated;
grant execute on function public.rr_fg_ready_packing_cards_v788(text) to authenticated;
grant execute on function public.rr_fg_accept_packing_v788(uuid) to authenticated;
grant execute on function public.rr_fg_generate_assigned_pack_v788(uuid,integer) to authenticated;
grant execute on function public.rr_fg_reset_equal_pack_plan_v9317(uuid,integer) to authenticated;
grant execute on function public.rr_fg_submit_assigned_pack_v788(uuid,uuid) to authenticated;

commit;
