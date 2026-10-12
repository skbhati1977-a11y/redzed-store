'use strict';

const crypto = require('node:crypto');

const TERMINAL = new Set(['READY_TO_IMPORT', 'REVIEW_REQUIRED', 'BLOCKED', 'ARCHIVE_ONLY']);

function sourceKey(row) {
  return `${row.module}\u0000${String(row.source_id)}`;
}

function rowHash(row) {
  return crypto.createHash('sha256').update(JSON.stringify({
    module: row.module,
    source_id: String(row.source_id),
    source_updated_at: row.source_updated_at ?? null,
    canonical: row.canonical,
    references: row.references ?? [],
  })).digest('hex');
}

function topologicalRows(rows, adapters) {
  const byKey = new Map(rows.map((row) => [sourceKey(row), row]));
  const visiting = new Set();
  const visited = new Set();
  const ordered = [];

  function visit(row) {
    const key = sourceKey(row);
    if (visited.has(key)) return;
    if (visiting.has(key)) throw new Error(`Dependency cycle at ${row.module}/${row.source_id}`);
    visiting.add(key);
    for (const ref of row.dependencies ?? []) {
      const parent = byKey.get(`${ref.module}\u0000${String(ref.source_id)}`);
      if (!parent) throw new Error(`Missing dependency ${ref.module}/${ref.source_id} for ${row.module}/${row.source_id}`);
      if (parent.classification === 'READY_TO_IMPORT') visit(parent);
    }
    visiting.delete(key);
    visited.add(key);
    ordered.push(row);
  }

  for (const row of rows) {
    const adapter = adapters[row.module];
    if (row.classification === 'READY_TO_IMPORT' && adapter) visit(row);
  }
  return ordered;
}

function buildOperationalImportPlan({ dataset, adapters }) {
  if (!dataset || dataset.format !== 'redzed-ci-operational-import/v1') {
    throw new Error('Unsupported migration dataset format.');
  }
  if (!dataset.source || !dataset.source.application || !dataset.source.reference || !/^[a-f0-9]{64}$/i.test(dataset.source.sha256 ?? '')) {
    throw new Error('Source application, reference, and SHA-256 are required.');
  }
  if (!Array.isArray(dataset.records)) throw new Error('Dataset records must be an array.');
  if (!adapters || typeof adapters !== 'object') throw new Error('Module adapter registry is required.');

  const seen = new Set();
  const records = dataset.records.map((row, index) => {
    if (!row || typeof row !== 'object' || Array.isArray(row)) throw new Error(`Record ${index + 1} must be an object.`);
    if (!row.module || row.source_id === undefined || row.source_id === null || String(row.source_id).trim() === '') {
      throw new Error(`Record ${index + 1} requires module and stable source_id.`);
    }
    if (!row.raw || typeof row.raw !== 'object' || Array.isArray(row.raw)) throw new Error(`Record ${index + 1} must preserve raw source values.`);
    if (!TERMINAL.has(row.classification)) throw new Error(`Record ${index + 1} has an unsupported classification.`);
    const key = sourceKey(row);
    if (seen.has(key)) throw new Error(`Duplicate source identity ${row.module}/${row.source_id}.`);
    seen.add(key);
    const adapter = adapters[row.module];
    if (row.classification === 'READY_TO_IMPORT') {
      if (!adapter) throw new Error(`No operational adapter is registered for ${row.module}.`);
      if (adapter.sideEffectFree !== true) throw new Error(`Adapter ${row.module} must prove it does not post operational side effects.`);
      if (adapter.testModeOnly !== true || adapter.writeMode !== 'insert-only') {
        throw new Error(`Adapter ${row.module} must be TEST-only and insert-only.`);
      }
      if (typeof adapter.targetTable !== 'string' || !/^public\.[a-z][a-z0-9_]*$/.test(adapter.targetTable)) {
        throw new Error(`Adapter ${row.module} must name one explicit public target table.`);
      }
      if (typeof adapter.findIdentityConflict !== 'function' || typeof adapter.insert !== 'function' || typeof adapter.verify !== 'function') {
        throw new Error(`Adapter ${row.module} requires conflict lookup, insert, and verify methods.`);
      }
      if (!row.canonical || typeof row.canonical !== 'object' || Array.isArray(row.canonical)) {
        throw new Error(`Ready record ${row.module}/${row.source_id} requires canonical mapped values.`);
      }
    }
    return { ...row, source_id: String(row.source_id), payload_sha256: rowHash(row), input_order: index };
  });

  const ordered = topologicalRows(records, adapters);
  return {
    format: dataset.format,
    source: { ...dataset.source },
    records: ordered,
    summary: records.reduce((acc, row) => {
      acc[row.classification] = (acc[row.classification] ?? 0) + 1;
      return acc;
    }, {}),
  };
}

