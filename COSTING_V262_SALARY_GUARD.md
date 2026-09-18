# Costing V262 — Salary allocation guard
Salaried Cost must never be guessed.
Before department/common allocation, every SALARIED payroll worker must resolve to the canonical worker directory with a real department and role.
If any salaried payroll row is unmapped, allocation status is BLOCK_ALLOCATION_UNTIL_CANONICAL_MAPPING.
This prevents Factory/Production salary from silently flowing into Readymade/Trading or the wrong department.
Production departments use their canonical production driver. Sales/Accounts/Admin/common support require an explicit business-scope driver before activation.
TEST keeps real incomplete data visible; no fake mapping or normalized salary is inserted.
