-- TEST70 Real Chat: missing canonical lifecycle events from cloth purchase through RCI.
-- Existing bridge keys are preserved; this adds only independently keyed source events.

create or replace view public.rr_real_chat_e2e_event_source_v71 as
with active_profile as (
  select distinct on (upper(role_code)) upper(role_code) role_code,id profile_id,auth_user_id,full_name
  from public.rr_user_profiles where is_active=true and coalesce(access_status,'ACTIVE')='ACTIVE'
  order by upper(role_code),created_at
), events as (
  select 'CB_PURCHASE:'||p.id||':'||g.dept canonical_key,'CB_PURCHASE' module,p.id::text record_id,
    'REGULAR_CLOTH_PURCHASE_'||upper(coalesce(p.operation_status,'POSTED')) event_type,g.dept,
    p.created_by sender_user,null::uuid receiver_user,null::uuid receiver_worker,null::text action_code,null::text action_label,
    jsonb_build_object('cb_no',coalesce(c.cb_no,p.cb_id::text),'qty',p.quantity,'rate',p.rate,'status',coalesce(p.operation_status,'POSTED'),'sender_name','Purchase Team','fabric_name',p.fabric_name) payload,
    p.created_at sent_at
  from public.rr_cb_purchase_entries p left join public.rr_cb_master c on c.id=p.cb_id
  cross join (values('CUTTING'),('ACCOUNTS')) g(dept)

  union all select 'MATCHING_PURCHASE:'||p.id||':'||g.dept,'MATCHING_PURCHASE',p.id::text,
    'MATCHING_CLOTH_PURCHASE_'||upper(coalesce(p.status,'POSTED')),g.dept,p.created_by,null,null,null,null,
    jsonb_build_object('cb_no',coalesce(c.cb_no,p.cb_id::text),'qty',p.quantity,'rate',p.rate,'status',coalesce(p.status,'POSTED'),'sender_name','Purchase Team','fabric_name',p.fabric_name),p.created_at
  from public.rr_matching_purchase_entries p left join public.rr_cb_master c on c.id=p.cb_id
  cross join (values('CUTTING'),('ACCOUNTS')) g(dept)

  union all select 'CUTTING_ACTION:'||a.id,'CUTTING',a.id::text,
    upper(a.action_type)||'_'||upper(a.status),'CUTTING',a.created_by,
    case when a.status in('PENDING_ADMIN','ADMIN_MESSAGE_SENT','RECHECK_REQUIRED') then ap_admin.auth_user_id
         when a.status='ADMIN_VERIFIED' and not a.effect_posted then ap_owner.auth_user_id end,null,
    case when a.status in('PENDING_ADMIN','ADMIN_MESSAGE_SENT','RECHECK_REQUIRED') then 'CUTTING_ADMIN_DECISION'
         when a.status='ADMIN_VERIFIED' and not a.effect_posted then 'CUTTING_OWNER_DECISION' end,
    case when a.status in('PENDING_ADMIN','ADMIN_MESSAGE_SENT','RECHECK_REQUIRED') then 'OPEN ADMIN DECISION'
         when a.status='ADMIN_VERIFIED' and not a.effect_posted then 'OPEN OWNER DECISION' end,
    jsonb_build_object('lot_no',a.source_lot_no,'qty',a.qty,'rate',a.rate_snapshot,'status',a.status,
      'sender_name','Cutting Master','reason',a.reason,'receiver_name',case when a.status='ADMIN_VERIFIED' then ap_owner.full_name else ap_admin.full_name end,
      'action_href','real-cutting-master.html?action_id='||a.id,'action_engine','rr_cutting_admin_decide_cb_action_v1 / rr_cutting_owner_decide_cb_action_v1'),a.created_at
  from public.rr_cutting_cb_actions a left join active_profile ap_admin on ap_admin.role_code='ADMIN' left join active_profile ap_owner on ap_owner.role_code='OWNER'

  union all select 'PRODUCT_DECISION:'||a.id||':'||x.dept,'PRODUCT_MASTER',a.id::text,
    x.kind||'_'||x.mode,x.dept,a.assigned_by,case when x.mode='DUE' then ap_admin.auth_user_id end,null,
    case when x.mode='DUE' then 'COMPLETE_'||x.kind||'_DECISION' end,
    case when x.mode='DUE' then 'COMPLETE '||replace(x.kind,'_',' ')||' DECISION' end,
    jsonb_build_object('cb_no',u.cb_base_no,'lot_no',u.cb_code,'status',x.mode,
      'sender_name','Product Master','receiver_name',case when x.mode='DUE' then ap_admin.full_name end,
      'allowed_roles',jsonb_build_array('OWNER','ADMIN'),'action_href','real-product-master-v720.html?unit='||a.cb_id,
      'action_engine','rr_pm_save_decision_bundle_v804','decision_kind',x.kind),coalesce(a.updated_at,a.created_at)
  from public.rr_cb_art_assignments a join public.rr_cb_units u on u.id=a.cb_id
  cross join lateral (values
    ('ART','CUTTING','SELECTED'),
    ('PRINT','PRINTING',case when a.print_due then 'DUE' when a.print_not_applicable then 'NA' when exists(select 1 from public.rr_cb_print_assignments z where z.assignment_id=a.id) then 'SELECTED' else 'NA' end),
    ('STICKER','STICKER',case when a.sticker_due then 'DUE' when a.sticker_not_applicable then 'NA' when exists(select 1 from public.rr_cb_sticker_assignments z where z.assignment_id=a.id) then 'SELECTED' else 'NA' end),
    ('METAL_ID','METAL_ID',case when a.metal_id_due then 'DUE' when a.metal_id_not_applicable then 'NA' when exists(select 1 from public.rr_cb_metal_id_assignments_v801 z where z.assignment_id=a.id) then 'SELECTED' else 'NA' end)
  ) x(kind,dept,mode)
  left join active_profile ap_admin on ap_admin.role_code='ADMIN'

  union all select 'LOT_RELEASE:'||l.id,'CUTTING',l.id::text,'LOT_'||upper(coalesce(l.status,'RELEASED')),'CUTTING',l.created_by,null,null,null,null,
    jsonb_build_object('lot_no',l.lot_no,'cb_no',l.cb_no,'qty',l.total_qty,'status',l.status,'sender_name','Cutting Master'),l.created_at
  from public.rr_upm_lot_registry l

  union all select 'RATE_REQUEST:'||r.id,'UPM_RATE',r.id::text,'RATE_'||upper(r.request_status),r.department_code,r.requested_by,
    coalesce(mgr.linked_auth_user_id,ap_admin.auth_user_id),mgr.worker_id,
    case when r.request_status in('PENDING','OPENED') then 'FILL_DEPARTMENT_RATE' end,
    case when r.request_status in('PENDING','OPENED') then 'FILL DEPARTMENT RATE' end,
    jsonb_build_object('lot_no',r.lot_no,'colour_code',r.colour_code,'status',r.request_status,'sender_name',r.requested_by_name,
      'receiver_name',coalesce(mgr.worker_name,ap_admin.full_name),'rate',r.filled_rate,
      'action_href','real-universal-production-v770-v9059.html?lot='||r.lot_no||'&dept='||r.department_code,
      'action_engine','rr_upm_set_department_rate_v760'),r.requested_at
  from public.rr_upm_rate_requests_v760 r
  left join lateral (select worker_id,worker_name,linked_auth_user_id from public.rr_worker_directory_unified_v1 w
    where upper(w.department_code)=upper(r.department_code) and upper(coalesce(w.role_code,'')) in('MANAGER','LINE_MANAGER') and coalesce(w.is_active,true) limit 1) mgr on true
  left join active_profile ap_admin on ap_admin.role_code='ADMIN'

  union all select 'DEPARTMENT_RATE_LOG:'||x.id,'UPM_RATE',x.id::text,'DEPARTMENT_RATE_UPDATED',r.department_code,x.changed_by,null,null,null,null,
    jsonb_build_object('lot_no',r.lot_no,'rate',x.new_rate,'status','COMPLETED','sender_name',x.changed_by_name,'old_rate',x.old_rate),x.created_at
  from public.rr_upm_department_rate_log_v2 x join public.rr_upm_department_rates_v2 r on r.id=x.rate_id

  union all select 'ASSIGNMENT_RATE_LOG:'||x.id,'UPM_RATE',x.id::text,'ASSIGNMENT_RATE_UPDATED',x.department_code,x.changed_by,w.linked_auth_user_id,x.worker_id,null,null,
    jsonb_build_object('lot_no',x.lot_no,'rate',x.new_rate,'status','COMPLETED','sender_name',x.changed_by_name,'worker_name',x.worker_name,'old_rate',x.old_rate,'reason',x.reason),x.created_at
  from public.rr_upm_assignment_rate_log_v772 x left join public.rr_worker_directory_unified_v1 w on w.worker_id=x.worker_id

  union all select 'PACK_ASSIGNMENT:'||a.id,'PACKING',a.id::text,'PACKING_'||upper(a.status),'PACKING',a.assigned_by,a.worker_user_id,w.worker_id,
    case when a.status='ASSIGNED' then 'ACCEPT_PACKING' when a.status='ACCEPTED' then 'SUBMIT_PACKING' end,
    case when a.status='ASSIGNED' then 'ACCEPT WORK' when a.status='ACCEPTED' then 'OPEN PACKING' end,
    jsonb_build_object('lot_no',a.lot_no,'qty',a.ready_qty,'status',a.status,'worker_name',a.worker_name,'receiver_name',a.worker_name,
      'action_href','real-finished-goods-v787.html?view=packing&lot='||a.lot_no,'action_engine','rr_fg_accept_packing_v788 / rr_fg_submit_assigned_pack_v788'),a.assigned_at
  from public.rr_fg_packing_assignments_v788 a left join public.rr_worker_directory_unified_v1 w on w.linked_auth_user_id=a.worker_user_id

  union all select 'PACK_RATE:'||r.id,'PACKING_RATE',r.id::text,'PACK_RATE_'||upper(r.status),'PACKING',r.requested_by,ap_admin.auth_user_id,null,
    case when r.status<>'APPROVED' then 'FINAL_RATE_REVIEW' end,case when r.status<>'APPROVED' then 'OPEN FINAL RATE REVIEW' end,
    jsonb_build_object('lot_no',r.lot_no,'qty',r.qty_snapshot,'rate',coalesce(r.final_rate,r.suggested_rate,r.source_rate),'status',r.status,
      'receiver_name',ap_admin.full_name,'sender_name','Packing Team','action_href','real-finished-goods-v787.html?view=packing&lot='||r.lot_no,
      'action_engine','rr_pack_rate_suggest_v9340 / rr_pack_rate_approve_v9340'),r.requested_at
  from public.rr_pack_rate_approval_v9340 r left join active_profile ap_admin on ap_admin.role_code='ADMIN'

  union all select 'MEDIA_AI:'||m.id,'MEDIA_AI',m.id::text,'MEDIA_'||upper(m.approval_status),'PACKING',m.created_by,ap_admin.auth_user_id,null,
    case when m.approval_status not in('APPROVED','REJECTED') then 'MEDIA_APPROVAL' end,case when m.approval_status not in('APPROVED','REJECTED') then 'OPEN MEDIA REVIEW' end,
    jsonb_build_object('lot_no',m.lot_no,'status',m.approval_status,'sender_name','Packing Media','receiver_name',ap_admin.full_name,
      'action_href','real-lot-media-ai-v808.html?lot='||m.lot_no,'action_engine','EXISTING MEDIA AI WORKFLOW'),m.created_at
  from public.rr_media_ai_flow_v808 m left join active_profile ap_admin on ap_admin.role_code='ADMIN'

  union all select 'MEDIA_AI_AUDIT:'||a.id,'MEDIA_AI',a.id::text,upper(a.event_type),'PACKING',a.actor_user_id,null,null,null,null,
    jsonb_build_object('lot_no',a.lot_no,'status',a.event_type,'sender_name','Media Workflow','details',a.details),a.event_at
  from public.rr_media_ai_audit_v808 a

  union all select 'DESPATCH:'||d.id,'DESPATCH',d.id::text,'DESPATCH_'||upper(d.status),'PACKING',d.sent_by,d.received_by,null,
    case when d.status not in('RECEIVED','CANCELLED') then 'RECEIVE_DESPATCH' end,case when d.status not in('RECEIVED','CANCELLED') then 'OPEN STORE RECEIVE' end,
    jsonb_build_object('lot_no',d.challan_no,'status',d.status,'sender_name','Despatch Team','action_href','real-finished-goods-v787.html?view=receive','action_engine','rr_fg_receive_despatch_v7981'),d.sent_at
  from public.rr_fg_despatch_v787 d

  union all select 'DESPATCH_ACCEPTANCE:'||a.despatch_id,'DESPATCH',a.despatch_id::text,
    case when a.finalized then 'DESPATCH_ACCEPTANCE_FINALIZED' when a.receiver_accepted and a.depositor_accepted then 'DESPATCH_DUAL_ACCEPTED'
      when a.receiver_accepted then 'DESPATCH_RECEIVER_ACCEPTED' else 'DESPATCH_ACCEPTANCE_PENDING' end,
    'PACKING',coalesce(a.depositor_by,a.receiver_by),null,null,
    case when not a.finalized then 'COMPLETE_DESPATCH_ACCEPTANCE' end,case when not a.finalized then 'OPEN ACCEPTANCE' end,
    jsonb_build_object('lot_no',d.challan_no,'status',case when a.finalized then 'FINALIZED' else 'PENDING' end,'sender_name','Despatch Custody',
      'action_href','real-finished-goods-v787.html?view=receive','action_engine','EXISTING DESPATCH ACCEPTANCE WORKFLOW','remarks',a.remarks),a.updated_at
  from public.rr_fg_despatch_acceptance_v9356 a join public.rr_fg_despatch_v787 d on d.id=a.despatch_id

  union all select 'PI_CPI:'||p.id||':'||g.dept,'SALES',p.id::text,'SALE_'||upper(p.status),g.dept,p.created_by,null,null,
    case when p.status='DRAFT' then 'OPEN_PI' when p.status='CI_FINAL' and not p.qty_verified then 'VERIFY_CPI_QTY' end,
    case when p.status='DRAFT' then 'OPEN PI' when p.status='CI_FINAL' and not p.qty_verified then 'VERIFY QTY' end,
    jsonb_build_object('pi_no',p.pi_no,'lot_no',coalesce(p.cpi_no,p.pi_no),'qty',0,'rate',p.grand_total,'status',p.status,'sender_name','Sales Team',
      'action_href','real-finished-goods-v787.html?view='||case when p.status='CI_FINAL' and not p.qty_verified then 'verify' else 'sale' end,
      'action_engine','rr_fg_save_pi_v787 / rr_fg_verify_cpi_qty_v787'),p.created_at
  from public.rr_fg_pi_v787 p cross join (values('SALES'),('ACCOUNTS')) g(dept)

  union all select 'SALES_RETURN:'||r.id||':'||g.dept,'SALES_RETURN',r.id::text,'SALES_RETURN_POSTED',g.dept,r.received_by,null,null,null,null,
    jsonb_build_object('return_no',r.return_no,'lot_no',r.lot_no,'qty',r.qty,'rate',r.rate,'status','POSTED','sender_name','Returns Team'),r.received_at
  from public.rr_fg_returns_v787 r cross join (values('SALES'),('ACCOUNTS')) g(dept)

  union all select 'RCI:'||r.id||':'||g.dept,'RCI',r.id::text,'RCI_'||upper(r.status),g.dept,
    coalesce(r.reversed_by,r.posted_by,r.created_by),null,null,
    case when r.status='DRAFT' then 'OPEN_RCI' end,case when r.status='DRAFT' then 'OPEN RCI' end,
    jsonb_build_object('rci_no',r.rci_no,'lot_no',r.rci_no,'qty',r.total_qty,'rate',r.total_amount,'status',r.status,
      'sender_name','Returns / RCI Team','action_href','real-finished-goods-v787.html?view=returns','action_engine','rr_rci_finalize_v9740'),r.created_at
  from public.rr_rci_v9740 r cross join (values('SALES'),('ACCOUNTS')) g(dept)

  union all select 'RCI_ACCOUNTS:'||a.rci_id,'RCI_ACCOUNTS',a.rci_id::text,'RCI_ACCOUNTS_'||upper(a.status),'ACCOUNTS',null,ap_admin.auth_user_id,null,
    case when a.status not in('POSTED','REVERSED') then 'POST_RCI_ACCOUNTS' end,case when a.status not in('POSTED','REVERSED') then 'POST RCI TO ACCOUNTS' end,
    jsonb_build_object('rci_no',a.rci_no,'lot_no',a.rci_no,'rate',a.total_amount,'status',a.status,'sender_name','RCI Workflow','receiver_name',ap_admin.full_name,
      'message',a.message,'action_href','real-accounts-suite-v857.html','action_engine','rr_accounts_post_rci_v9754'),a.updated_at
  from public.rr_rci_accounts_link_v9754 a left join active_profile ap_admin on ap_admin.role_code='ADMIN'

  union all select 'RRQ_LEDGER:'||q.id,'RRQ',q.id::text,upper(q.event_type),'ACCOUNTS',q.created_by,ap_admin.auth_user_id,null,null,null,
    jsonb_build_object('lot_no',q.lot_no,'qty',q.qty,'rate',q.new_rate,'status','POSTED','sender_name','RRQ Workflow','receiver_name',ap_admin.full_name,
      'previous_rate',q.previous_rate,'quota_delta',q.quota_delta,'balance_after',q.balance_after,'reason',q.reason),q.created_at
  from public.rrq_rate_ledger_v9300 q left join active_profile ap_admin on ap_admin.role_code='ADMIN'

  union all select 'PAYROLL_RUN:'||r.id,'MONTHLY_PAYROLL',r.id::text,'PAYROLL_'||upper(r.status),'ACCOUNTS',
    coalesce(r.reopened_by,r.approved_by,r.calculated_by),ap_admin.auth_user_id,null,
    case when r.status in('CALCULATED','DRAFT') then 'APPROVE_PAYROLL' end,case when r.status in('CALCULATED','DRAFT') then 'APPROVE PAYROLL' end,
    jsonb_build_object('lot_no',to_char(r.period_month,'YYYY-MM'),'qty',r.worker_count,'rate',r.net_total,'status',r.status,
      'sender_name','Payroll','receiver_name',ap_admin.full_name,'allowed_roles',jsonb_build_array('OWNER','ADMIN','ACCOUNTS'),
      'action_href','real-attendance-salary-v778.html','action_engine','rr_payroll_approve_v778 / rr_payroll_reopen_v778'),r.created_at
  from public.rr_payroll_runs_v778 r left join active_profile ap_admin on ap_admin.role_code='ADMIN'

  union all select 'PAYROLL_LINE:'||l.id,'MONTHLY_PAYROLL',l.id::text,'MONTHLY_PAYROLL_CALCULATED',l.department_code,
    r.calculated_by,w.linked_auth_user_id,l.worker_id,null,null,
    jsonb_build_object('lot_no',to_char(r.period_month,'YYYY-MM'),'qty',l.present_days,'rate',l.net_pay,
      'status',r.status,'sender_name','Payroll','worker_name',l.worker_name,'receiver_name',l.worker_name,'privacy','FINANCIAL'),l.created_at
  from public.rr_payroll_run_lines_v778 l join public.rr_payroll_runs_v778 r on r.id=l.payroll_run_id
  left join public.rr_worker_directory_unified_v1 w on w.worker_id=l.worker_id

  union all select 'SALARY_PAYMENT:'||l.id,'SALARY_PAYMENT',l.id::text,'SALARY_PAYMENT_'||upper(b.status),l.department_code,
    coalesce(b.voided_by,b.created_by),w.linked_auth_user_id,l.worker_id,null,null,
    jsonb_build_object('lot_no',coalesce(b.voucher_no,to_char(b.payment_date,'YYYY-MM-DD')),'qty',0,'rate',l.amount_paid,
      'status',b.status,'sender_name',coalesce(b.voided_by_name,b.created_by_name,'Accounts'),'worker_name',l.worker_name,
      'receiver_name',l.worker_name,'new_outstanding',l.new_total_outstanding,'privacy','FINANCIAL'),b.created_at
  from public.rr_salary_payment_batch_lines_v785 l join public.rr_salary_payment_batches_v785 b on b.id=l.batch_id
  left join public.rr_worker_directory_unified_v1 w on w.worker_id=l.worker_id

  union all select 'PCS_PAYMENT:'||l.id,'PCS_PAYROLL',l.id::text,'PCS_PAYMENT_'||upper(b.status),l.department_code,
    coalesce(b.voided_by,b.created_by),w.linked_auth_user_id,l.worker_id,null,null,
    jsonb_build_object('lot_no',coalesce(b.voucher_no,to_char(b.payment_date,'YYYY-MM-DD')),'qty',0,'rate',l.amount_paid,
      'status',b.status,'sender_name',coalesce(b.voided_by_name,b.created_by_name,'Accounts'),'worker_name',l.worker_name,
      'receiver_name',l.worker_name,'new_outstanding',l.new_outstanding,'privacy','FINANCIAL'),b.created_at
  from public.rr_pcs_payment_batch_lines_v784 l join public.rr_pcs_payment_batches_v784 b on b.id=l.batch_id
  left join public.rr_worker_directory_unified_v1 w on w.worker_id=l.worker_id

  union all select 'ATTENDANCE:'||a.id,'ATTENDANCE',a.id::text,'ATTENDANCE_'||upper(a.status),coalesce(w.department_code,'ADMIN'),
    coalesce(a.updated_by,a.created_by),w.linked_auth_user_id,a.worker_id,null,null,
    jsonb_build_object('lot_no',a.attendance_date::text,'qty',0,'status',a.status,'sender_name','Attendance',
      'worker_name',w.worker_name,'receiver_name',w.worker_name,'revision_no',a.revision_no,'privacy','PERSONAL'),a.created_at
  from public.rr_attendance_day_v778 a left join public.rr_worker_directory_unified_v1 w on w.worker_id=a.worker_id

  union all select 'PAYROLL_PROFILE_EVENT:'||e.event_id,'WORKER_PAYROLL',e.event_id::text,upper(e.event_type),coalesce(w.department_code,'ADMIN'),
    e.actor_auth_user_id,w.linked_auth_user_id,e.worker_id,null,null,
    jsonb_build_object('lot_no','WORKER SETUP','qty',0,'status',e.event_type,'sender_name',e.actor_name,
      'worker_name',w.worker_name,'receiver_name',w.worker_name,'reason',e.reason,'privacy','FINANCIAL'),e.created_at
  from public.rr_worker_payroll_profile_events_v777_2 e left join public.rr_worker_directory_unified_v1 w on w.worker_id=e.worker_id

  union all select 'ACCOUNT_TRANSACTION:'||a.id,'ACCOUNTS',a.id::text,'ACCOUNT_'||upper(a.transaction_type)||'_'||upper(a.status),'ACCOUNTS',
    a.created_by,ap_admin.auth_user_id,null,null,null,
    jsonb_build_object('lot_no',a.voucher_no,'rate',a.total_amount,'status',a.status,'sender_name','Accounts',
      'receiver_name',ap_admin.full_name,'transaction_type',a.transaction_type,'source_module',a.source_module,
      'bill_no',a.bill_no,'narration',a.narration,'privacy','FINANCIAL'),a.created_at
  from public.rr_account_transactions_v805 a left join active_profile ap_admin on ap_admin.role_code='ADMIN'

  union all select 'ADVANCE_PAYMENT:'||l.id,'SALARY_PAYMENT',l.id::text,'ADVANCE_PAYMENT_'||upper(b.status),l.department_code,
    b.created_by,w.linked_auth_user_id,l.worker_id,null,null,
    jsonb_build_object('lot_no',coalesce(b.voucher_no,b.payment_date::text),'rate',l.new_advance_amount,'status',b.status,
      'sender_name',b.created_by_name,'worker_name',l.worker_name,'receiver_name',l.worker_name,
      'updated_advance_balance',l.updated_advance_balance,'privacy','FINANCIAL'),b.created_at
  from public.rr_advance_payment_batch_lines_v785 l join public.rr_advance_payment_batches_v785 b on b.id=l.batch_id
  left join public.rr_worker_directory_unified_v1 w on w.worker_id=l.worker_id

  union all select 'COMMITTEE_PAYMENT:'||c.id,'ACCOUNTS',c.id::text,'COMMITTEE_PAYMENT_'||upper(c.status),'ACCOUNTS',
    coalesce(c.reversed_by,c.updated_by,c.created_by),ap_admin.auth_user_id,null,null,null,
    jsonb_build_object('lot_no',c.payment_no,'rate',c.amount,'status',c.status,'sender_name','Committee Accounts',
      'receiver_name',ap_admin.full_name,'payment_mode',c.payment_mode,'privacy','FINANCIAL'),c.created_at
  from public.rr_committee_payments_v824 c left join active_profile ap_admin on ap_admin.role_code='ADMIN'

  union all select 'NOTIFICATION:'||n.id,'NOTIFICATION',n.id::text,'NOTIFICATION',upper(coalesce(n.department_code,n.role_code,'ADMIN')),
    null,p.auth_user_id,null,'OPEN_NOTIFICATION',upper(n.title),
    jsonb_build_object('lot_no',coalesce(n.title,'Notification'),'status',case when n.is_read then 'READ' else 'PENDING' end,
      'sender_name','Workflow','receiver_name',p.full_name,'message',n.message,
      'action_href',case when lower(coalesce(n.department_code,''))='packing' then 'real-finished-goods-v787.html?view=packing' else 'real-dashboard.html' end,
      'action_engine','EXISTING NOTIFICATION TARGET'),n.created_at
  from public.rr_notifications n left join public.rr_user_profiles p on p.id=n.user_id
)
select canonical_key,module,record_id,event_type,upper(dept) department_code,sender_user,receiver_user,receiver_worker,
  action_code,action_label,payload personal_payload,payload - 'message' group_payload,
  case when receiver_worker is not null then 'test70-cb-purchase-real-chat-pilot.html?chat=personal&worker_id='||receiver_worker
       else 'test70-cb-purchase-real-chat-pilot.html?chat=group&department='||upper(dept) end deep_link,
  coalesce(sent_at,now()) sent_at from events;

