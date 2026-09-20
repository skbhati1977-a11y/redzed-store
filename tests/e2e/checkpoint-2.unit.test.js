const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const migration = fs.readFileSync("supabase/migrations/20260920200000_test71_checkpoint2_canonical_accept_variance_v324.sql", "utf8");
const accept = fs.readFileSync("test70-accept-work-v205.html", "utf8");
const chat = fs.readFileSync("test70-real-chat-live-v70.js", "utf8");

test("accepted physical quantity remains canonical WORKING quantity", () => {
  assert.match(migration, /r\.status='CONFIRMED'.*r\.confirmed_qty/s);
  assert.match(migration, /status='IN_PROGRESS'/);
  assert.match(migration, /'work_status'.*'WORKING'/s);
  assert.doesNotMatch(migration, /p_counted_qty\s*>\s*v_expected.*raise exception/is);
});

test("SHORT and EXCESS are separate, colour-preserving and assignment-idempotent", () => {
  assert.match(migration, /unique index if not exists rr_upm_excess_count_v224_assignment_unique[\s\S]*assignment_id/);
  assert.match(migration, /on conflict\(assignment_id\) do update/);
  assert.match(migration, /'type','SHORT'[\s\S]*'colour',v_r\.colour_code/);
  assert.match(migration, /'type','EXCESS'[\s\S]*'colour',a\.colour_code/);
  assert.match(migration, /pg_advisory_xact_lock\(hashtextextended\(p_receipt_batch_id::text,204\)\)/);
});

test("only a genuine receipt batch requires all colours", () => {
  assert.match(migration, /r\.receipt_batch_id=p_receipt_batch_id/);
  assert.match(migration, /Count every colour in this atomic handover together/);
  assert.match(accept, /const cr=batch\.colour_rows\|\|\[\]/);
  assert.doesNotMatch(accept, /colour_rows\|\|\[\]\)\.filter/);
});

test("first tap is pending and excess is allowed", () => {
  assert.match(accept, /btn\.disabled=true;btn\.textContent='ACCEPTING…'/);
  assert.match(accept, /type="number" min="0" value=/);
  assert.doesNotMatch(accept, /type="number"[^>]*max=/);
  assert.match(accept, /Short \/ Excess remarks required/);
});

test("Personal Chat shows main WORKING card and separate variance card", () => {
  assert.match(migration, /'good_qty',good_qty,'qty',good_qty/);
  assert.match(migration, /'variance'.*'type','EXCESS'/s);
  assert.match(chat, /event_key:'RECEIPT_VARIANCE:'/);
  assert.match(chat, /source_module:'UPM_RECEIPT_VARIANCE'/);
});
