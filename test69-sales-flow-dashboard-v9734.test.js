"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");

const page = fs.readFileSync("real-sales-flow-dashboard-test69-v9734.html", "utf8");
const links = [...page.matchAll(/href="([^"]+)"/g)].map((match) => match[1].replaceAll("&amp;", "&"));

for (const required of [
  "real-sales-live-chat-v9434.html",
  "real-market-distributor-test67.html",
  "real-pi-specimen-v9514-replace-test.html",
  "real-market-staff-batch-test67.html",
  "real-accounts-v805.html",
  "real-finished-goods-v787.html",
]) {
  assert.ok(links.some((link) => link.startsWith(required)), `Missing dashboard route: ${required}`);
  assert.ok(fs.existsSync(required), `Dashboard target does not exist: ${required}`);
}

assert.match(page, /Chat \+ Requirement stable/);
assert.match(page, /Accounts bridge pending/);
assert.match(page, /Inventory bridge pending/);
assert.match(page, /MAIN unchanged/);
console.log("TEST69 sales flow dashboard checks passed");
