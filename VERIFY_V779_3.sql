
select jsonb_build_object(
  'dispute_table',
    to_regclass('public.rr_payroll_disputes_v779_3') is not null,

  'payslip_request_table',
    to_regclass('public.rr_payroll_payslip_requests_v779_3') is not null,

  'access_guard_rpc',
    to_regprocedure(
      'public.rr_payroll_can_view_worker_v779_3(uuid)'
    ) is not null,

  'my_history_rpc',
    to_regprocedure(
      'public.rr_get_my_payroll_history_v779_3(integer,text)'
    ) is not null,

  'summary_rpc',
    to_regprocedure(
      'public.rr_get_payroll_summary_v779_3(uuid)'
    ) is not null,

  'section_details_rpc',
    to_regprocedure(
      'public.rr_get_payroll_section_details_v779_3(uuid,text)'
    ) is not null,

  'raise_dispute_rpc',
    to_regprocedure(
      'public.rr_raise_payroll_dispute_v779_3(uuid,text,text,jsonb)'
    ) is not null,

  'resolve_dispute_rpc',
    to_regprocedure(
      'public.rr_resolve_payroll_dispute_v779_3(uuid,text,text)'
    ) is not null,

  'management_board_rpc',
    to_regprocedure(
      'public.rr_get_payroll_management_board_v779_3(date,text)'
    ) is not null,

  'pdf_payload_rpc',
    to_regprocedure(
      'public.rr_get_payslip_payload_v779_3(uuid)'
    ) is not null,

  'whatsapp_payload_rpc',
    to_regprocedure(
      'public.rr_get_whatsapp_payslip_payload_v779_3(uuid)'
    ) is not null

) as rr_upm_v779_3_verify;
