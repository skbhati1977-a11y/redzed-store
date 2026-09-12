(() => {
  "use strict";
  if (window.__RR_CHAT_CHRONOLOGICAL_ORDER_V9719__) return;
  window.__RR_CHAT_CHRONOLOGICAL_ORDER_V9719__ = true;
  let sorting = false;

  function stamp(node) {
    const text = String(node.querySelector("time")?.textContent || "").trim();
    const parts = text.match(/(\d{1,2})\/(\d{1,2})\/(\d{4}),?\s+(\d{1,2}):(\d{2}):(\d{2})/);
    if (parts) return new Date(+parts[3], +parts[2] - 1, +parts[1], +parts[4], +parts[5], +parts[6]).getTime();
    const parsed = Date.parse(text);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function sortTimeline() {
    if (sorting) return;
    const root = document.getElementById("msgs");
    if (!root) return;
    const rows = [...root.querySelectorAll(":scope > .msg")];
    if (rows.length < 2) return;
    const sorted = rows.slice().sort((a, b) =>
      stamp(a) - stamp(b) || String(a.dataset.msgId || "").localeCompare(String(b.dataset.msgId || ""))
    );
    if (sorted.every((row, index) => row === rows[index])) return;
    const atBottom = root.scrollHeight - root.scrollTop - root.clientHeight < 100;
    const oldTop = root.scrollTop;
    sorting = true;
    try {
      sorted.forEach((row) => root.appendChild(row));
      root.scrollTop = atBottom ? root.scrollHeight : oldTop;
    } finally {
      sorting = false;
    }
  }

  function bind() {
    const root = document.getElementById("msgs");
    if (!root || root.dataset.rrChronological9719 === "1") return false;
    root.dataset.rrChronological9719 = "1";
    new MutationObserver(() => queueMicrotask(sortTimeline)).observe(root, { childList: true });
    sortTimeline();
    return true;
  }

  function boot() {
    if (bind()) return;
    let tries = 0;
    const timer = setInterval(() => {
      if (bind() || ++tries > 60) clearInterval(timer);
    }, 100);
  }
  document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", boot, { once: true }) : boot();
})();
