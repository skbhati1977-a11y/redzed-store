# V294 Canonical Salary Pools
Canonical payroll identity is resolved through rr_canonical_worker_id_v264 before salary allocation. Legacy alias profiles cannot double count the same worker; Shailender resolves to one canonical worker/profile.

Salary pools:
- Production department pools: PRINTING, STICKER, KAJ_BUTTON, QC.
- STAFF_SUPPORT pool: Fabrication staff (Manager/Line Man) plus Admin/Accounts/Sales salaried staff currently mapped in payroll.
Department salary / department period production PCS = department salaried cost/PCS.
Support salary / company period cutting production PCS = support salaried cost/PCS.

September TEST verification:
PRINTING salary 45,000 / 684 PCS = 65.789474/PCS.
STAFF_SUPPORT salary 129,000 / 972 PCS = 132.716049/PCS.
KAJ_BUTTON/QC/STICKER currently have zero TEST production denominator, therefore their rate remains null rather than inventing a cost.
No fake zero is generated for an unavailable denominator.
RPC: rr_costing_salary_pool_v294.
