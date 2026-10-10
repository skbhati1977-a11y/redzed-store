# TEST71 — सभी modules की Accounts wiring और mapping audit

**Latest status: full audit sign-off NOT COMPLETE.** 132 scenario rows: 85 PASS, 23 FAIL, 5 BLOCKED, 19 NOT_RUN। Current scenario matrix is authoritative; baseline findings below are retained, with fix continuation tracked separately; earlier completion wording superseded है। प्रत्येक PASS केवल लिखे हुए check का है।

दिनांक: 10 October 2026, Asia/Kolkata. Repository: redzed-store; branch: test71-real-chat-e2e-finalization; inspected HEAD: 18b89ccfe55dd8ecb22411905c303f1083bd7423. Database: hruartsemierwhtzonei.

## निर्णय

**अभी universal clean chit नहीं दी जा सकती। नया उपलब्ध business data इसी TEST database में import करने के लिए अभी तैयार नहीं है।** नीचे प्रमाणित financial, permission और isolation gaps हैं। खाली attendance records failure नहीं हैं: वर्तमान data app-design fixtures है। Business actions, database definitions, live records, grants/policies, reporting queries और targeted tests के evidence पर यह निष्कर्ष है।

इस audit में production/main नहीं बदले गए। कोई पुराने records delete/archive/repost नहीं किए गए। Readymade business test transaction ROLLBACK हुआ। SQL read checks elevated database context में हुए; anonymous report access अलग SET LOCAL ROLE anon से प्रमाणित किया गया। यह report code/database audit है; सभी roles के browser/device end-to-end completion का प्रमाण नहीं है।

## प्रमाणित अच्छे checks

| Check | परिणाम |
|---|---|
| Account transactions | 344 total; 319 POSTED |
| Active source की duplicate POSTED transactions | 0 |
| दो posting lines से कम या unbalanced transaction | 0 |
| ACTIVE source link का missing transaction | 0 |
| ACTIVE link का non-POSTED transaction | 0 |
| Posted ledger की missing report mapping | 0 |
| Reporting base में एक posting की multiple report rows | 0 |
| Positive Final CI का missing FG_CPI posting | 0 |
| Positive POSTED RCI का missing RCI posting | 0 |
| Eligible Sticker/Metal ID purchase का missing mirror | 0 |
| Positive POSTED Readymade purchase का missing mirror | 0 |
| Trial Balance, 1 Jan–10 Oct 2026 TEST | Debit = Credit = ₹3,27,98,426.72; difference ₹0 |
| Balance Sheet, 10 Oct 2026 TEST | difference ₹0; balanced=true |

इन balances में काल्पनिक fixtures शामिल हैं। Balanced report से omitted business transactions, गलत effective date, गलत classification या incomplete payroll सही साबित नहीं होते।

## Module-wise mapping और status

