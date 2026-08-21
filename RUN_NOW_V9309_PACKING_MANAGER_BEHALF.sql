-- V9309: Allow Owner/Admin/Manager to accept, run algorithm, and submit
-- assigned Finished Goods Packing work on behalf of the assigned worker.

create or replace function public.rr_fg_accept_packing_v788(p_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  a public.rr_fg_packing_assignments_v788%rowtype;
  v_manager boolean:=public.rr_fg_is_pack_assigner_v788();
begin
  perform public.rr_fg_assert_user_v787();
  select * into a from public.rr_fg_packing_assignments_v788 where id=p_assignment_id for update;
  if not found or a.status<>'ASSIGNED' then
    raise exception 'Open Packing assignment not found';
  end if;
  if not v_manager and a.worker_user_id<>auth.uid() then
    raise exception 'Only assigned Packing Worker or Owner/Admin/Manager can accept';
  end if;
  update public.rr_fg_packing_assignments_v788
     set status='ACCEPTED',accepted_by=auth.uid(),accepted_at=now()
   where id=a.id;
  return jsonb_build_object('assignment_id',a.id,'accepted',true,'lot_no',a.lot_no,'manager_behalf',v_manager and a.worker_user_id<>auth.uid());
end;
$$;

create or replace function public.rr_fg_generate_assigned_pack_v788(p_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  a public.rr_fg_packing_assignments_v788%rowtype;
  r jsonb;
  v_manager boolean:=public.rr_fg_is_pack_assigner_v788();
begin
  perform public.rr_fg_assert_user_v787();
  select * into a from public.rr_fg_packing_assignments_v788 where id=p_assignment_id for update;
  if not found or a.status<>'ACCEPTED' then
    raise exception 'Accepted assigned Packing Work required';
  end if;
  if not v_manager and a.worker_user_id<>auth.uid() then
    raise exception 'Only assigned Packing Worker or Owner/Admin/Manager can run packing algorithm';
  end if;
  r:=public.rr_fg_generate_pack_v787(a.lot_no,a.source_matrix,a.data_mode);
  update public.rr_fg_packing_assignments_v788 set pack_plan_id=(r->>'plan_id')::uuid where id=a.id;
  return r||jsonb_build_object('manager_behalf',v_manager and a.worker_user_id<>auth.uid());
end;
$$;

create or replace function public.rr_fg_submit_assigned_pack_v788(p_assignment_id uuid,p_plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  a public.rr_fg_packing_assignments_v788%rowtype;
  r jsonb;
  v_manager boolean:=public.rr_fg_is_pack_assigner_v788();
begin
  perform public.rr_fg_assert_user_v787();
  select * into a from public.rr_fg_packing_assignments_v788 where id=p_assignment_id for update;
  if not found or a.status<>'ACCEPTED' or a.pack_plan_id<>p_plan_id then
    raise exception 'Assigned accepted Packing Plan required';
  end if;
  if not v_manager and a.worker_user_id<>auth.uid() then
    raise exception 'Only assigned Packing Worker or Owner/Admin/Manager can submit packing plan';
  end if;
  r:=public.rr_fg_submit_pack_v787(p_plan_id);
  update public.rr_fg_packing_assignments_v788 set status='SUBMITTED',submitted_by=auth.uid(),submitted_at=now() where id=a.id;
  return r||jsonb_build_object('handover_no',a.handover_no,'lot_no',a.lot_no,'manager_behalf',v_manager and a.worker_user_id<>auth.uid());
end;
$$;

grant execute on function public.rr_fg_accept_packing_v788(uuid),public.rr_fg_generate_assigned_pack_v788(uuid),public.rr_fg_submit_assigned_pack_v788(uuid,uuid) to authenticated;