async function runOperationalImport({ plan, adapters, repository, mode = 'DRY_RUN', environment = 'TEST', backupReference = null }) {
  if (!plan || !Array.isArray(plan.records)) throw new Error('A validated import plan is required.');
  if (!repository || typeof repository.transaction !== 'function') throw new Error('Transactional repository is required.');
  if (!['DRY_RUN', 'APPLY'].includes(mode)) throw new Error('Mode must be DRY_RUN or APPLY.');
  if (mode === 'APPLY' && (environment !== 'TEST' || !backupReference || !String(backupReference).trim())) {
    throw new Error('Apply requires TEST environment and a recorded target backup reference.');
  }

  return repository.transaction(async (tx) => {
    const results = [];
    const identityCache = new Map();
    for (const row of plan.records) {
      if (row.classification !== 'READY_TO_IMPORT') {
        results.push({ module: row.module, source_id: row.source_id, status: row.classification });
        continue;
      }
      const adapter = adapters[row.module];
      const prior = await repository.findSourceIdentity(tx, row.module, row.source_id);
      if (prior) {
        results.push({ module: row.module, source_id: row.source_id,
          status: prior.payload_sha256 === row.payload_sha256 ? 'SKIPPED_DUPLICATE' : 'REVIEW_REQUIRED',
          target_id: prior.target_id ?? null, reason: prior.payload_sha256 === row.payload_sha256 ? 'SOURCE_ID_ALREADY_LINKED' : 'SOURCE_ID_PAYLOAD_CHANGED' });
        continue;
      }

      const conflict = await adapter.findIdentityConflict(tx, row.canonical, row);
      if (conflict) {
        results.push({ module: row.module, source_id: row.source_id, status: 'REVIEW_REQUIRED',
          reason: 'TARGET_IDENTITY_CONFLICT', conflicting_target_id: conflict.id ?? null });
        continue;
      }

      const references = {};
      let unresolved = null;
      for (const ref of row.dependencies ?? []) {
        const key = `${ref.module}\u0000${String(ref.source_id)}`;
        let mapped = identityCache.get(key);
        if (!mapped) mapped = await repository.findSourceIdentity(tx, ref.module, String(ref.source_id));
        if (!mapped?.target_id) { unresolved = ref; break; }
        references[ref.alias ?? `${ref.module}:${ref.source_id}`] = mapped.target_id;
      }
      if (unresolved) {
        results.push({ module: row.module, source_id: row.source_id, status: 'BLOCKED',
          reason: 'UNRESOLVED_FOREIGN_KEY', dependency: unresolved });
        continue;
      }

      if (mode === 'DRY_RUN') {
        results.push({ module: row.module, source_id: row.source_id, status: 'READY_TO_IMPORT',
          target_table: adapter.targetTable, dependencies_resolved: true, write_performed: false });
        continue;
      }

      const target = await adapter.insert(tx, row.canonical, references, row);
      if (!target || target.id === undefined || target.id === null) throw new Error(`Adapter ${row.module} did not return a target id.`);
      await repository.recordSourceIdentity(tx, {
        module: row.module, source_id: row.source_id, target_table: adapter.targetTable,
        target_id: target.id, payload_sha256: row.payload_sha256,
        source_reference: plan.source.reference, backup_reference: backupReference,
      });
      await repository.writeRowLog(tx, { module: row.module, source_id: row.source_id,
        target_table: adapter.targetTable, target_id: target.id, status: 'IMPORTED_PENDING_VERIFY',
        source_reference: plan.source.reference, payload_sha256: row.payload_sha256 });
      identityCache.set(sourceKey(row), { target_id: target.id, payload_sha256: row.payload_sha256 });
      results.push({ module: row.module, source_id: row.source_id, status: 'IMPORTED_PENDING_VERIFY', target_id: target.id });
    }
    return { mode, environment, source_reference: plan.source.reference, source_sha256: plan.source.sha256,
      results, summary: results.reduce((acc, row) => { acc[row.status] = (acc[row.status] ?? 0) + 1; return acc; }, {}) };
  }, { readOnly: mode === 'DRY_RUN', rollbackOnError: true });
}

async function verifyImportedRows({ plan, adapters, repository }) {
  if (!repository || typeof repository.transaction !== 'function') throw new Error('Transactional repository is required.');
  return repository.transaction(async (tx) => {
    const results = [];
    for (const row of plan.records) {
      if (row.classification !== 'READY_TO_IMPORT') continue;
      const mapping = await repository.findSourceIdentity(tx, row.module, row.source_id);
      if (!mapping?.target_id) {
        results.push({ module: row.module, source_id: row.source_id, status: 'NOT_IMPORTED' });
        continue;
      }
      const actual = await adapters[row.module].verify(tx, mapping.target_id, row.canonical, row);
      const ok = actual === true || actual?.matches === true;
      const result = { module: row.module, source_id: row.source_id, target_id: mapping.target_id,
        status: ok ? 'IMPORTED_VERIFIED' : 'REVIEW_REQUIRED', mismatches: ok ? [] : (actual?.mismatches ?? ['TARGET_VALUE_MISMATCH']) };
      if (typeof repository.writeRowLog === 'function') await repository.writeRowLog(tx, { ...result, payload_sha256: row.payload_sha256 });
      results.push(result);
    }
    return { results, summary: results.reduce((acc, row) => { acc[row.status] = (acc[row.status] ?? 0) + 1; return acc; }, {}) };
  }, { readOnly: false, rollbackOnError: true });
}

module.exports = { buildOperationalImportPlan, runOperationalImport, verifyImportedRows };