| Module/feature | Live wiring/evidence | Audit status और जरूरी काम |
|---|---|---|
| CB Regular Cloth | Entry trigger → mode tag → regular-cloth mirror → purchase debit/supplier credit; 87 posted purchase records; return और damage sources भी मिले | Bridge retain करें। Draft/confirm timing, edited bill, multiple purchase-entry scopes और pending financial actions का अलग lifecycle proof अभी चाहिए। |
| CB Weight Short/Excess | Confirm reconciliation → purchase return debit / excess credit note | Function मौजूद; सभी decision branches का fresh rollback proof बाकी। Caller-supplied mode को source mode से enforce करना चाहिए। |
| MC1 Matching Cloth | Current purchase v3 → MC stock/account/fabric ledger; supplier ID मिलता है | **गंभीर gap:** purchase v3 Accounts mirror और mode tag नहीं बुलाता। 30 ACTIVE purchases ₹3,27,080.75 + 1 FULL_GR ₹2,500: सभी 31 untagged और matching Accounts purchase mirror अनुपस्थित। Returned record को outstanding मानकर repost न करें। |
| Sticker/Metal ID | Purchase writers → accessory mirror; stock sync triggers | Existing eligible purchases के missing mirrors 0। Retain; adjustment/GR/return/exchange के सभी branches का fresh proof बाकी। |
| अन्य material purchases | Material purchase function → quantity conversion → paid/credit split → balanced Accounts transaction | Structure मौजूद। Paid/partial/credit, tax, source duplicate, rounding और stock-consumption reversal का complete fresh matrix बाकी। |
| Cutting, Fabrication, Printer, Stitching/Karigar, Overlock, Folding, Kaaj/Btn, Teak/Tanki, Thread Cut, QC, Press | Shared production/payroll/costing engines; salary final gate और reconciliation v401/v402/v403 मौजूद | Per department submit/alter/rectify/short/damage से earned salary, claim और lot cost की exact source linkage का full live E2E proof बाकी। Workflow completion अपने आप salary payment या cash posting नहीं है। |
| Packing/Despatch | Costing final salary gate और existing final CI/stock engines | Salary accrual boundary, packed/dispatch quantities, unsold stock और sale cost reconciliation का fixture matrix चाहिए। कोई additional sale posting केवल packing पर न बने। |
| Attendance | Manual v778 save/run UI; separate raw-event, regular-session और v777 daily engines | Worker personal check-in/out → approved daily record → authoritative payroll chain पूरी तरह wired नहीं मिली। Reminder generator मौजूद, delivery/scheduler नहीं मिला। |
| Monthly Payroll | v778 payroll runs और v779 monthly snapshots दोनों; legacy run → worker salary ledger hook | Parallel authorities reconcile किए बिना retain करना जोखिम है। v779 safe generation में एक approved day पर्याप्त है; complete active-period coverage/review gate नहीं मिला। |
| Salary payment / advances | v781 worker salary ledger; v785/v786 batch payment और advance recovery | Subledger updates मौजूद। v779 personal payroll PAYMENT केवल settlement/payroll/event बदलता है; ledger/cash Accounts bridge नहीं मिला। v785/v786 worker salary postings भी general Accounts mapping से अलग हैं। |
| Readymade Purchase/receipt | Party bill → original purchase; received PCS → stock; shortage/excess → DR/CR note | **Fresh rollback PASS:** Short/Excess/Matched, draft edit, supplier value, stock, P&L/BS/TB deltas, balanced journals, retries, purchase return, invalid-input rollback, receipt anonymous denial। TEST-only guards retain। |
| Readymade Sales/returns | Shared final CI bridge; RM known return trigger; purchase return stock + Accounts | Current final CI/RCI records mapped। All sale/return/RCI/cancel scenarios fresh browser+SQL E2E अभी नहीं हुए। |
| Readymade overheads | rr_rm_overhead_save_test71 → cost expense pool only | Cost allocation input और actual business expense अलग रखें। इस action से Accounts expense/payment posting नहीं बनती; paid business expense के लिए source link चाहिए। |
| Market Window/PI | Collection/requirements/PI working flows; financial sale function CI_FINAL पर ही | PI को final sale मानकर ledger न बनाएं। Reserve/release/finalize/return exact stock-date proof बाकी। |
| CI/RCI | Final CI → customer debit/sales credit; RCI → sales return debit/customer credit; source links/triggers | Existing positive finalized/posted documents के missing mirrors 0। Existing exceptions ERROR/PENDING ledger mapping बन सकते हैं; universal Accounts Open को यह backlog उठाना चाहिए। |
| Receipts/Payments/Journal | Backend balanced posting wrappers और source reversal मौजूद | Counterparty/cash-bank kind checks, allocation against bills, retries, permissions और reversal का role-based fresh E2E बाकी। |
| Committee | Installment/prize/dividend/receive functions और कई posted sources | Retain historical sources; v820/v822/v825/v826 overlap को business obligation IDs से reconcile करें। केवल version संख्या देखकर retire या duplicate घोषित न करें। |
| Reports / Accounts Open | v805/v853 report RPCs; separate v857 generic suite; Open due view | नीचे दिए हुए isolation, date, opening और permission gaps सुधारें। |

## प्रमाणित gaps और प्राथमिकता

### P0 — उपलब्ध business records डालने से पहले

1. **TEST fixtures और नए rehearsal records का isolation नहीं है।** Accounts, Attendance, Monthly Payroll, Worker Salary और RM purchase tables में data_mode है; dataset/workspace scope नहीं मिला। TEST नाम/lot prefix बदलने से reports, masters, notices, caches और balances अलग नहीं होंगे। Recommended: मौजूदा fixture environment सुरक्षित snapshot/freeze करें और उसी code का अलग TEST rehearsal database/environment रखें। Alternative dataset_id तभी जब हर table, join, RPC, unique key, RLS, cache और storage path scoped हो; partial implementation स्वीकार न करें। अभी कोई environment बनाया या data copy नहीं हुआ।

2. **Anonymous financial report access प्रमाणित।** SET LOCAL ROLE anon पर rr_trial_balance_v806 से 69 report rows मिलीं। v807 ledger और day-book/report RPCs में भी anon EXECUTE grants मिले। rr_material_opening_balance_v664 SECURITY DEFINER है, anon execute=true, body में actor guard नहीं है। Opening mutation perform नहीं की गई; code+grant gap है। केवल frontend login या table RLS इसे नहीं रोकते। Privileged RPCs में actor/role/source-scope checks और explicit execute grants लगें। Existing Accounts posting helper की anon invocation denied मिली—पूरे Accounts को unrestricted घोषित करना गलत होगा।

3. **MC1 stock और Accounts अलग हो सकते हैं।** rr_post_mc_fabric_purchase_v3 और current matching UI stock increase करते हैं; mode tagging और mirror call अनुपस्थित। Matching mirror API स्वयं mode tag मांगता है। 31 unmatched records मिले। Fix एक atomic purchase action में mode + source + stock + supplier posting हो। पहले old ACTIVE/FULL_GR/return/exchange reconciliation report; फिर approved targeted backfill।

4. **Salary/advance subledger और general Accounts का एक transaction contract नहीं है।** Monthly v779 payment route settlement और event बदलती है; उसी route में worker salary ledger/general cash posting नहीं मिली। v785/v786 salary/advance functions worker ledgers बदलती हैं; general Accounts posting helper call नहीं मिला। कोई universal automatic bridge भी function dependencies में नहीं मिला। Fixture SALARY_MONTHLY_E2E/SALARY_PCS_E2E journal rows automatic mapping का प्रमाण नहीं। Payroll accrual, payment, advance issue/recovery, reversal को source-ID से exactly once linked करें; repeated request original result लौटाए।

