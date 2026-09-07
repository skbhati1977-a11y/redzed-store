(() => {
  "use strict";
  if (window.__RR_TECH_REQ_CLEANER_TEST67__) return;
  window.__RR_TECH_REQ_CLEANER_TEST67__ = true;
  const technical = (node) => {
    if (!(node instanceof Element) || !node.classList.contains("fsm")) return false;
    const text = String(node.textContent || "").replace(/\s+/g, " ").trim();
    return /\[REQ:[0-9a-f-]{20,}\]/i.test(text) && /REQUIREMENT\s+\d+/i.test(text);
  };
  const clean = () => document.querySelectorAll("#fsMsgs .fsm").forEach((node) => {
    if (technical(node)) node.remove();
  });
  const boot = () => {
    clean();
    const root = document.getElementById("fsMsgs");
    if (root) new MutationObserver(clean).observe(root, { childList: true });
  };
  document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", boot, { once: true }) : boot();
})();
