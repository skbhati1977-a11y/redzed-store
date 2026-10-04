const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');

const root=path.resolve(__dirname,'../..');
const cb=fs.readFileSync(path.join(root,'real-cb-new-v9130-fix2.html'),'utf8');
const live=fs.readFileSync(path.join(root,'r.html'),'utf8');
const migration=fs.readFileSync(
  path.join(root,'supabase/migrations/20261004084847_test71_cb_requirement_live_update_v3.sql'),
  'utf8'
);
const shareBlock=cb.slice(
  cb.indexOf('async function sendDerivedRequirementWhatsApp'),
  cb.indexOf('const CB_COMBO_MASTER_META')
);

test('CB requirement share uses the native manual contact picker with exactly one receipt',()=>{
  assert.ok(shareBlock.includes("navigator.share({title:'CB '"));
  assert.ok(shareBlock.includes("text:'LIVE UPDATE: '+ctx.live_update_url"));
  assert.ok(shareBlock.includes('files:[receiptFile]'));
  assert.ok(shareBlock.includes('rr_cb_requirement_receipt_record_v2'));
  assert.ok(!shareBlock.includes('https://wa.me/'));
  assert.ok(!shareBlock.includes('api.whatsapp.com'));
  assert.ok(!shareBlock.includes('phone='));
  assert.ok(!shareBlock.includes('shareFiles'));
});

test('one requirement receipt supports JPG or PDF, numbered thumbnails and LIVE UPDATE',()=>{
  assert.ok(cb.includes('requirementReportJpegFile'));
  assert.ok(cb.includes('requirementReportPdfFile'));
  assert.ok(cb.includes('jspdf.umd.min.js'));
  assert.ok(cb.includes('qrcodejs@1.0.0'));
  assert.ok(cb.includes("String(item.index)+'. '"));
  assert.ok(cb.includes("String(index).padStart(2,'0')"));
  assert.ok(cb.includes("pdf.textWithLink('LIVE UPDATE'"));
  assert.ok(cb.includes('REQUIREMENT-RECEIPT'));
  assert.ok(!shareBlock.includes('allFiles='));
});

test('receipt carries required fields and a colour-by-colour Appx/Actual table',()=>{
  for(const token of [
    "'CB No: '",
    "'Item: '",
    "'Set / Profile: '",
    "'Appx PCS: '",
    "'Cutting PCS: '",
    "'Required: '",
    "'Revision: R'",
    "'Mode: '",
    "'Supplier: '",
    "'Short Note: '",
    "'LIVE UPDATE: '",
    "'COLOUR-WISE PCS · '",
    'Actual PCS',
    'Use PCS'
  ]) assert.ok(cb.includes(token),token);
});

test('backend receipt context returns item, art, print, sticker, metal and colour media',()=>{
  for(const token of [
    "entity_type='material_master_v805'",
    "entity_type='art'",
    "entity_type='printing'",
    "entity_type='sticker_master_v803'",
    "entity_type='metal_id_master_v803'",
    "'ITEM / COLOUR' kind",
    "'attachments'",
    "'colour_projection'"
  ]) assert.ok(migration.includes(token),token);
});

test('cutting projection covers single and multi lot colour breakups',()=>{
  assert.ok(migration.includes('rr_cutting_breakup_v3'));
  assert.ok(migration.includes('rr_production_lot_breakup_v3'));
  assert.ok(migration.includes("'mode',case"));
  assert.ok(migration.includes("'HYBRID'"));
  assert.ok(migration.includes("'source_mode'"));
});

test('LIVE UPDATE is permanent, token-only and switches only after full receipt confirmation',()=>{
  assert.ok(migration.includes('rr_cb_requirement_live_link_v1'));
  assert.ok(migration.includes('rr_cb_requirement_live_projection_v1'));
  assert.ok(migration.includes('rr_cb_requirement_received_confirm_v1'));
  assert.ok(migration.includes("'CLOSE REQUIREMENT'"));
  assert.ok(migration.includes('fully_received_confirmed'));
  assert.ok(migration.includes('grant execute on function public.rr_cb_requirement_live_projection_v1(text)'));
  assert.ok(migration.includes('to anon,authenticated'));
  assert.ok(migration.includes('v_purchase_received+0.0005>=v_required'));
  assert.ok(migration.includes('v_purchase_pending=0'));
});

test('public supplier slip is read-only, polls one projection and does not load the app config',()=>{
  assert.ok(live.includes('REQUIREMENT SLIP PROJECTION'));
  assert.ok(live.includes("client.rpc('rr_cb_requirement_live_projection_v1'"));
  assert.ok(live.includes('setInterval(refresh,10000)'));
  assert.ok(live.includes('Read-only supplier slip · no app access'));
  assert.ok(live.includes('CLOSE REQUIREMENT'));
  assert.ok(!live.includes('config.js'));
  assert.ok(!live.includes('persistSession:true'));
});

test('supplier mobile remains optional and no direct-number requirement is introduced',()=>{
  assert.ok(!migration.includes('Supplier WhatsApp mobile required.'));
  assert.ok(!migration.includes('Supplier required before WhatsApp send.'));
  assert.ok(!shareBlock.includes('supplier_mobile'));
});
