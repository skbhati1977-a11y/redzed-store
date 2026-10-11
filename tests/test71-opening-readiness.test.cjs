'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { inspectOpening } = require('../scripts/test71-opening-readiness.cjs');
const fixture = () => ({ source_ref:'synthetic-rollback-only',source_sha256:'a'.repeat(64),approved_cutoff:'2026-10-01',approval_evidence_ref:'synthetic-not-business-approval',approved_ledger_mapping:{inventory:'STOCK',equity:'EQUITY'},not_applicable_evidence:{WIP:'synthetic explicit no WIP'},rows:[
 {module:'OPENING_GL',source_key:'stock',record_date:'2026-10-01',evidence_status:'KNOWN',values:{ledger_key:'inventory',debit:'10.10',credit:'0'}},
 {module:'OPENING_GL',source_key:'equity',record_date:'2026-10-01',evidence_status:'KNOWN',values:{ledger_key:'equity',debit:'0',credit:'10.10'}},
 {module:'OPENING_STOCK',source_key:'item',record_date:'2026-10-01',evidence_status:'KNOWN',values:{item_key:'item',unit:'PCS',quantity:'2',value:'10.10'}} ]});
test('balanced source reconciles exactly but never grants import clearance',()=>{ const r=inspectOpening(fixture());assert.equal(r.checks_passed,true);assert.equal(r.cleared_for_import,false);assert.equal(r.business_records_posted,0);assert.equal(r.totals.stock_gl,'10.10'); });
test('balanced GL cannot hide physical valuation mismatch',()=>{const s=fixture();s.rows[2].values.value='10.09';assert(inspectOpening(s).findings.some(f=>f.code==='STOCK_GL_MISMATCH'));});
test('unknown and false zero remain blocked',()=>{const s=fixture();s.rows[2].evidence_status='UNKNOWN';assert(inspectOpening(s).findings.some(f=>f.code==='UNKNOWN_OPENING'));s.rows[2].evidence_status='ZERO';assert(inspectOpening(s).findings.some(f=>f.code==='FALSE_ZERO'));});
test('missing source and unapproved mappings stay pending',()=>{assert(inspectOpening({}).findings.some(f=>f.code==='SOURCE_MISSING'));const s=fixture();s.approved_ledger_mapping={};assert(inspectOpening(s).findings.some(f=>f.code==='LEDGER_MAPPING_UNAPPROVED'));});
test('invalid date and mismatched cutoff cannot be accepted',()=>{const s=fixture();s.rows[2].record_date='2026-02-30';const r=inspectOpening(s);assert(r.findings.some(f=>f.code==='DATE_INVALID'));assert(r.findings.some(f=>f.code==='OPENING_CUTOFF_MISMATCH'));});
test('missing WIP coverage cannot silently become zero',()=>{const s=fixture();delete s.not_applicable_evidence.WIP;assert(inspectOpening(s).findings.some(f=>f.code==='WIP_COVERAGE_UNKNOWN'));});
test('malformed rows return findings without crashing',()=>{const s=fixture();s.rows.push(null,'bad',[]);assert.equal(inspectOpening(s).findings.filter(f=>f.code==='ROW_INVALID').length,3);});
test('whitespace evidence and empty mappings remain blocked',()=>{const s=fixture();s.source_ref=' ';s.approval_evidence_ref=' ';s.rows[2].values.unit=' ';s.approved_ledger_mapping.inventory=' ';const r=inspectOpening(s);for(const code of ['SOURCE_EVIDENCE_MISSING','APPROVAL_EVIDENCE_MISSING','STOCK_VALUES_INVALID','LEDGER_MAPPING_UNAPPROVED'])assert(r.findings.some(f=>f.code===code));});
test('tiny positive quantities never underflow into false zero',()=>{const s=fixture();s.rows[2].evidence_status='ZERO';s.rows[2].values.quantity='0.'+'0'.repeat(400)+'1';s.rows[2].values.value='0';assert(inspectOpening(s).findings.some(f=>f.code==='FALSE_ZERO'));});
test('invalid evidence states never contribute to totals',()=>{const s=fixture();s.rows[0].evidence_status='INVALID';assert.equal(inspectOpening(s).totals.debit,'0.00');});
test('negative inventory GL preserves its sign',()=>{const s=fixture();s.rows[0].values.debit='0';s.rows[0].values.credit='0.50';assert.equal(inspectOpening(s).totals.stock_gl,'-0.50');});
test('malformed CLI input exits with controlled error',()=>{const {spawnSync}=require('node:child_process');const r=spawnSync(process.execPath,['scripts/test71-opening-readiness.cjs','/dev/null'],{encoding:'utf8'});assert.equal(r.status,2);assert.match(r.stderr,/valid JSON/);assert.doesNotMatch(r.stderr,/SyntaxError|at /);});