5. **Universal opening/activation contract incomplete।** Material-specific opening function मिला; all-module approved opening batch, cut-off और evidence status का unified model नहीं मिला। Need cash/bank, parties, salary dues, advances, materials, traded/FG/WIP snapshot; UNKNOWN बनाम ZERO बनाम N/A; approval/lock; source evidence; idempotent imports; balance checks; reasoned corrections। पुरानी history उपलब्ध नहीं तो consolidated opening दें; imaginary historical attendance/submit/payment events न बनाएं।

### P1 — daily workflow reliability और correct reporting

6. **Accounts Open universal नहीं है।** rr_accounts_due_v834 केवल TEST Committee dues select करती है; rr_accounts_real_chat_home_v500 OPEN path mode filter नहीं लगाता। Supplier/customer/payroll/CI mapping errors इस Open source में नहीं हैं। New source-derived pending queue में TEST/REAL/rehearsal scope, actor, next action और exact document link चाहिए। Financial outstanding और pending workflow card अलग concepts हैं।

7. **Report effective date गलत month/cut-off में जा सकती है।** Posting function transaction_datetime=now(); report base exposes posting.created_at और reports उसी तारीख से filter करती हैं। 111 transactions में bill_date और transaction date अलग मिले। Backdated bill date जरूरी नहीं हमेशा accounting date हो: अलग approved accounting_date चाहिए, जो reports और cut-off में consistent उपयोग हो।

8. **Ledger statement opening नहीं जोड़ता।** v806 और v807 दोनों selected date window में running sum शून्य से शुरू करते हैं। Prior balance + period movement = closing दिखाएं; opening row/provenance रखें। v807 hidden reversal-pair behavior को v806 reports से reconcile करें। Current reports original REVERSED और inverse POSTED reversal दोनों शामिल करते हैं (केवल VOIDED/CANCELLED exclude)—इसे अकेले bug न कहें; pair netting/date intent verify करें।

9. **Attendance engines split हैं।** Event recorder daily/payroll recalculation नहीं बुलाता; regular-session calculator और raw-event calculator अलग tables/leave sources और rules उपयोग करते हैं। Reminder function regular sessions देखती है, salary approved v777 daily records। One canonical worker/day pipeline; approved correction, checkout review, timezone/shift and activation boundaries; late arrival vs late marking; reason/voice evidence चाहिए। Test gaps पर absence/salary penalty न बनाएँ।

10. **Payroll completeness gate missing।** Safe v779 generator completed month check करता है पर approved attendance count>0 को पर्याप्त मानता है। Active date range के all expected days resolved हों; incomplete checkout/review/leave/holiday रोकें; partial-month start/end सही prorate हो। Rate formulas alone E2E proof नहीं।

11. **Cost pool actual expense/payment नहीं है।** RM overhead action only allocation pool save करता है। Accounting journal/payment और costing allocation source-link रखें; वही expense twice charge न हो। P&L function inspected केवल net purchase, expenses और salaries subtract करती है; closing stock/WIP/COGS bridge इस function में नहीं है। All-module inventory valuation reconciliation के बिना universal profit accuracy certify न करें।

12. **Generic Accounts suite incomplete/misleading।** real-accounts-suite-v857.js select('*').limit(100), no explicit mode filter, error पर fallback raw table, guessed amountOf fields। rr_profit_loss_v857 और rr_balance_sheet_v857 live view inventory में नहीं मिले; canonical v806 report RPCs exist। Fallback को report-success न दिखाएं; server aggregates, pagination, consistent role/mode and accounting dates चाहिए।

## क्या retain करना चाहिए

- Balanced Accounts posting validation, source links और reversal lifecycle/audit trail।
- Readymade bill/receipt atomic reconciliation; original purchase snapshots; fixed margin/privacy and stock safeguards।
- Final CI sale trigger, posted RCI return bridge; draft PI non-posting intent।
- Shared canonical production identity/one-card queues; payroll salary authority और costing allocation separation।
- Existing raw fixture data and valid historical financial entries; पुराने data पर blanket cleanup नहीं।

## क्या retire/consolidate करना चाहिए — verification के बाद

| Candidate | Replacement और शर्त |
|---|---|
| Generic v857 fallback reports | Canonical scoped report RPCs; all inbound links/role screens verified होने पर redirect; history retain। |
| v779 settlement-only PAYMENT route | One payment command → payroll + salary subledger + cash/bank + Accounts; existing payments reconcile; तब old write action disable। |
| Multiple independent attendance/day calculators | One canonical daily engine; same input cases की compared results, old table provenance और approved adjustments preserve। |
| Parallel monthly payroll write authorities | One approved monthly snapshot with adapters for old views; no double accrual; migrated balances verified। |
| Legacy purchase v2 fallback | Correct v3 atomic contract and schema verified; old entry points inventory के बाद disable—not immediate deletion। |
| Hardcoded Committee TEST Open projection | Universal scoped pending-action projection; Committee remains a module contributor। |
| Raw client holiday/financial writes | Guarded validated commands where needed; don't break unrelated tested UI। |
| Obsolete tests | Current lot suggestion/cache key contracts; retain business assertions; don't weaken tests to make PASS। |