create or replace function public.rr_real_chat_sync_e2e_events_v71(p_key text default null)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer;
begin
  insert into public.rr_real_chat_message_bridge_v70(canonical_key,source_module,source_record_id,source_event_type,department_code,
    sender_user_id,receiver_user_id,receiver_worker_id,action_code,action_label,personal_payload,group_payload,deep_link,sent_at)
  select canonical_key,module,record_id,event_type,department_code,sender_user,receiver_user,receiver_worker,action_code,action_label,
    personal_payload,group_payload,deep_link,sent_at from public.rr_real_chat_e2e_event_source_v71 where p_key is null or canonical_key like p_key||'%'
  on conflict(canonical_key) do update set source_event_type=excluded.source_event_type,receiver_user_id=excluded.receiver_user_id,
    receiver_worker_id=excluded.receiver_worker_id,action_code=excluded.action_code,action_label=excluded.action_label,
    personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,deep_link=excluded.deep_link,sent_at=excluded.sent_at
  where public.rr_real_chat_message_bridge_v70.source_module=excluded.source_module;
  get diagnostics n=row_count;
  insert into public.rr_real_chat_receipts_v70(message_id,receiver_key,receiver_user_id,receiver_worker_id)
  select id,case when receiver_worker_id is not null then 'WORKER:'||receiver_worker_id else 'USER:'||receiver_user_id end,receiver_user_id,receiver_worker_id
  from public.rr_real_chat_message_bridge_v70 where receiver_user_id is not null and (p_key is null or canonical_key like p_key||'%')
  on conflict(message_id,receiver_key) do update set receiver_user_id=excluded.receiver_user_id;
  return n;
