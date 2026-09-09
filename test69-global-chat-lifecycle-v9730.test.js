"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const window = {};
vm.runInNewContext(fs.readFileSync("real-market-global-lifecycle-v9730.js", "utf8"), { window });
const state = window.RRMarketLifecycle.state;

assert.deepEqual({ ...state({ status: "READY_FOR_PI" }) }, {
  status: "READY_FOR_PI", hasPi: false, ciFinal: false, piEditable: false, canPreparePi: true
});
assert.equal(state({ status: "PI_GENERATED", pi_no: "09/001" }).piEditable, true);
assert.equal(state({ status: "DRAFT", pi_ref: "PI 12" }).piEditable, true);
assert.equal(state({ status: "WAITING_CONFIRMATION", pi_ref: "PI 13" }).piEditable, true);
assert.equal(state({ status: "CI_FINAL", pi_ref: "PI 13" }).piEditable, false);
assert.equal(state({ status: "DRAFT", customer_ci_ref: "CI 13" }).ciFinal, true);
assert.equal(state({ kind: "CI", ref: "CI 14" }).canPreparePi, false);
assert.equal(state({ status: "PI_CANCELLED", pi_ref: "PI 15" }).piEditable, true);

const open = fs.readFileSync("real-chat-requirement-open-stable-v9727.js", "utf8");
assert.doesNotMatch(open, /addEventListener\("touchstart", intercept/);
assert.doesNotMatch(open, /addEventListener\("pointerdown", intercept/);
assert.match(open, /addEventListener\("pointerup", intercept/);
assert.match(open, /EDIT PI/);

const bridge = fs.readFileSync("real-market-redzed-staff-chat-bridge-test67.js", "utf8");
assert.match(bridge, /activeBaseTitle/);
assert.match(bridge, /setText\(\$\("chatTitle"\), activeBaseTitle\)/);

console.log("TEST69 global chat lifecycle checks passed");
