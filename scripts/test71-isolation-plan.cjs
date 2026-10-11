'use strict';
// Offline dry-run only. It neither connects to the database nor activates archives.
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const REQUIRED_SURFACES = Object.freeze([
  'masters', 'cards', 'stock', 'balances', 'reports', 'payroll',
  'calendar', 'notifications', 'storage', 'cache', 'writers', 'unique_keys', 'rls'
]);
const sha = text => createHash('sha256').update(text).digest('hex');
const hex = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const text = value => typeof value === 'string' && value.trim().length > 0;
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
function planIsolation(input) {
  const blockers = [];
  const reject = (code, detail) => blockers.push({ code, detail });
  if (!input || typeof input !== 'object' || Array.isArray(input)) input = {};
  if (input.data_mode !== 'TEST') reject('TEST_ONLY', 'An explicit TEST manifest is required.');
  if (!text(input.snapshot_ref) || !hex(input.snapshot_sha256)) reject('SNAPSHOT_REQUIRED', 'Supply a preserved snapshot reference and SHA-256.');
  if (!text(input.restore_evidence_ref)) reject('RESTORE_UNVERIFIED', 'Supply the successful snapshot restore evidence.');
  const rows = Array.isArray(input.rows) ? input.rows : [];
  if (!Array.isArray(input.rows)) reject('INVALID_ROWS', 'rows must be an array.');
  if (!rows.length) reject('EMPTY_MANIFEST', 'No explicit legacy rows selected.');
  const seen = new Set();
  const refs = [];
  for (const [index, row] of rows.entries()) {
    if (!row || typeof row !== 'object' || Array.isArray(row)) { reject('INVALID_ROW', index); continue; }
    const key = JSON.stringify([row.table, row.row_id]);
    if (!/^public\.[a-z][a-z0-9_]*$/.test(row.table || '') || !text(row.row_id)) reject('INVALID_ROW_REFERENCE', index);
    if (seen.has(key)) reject('DUPLICATE_ROW', key);
    seen.add(key);
    // Lot prefixes and names are deliberately insufficient; missing mode stays unknown.
    if (row.source_data_mode !== 'TEST') reject('UNVERIFIED_TEST_PROVENANCE', key);
    if (!text(row.provenance_ref) || !hex(row.source_row_sha256)) reject('SOURCE_EVIDENCE_REQUIRED', key);
    if (row.dependencies_verified !== true) reject('DEPENDENCIES_UNVERIFIED', key);
    refs.push({ table: row.table, row_id: row.row_id, source_row_sha256: row.source_row_sha256, provenance_ref: row.provenance_ref });
  }
  const coverage = Array.isArray(input.coverage) ? input.coverage : [];
  if (!Array.isArray(input.coverage) || coverage.some(entry => !entry || typeof entry !== 'object' || Array.isArray(entry))) reject('INVALID_COVERAGE', 'coverage must contain evidence objects.');
  for (const surface of REQUIRED_SURFACES) {
    const matches = coverage.filter(entry => entry && entry.surface === surface);
    if (matches.length !== 1 || matches[0].isolated !== true || !text(matches[0].evidence_ref)) reject('COVERAGE_INCOMPLETE', surface);
  }
  if (input.reader_inventory_complete !== true || !hex(input.reader_inventory_sha256)) reject('READER_INVENTORY_UNVERIFIED', 'All direct readers, security-definer RPCs and aggregates must be reviewed.');
  if (input.approved_opening_reconciled !== true || !text(input.opening_evidence_ref)) reject('OPENING_UNRECONCILED', 'Approved opening stock, WIP and ledger bridge is required.');
  if (input.preview_sha_verified !== true || !hex(input.preview_source_sha256)) reject('PREVIEW_UNVERIFIED', 'Verify the exact TEST preview source artifact.');
  refs.sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
  return {
    schema_version: 1, data_mode: 'TEST', operation: 'DRY_RUN',
    manifest_sha256: sha(JSON.stringify(canonical(input))), selected_rows: refs,
    counts: { selected: rows.length, explicit_test: rows.filter(r => r && r.source_data_mode === 'TEST').length, real: rows.filter(r => r && r.source_data_mode === 'REAL').length, ambiguous: rows.filter(r => !r || !['TEST','REAL'].includes(r.source_data_mode)).length, business_rows_staged: 0 },
    blockers, ready_for_review: blockers.length === 0,
    archive_activated: false, business_records_changed: 0,
    warning: 'Offline evidence validation only. A reviewer must verify the referenced evidence against live sources before any separate archive activation.'
  };
}
module.exports = { planIsolation, REQUIRED_SURFACES };
if (require.main === module) {
  try {
    const result = planIsolation(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')));
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
    process.exitCode = result.ready_for_review ? 0 : 2;
  } catch (error) { process.stderr.write('Isolation plan failed: ' + error.message + '\n'); process.exitCode = 1; }
}