end $$;
revoke all on function public.rr_real_chat_sync_e2e_events_v71(text) from public,anon;
grant execute on function public.rr_real_chat_sync_e2e_events_v71(text) to authenticated;

create or replace function public.rr_real_chat_e2e_trigger_v71() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare k text;
begin
  k:=case tg_table_name
    when 'rr_cb_purchase_entries' then 'CB_PURCHASE:'||new.id
    when 'rr_matching_purchase_entries' then 'MATCHING_PURCHASE:'||new.id
    when 'rr_cutting_cb_actions' then 'CUTTING_ACTION:'||new.id
    when 'rr_cb_art_assignments' then 'PRODUCT_DECISION:'||new.id
    when 'rr_cb_print_assignments' then 'PRODUCT_DECISION:'||new.assignment_id
    when 'rr_cb_sticker_assignments' then 'PRODUCT_DECISION:'||new.assignment_id
    when 'rr_cb_metal_id_assignments_v801' then 'PRODUCT_DECISION:'||new.assignment_id
    when 'rr_upm_lot_registry' then 'LOT_RELEASE:'||new.id
    when 'rr_upm_rate_requests_v760' then 'RATE_REQUEST:'||new.id
    when 'rr_upm_department_rate_log_v2' then 'DEPARTMENT_RATE_LOG:'||new.id
    when 'rr_upm_assignment_rate_log_v772' then 'ASSIGNMENT_RATE_LOG:'||new.id
    when 'rr_fg_packing_assignments_v788' then 'PACK_ASSIGNMENT:'||new.id
    when 'rr_pack_rate_approval_v9340' then 'PACK_RATE:'||new.id
    when 'rr_media_ai_flow_v808' then 'MEDIA_AI:'||new.id
    when 'rr_media_ai_audit_v808' then 'MEDIA_AI_AUDIT:'||new.id
    when 'rr_fg_despatch_v787' then 'DESPATCH:'||new.id
    when 'rr_fg_despatch_acceptance_v9356' then 'DESPATCH_ACCEPTANCE:'||new.despatch_id
    when 'rr_fg_pi_v787' then 'PI_CPI:'||new.id
    when 'rr_fg_returns_v787' then 'SALES_RETURN:'||new.id
    when 'rr_rci_v9740' then 'RCI:'||new.id
    when 'rr_rci_accounts_link_v9754' then 'RCI_ACCOUNTS:'||new.rci_id
    when 'rrq_rate_ledger_v9300' then 'RRQ_LEDGER:'||new.id
    when 'rr_payroll_runs_v778' then 'PAYROLL_RUN:'||new.id
    when 'rr_payroll_run_lines_v778' then 'PAYROLL_LINE:'||new.id
    when 'rr_salary_payment_batch_lines_v785' then 'SALARY_PAYMENT:'||new.id
    when 'rr_pcs_payment_batch_lines_v784' then 'PCS_PAYMENT:'||new.id
    when 'rr_attendance_day_v778' then 'ATTENDANCE:'||new.id
    when 'rr_worker_payroll_profile_events_v777_2' then 'PAYROLL_PROFILE_EVENT:'||new.event_id
    when 'rr_account_transactions_v805' then 'ACCOUNT_TRANSACTION:'||new.id
    when 'rr_advance_payment_batch_lines_v785' then 'ADVANCE_PAYMENT:'||new.id
    when 'rr_committee_payments_v824' then 'COMMITTEE_PAYMENT:'||new.id
    when 'rr_notifications' then 'NOTIFICATION:'||new.id else null end;
  perform public.rr_real_chat_sync_e2e_events_v71(k);return new;
