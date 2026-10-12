'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const { buildOperationalImportPlan, runOperationalImport } = require('./redzed-operational-import-core.test71.cjs');

const SOURCE_APP = 'Redzed Clothing';
const TARGET_ART_TABLE = 'public.rr_art_master_core_v402';
const ART_ADAPTER = Object.freeze({
  targetTable: TARGET_ART_TABLE,
  testModeOnly: true,
  writeMode: 'insert-only',
  sideEffectFree: true,
  // Operational writes are implemented in one PostgreSQL RPC transaction.
  // These methods deliberately fail if someone removes that atomic writer.
  findIdentityConflict: async () => { throw new Error('Use the transactional Supabase batch writer.'); },
  insert: async () => { throw new Error('Use the transactional Supabase batch writer.'); },
  verify: async () => { throw new Error('Use the transactional Supabase batch writer.'); },
});

function text(value) {
  if (value === null || value === undefined) return null;
  const result = String(value).trim();
  return result || null;
}

function mapArtMasterRow(raw) {
  const sourceId = text(raw?.ID);
  const artNo = text(raw?.art_no);
  const itemName = text(raw?.['Item Name']);
  const statusIsExact = raw?.art_status === 'NAME_CODE_MASTER_ID_AGREES'
    && sourceId !== null && artNo === sourceId;
  const rawImage = text(raw?.image_source);
  const sourceImageUrl = rawImage?.replace(/^http:\/\//i, 'https://') ?? null;
  const imageIsTrusted = Boolean(sourceImageUrl)
    && /^https:\/\/redzedclothing\.in\/uploads\/[^\s]+$/i.test(sourceImageUrl);
  const classification = !statusIsExact
    ? 'REVIEW_REQUIRED'
    : (!imageIsTrusted ? 'BLOCKED' : 'READY_TO_IMPORT');
  return {
    module: 'ART',
    source_id: sourceId,
    source_updated_at: text(raw?.['Created At']),
    raw,
    canonical: {
      art_no: artNo,
      item_name: itemName,
      product_name: itemName,
      category: null,
      art_category_id: null,
      source_image_url: sourceImageUrl,
    },
    classification,
    dependencies: [],
  };
}

function buildArtDataset({ sourceReference, sourceSha256, rows }) {
  return {
    format: 'redzed-ci-operational-import/v1',
    source: { application: SOURCE_APP, reference: sourceReference, sha256: sourceSha256 },
    records: rows.map(mapArtMasterRow),
  };
}

class SupabaseOperationalRepository {
  constructor({ url, serviceRoleKey, fetchImpl = globalThis.fetch }) {
    if (!url || !serviceRoleKey || typeof fetchImpl !== 'function') {
      throw new Error('TEST Supabase URL, service role key, and fetch are required.');
    }
    const parsed = new URL(url);
    if (parsed.hostname !== 'hruartsemierwhtzonei.supabase.co') {
      throw new Error('Refusing to connect: expected the approved CI TEST Supabase project.');
    }
    this.url = parsed.origin;
    this.serviceRoleKey = serviceRoleKey;
    this.fetchImpl = fetchImpl;
  }

  async request(route, { method = 'GET', body, prefer } = {}) {
    const headers = {
      apikey: this.serviceRoleKey,
      Authorization: `Bearer ${this.serviceRoleKey}`,
      Accept: 'application/json',
    };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (prefer) headers.Prefer = prefer;
    const response = await this.fetchImpl(`${this.url}/rest/v1/${route}`, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    });
    const textBody = await response.text();
    if (!response.ok) throw new Error(`TEST Supabase request failed (${response.status}): ${textBody.slice(0, 600)}`);
    return textBody ? JSON.parse(textBody) : null;
  }

  async runOperationalBatch({ plan, mode, environment, backupReference }) {
    if (plan.records.some((row) => row.module !== 'ART')) {
      throw new Error('The first TEST writer only supports ART records; split other modules into separate adapters.');
    }
    const response = await this.request('rpc/rr_import_redzed_art_batch_test71', {
      method: 'POST',
      body: {
        p_source_app: plan.source.application,
        p_source_reference: plan.source.reference,
        p_source_sha256: plan.source.sha256,
        p_environment: environment,
        p_mode: mode,
        p_backup_reference: backupReference,
        p_records: plan.records,
      },
    });
    const results = response?.results ?? [];
    if (mode === 'APPLY') {
      for (const result of results) {
        if (result.status !== 'IMPORTED_PENDING_VERIFY') continue;
        const source = plan.records.find((row) => row.module === result.module && row.source_id === result.source_id);
        const verified = await this.verifyArt(result, source);
        if (verified) {
          const filter = new URLSearchParams({
            source_app: `eq.${plan.source.application}`,
            source_module: 'eq.ART',
            source_id: `eq.${result.source_id}`,
          });
          await this.request(`rr_operational_source_identity_test71?${filter}`, {
            method: 'PATCH', body: { status: 'IMPORTED_VERIFIED' }, prefer: 'return=minimal',
          });
          const logFilter = new URLSearchParams({
            source_app: `eq.${plan.source.application}`,
            source_module: 'eq.ART',
            source_id: `eq.${result.source_id}`,
            status: 'eq.IMPORTED_PENDING_VERIFY',
          });
          await this.request(`rr_operational_import_row_log_test71?${logFilter}`, {
            method: 'PATCH', body: { status: 'IMPORTED_VERIFIED', reason: 'OPERATIONAL_VIEW_AND_MEDIA_READBACK_MATCHED' }, prefer: 'return=minimal',
          });
          result.status = 'IMPORTED_VERIFIED';
          result.verification = 'rr_art_master view and rr_media read-back matched';
        } else {
          result.status = 'REVIEW_REQUIRED';
          result.reason = 'POST_IMPORT_READBACK_MISMATCH';
        }
      }
    }
    return {
      mode, environment, source_reference: plan.source.reference,
      results,
      summary: results.reduce((acc, row) => { acc[row.status] = (acc[row.status] ?? 0) + 1; return acc; }, {}),
    };
  }

  async verifyArt(result, source) {
    const artFilter = new URLSearchParams({
      select: 'id,art_no,item_name,product_name,category',
      id: `eq.${result.target_id}`,
    });
    const arts = await this.request(`rr_art_master?${artFilter}`);
    const art = arts?.[0];
    const coreFilter = new URLSearchParams({ select: 'id,default_margin', id: `eq.${result.target_id}` });
    const coreRows = await this.request(`rr_art_master_core_v402?${coreFilter}`);
    const core = coreRows?.[0];
    if (!art || art.art_no !== source.canonical.art_no
      || art.item_name !== source.canonical.item_name
      || art.product_name !== source.canonical.product_name
      || art.category !== null || !core || Number(core.default_margin) !== 22) return false;
    const mediaFilter = new URLSearchParams({
      select: 'id,entity_type,entity_id,file_url,is_cover,storage_path',
      id: `eq.${result.media_id}`,
    });
    const mediaRows = await this.request(`rr_media?${mediaFilter}`);
    const media = mediaRows?.[0];
    return Boolean(media && media.entity_type === 'art'
      && media.entity_id === result.target_id
      && media.file_url === source.canonical.source_image_url
      && media.is_cover === true && media.storage_path === null);
  }
}

