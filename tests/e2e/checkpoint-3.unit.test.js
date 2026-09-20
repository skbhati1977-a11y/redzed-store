const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const migration = fs.readFileSync('supabase/migrations/20260920213000_test71_checkpoint3_canonical_media_master_security_v325.sql', 'utf8');
const printAuth = fs.readFileSync('supabase/migrations/20260920214500_test71_checkpoint3_print_master_canonical_auth_v326.sql', 'utf8');
const productAuth = fs.readFileSync('supabase/migrations/20260920220000_test71_checkpoint3_product_master_superadmin_v327.sql', 'utf8');
const common = fs.readFileSync('real-common.js', 'utf8');

test('canonical thumbnail stays compact, Art-first, colour-aware and safe', () => {
  assert.match(chat, /\[\["Art"/);
  assert.match(chat, /colourRows=.*filter/);
  assert.match(chat, /m\.length>1\?'<b>\+'\+\(m\.length-1\)/);
  assert.match(chat, /validMediaUrl/);
  assert.match(chat, /mediaByUnit\.get\(unit\).*mediaByLot\.get\(lot\).*mediaByCb\.get\(cb\)/);
});

test('canonical media map includes colour-specific media and master writes are protected', () => {
  assert.match(migration, /create or replace function public\.rr_real_chat_media_map_v1/);
  assert.match(migration, /'colour_images'/);
  assert.match(migration, /'colour_code'/);
  assert.match(migration, /revoke execute on function public\.rr_upsert_sticker_master_v804.*from anon/);
  assert.match(migration, /rr_art_master_art_no_normalized_uq/);
  assert.match(printAuth, /rr_print_master_owner_admin_insert/);
  assert.match(printAuth, /with check \(public\.rr_is_owner_or_admin\(\)\)/);
  assert.match(productAuth, /rr_can_manage_product_masters_v327/);
  assert.match(productAuth, /'owner','admin','super_admin'/);
  assert.match(common, /"owner","admin","super_admin"/);
});
