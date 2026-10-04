const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');

const root=path.resolve(__dirname,'../..');
const cb=fs.readFileSync(path.join(root,'real-cb-new-v9130-fix2.html'),'utf8');
const migration=fs.readFileSync(
  path.join(root,'supabase/migrations/20261004072000_test71_cb_requirement_whatsapp_media_share_v1.sql'),
  'utf8'
);

test('CB requirement WhatsApp uses native multi-file share instead of direct supplier number URL',()=>{
  assert.ok(cb.includes("navigator.share({title:'CB '"));
  assert.ok(cb.includes("files:shareFiles"));
  assert.ok(cb.includes("https://api.whatsapp.com/send?text="));
  const block=cb.slice(cb.indexOf('async function sendDerivedRequirementWhatsApp'),cb.indexOf('const CB_COMBO_MASTER_META'));
  assert.ok(!block.includes("https://wa.me/"));
  assert.ok(!block.includes("phone="));
});

test('CB requirement share builds JPEG and PDF with numbered thumbnails',()=>{
  assert.ok(cb.includes('requirementReportJpegFile'));
  assert.ok(cb.includes('requirementReportPdfFile'));
  assert.ok(cb.includes('jspdf.umd.min.js'));
  assert.ok(cb.includes("String(x.index)+'. '"));
  assert.ok(cb.includes("String(index).padStart(2,'0')"));
  assert.ok(cb.includes("allFiles=[report.file,...(pdf?[pdf]:[]),...thumbFiles]"));
});

test('share caption carries Appx, Cutting and Required details',()=>{
  assert.ok(cb.includes("'Appx PCS: '"));
  assert.ok(cb.includes("'Cutting PCS: '"));
  assert.ok(cb.includes("'Required: '"));
  assert.ok(cb.includes("'Set / Profile: '"));
});

test('backend share context returns item, art, print and colour media when available',()=>{
  for(const token of [
    "entity_type='art'",
    "entity_type='printing'",
    "entity_type='sticker_master_v803'",
    "entity_type='metal_id_master_v803'",
    "'COLOUR' kind",
    "'attachments'"
  ]) assert.ok(migration.includes(token),token);
});

test('mapped supplier mobile is optional for manual WhatsApp contact share',()=>{
  assert.ok(!migration.includes("Supplier WhatsApp mobile required."));
  assert.ok(!migration.includes("Supplier required before WhatsApp send."));
});
