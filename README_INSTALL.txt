REDZED STORE — DYNAMIC DEPARTMENT + MULTI-SKILL WORKER + COLOUR-BOUND UPM FLOW

IMPORTANT
- Web filenames are intentionally unchanged.
- Version is written only in the Git commit message.
- Do not upload the BACKUP_BEFORE_UPDATE folder.

FILES TO UPDATE IN REPOSITORY ROOT
1. real-role-permission-v72054.html
2. real-role-permission-v72054.js
3. real-universal-production-v726.html
4. real-universal-production-v726.js

SUPABASE SQL
Run once in Supabase SQL Editor:
REDZED_DYNAMIC_DEPARTMENT_AND_UPM_FLOW.sql

INSTALL ORDER
1. Back up the four current web files.
2. Run REDZED_DYNAMIC_DEPARTMENT_AND_UPM_FLOW.sql completely.
3. Upload/replace the four web files above with the same filenames.
4. Commit using the message in COMMIT_MESSAGE.txt.
5. Hard refresh browser/cache.

WHAT IS IMPLEMENTED

A. DEPARTMENT MASTER — inside existing Role & Permission file
- New Department Master tab.
- Create future departments without changing filenames.
- Permanent department_code; display name/order/capabilities can be edited.
- Parent department and permission-template copy.
- Auto mapping to:
  * Role & Permission field matrix
  * Action matrix
  * User role/department selector
  * Worker Skills
  * rr_upm_departments
- No hard delete. Archive is blocked while active UPM assignments exist.

B. KAAJ / BUTTON ARCHITECTURE
- Kaaj and Button / BTN remain separate departments/processes.
- One worker may have Kaaj as Primary and Button as additional Skill, or vice versa.
- The same worker then appears in both UPM department worker dropdowns.
- Different workers can still be used for Kaaj and Button when required.

C. UPM ASSIGNMENT LOCK
- Permanent assignment unit: Lot + Department + complete Colour.
- Every Cutting size belonging to that Colour is permanently bound together.
- No size can be assigned to another worker separately.
- One Colour, multiple Colours, or ALL open Colours can be selected.
- Select All + one Bulk Worker + Assign Selected supports all-colour one-flow assignment.
- Backend verifies full Cutting size_breakup and full Cutting colour total before assignment.

D. DEPARTMENT FLOW GATE
- A downstream department cannot assign a Colour before upstream Submit.
- Department sequence_no controls the next department.
- Submit is Colour-level and processes all sizes together.
- On Submit, every size's remaining direct Pending becomes Good automatically.
- Open Alter/Remake is excluded from that Submit and remains in the current department.
- Submitted Good quantity opens the same Colour in the next department.
- Repaired/remade quantity can be submitted later; an already completed downstream assignment is reopened automatically for the new inbound quantity.

E. ACTIONS
- Register Alter: Pending -> Alter Open.
- Issue Remake: Alter Open -> Remake Open.
- Complete Remake: Remake Open -> Good / Ready Submit.
- Damage: can be taken from Pending, Alter, or Remake with server balance validation.
- Reassign Direct Pending: preserves completed worker history; Alter/Remake must be resolved first.
- Submit Selected Colours: all sizes together, non-Alter balance only.

F. DEBUG / SAFETY
- Single Lot mapping: rr_cutting_lots_v3 + rr_cutting_breakup_v3.
- Multi Lot mapping: rr_production_lots + rr_production_lot_breakup_v3.
- Colour identity uses cb_colour_id when available.
- Batch actions run transactionally in Supabase RPC.
- Request IDs prevent duplicate action posting.
- Flow Debug reports mapping, workers, assignments, handoffs and waiting rows.

VERIFICATION

1. Department console:
select public.rr_owner_department_console_v2();

2. Cutting map:
select * from public.rr_upm_verify_cutting_map_v726('YOUR-LOT-NO');

3. Full flow debug:
select public.rr_upm_debug_lot_flow_v726('YOUR-CANONICAL-LOT-ID','STITCHING');

4. Handoff ledger:
select * from public.rr_upm_handoff_ledger_v727
where canonical_lot_id='YOUR-CANONICAL-LOT-ID'
order by created_at;

STATIC CHECKS PERFORMED
- Both JavaScript files pass node --check.
- HTML files have no duplicate element IDs.
- Required RPC/function names and one final SQL COMMIT are present.

LIVE DATABASE NOTE
The package is built against the uploaded REDZED schema/code files. Run the SQL in a test Supabase project or transaction-safe staging copy first because this environment cannot execute against your live Supabase database.
