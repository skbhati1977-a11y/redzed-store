-- TEST70 V172: App-mirrored rate roles and approved RRQ impact visibility.
begin;

create or replace function public.rr_pack_rate_status_v9340(p_lot_no text,p_data_mode text default 'TEST')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare r record;v_art text;
begin
 perform public.rr_fg_assert_user_v787();
 select * into r from public.rr_pack_rate_approval_v9340 where data_mode=upper(p_data_mode)and lot_no=trim(p_lot_no);
 if not found then return jsonb_build_object('lot_no',trim(p_lot_no),'status','NOT_REQUESTED','approved',false,'art_code',null);end if;
 if r.status='APPROVED'then v_art:=public.rr_pack_art_code_v9340(r.final_rate);end if;
 return jsonb_build_object('lot_no',r.lot_no,'status',r.status,'approved',r.status='APPROVED','art_code',v_art,
  'source_rate',r.source_rate,'suggested_rate',r.suggested_rate,'sales_suggested_rate',r.sales_suggested_rate,
  'admin_suggested_rate',r.admin_suggested_rate,'final_rate',r.final_rate,'qty',r.qty_snapshot,
  'reserve_delta_per_pc',case when r.status='APPROVED'then r.reserve_delta_per_pc end,
  'reserve_quota_impact',case when r.status='APPROVED'then r.reserve_quota_impact end,
  'requested_at',r.requested_at,'suggested_at',r.suggested_at,'approved_at',r.approved_at);
end $$;

create or replace function public.rr_pack_rate_suggest_v9340(p_lot_no text,p_suggested_rate numeric,p_data_mode text default 'TEST')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text:=lower(coalesce(public.rr_current_role(),''));v_kind text;
begin
 if v_role not in('admin','sales')then raise exception 'Sales/Admin suggestion access required';end if;
 if p_suggested_rate is null or p_suggested_rate<=0 or p_suggested_rate<>round(p_suggested_rate,0)then raise exception 'Suggested rate must be whole rupee';end if;
 v_kind:=case when v_role='sales'then'SALES'else'ADMIN'end;
 update public.rr_pack_rate_approval_v9340 set
  sales_suggested_rate=case when v_kind='SALES'then p_suggested_rate else sales_suggested_rate end,
  sales_suggested_by=case when v_kind='SALES'then auth.uid()else sales_suggested_by end,
  sales_suggested_at=case when v_kind='SALES'then now()else sales_suggested_at end,
  admin_suggested_rate=case when v_kind='ADMIN'then p_suggested_rate else admin_suggested_rate end,
  admin_suggested_by=case when v_kind='ADMIN'then auth.uid()else admin_suggested_by end,
  admin_suggested_at=case when v_kind='ADMIN'then now()else admin_suggested_at end,
  suggested_rate=p_suggested_rate,suggested_by=auth.uid(),suggested_at=now(),status='SUGGESTED',updated_at=now()
 where data_mode=upper(p_data_mode)and lot_no=trim(p_lot_no)and status<>'APPROVED';
 if not found then raise exception 'Rate request not found or already approved';end if;
 return jsonb_build_object('ok',true,'suggestion_type',v_kind,'suggested_rate',p_suggested_rate);
end $$;

create or replace function public.rr_pack_rate_approve_v9340(p_lot_no text,p_final_rate numeric,p_data_mode text default 'TEST')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text:=lower(coalesce(public.rr_current_role(),''));r record;v_apply jsonb;v_delta numeric;v_impact numeric;v_ctx jsonb;
begin
 if v_role not in('owner','super_admin')then raise exception 'Super Admin approval required';end if;
 if p_final_rate is null or p_final_rate<=0 or p_final_rate<>round(p_final_rate,0)then raise exception 'Final rate must be whole rupee';end if;
 v_ctx:=public.rr_pack_rate_context_universal_v9405(trim(p_lot_no),upper(p_data_mode));
 if coalesce((v_ctx->>'costing_complete')::boolean,false)is not true then raise exception 'Material ya department actual costing incomplete';end if;
 select * into r from public.rr_pack_rate_approval_v9340 where data_mode=upper(p_data_mode)and lot_no=trim(p_lot_no)for update;
 if not found then raise exception 'Rate request not found';end if;
 v_apply:=public.rrq_apply_packing_rate_v9300(trim(p_lot_no),p_final_rate,upper(p_data_mode),'Packing final rate approved from mirrored App/Real Chat review');
 v_delta:=p_final_rate-round((v_ctx->>'source_rate')::numeric,0);v_impact:=v_delta*r.qty_snapshot;
 update public.rr_pack_rate_approval_v9340 set source_rate=round((v_ctx->>'source_rate')::numeric,0),final_rate=p_final_rate,
  reserve_delta_per_pc=v_delta,reserve_quota_impact=v_impact,status='APPROVED',approved_by=auth.uid(),approved_at=now(),updated_at=now()where id=r.id;
 return jsonb_build_object('ok',true,'lot_no',r.lot_no,'mapped_cost_per_pc',v_ctx->'base_cost_per_pc','mapped_sale_suggestion',v_ctx->'source_rate',
  'final_rate',p_final_rate,'art_code',public.rr_pack_art_code_v9340(p_final_rate),'reserve_delta_per_pc',v_delta,'reserve_quota_impact',v_impact,'rrq',v_apply);
end $$;

revoke all on function public.rr_pack_rate_status_v9340(text,text)from public,anon;
revoke all on function public.rr_pack_rate_suggest_v9340(text,numeric,text)from public,anon;
revoke all on function public.rr_pack_rate_approve_v9340(text,numeric,text)from public,anon;
grant execute on function public.rr_pack_rate_status_v9340(text,text)to authenticated;
grant execute on function public.rr_pack_rate_suggest_v9340(text,numeric,text)to authenticated;
grant execute on function public.rr_pack_rate_approve_v9340(text,numeric,text)to authenticated;

commit;