Retiring means stop duplicate new writes and route callers to the canonical path; delete old ledger/history नहीं। Usage/dependency inventory और parity tests के बिना कोई version retire नहीं हुई है।

## Implementation क्रम

1. Fixture snapshot/restore proof और isolated rehearsal environment boundary तय करें। यह both TEST रहें; production untouched।
2. Anonymous financial access और opening API permissions close करें; role matrix में positive/negative tests।
3. MC1 तथा salary/advance source posting contracts atomic बनाएं; old-data exception report दें; no blind backfill।
4. Universal opening batch + cut-off + worker effective activation dates; missing detail provisional/unknown explicitly।
5. Attendance → daily approval → payroll → ledger/payment pipeline; pending reminders/card focus; correction/reversal workflow।
6. Accounts universal Open queue and canonical date/opening/report pipeline; expense-cost/stock valuation reconciliation।
7. Department/module scenario matrix, retry/reversal/concurrency and role tests; old callers redirected only after parity।
8. Dry-run available records: row validation, alias/ID match, duplicate report, opening reconciliation; approval then atomic import. Re-running the same batch must not duplicate anything।

## Tests और limits

- Targeted node run: 20 PASS; 1 MC1 asset-version assertion FAIL; 1 receipt test wrong cwd से ENOENT. Receipt test correct parent cwd से 3/3 PASS। Combined successful assertions: 23; MC1 asset assertion unresolved obsolete format (parseInt('TEST71-…') gives NaN), not proof MC1 runtime asset missing। No test source changed।
- Fresh Readymade receipt SQL initially old random lot ID पर continuous lot gate से blocked। Temporary test-only lot assignments changed to rr_rm_lot_hint_test71()->>'suggested_lot'; rerun **PASS**, all fixtures ROLLBACK। Business assertions preserved।
- SQL duplicate/link/posting/report-map and CI/RCI/accessory/RM existing-source checks ऊपर recorded हैं।
- A duplicate-ledger-code grouping initially returned 1 group: further inspection showed five NULL codes, no proven duplicate non-null ledger code। Do not report it as duplicate identity corruption।
- Browser/device all-role walkthrough, offline retry, performance percentile measurements, every department Alter/Rectify and every committee/return/exchange branch not fully executed in this audit. No universal stability/performance clean chit।
- E2E sign-off requires source → stock/subledger → general posting → due → report → reversal assertions, permission-denial checks, concurrent repeat submission, restart/reload, and full opening rehearsal for every applicable module।

**Import readiness: HOLD until P0 gaps fixed and verified. Existing data preserved.**

## Continuation: अंतिम technical audit evidence

यह भाग उसी audit को आगे बढ़ाकर जोड़ा गया है; पिछली जाँच restart नहीं की गई। नीचे PASS backend/code के निर्दिष्ट scope में है। Browser journey अथवा हर branch का PASS उससे अनुमानित नहीं है।

| अतिरिक्त जाँच | परिणाम / प्रमाण |
|---|---|
| 10 Node test files, 44 assertions | 42 PASS; 2 source-contract FAIL। Commercial test old v500 queue string मांगता है जबकि UI canonical test71 queue बुलाता है; compensation test old v769 route मांगता है जबकि UI atomic count context/save बुलाता है। Tests बदले नहीं; current contract पर update आवश्यक। |
| Sales canonical queue parity | OPEN के तीन search cases और WORKING/CLOSE parity PASS; OPEN calls test की 1-second server gate में; unauthenticated तथा PROD scope denied। यह mobile/network latency measurement नहीं। |
| Cutting canonical queue | Ready lifecycle ↔ visible card count ↔ exact unread event/card mapping PASS। |
| Shared Open/Working contract | 13 department projections, 6 assertions PASS: assignment-only Open, submitted work supersession, pending handover visibility, correct last action, atomic Accept & Count → Open, assigned receipt → Worker Submit, unrelated worker denial। Test में rates rollback fixture के लिए ही डाली गईं। |
| Costing adapters | 43 App/Chat costing totals match; 39 BOM quantity/rate mappings match; 100 worker/direct pending adapters match। 4 category-unmapped lots: 2615, 2634, 2613, 2614 (Art test03)। |
| Rate authority checkpoint 4 | PASS: first set, duplicate rejection, single rate event। |
| Recovery/retry checkpoint 5 | PASS: same event reused, count 1; expected outbox records 2। |
| Rate approval checkpoint 6 | BLOCKED: lot 2614 material/department actual costing incomplete। Correct gate को bypass नहीं किया। |
| Despatch/receive checkpoint 7 | BLOCKED: E2E-FRESH-03 FOLDING costing missing। Full dispatch journey sign-off नहीं। |
| MC1 operational invariant selftest | PASS: purchase/reservation/consumption exactly once; .001 kg × ₹250 = ₹.25। यह Accounts mirror PASS नहीं। |
| Readymade Art/FIFO/sale/return rollback | PASS: 600 PCS split 530+70; one logical Art; PI reservation/edit; oversell denied; single CI stock posting; return original lot; shared Art balance। |
| General payment, receipt, journal reversal | Balanced posting/reversal PASS; original payment REVERSED और inverse balanced। Payment duplicate/ledger-type validation FAIL नीचे। |
| Bill allocations | Negative/excess outstanding, nonpositive allocations, allocations exceeding original amount: existing-record counts 0। |
| Salary due payment | Payment + reversal PASS; repeat reversal and overpayment denied। Same-reference payment duplication and missing general Accounts bridge FAIL। |
| Advance first issue | Configured ACTIVE TEST SALARIED worker के लिए amount 1 preview: selected 0, new advance 0। Existing-positive-balance requirement first issue रोकती है। Recovery/posting end-to-end fixture unavailable। |
| MC1 GR/exchange | Partial GR/exchange quantity mechanics run; repeated same challan inserted twice; CLOSED/non-exchange GR accepted exchange। Financial bridge missing। |
| Alter claim reserve/final helper | 14 departments: retry generated one final debit ₹6। Converted reserve बाद में ₹20 तक बदल सका जबकि final debit ₹6 रहा: immutable-final guard FAIL। यह 14 full Alter journeys का प्रमाण नहीं। |
| Role audit | Worker, Line Manager, Manager, Sales के Accounts home denied; resolved Admin allowed। सभी tested actor contexts financial trial balance की 69 rows पढ़ सके। Actual signed-in browser role test नहीं। |