async function runFromFile({ inputPath, mode = 'DRY_RUN', environment = 'TEST', backupReference = null, outputPath = null, repository = null }) {
  const dataset = JSON.parse(await fs.readFile(inputPath, 'utf8'));
  const plan = buildOperationalImportPlan({ dataset, adapters: { ART: ART_ADAPTER } });
  const repo = repository || new SupabaseOperationalRepository({
    url: process.env.CI_TEST_SUPABASE_URL,
    serviceRoleKey: process.env.CI_TEST_SUPABASE_SERVICE_ROLE_KEY,
  });
  const result = await runOperationalImport({ plan, adapters: { ART: ART_ADAPTER }, repository: repo, mode, environment, backupReference });
  if (outputPath) await fs.writeFile(outputPath, `${JSON.stringify(result, null, 2)}\n`);
  return result;
}

if (require.main === module) {
  (async () => {
    const [modeArg, inputPath, outputPath] = process.argv.slice(2);
    const mode = modeArg || 'DRY_RUN';
    if (!['DRY_RUN','APPLY'].includes(mode) || !inputPath) {
      throw new Error('Usage: node scripts/redzed-operational-import-supabase.test71.cjs DRY_RUN|APPLY <dataset.json> [report.json]');
    }
    const backupReference = mode === 'APPLY' ? process.env.CI_IMPORT_BACKUP_REFERENCE : null;
    const result = await runFromFile({ inputPath: path.resolve(inputPath), mode, environment: 'TEST', backupReference,
      outputPath: outputPath ? path.resolve(outputPath) : null });
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  })().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
}

module.exports = { ART_ADAPTER, SupabaseOperationalRepository, buildArtDataset, mapArtMasterRow, runFromFile };