exception when others then raise warning 'TEST70 E2E chat reconciliation deferred: %',sqlerrm;return new;end $$;

do $$ declare t text; begin
  foreach t in array array['rr_cb_purchase_entries','rr_matching_purchase_entries','rr_cutting_cb_actions','rr_cb_art_assignments',
    'rr_cb_print_assignments','rr_cb_sticker_assignments','rr_cb_metal_id_assignments_v801','rr_upm_lot_registry',
    'rr_upm_rate_requests_v760','rr_upm_department_rate_log_v2','rr_upm_assignment_rate_log_v772',
    'rr_fg_packing_assignments_v788','rr_pack_rate_approval_v9340','rr_media_ai_flow_v808','rr_media_ai_audit_v808',
    'rr_fg_despatch_v787','rr_fg_despatch_acceptance_v9356','rr_fg_pi_v787','rr_fg_returns_v787','rr_rci_v9740',
    'rr_rci_accounts_link_v9754','rrq_rate_ledger_v9300','rr_payroll_runs_v778','rr_payroll_run_lines_v778',
    'rr_salary_payment_batches_v785','rr_salary_payment_batch_lines_v785','rr_pcs_payment_batches_v784','rr_pcs_payment_batch_lines_v784',
    'rr_attendance_day_v778','rr_worker_payroll_profile_events_v777_2','rr_account_transactions_v805',
    'rr_advance_payment_batches_v785','rr_advance_payment_batch_lines_v785','rr_committee_payments_v824','rr_notifications'] loop
    execute format('drop trigger if exists rr_real_chat_e2e_sync_v71 on public.%I',t);
    execute format('create trigger rr_real_chat_e2e_sync_v71 after insert or update on public.%I for each row execute function public.rr_real_chat_e2e_trigger_v71()',t);
  end loop;