### नए प्रमाणित essentials

1. **Payment idempotency और cash/bank validation (P0)।** Same payment reference पर दो transaction IDs बने; same ledger को party तथा cash दोनों बनाया जा सका; non-cash ledger को paid-from दिया जा सका। Same-reference salary payment भी दो rows बना सकी। केवल reference को globally unique न करें: scoped stable request/source ID, payload match, distinct party/cash-bank ledger और kind checks लगें। Receipt/journal के reversal PASS से उनकी duplicate-submit safety सिद्ध नहीं होती; उन्हें उसी canonical command contract में शामिल करके verify करें।

2. **Salary posting gap अब runtime प्रमाणित (P0)।** Fresh salary payment ने worker ledger बदला, general Accounts transaction delta 0 रहा। One atomic command में salary due settlement + cash/bank + linked general posting + reversal चाहिए। Payroll accrual और payment अलग accounting events हों; duplicated manual bridge entries न जोड़ें।

3. **MC1 exchange lifecycle/idempotency (P0)।** Same challan दो exchanges बना सका; closed-without-exchange GR पर नया exchange accepted हुआ। GR state, request ID, supplier/source scope, remaining quantity/value और financial return/replacement adjustments atomically enforce हों। Current purchase mode tag NULL तथा source Accounts posting 0 मिला।

4. **First advance creation (P1)।** Preview existing advance balance>0 workers ही लेता है; zero-balance salaried worker पहली advance नहीं पा रहा। Eligibility को configured worker/payroll policy से तय करें; previous balance repayment/recovery के लिए उपयोग हो। Advance creation, payment, recovery और reversal source-linked हों।

5. **Final claim consistency और payroll bridge (P0)।** Converted reserve edit final debit से अलग हो सकता है। Conversion के बाद immutable snapshot और approved adjustment/reversal चाहिए। v800 final claims अलग debit table/view में हैं; monthly generator v779.1 v777.2 claims पढ़ता है। v800 debit table पर user triggers 0; final-deduction view के DB function consumers 0; inspected JS/HTML consumers नहीं मिले। इसलिए end-to-end salary deduction wired प्रमाणित नहीं है—canonical deduction adapter और reconciliation आवश्यक।

6. **Rectify input/permission review (P1, code finding)।** Close function केवल good+damage+alter total बराबर होने को जाँचता है; individual nonnegative checks नहीं मिले, case table में इन fields की check constraints नहीं मिलीं। Wrapper staff roles को allow करता है, department scope इस body में नहीं दिखा; underlying assignment selection lot/dept/colour से है। Active cases 0 होने से real-case invalid-input rollback नहीं चला। इसे proven negative-quantity transaction न कहें; dedicated valid fixture पर nonnegative/whole-PCS, case worker identity, staff department scope और retry checks जरूरी हैं।

7. **Category mappings (P1)।** ऊपर के 4 lots का category ambiguity resolve करें; अनुमान लगाकर cost category न भरें। Existing costing adapter consistency और complete source category coverage अलग checks हैं।

### बाकी sign-off checks — PASS नहीं दिए गए

