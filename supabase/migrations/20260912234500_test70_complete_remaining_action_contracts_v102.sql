-- TEST70 V102: finish the two pre-existing registry rows that predate the
-- canonical action contract. Existing engines remain authoritative.
begin;

update public.rr_real_chat_action_registry_v70
set parent_type='LOT',source_state='WORKING',success_state='WORKING',
    next_action_code='SUBMIT',receiver_rule='EXACT_DEPARTMENT_MANAGER',
    unit_label='RATE / PCS',message_template='{department_name} rate saved for Lot {lot_no}.',
    rollback_rule='Existing department-rate correction audit.',updated_at=now()
where action_code='DEPARTMENT_RATE';

update public.rr_real_chat_action_registry_v70
set parent_type='LOT',source_state='WORKING',success_state='WORKING',
    next_action_code='PACKING_SUBMIT',receiver_rule='EXACT_ADMIN_RRQ_QUEUE',
    unit_label='RATE / PCS',message_template='Final sale rate / RRQ opened for Lot {lot_no}.',
    rollback_rule='Existing Packing RRQ review and approval rules.',updated_at=now()
where action_code='FINAL_SALE_RATE_RRQ';

commit;
