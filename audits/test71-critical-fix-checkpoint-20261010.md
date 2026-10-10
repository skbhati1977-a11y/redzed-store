# TEST71 critical fixes — प्रमाण और remaining work

**निर्णय: full clean chit अभी नहीं।** Current matrix: 132 scenarios — 85 PASS, 23 FAIL, 5 BLOCKED, 19 NOT_RUN. PASS केवल लिखे हुए scenario का परिणाम है। नए financial rollback fixtures commit नहीं किए गए; पुराने records delete/repost/import नहीं हुए। TEST schema fixes लागू हैं; updated frontend अभी deployed/browser verified नहीं है।

## Verified fixes

| Target | प्रमाणित परिणाम | सीमा |
|---|---|---|
| Anonymous finance | 196 account/finance/claim/salary/payroll/advance नाम वाले RPCs: anonymous EXECUTE 0; financial-name relations: anonymous SELECT 0 | बाकी schema की complete security certification नहीं |
| Role separation | Accounts worker contexts denied; Admin allowed; Owner764 financial rows और38 payroll profiles retained; other-worker payroll/advance rows0 | SQL effective-role proof; independent browser sessions बाकी |
| Super Admin | Salary management/payment/reversal तथा attendance checks pass | UI parity browser verification बाकी |
| Material return | Frozen purchase cost से2 units का return₹4; reverse pass | अन्य conversion/master/isolation checks बाकी |
| Payment validation | Same party/cash ledger तथा invalid cash/bank rejected | Legacy direct writers अभी retired नहीं |
| Request retry | Payment/material/Committee/salary/advance request identity retained; changed payload rejected; UI8 unit checks pass | New preview और concurrent browser checks बाकी |
| Committee | Payment + journal atomic; linked reversal reverses Accounts | Prize/dividend और complete lifecycle बाकी |
| Salary settlement | New payment balanced worker/cash journal; linked balanced reversal; approved bank route verified | Accrual, advance/claim split, historical opening reconciliation बाकी |
| MC1 exchange | Same retry returns original exchange; conflicting payload/closed invalid GR rejected | MC1 purchase financial bridge अभी missing |
| Alter reserve | Converted claim immutable across14 helpers; identical retry safe | Real payroll final claim consumption बाकी |
| Ledger period | Prior10 + selected movement2 = closing12; v806/v807 pass | Approved universal opening/cutoff policies अलग काम |
| Future attendance | Save और दोनों calculation engines tomorrow reject; past guards preserved | Local screen change4 unit checks pass; preview browser check बाकी |
| First advance | Active configured zero-balance salaried worker selected; first issue retry same batch | Accounts transaction delta0: issue/recovery/reversal पूरा pass नहीं |

## आवश्यक खुले gaps

1. Salary accrual, advance cash/asset posting और payroll advance/claim recovery को linked Accounts entries और reversal से पूरा करना।
2. Attendance daily authority consolidate करना: manual V778 save अभी canonical V777 row नहीं बदलता (delta0); checkout/policy/activation/approval/personal chat pipeline पूरा verify करना।
3. MC1 purchase और सभी pending financial sources की Accounts queue mapping पूरा करना; accounting dates और closing stock/WIP/COGS reconcile करना।
4. Updated TEST frontend deploy/browser verify करके legacy duplicate-prone entry points retire करना। अभी direct authenticated old writers को closed नहीं माना है।
5. Approved opening batch/cutoff, UNKNOWN/ZERO/N/A और isolated rehearsal boundary लागू करना; पुराने imaginary fixtures सुरक्षित रखना। नया business data अभी import नहीं करना।
6. Independent role sessions, mobile/offline/concurrency,14 department full Submit/Alter/Rectify→payroll→Accounts, Committee branches, CB/accessory branches तथा blocked despatch fixture checks पूरे करना।
7. Security advisors अभी residual findings देते हैं (69 RLS-disabled,192 security-definer-view findings आदि)। Guarded views पर advisor label बना रह सकता है; प्रत्येक residual finding की scope/effective access जाँच बाकी है।

## Deployment blockage

Local reviewed fix commit तैयार है। GitHub push automatic approval review ने रोका: payload में application code, SQL migrations, audit evidence और potentially sensitive identifiers हैं; TEST-fix authorization को GitHub disclosure की explicit authorization नहीं माना गया। Rejection को किसी अन्य tool/route से bypass नहीं किया गया। Updated deployment/browser verification इस कारण अभी पूरा नहीं हुआ।

## Evidence

- `test71-audit-scenario-matrix-20261010.json/.md`: scenario, expected, actual, status, evidence और old failure history.
- `test71-critical-fix-runtime-evidence-20261010.json`: first critical fixes.
- `test71-salary-ledger-fix-evidence-20261010.json`: strict settlement/period assertions.
- `test71-fix-continuation-evidence-20261010.json`: future day, remaining privacy, first advance.
- `test71-final-acl-replays-20261010.json`: permission, salary, request, ledger reruns after ACL hardening.
- `test71-post-fix-security-advisors-20261010.json`: unresolved security findings retained.
- `tests/evidence/*fixed-20261010.sql`: reproducible rollback scenarios; local request/calendar unit tests12 PASS.

यह checkpoint report है; final universal audit sign-off नहीं।
