"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");

const main = fs.readFileSync("real-pi-specimen-v9514-replace-test.js", "utf8");
const requirementHelper = fs.readFileSync("real-pi-party-discount-test-v9557.js", "utf8");
const page = fs.readFileSync("real-pi-specimen-v9514-replace-test.html", "utf8");

assert.match(requirementHelper, /entry_mode'\)===\'DIRECT_SALE\'\)return/,
  "Requirement-only discount helper must not mount in Direct Sale");
assert.match(main, /function syncDirectPartyDiscount\(\)/,
  "Direct Sale must expose one canonical row-normalization path");
assert.match(main, /discount:DIRECT\?directPartyDiscount\(\)/,
  "New and replaced Direct Sale rows must use the selected party discount");
assert.match(main, /x\.allowed=DIRECT\?directPartyDiscount\(\)/,
  "Revalidated Direct Sale rows must preserve the selected party discount");
assert.match(main, /syncDirectPartyDiscount\(\);const d=directPartyDiscount\(\);/,
  "Legacy/current rows must normalize immediately before Direct Sale save");
assert.doesNotMatch(main, /Direct Sale की सभी rows में selected party discount समान होना चाहिए/,
  "A stale hidden row must not block a valid Direct Sale");
assert.match(page, /real-pi-party-discount-test-v9557\.js\?v=9735/);
assert.match(page, /real-pi-specimen-v9514-replace-test\.js\?v=9735/);

console.log("TEST69 global Direct Sale discount v9735 checks passed");
