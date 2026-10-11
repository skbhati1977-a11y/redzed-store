const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const context={window:{}};vm.runInNewContext(fs.readFileSync('test71-source-intake.js','utf8'),context);const {csv,inspect}=context.window.RRSourceIntake71;
const source=(key,date='2025-03-15')=>({module:'CUSTOMERS',source_key:key,record_date:date,evidence_status:'KNOWN',values:{name:key},references:[]});
test('earliest supplied date controls cutoff without using today',()=>{
 const result=inspect([source('later','2026-04-01'),source('first')]);assert.equal(result.earliest_source_date,'2025-03-15');assert.equal(result.latest_source_date,'2026-04-01');assert.equal(result.findings.length,0);assert.equal(result.cleared_for_import,false);assert.equal(result.business_records_posted,0);
});
test('unknown, invalid dates, duplicates and missing references remain visible',()=>{
 const a=source('same','2026-02-30');a.evidence_status='UNKNOWN';a.references=[{module:'LEDGERS',source_key:'missing'}];
 const findings=inspect([a,source('same')]).findings.map(row=>row.code);
 for(const code of ['RECORD_DATE','UNKNOWN_EVIDENCE','DUPLICATE_SOURCE_KEY','UNRESOLVED_SOURCE_REFERENCE'])assert.ok(findings.includes(code));
});
test('zero is explicit and N/A requires source reason; originals remain unchanged',()=>{
 const a=source('zero');a.evidence_status='ZERO';a.values={amount:0};const b=source('na');b.evidence_status='NOT_APPLICABLE';
 const result=inspect([a,b]);assert.equal(result.rows[0].values.amount,0);assert.ok(result.findings.some(f=>f.code==='NA_REASON'));assert.equal(a.module,'CUSTOMERS');
});
test('CSV preserves quoted commas, multiline source notes and leading-zero identifiers',()=>{
 const text='module,source_key,record_date,evidence_status,values_json,references_json,note\r\nCUSTOMERS,001,2025-03-15,KNOWN,"{""name"":""A, B""}",[],"first\nsecond"\r\n';
 const rows=csv(text);assert.equal(rows[0].source_key,'001');assert.equal(rows[0].values.name,'A, B');assert.equal(rows[0].original_csv.note,'first\nsecond');assert.equal(inspect(rows).findings.length,0);
});
test('malformed CSV and arbitrary column mappings cannot silently change source meaning',()=>{
 assert.throws(()=>csv('name,date\nWorker,2026-01-01'),/Missing CSV column/);
 assert.throws(()=>csv('module,module\nx,y'),/unique/);
 assert.throws(()=>csv('"unfinished'),/Unclosed/);
 assert.throws(()=>inspect([]),/1–10000/);
});
test('source reference resolves only to the supplied explicit master key',()=>{
 const a=source('master'),b=source('sale');b.module='SALES';b.references=[{module:'CUSTOMERS',source_key:'master'}];
 assert.equal(inspect([a,b]).findings.length,0);b.references[0].source_key='001';assert.ok(inspect([a,b]).findings.some(f=>f.code==='UNRESOLVED_SOURCE_REFERENCE'));
});
test('opening GL checks exact decimal balance without rounding away a difference',()=>{
 const gl=(key,debit,credit)=>({...source(key),module:'OPENING_GL',values:{ledger_key:key,debit,credit}});
 assert.equal(inspect([gl('a','0.10',0),gl('b','0.20',0),gl('c',0,'0.30')]).findings.length,0);
 assert.ok(inspect([gl('a','9007199254740993.01',0),gl('b',0,'9007199254740993.00')]).findings.some(f=>f.code==='OPENING_GL_UNBALANCED'));
 for(const debit of [null,'',-1,true,'NaN','Infinity'])assert.ok(inspect([gl('bad',debit,0)]).findings.some(f=>f.code==='OPENING_GL_VALUES'));
 assert.ok(inspect([gl('both',1,1)]).findings.some(f=>f.code==='OPENING_GL_VALUES'));
});
test('opening stock and WIP preserve unknown values and reject false zero evidence',()=>{
 for(const module of ['OPENING_STOCK','OPENING_WIP']){
  const row={...source('stock'),module,evidence_status:'ZERO',values:{item_key:'A001',unit:'PCS',quantity:0,value:0}};
  assert.equal(inspect([row]).findings.length,0);
  row.values.quantity=1;assert.ok(inspect([row]).findings.some(f=>f.code==='OPENING_STOCK_VALUES'));
  row.evidence_status='UNKNOWN';row.values.quantity=null;assert.ok(inspect([row]).findings.some(f=>f.code==='UNKNOWN_EVIDENCE'));assert.equal(row.values.quantity,null);
 }
});
test('duplicate master keys cannot satisfy source references',()=>{
 const sale={...source('sale'),module:'SALES',references:[{module:'CUSTOMERS',source_key:'master'}]};
 assert.ok(inspect([source('master'),source('master'),sale]).findings.some(f=>f.row_no===3&&f.code==='UNRESOLVED_SOURCE_REFERENCE'));
});
