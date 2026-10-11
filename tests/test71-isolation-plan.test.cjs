'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { planIsolation, REQUIRED_SURFACES } = require('../scripts/test71-isolation-plan.cjs');
const hash = 'a'.repeat(64);
const valid = () => ({ data_mode: 'TEST', snapshot_ref: 'snapshot-proof', snapshot_sha256: hash, restore_evidence_ref: 'restore-proof', rows: [{ table: 'public.rr_account_transactions_v805', row_id: 'fixture-id', source_data_mode: 'TEST', provenance_ref: 'explicit-mode-source', source_row_sha256: hash, dependencies_verified: true }], coverage: REQUIRED_SURFACES.map(surface => ({ surface, isolated: true, evidence_ref: surface + '-proof' })), reader_inventory_complete: true, reader_inventory_sha256: hash, approved_opening_reconciled: true, opening_evidence_ref: 'opening-proof', preview_sha_verified: true, preview_source_sha256: hash });
test('complete synthetic evidence creates a review plan and never activates anything', () => {
  const result = planIsolation(valid());
  assert.equal(result.ready_for_review, true); assert.equal(result.archive_activated, false); assert.equal(result.business_records_changed, 0);
});
test('REAL, untagged and prefix-only rows cannot be archived by inference', () => {
  for (const mode of ['REAL', undefined, 'test']) {
    const input = valid(); input.rows[0].source_data_mode = mode; input.rows[0].row_id = 'TEST71-imaginary';
    assert.ok(planIsolation(input).blockers.some(b => b.code === 'UNVERIFIED_TEST_PROVENANCE'));
  }
});
test('all reader and aggregate surfaces require unique evidence', () => {
  for (const surface of REQUIRED_SURFACES) {
    const input = valid(); input.coverage = input.coverage.filter(c => c.surface !== surface);
    assert.ok(planIsolation(input).blockers.some(b => b.code === 'COVERAGE_INCOMPLETE' && b.detail === surface));
  }
  const input = valid(); input.coverage.push(input.coverage[0]); assert.equal(planIsolation(input).ready_for_review, false);
});
test('snapshot restore, source hashes, dependency closure and openings fail closed', () => {
  for (const key of ['snapshot_ref', 'snapshot_sha256', 'restore_evidence_ref', 'reader_inventory_complete', 'reader_inventory_sha256', 'approved_opening_reconciled', 'opening_evidence_ref', 'preview_sha_verified', 'preview_source_sha256']) {
    const input = valid(); delete input[key]; assert.equal(planIsolation(input).ready_for_review, false, key);
  }
  for (const key of ['provenance_ref', 'source_row_sha256', 'dependencies_verified']) { const input = valid(); delete input.rows[0][key]; assert.equal(planIsolation(input).ready_for_review, false, key); }
});
test('duplicate and malformed row references are rejected', () => {
  const input = valid(); input.rows.push({...input.rows[0]}); assert.ok(planIsolation(input).blockers.some(b => b.code === 'DUPLICATE_ROW'));
  input.rows = [{...input.rows[0], table: 'public.x;delete'}]; assert.ok(planIsolation(input).blockers.some(b => b.code === 'INVALID_ROW_REFERENCE'));
});
test('invalid input is blocked, never treated as an empty successful archive', () => {
  for (const input of [null, [], {}, 'TEST']) assert.equal(planIsolation(input).ready_for_review, false);
});
test('review hash binds provenance mode, snapshots, dependencies and aggregate evidence', () => {
  const original = valid(), hash = planIsolation(original).manifest_sha256;
  for (const mutate of [x => x.snapshot_ref = 'changed', x => x.rows[0].source_data_mode = 'REAL', x => x.rows[0].dependencies_verified = false, x => x.coverage[0].evidence_ref = 'changed', x => x.opening_evidence_ref = 'changed']) {
    const input = valid(); mutate(input); assert.notEqual(planIsolation(input).manifest_sha256, hash);
  }
  const reordered = Object.fromEntries(Object.entries(original).reverse()); assert.equal(planIsolation(reordered).manifest_sha256, hash);
});
test('malformed collections fail closed and counts retain REAL and ambiguous rows', () => {
  for (const [key, value] of [['rows', {}], ['coverage', {}], ['coverage', [null]]]) {
    const input = valid(); input[key] = value; assert.equal(planIsolation(input).ready_for_review, false);
  }
  const input = valid(); input.rows.push({...input.rows[0], row_id: 'real', source_data_mode: 'REAL'}, {...input.rows[0], row_id: 'unknown', source_data_mode: null});
  assert.deepEqual(planIsolation(input).counts, {selected: 3, explicit_test: 1, real: 1, ambiguous: 1, business_rows_staged: 0});
});
