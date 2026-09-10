(() => {
  "use strict";
  const $ = id => document.getElementById(id);
  const today = new Date().toISOString().slice(0, 10);
  document.querySelectorAll('input[type="date"]').forEach(input => { if (!input.value) input.value = today; });

  function open(id) { $(id).classList.add("on"); }
  function close(id) { $(id).classList.remove("on"); }
  document.querySelectorAll("[data-start]").forEach(button => button.addEventListener("click", () => open(button.dataset.start === "cb" ? "cbBack" : "mcBack")));
  document.querySelectorAll("[data-close]").forEach(button => button.addEventListener("click", () => close(button.dataset.close)));
  document.querySelectorAll(".sheetback").forEach(back => back.addEventListener("click", event => { if (event.target === back) close(back.id); }));
  $("back").addEventListener("click", () => $("inbox").classList.toggle("hide"));
  document.querySelector('[data-open="cb"]').addEventListener("click", () => $("inbox").classList.add("hide"));

  function addChatResult(title, detail) {
    const node = document.createElement("div");
    node.className = "msg me";
    node.innerHTML = `<b>${title}</b><div>${detail}</div><time>TEST PREVIEW · ✓ SENT LOCALLY · NO DATABASE WRITE</time>`;
    $("msgs").appendChild(node);
    node.scrollIntoView({ block: "end" });
  }

  $("cbForm").addEventListener("submit", event => {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const qty = Number(data.get("roll_1")) + Number(data.get("roll_2"));
    const result = $("cbResult");
    result.textContent = `PASS · ${data.get("cb_no")} · ${data.get("divisions")} D cards · ${qty.toFixed(3)} kg · database write blocked.`;
    result.classList.add("on");
    addChatResult("CB NEW TEST PASSED", `${data.get("cb_no")} · Regular Cloth ${qty.toFixed(3)} kg`);
  });

  $("mcForm").addEventListener("submit", event => {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const qty = Number(data.get("qty"));
    const value = Number(data.get("value"));
    const rate = qty > 0 ? value / qty : 0;
    const result = $("mcResult");
    result.textContent = `PASS · MC1 IN ${qty.toFixed(3)} kg · preview average ₹${rate.toFixed(4)}/kg · database write blocked.`;
    result.classList.add("on");
    addChatResult("MC1 TEST PASSED", `Matching Cloth ${qty.toFixed(3)} kg · ₹${value.toFixed(2)}`);
  });

  window.__TEST70_CB_CHAT_PILOT__ = { mode: "AUTOMATED_TEST", databaseWrites: false, ready: true };
})();