| बाकी प्रमाण | अभी कारण / आगे कैसे पूरा होगा |
|---|---|
| सभी roles signed-in browser flows | Chromium executable, saved Super Admin auth state और short-lived runner OIDC उपलब्ध नहीं। Authorized E2E runner पर UI → API → source → report पूरा करें। |
| Attendance checkout → approval → payroll → payment | Current TEST में attendance fixtures खाली; engine/coverage gaps प्रमाणित। Shift, late marking, missing checkout, approved correction, leave/holiday, month boundary और activation date fixtures चाहिए। |
| Every department full Alter/Rectify/claim recovery | Helper checks हुए; full journeys नहीं। Correct costing/rate fixtures और valid recall cases से test करें। |
| CB all shortage/excess/GR/exchange financial branches | Bridge/code inspected; fresh exhaustive delta tests बाकी। CB exchange में MC1 जैसा closed guard absent नहीं है—दोनों को एक जैसा failure न कहें। |
| Accessories/material paid/credit/tax/return branches | Existing source coverage checks PASS; every fresh lifecycle/permission/concurrency branch बाकी। |
| Committee all overlap/retry branches | Sources/version dependency inspection हुई; exhaustive fresh obligations and settlement matrix बाकी। |
| Mobile instant loading, stale department UI, tick-row stability | Canonical SQL checks PASS; browser slow-network/reload/cache invalidation and cross-department rendered-state proof बाकी। कोई “instant” या regression-free promise नहीं। |
| Profit accuracy / opening rehearsal | Balanced trial balance alone insufficient; inventory/WIP/COGS, accounting date, source omissions, approved openings तथा dataset isolation fix/reconcile जरूरी। |

### अंतिम कार्य-क्रम और retirement decision

पहले permission closure + dataset boundary; फिर canonical payment/salary/MC1 posting और duplicate/state guards; फिर claim/advance/attendance authority; फिर approved opening/cut-off और report reconciliation; अंत में browser/concurrency और available-record dry-run। Existing fixture data preserve करें। History delete या blanket repost न करें।

Retire candidates वही ऊपर की सूची है: v857 guessed fallback reports, settlement-only salary PAYMENT, independently writing attendance/payroll engines, unverified legacy purchase fallback। **अभी कोई route retire नहीं किया गया।** Canonical replacement, caller inventory, balance reconciliation और parity proof के बाद old writes बंद हों।

Audit के दौरान business scenarios ROLLBACK में हुए; production/main untouched। DB sequences में rollback के कारण gaps संभव हैं; gaps को missing transaction न समझें। New SQL reproductions tests/evidence/test71-accounts-*-rollback-20261010.sql में हैं।

**Final verdict: technical audit में multiple proven blockers हैं; universal clean chit और new-data import approval HOLD। Pending end-to-end checks explicitly खुले हैं। यह report audit completion है, fixes या all-module operational certification नहीं।**

## Final continuation — pure audit, 10 October 2026

User के निर्देशानुसार केवल audit जारी रखा गया। कोई permission, financial function, attendance engine या import schema fix लागू नहीं किया गया। इस section की fresh evidence earlier “proof बाकी” rows को अपने निर्दिष्ट scope में supersede करती है।

### Further runtime results

| क्षेत्र | Actual result | निष्कर्ष |
|---|---|---|
| Manual attendance v778 | PRESENT saved; missing checkout → INCOMPLETE; PRESENT बिना checkout denied; उल्टे punches denied; profile effective date से पहले denied | ये guards PASS। |
| Manual attendance → monthly v777 day | v778 save के बाद v777 day count delta **0** | Split engine issue runtime confirmed; v779 monthly generator approved v777 days पढ़ता है। |
| Attendance actor authority | Dedicated Super Admin profile denied; Owner allowed | v778 manage helper owner/admin/account/manager/payroll/hr ही allow करता है; Super Admin parity missing। Role labels canonical होने चाहिए; privilege blanket broaden न करें। |
| Committee payment retry | Same organizer reference पर **दो payments** बने | Stable request/source idempotency missing। |
| Committee Accounts mirror retry | Same payment पर already_posted=true और same transaction | Mirror retry PASS; payment creation retry इससे सुरक्षित नहीं होती। |
| Committee payment reversal | Payment status REVERSED; linked Accounts transaction **POSTED** रहा | Source reversal और financial reversal inconsistent। Existing data में ऐसे reversed-with-posted records count 0; fresh scenario ने defect reproduced किया। |
| Generic material CREDIT / PARTIAL / PAID | हर ₹20 purchase balanced debit=credit20; respective paid0/10/20, credit20/10/0 | Basic financial split PASS। |
| Generic material same bill retry | दो purchase IDs बने | Wrapper हर call random source ID बनाता है; upstream helper का duplicate_source_guard=true इस command retry को नहीं रोकता। |
| Generic material partial return | Positive ₹2 rate वाले purchase पर return rate 0 निकला; return_value_check से rejected | **FAIL:** purchase stores rate_per_purchase_unit; return reader effective_rate/rate पढ़ता है। Return/reversal journey वहीं blocked; rate manually patch कर “PASS” नहीं बनाया। |
| Material opening | qty10/value20 saved; repeat qty15/value30 same reference → duplicate_blocked=true, saved qty10 | Duplicate row guard works, changed-payload conflict नहीं पहचानता। |
| Material opening → Accounts | General Accounts transaction delta **0** | Quantity/value subledger snapshot को approved universal opening journal से reconcile करने का bridge नहीं मिला। हर inventory opening को purchase expense बनाना solution नहीं। |
| Isolation catalog | Public schema में dataset_id/workspace_id/rehearsal_id columns **0**; holiday table में data_mode/dataset_id **0** | TEST/REAL alone adequate dataset isolation नहीं। Shared calendar को explicitly shared approved master या scoped calendar बनाना होगा। |
| Direct anon table reads | Transactions, postings, material purchases, attendance counts **0** | RLS table reads blocked। Earlier anonymous report RPC leak अलग privileged-function boundary पर है। Table grant alone exposure का proof नहीं। |
| Payroll vs costing contract | Additional 2 Node assertions PASS | Salary authority payroll, costing allocation-only source contract retains। Runtime full attendance/payroll certification नहीं। |

