-- Read-only audit checks. No business mutations.
with duplicates as (
 select source_module,source_record_id,data_mode,count(*) n
 from public.rr_account_transactions_v805
 where status='POSTED' and source_record_id is not null
 group by 1,2,3 having count(*)>1
), invalid_postings as (
 select t.id from public.rr_account_transactions_v805 t
 left join public.rr_account_postings_v805 p on p.transaction_id=t.id
 group by t.id having count(p.id)<2 or abs(coalesce(sum(p.dr_amount-p.cr_amount),0))>0.005
)
select 'duplicate_active_sources' check_name,count(*) n from duplicates
union all select 'unbalanced_or_missing_postings',count(*) from invalid_postings
union all select 'active_source_links_missing_transaction',count(*)
from public.rr_account_source_links_v806 l left join public.rr_account_transactions_v805 t on t.id=l.account_transaction_id
where l.status='ACTIVE' and t.id is null;

select operation_status,count(*) purchases,sum(bill_value) bill_value,
count(*) filter(where public.rr_source_data_mode_get_v806('MATCHING_CLOTH_PURCHASE',id::text) is null) untagged
from public.rr_mc1_purchases where coalesce(entry_kind,'PURCHASE')='PURCHASE' group by operation_status;

select count(*) rows,round(sum(total_debit),2) debit,round(sum(total_credit),2) credit,
round(sum(total_debit-total_credit),2) difference
from public.rr_trial_balance_v806('2026-01-01','2026-10-10','TEST');

-- Anonymous exposure proof: aggregate only; transaction is rolled back.
begin;
set local role anon;
select count(*) accessible_trial_balance_rows
from public.rr_trial_balance_v806('2026-01-01','2026-10-10','TEST');
rollback;
