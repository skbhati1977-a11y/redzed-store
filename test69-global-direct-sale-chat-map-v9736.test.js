"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");

const main = fs.readFileSync("real-pi-specimen-v9514-replace-test.js", "utf8");
const actions = fs.readFileSync("real-pi-actions-v9707.js", "utf8");
const page = fs.readFileSync("real-pi-specimen-v9514-replace-test.html", "utf8");

assert.match(main, /customerId,customerName:ctx\.customer_name/,
  "PI document state must retain the selected canonical customer");
assert.match(main, /syncDirectPartyDiscount\(\);applyLifecycleUi\(\)/,
  "Selecting a Direct Sale customer must refresh the shared PI state");
assert.match(main, /else\{applyLifecycleUi\(\);\$\('msg'\)/,
  "Saving a Direct Sale PI must publish its current chat mapping");
assert.match(actions, /async function chatId\(\)/,
  "Real Chat send must use an asynchronous canonical mapping resolver");
assert.match(actions, /rr_sales_customer_relation_ids_v9704/,
  "Legacy customers without a cached chat ID must be repaired through canonical relation mapping");
assert.match(actions, /const id = await chatId\(\)/,
  "Real Chat send must await mapping repair before upload");
assert.match(page, /real-pi-specimen-v9514-replace-test\.js\?v=9736/);
assert.match(page, /real-pi-actions-v9707\.js\?v=9736/);

console.log("TEST69 global Direct Sale Real Chat mapping v9736 checks passed");
