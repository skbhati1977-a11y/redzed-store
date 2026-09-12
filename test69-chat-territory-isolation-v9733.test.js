"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

(async () => {
  let releaseOld;
  const oldResponse = new Promise((resolve) => { releaseOld = resolve; });
  const calls = [];
  const RF853 = {
    async rpc(name, args) {
      calls.push({ name, args });
      if (args.p_chat_id === "veer-chat") return oldResponse;
      if (args.p_test_requirement) return [{ id: "legacy-requirement", sender_name: "Veer Bhati", message_type: "REQUIREMENT", body: "[REQ:00000000-0000-0000-0000-000000000001]" }];
      return [{ id: "rika-message", sender_name: "Rika Bhati", body: "Current chat" }];
    },
  };
  const window = { RF853, __RR_CURRENT_CHAT_ID__: "veer-chat" };
  const document = { getElementById: () => ({ textContent: "Rika Bhati" }) };
  vm.runInNewContext(fs.readFileSync("real-chat-sender-alignment-v9732.js", "utf8"), { window, RF853, document });

  const pending = RF853.rpc("rr_chat_staff_messages_v9434", { p_chat_id: "veer-chat", p_channel: "GROUP" });
  window.__RR_CURRENT_CHAT_ID__ = "rika-chat";
  releaseOld([{ id: "veer-message", sender_name: "Veer Bhati", body: "Hi" }]);
  const rows = await pending;

  assert.equal(calls.length, 2);
  assert.equal(calls[1].args.p_chat_id, "rika-chat");
  assert.equal(rows[0].id, "rika-message");

  const requirement = await RF853.rpc("rr_chat_staff_messages_v9434", { p_chat_id: "rika-chat", p_test_requirement: true });
  assert.equal(requirement[0].sender_name, "Rika Bhati");
  console.log("TEST69 chat territory isolation checks passed");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
