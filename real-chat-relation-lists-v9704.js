(() => {
  "use strict";
  if (window.__RR_CHAT_RELATION_LISTS_V9704__) return;
  window.__RR_CHAT_RELATION_LISTS_V9704__ = true;
  const KEY = "rr_staff_chat_relation_filter_v9704";
  const saved = localStorage.getItem(KEY);
  let mode = ["DIRECT_CUSTOMER", "DISTRIBUTOR_REDZED", "WORKER_DIRECT"].includes(saved) ? saved : "DIRECT_CUSTOMER";
  const label = value => value === "DISTRIBUTOR_REDZED" ? "DISTRIBUTOR" : value === "WORKER_DIRECT" ? "WORKER" : "CUSTOMER";
  function style() {
    if (document.getElementById("rrRelationCss9704")) return;
    const s = document.createElement("style");
    s.id = "rrRelationCss9704";
    s.textContent = ".rrRelationTabs9704{position:sticky;top:0;z-index:4;display:grid;grid-template-columns:1fr 1fr 1fr;gap:7px;padding:8px;background:#10161f;border-bottom:1px solid #293343}.rrRelationTabs9704 button{min-height:42px;border:1px solid #43536b;border-radius:10px;background:#182535;color:#cbd5e1;font-weight:900}.rrRelationTabs9704 button.on{background:#176ca8;border-color:#73c5ff;color:#fff}.chatrow[data-relation].rrRelationHidden9704{display:none!important}.rrRelationBadge9704{display:inline-block;margin-top:4px;padding:2px 6px;border:1px solid #45617d;border-radius:999px;color:#90caff;font-size:9px;font-weight:900}";
    document.head.appendChild(s);
  }
  function apply() {
    document.querySelectorAll("#inboxRows .chatrow[data-relation]").forEach(row => {
      row.classList.toggle("rrRelationHidden9704", row.dataset.relation !== mode);
      let badge = row.querySelector(".rrRelationBadge9704");
      if (!badge) { badge = document.createElement("span"); badge.className = "rrRelationBadge9704"; row.appendChild(badge); }
      badge.textContent = label(row.dataset.relation);
    });
    document.querySelectorAll("#rrRelationTabs9704 [data-relation-filter]").forEach(b => b.classList.toggle("on", b.dataset.relationFilter === mode));
  }
  function select(next) {
    mode = next; localStorage.setItem(KEY, mode); apply();
    if (window.__RR_CURRENT_CHAT_RELATION__ && window.__RR_CURRENT_CHAT_RELATION__ !== mode) {
      document.getElementById("inbox")?.classList.remove("hide");
    }
  }
  function init() {
    style();
    const inbox = document.getElementById("inbox"), head = inbox?.querySelector(".head");
    if (!inbox || !head) return;
    if (!document.getElementById("rrRelationTabs9704")) {
      head.insertAdjacentHTML("afterend", '<div id="rrRelationTabs9704" class="rrRelationTabs9704"><button data-relation-filter="DIRECT_CUSTOMER">CUSTOMERS</button><button data-relation-filter="DISTRIBUTOR_REDZED">DISTRIBUTORS</button><button data-relation-filter="WORKER_DIRECT">WORKERS</button></div>');
      document.querySelectorAll("#rrRelationTabs9704 [data-relation-filter]").forEach(b => b.onclick = () => select(b.dataset.relationFilter));
    }
    apply();
    new MutationObserver(apply).observe(document.getElementById("inboxRows"), { childList: true });
  }
  document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", init, { once: true }) : init();
})();
