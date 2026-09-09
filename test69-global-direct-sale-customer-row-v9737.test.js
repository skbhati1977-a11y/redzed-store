"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");

const main = fs.readFileSync("real-pi-specimen-v9514-replace-test.js", "utf8");
const page = fs.readFileSync("real-pi-specimen-v9514-replace-test.html", "utf8");

assert.match(main, /if\(DIRECT&&!customerId\)\{await loadDirectCustomers\(\$\('customer'\)\.value\);pickDirectCustomer\(\)\}/,
  "Add Row must re-resolve an exact list customer when mobile change did not commit state");
assert.match(main, /customerId=saved\.customer_id/,
  "A newly saved customer must become selected immediately");
assert.match(main, /const relations=await rpc\('rr_sales_customer_relation_ids_v9704'/,
  "Saving a customer must resolve its canonical Direct Customer chat");
assert.match(main, /\$\('addLot'\)\.value='';\$\('addQty'\)\.value='';\$\('addAvailable'\)\.value='—';\$\('addPack'\)\.value='—'/,
  "Successful Add Row must explicitly clear all add-lot inputs");
assert.doesNotMatch(main, /SAVE se pehle phir stock check hoga\.`;\$\('addLot'\)\.focus\(\)/,
  "Successful Add Row must not refocus and repopulate the cleared lot field");
assert.match(page, /real-pi-specimen-v9514-replace-test\.js\?v=9737/);

console.log("TEST69 global Direct Sale customer/add-row v9737 checks passed");