### Attendance/personal chat feature audit

| Required feature | Present state | Required canonical design |
|---|---|---|
| Worker का distinct personal Attendance section | Inspected Real Chat में generic Attendance external link; worker-bound separate attendance thread consumer नहीं मिला | Personal chat में separate attendance section, worker ID + business date identity; work cards से distinct। |
| Real check-in / check-out | Factory geofence recorder exists; inspected JS calls TEST scenario, actual factory event caller नहीं मिला | UI → authorized event command → event/day calculation → personal status/message, exact worker binding। |
| TEST vs real-function rehearsal | TEST scenario explicitly salary_attendance_affected=false | Geofence simulation evidence और full salaried attendance rehearsal अलग test modes/contracts; simulated GPS को real GPS evidence न कहें। |
| Missing checkout | Manual engine INCOMPLETE gate PASS; raw-event payroll flow incomplete | Checkout due/review message; approved correction before payroll; unexplained gap को automatic completed attendance न बनाएं। |
| Late arrival vs late marking | User requirement है; canonical complete chat path प्रमाणित नहीं | Separate event_at/recorded_at, timezone/shift, late reason, performer/on-behalf and revision trail। |
| Voice reason/evidence | Attendance-related video/correction tables exist; inspected personal-chat late voice wiring नहीं मिली | Voice record Storage object + worker/day/correction FK, authorized access, playback and reviewer status। |
| Reminders | Due/reminder functions exist; complete scheduler → dispatch → acknowledgement evidence नहीं | Idempotent scheduled due event, delivered/read state, deep link to exact attendance date। |
| Approved day → monthly salary | Legacy v778 and v777/v779 authorities split; manual save v777 delta0 | One authoritative approved-day contract + adapters; active period coverage resolved before generation। |
| Payslip PDF / WhatsApp | v779 UI shows payload-ready; actual PDF renderer/sending not implemented in inspected actions | Renderer/download/share integration and delivery proof; payload readiness ≠ file generated/message sent। |
| Test attendance gaps | Expected with imaginary fixtures | Before approved activation no absence debit/penalty; rehearsal scenario gaps clearly labeled। |

### Essential additions / consolidation

- **P0 Committee reversal:** one command must reverse source payment and linked financial transaction, recompute month due; repeat retry result stable; cash/bank and reporting movements net correctly. Check older member-post/payment sources by obligation ID before allowing another write.
- **P0 Generic material return rate:** read immutable purchase rate snapshot; preserve purchase-unit vs stock/consumption-unit conversion; tax proportional reversal; return/reversal must restore correct stock and supplier/general ledger. No repair/backfill performed.
- **P0 Command idempotency:** purchase/payment/committee/advance/salary commands use scoped operation ID and immutable payload hash. Same ID+same payload returns prior result; same ID+different payload rejects. Legitimate distinct partial payments remain allowed.
- **P1 Permission parity:** one authoritative role map for Super Admin/Owner/Admin/Accounts/Manager/Worker, with positive and negative tests. v778 Super Admin denial and report access bypass must both be addressed; frontend display permission insufficient.
- **P0 Opening contract:** approved batch, as-of cut-off, baseline quantities/value and party/cash/salary/advance/WIP balances; evidence status UNKNOWN/ZERO/N/A; balancing control; active date; per-source stable identity; changed-payload conflicts and approved correction/reversal. Consolidated opening can use available records without invented history.
- **P1 Attendance closure:** only one day/payroll authority writes; keep historical tables and approved snapshots via read adapters. Real personal attendance check-in/out, reason/voice, notifications and salary wiring must be end-to-end; TEST geofence helper should remain labeled evidence-only.
- **P0 Dataset isolation:** preserve existing imaginary fixture environment; use separate TEST rehearsal environment as recommended. If same database is chosen, full scope across masters, dependent tables, financial reports, unique identities, RPCs/RLS, calendar policy, Storage and caches is mandatory. No partial prefix solution.

### Audit completion and operational sign-off

Source/schema/grants/role-context inspection, existing-record reconciliation और available targeted rollback scenarios के audit findings इस report में complete किए गए हैं। Unavailable browser runner और unsuitable/missing fixtures के कारण exhaustive end-to-end certification **BLOCKED**, और पिछली unresolved branch matrix अभी applicable है। Failed functional journeys को audit finding मानकर बंद किया गया है—उन्हें successful journey नहीं माना गया।

यह final **audit report** है; implementation, universal clean chit, exhaustive performance certification अथवा new-data import clearance नहीं। Import readiness **HOLD**। पहले audited defects का targeted fix, फिर same reproductions + full module browser/role/concurrency matrix और isolated opening rehearsal; तब acceptance evidence पर readiness decision हो।

Evidence scripts: test71-accounts-attendance-continuation-20261010.sql, test71-accounts-committee-continuation-20261010.sql, test71-accounts-material-continuation-20261010.sql, test71-accounts-opening-continuation-20261010.sql. ये audited owner/TEST context और BEGIN/ROLLBACK के reproductions हैं; production run scripts नहीं।