end $$;

select public.rr_real_chat_sync_e2e_events_v71(null);

drop policy if exists rr_rc_bridge_select_v70 on public.rr_real_chat_message_bridge_v70;
create policy rr_rc_bridge_select_v70 on public.rr_real_chat_message_bridge_v70 for select to authenticated using (
  auth.uid() is not null and (
    auth.uid() in (sender_user_id,receiver_user_id)
    or (
      source_module in ('ACCOUNTS','MONTHLY_PAYROLL','SALARY_PAYMENT','PCS_PAYROLL','WORKER_PAYROLL','RCI_ACCOUNTS','RRQ')
      and exists(select 1 from public.rr_user_profiles p where p.auth_user_id=auth.uid() and p.is_active
        and upper(p.role_code) in ('OWNER','ADMIN','ACCOUNTS'))
    )
    or (
      source_module not in ('ACCOUNTS','MONTHLY_PAYROLL','SALARY_PAYMENT','PCS_PAYROLL','WORKER_PAYROLL','RCI_ACCOUNTS','RRQ')
      and (
        public.rr_real_chat_is_global_staff_v70(auth.uid())
        or exists(select 1 from public.rr_worker_directory_unified_v1 w where w.linked_auth_user_id=auth.uid()
          and upper(w.department_code)=upper(rr_real_chat_message_bridge_v70.department_code) and coalesce(w.is_active,true))
        or exists(select 1 from public.rr_real_chat_department_membership_v70 m
          join public.rr_worker_directory_unified_v1 w on w.worker_id=m.worker_id
          where w.linked_auth_user_id=auth.uid() and m.is_active
            and upper(m.department_code)=upper(rr_real_chat_message_bridge_v70.department_code))
      )
    )
  )
);
