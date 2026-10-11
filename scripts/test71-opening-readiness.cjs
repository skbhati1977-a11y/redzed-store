'use strict';
// Source-side readiness only. Never writes, approves or posts business data.
const fs = require('node:fs');
function inspectOpening(source) {
  const findings = [];
  const add = (code, row, detail) => findings.push({ code, row, detail });
  const nonblank = value => typeof value === 'string' && value.trim().length > 0;
  const rows = Array.isArray(source?.rows) ? source.rows : [];
  const date = value => /^\d{4}-\d{2}-\d{2}$/.test(value || '') && !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
  const money = value => {
    const text = String(value ?? '');
    if (!/^\d+(\.\d{1,2})?$/.test(text)) return null;
    const [whole, fraction = ''] = text.split('.');
    return BigInt(whole) * 100n + BigInt(fraction.padEnd(2, '0'));
  };
  if (!rows.length) add('SOURCE_MISSING', null, 'Actual opening source rows have not been supplied.');
  if (!nonblank(source?.source_ref) || !/^[a-f0-9]{64}$/.test(source?.source_sha256 || '')) add('SOURCE_EVIDENCE_MISSING', null, 'Source reference and SHA256 required.');
  const dates = rows.map(row => row?.record_date).filter(date).sort();
  const earliest = dates[0] || null;
  if (!date(source?.approved_cutoff)) add('CUTOFF_UNAPPROVED', null, 'Explicit business-approved cutoff required.');
  if (!nonblank(source?.approval_evidence_ref)) add('APPROVAL_EVIDENCE_MISSING', null, 'Approval evidence reference required; this tool cannot approve it.');
  const mappings = source?.approved_ledger_mapping || {};
  let debit = 0n, credit = 0n, stock = 0n, wip = 0n, stockGl = 0n, wipGl = 0n;
  let glCount = 0, stockCount = 0, wipCount = 0;
  const seen = new Set();
  rows.forEach((row, index) => {
    const n = index + 1;
    if (!row || typeof row !== 'object' || Array.isArray(row)) { add('ROW_INVALID', n, 'Object row required.'); return; }
    const kind = row.module, state = row.evidence_status, v = row.values || {};
    if (!nonblank(row.source_key) || seen.has(`${kind}|${row.source_key}`)) add('SOURCE_KEY_INVALID', n, 'Stable unique module/source key required.');
    seen.add(`${kind}|${row.source_key}`);
    if (!date(row.record_date)) add('DATE_INVALID', n, 'Valid ISO calendar date required.');
    if (!['OPENING_GL', 'OPENING_STOCK', 'OPENING_WIP'].includes(kind)) return;
    if (row.record_date !== source?.approved_cutoff) add('OPENING_CUTOFF_MISMATCH', n, 'Opening must use the approved cutoff.');
    if (!['KNOWN', 'ZERO', 'UNKNOWN', 'NOT_APPLICABLE'].includes(state)) { add('EVIDENCE_STATE_INVALID', n, 'Explicit evidence state required.'); return; }
    if (state === 'UNKNOWN') { add('UNKNOWN_OPENING', n, 'Unknown remains pending, never zero.'); return; }
    if (state === 'NOT_APPLICABLE') {
      if (!String(v.reason || '').trim()) add('NA_REASON_MISSING', n, 'Source reason required.');
      if (['debit','credit','quantity','value'].some(key => v[key] != null && !/^0+(\.0+)?$/.test(String(v[key])))) add('NA_WITH_VALUE', n, 'Not-applicable cannot hide a financial quantity/value.');
      return;
    }
    if (kind === 'OPENING_GL') {
      glCount++;
      const dr = money(v.debit), cr = money(v.credit);
      if (dr === null || cr === null || (dr > 0n && cr > 0n)) { add('GL_VALUES_INVALID', n, 'Explicit nonnegative debit/credit with at most two decimals required.'); return; }
      if (state === 'ZERO' && (dr !== 0n || cr !== 0n)) add('FALSE_ZERO', n, 'ZERO requires exact zeros.');
      debit += dr; credit += cr;
      if (!nonblank(v.ledger_key) || !Object.prototype.hasOwnProperty.call(mappings, v.ledger_key) || !['STOCK','WIP','CASH_BANK','RECEIVABLES','PAYABLES','ADVANCES','SALARY_PAYABLE','EQUITY','OTHER'].includes(mappings[v.ledger_key])) add('LEDGER_MAPPING_UNAPPROVED', n, 'Ledger mapping must come from approved source evidence.');
      if (mappings[v.ledger_key] === 'STOCK') stockGl += dr - cr;
      if (mappings[v.ledger_key] === 'WIP') wipGl += dr - cr;
    } else {
      const amount = money(v.value), qty = String(v.quantity ?? '');
      if (amount === null || !/^\d+(\.\d+)?$/.test(qty) || !nonblank(v.item_key) || !nonblank(v.unit)) { add('STOCK_VALUES_INVALID', n, 'Item, unit and explicit nonnegative quantity/value required.'); return; }
      if (state === 'ZERO' && (amount !== 0n || !/^0+(\.0+)?$/.test(qty))) add('FALSE_ZERO', n, 'ZERO requires exact zeros.');
      if (/^0+(\.0+)?$/.test(qty) && amount !== 0n) add('ZERO_QUANTITY_WITH_VALUE', n, 'Zero physical quantity cannot carry unexplained inventory value.');
      if (kind === 'OPENING_STOCK') { stock += amount; stockCount++; } else { wip += amount; wipCount++; }
    }
  });
  if (!glCount) add('OPENING_GL_MISSING', null, 'Opening ledger rows required.');
  if (debit !== credit) add('OPENING_GL_UNBALANCED', null, 'Debit and credit totals differ.');
  for (const [kind, count, amount, gl] of [['STOCK',stockCount,stock,stockGl],['WIP',wipCount,wip,wipGl]]) {
    if (!count && !nonblank(source?.not_applicable_evidence?.[kind])) add(`${kind}_COVERAGE_UNKNOWN`, null, 'Supply opening rows or explicit approved not-applicable evidence.');
    if (amount !== gl) add(`${kind}_GL_MISMATCH`, null, 'Physical valuation does not reconcile to approved GL mapping.');
  }
  const format = cents => { const absolute = cents < 0n ? -cents : cents; return `${cents < 0n ? '-' : ''}${absolute / 100n}.${String(absolute % 100n).padStart(2, '0')}`; };
  return { source_ref: source?.source_ref || null, earliest_source_date: earliest, approved_cutoff: source?.approved_cutoff || null,
    findings, checks_passed: findings.length === 0, cleared_for_import: false, business_records_posted: 0,
    remaining_gates: ['VERIFY_BUSINESS_APPROVAL_EVIDENCE','ACTIVE_ARCHIVE_READER_AND_AGGREGATE_ISOLATION','APPROVED_MASTER_REFERENCE_MAPPING','CONTROLLED_OPENING_POSTING_AND_RECONCILIATION','ROLE_FINANCIAL_ACCEPTANCE'],
    totals: { debit: format(debit), credit: format(credit), stock_value: format(stock), stock_gl: format(stockGl), wip_value: format(wip), wip_gl: format(wipGl) } };
}
module.exports = { inspectOpening };
if (require.main === module) {
  const path = process.argv[2];
  if (!path) { process.stderr.write('Usage: node scripts/test71-opening-readiness.cjs source.json\n'); process.exitCode = 2; }
  else { try { const result = inspectOpening(JSON.parse(fs.readFileSync(path, 'utf8'))); process.stdout.write(JSON.stringify(result, null, 2) + '\n'); process.exitCode = result.checks_passed ? 0 : 1; } catch { process.stderr.write('Opening source could not be read as valid JSON. No records posted.\n'); process.exitCode = 2; } }
}