## Current evidence-based completion status — supersedes earlier “final/completed” wording

**Full audit sign-off: NOT COMPLETE.** Latest scenario checklist has **127 checks: 54 PASS, 48 FAIL, 6 BLOCKED, 19 NOT_RUN**. These are check rows, not 48 distinct defects; department helper/projection cohorts share executions. Checklist is the explicit Accounts-related acceptance baseline identified so far, not a claim that every unknown app feature has been inventoried and executed.

- Scenario/expected/actual/status/evidence: audits/test71-audit-scenario-matrix-20261010.md and matching JSON.
- Executed rollback raw outputs: audits/test71-sql-runtime-evidence-20261010.json, audits/test71-sql-runtime-rerun-evidence-20261010.json and audits/test71-core-runtime-evidence-20261010.json.
- Repeated existing-data / anonymous aggregates: audits/test71-invariants-runtime-evidence-20261010.json.
- Browser DOM evidence: audits/test71-browser-evidence-20261010.json. Attendance screenshot: audits/test71-attendance-browser-20261010.jpg.
- Broad source suite: audits/test71-source-suite-evidence-20261010.json. 108 unique files after correct-cwd reruns: **77 passed files, 30 failed files, 1 timeout**. These file counts are not assertion counts and not live E2E success counts. Original broad combined run stalled; bounded per-file runs retained raw output. Two Readymade relative-path failures passed from their intended parent cwd. Other failures remain unresolved; many show incomplete DOM mocks/missing extracted dependencies, so they must not all be called production defects or all dismissed as obsolete tests.

### Browser blocker resolution and newly observed evidence

Secure browser sign-in succeeded as Sudesh Bhati; earlier “browser unavailable/login unavailable” limitation is superseded for the Owner session. Signed-in browser showed:
- Canonical Trial Balance **69 rendered rows**; Balance Sheet rendered assets/liabilities/equity.
- Cutting OPEN count **3**, detail cards exactly **1009-S2, 1007-S1, 1008-S1**.
- Cutting WORKING first reached **Cards load नहीं हुए**. OPEN later recovered and rendered. A stale RETRY locator no longer existed after state changed; no retry success was assumed.
- Accounts OPEN eventually rendered **24 Committee cards**, confirming earlier restricted contributor coverage; it spent multiple observations loading. Exact browser latency percentiles were not measured.
- Official TEST Act As Imamul opened personal WORKING lanes: **Assigned Receipt4 / Submit2 / Short-Excess1**. This is on-behalf simulation, not independent worker login proof.
- Owner Attendance UI accepted Madan TEST October selection; **future Oct27–31 also displayed ABSENT / MISSING→ABSENT** on Oct10; summary showed27 absent/missing. This is a verified display error; no actual salary deduction from those future dates was proved.
- Act As restoration UI remained stale in observed tab after attempts. Audit-created backend on-behalf context was explicitly cleared using existing TEST clear command; read-back showed no active context row. That cleanup changed only test preview context, not business data/schema. Browser sessionStorage rendering parity remains an audit concern.

Server single-call timing observations in Owner rollback: Accounts OPEN **427.592 ms**,24cards; Cutting WORKING **425.254 ms**,7cards. One DB sample is not p95 mobile/network performance. Backend availability and slow/failed browser rendering are separate outcomes.

### Why the remaining 25 checks cannot be declared complete

| Remaining cohort | Required next action / completion evidence |
|---|---|
| Attendance → approved day → payroll → payment → Accounts | Failed authority/posting bridges must first be corrected, then complete shifts/late/checkout/leave/holiday/month-boundary/activation fixtures and reversal assertions. |
| Advance issue/recovery and generic return reversal | First-advance eligibility and return-rate defects prevent valid fresh scenario; fix then execute downstream stock/subledger/GL deltas. |
| Full department Submit/Alter/Rectify financial journeys | Shared queues and 14-department claim helpers are insufficient; valid rates/costing/recall fixtures and independent journeys with deductions/payroll/GL/reversal needed. |
| Despatch receive checkpoint | Missing FOLDING costing is correctly blocking fixture; prepare approved valid costing fixture and rerun, without bypassing gate. |
| CB, accessory and Committee exhaustive financial branches | Fresh branch matrix still unexecuted; execute source/stock/tax/supplier/customer/GL/report/reversal assertions and scoped permissions. |
| All independent role/browser/mobile/concurrency sessions | Authorized TEST role sessions and runnable harness needed; official Act As results remain labeled simulation. Module CI steps for MC1/CB/material/checkpoint8 currently if:false. The connector returned no PR-triggered run for HEAD; its limited filter does not prove absence of all push/manual runs. |
| Isolated opening/new-data rehearsal | Dataset boundary and approved universal opening contract absent; fix/design before importing any available business records. No import/archive performed. |

Audit-only scope was honored: no functional/permission fixes, no production/main changes, no imported/deleted/reposted business records. Business tests were rolled back; sequences may advance. The report is an evidence-backed findings and coverage report. It **does not meet** the user's stricter requirement of no necessary BLOCKED/NOT_RUN checks, and therefore is **not a full audit certificate**.
