(() => {
  "use strict";
  if (window.__RR_CUSTOMER_CYCLE_CARD_V9688__) return;
  window.__RR_CUSTOMER_CYCLE_CARD_V9688__ = true;
  const cache = new Map();
  let busy = false;
  const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const norm = (v) => String(v ?? "").replace(/\\\\n/g, " ").replace(/\s+/g, " ").trim();

  async function context() {
    await RR_CUSTOMER_SECURE_SESSION_V9592.ensure();
    const s = JSON.parse(localStorage.getItem("rr_customer_secure_session_v9592") || "null");
    if (!s?.session_token) throw Error("Secure session missing");
    return { token: s.session_token, device: RR_CUSTOMER_SECURE_SESSION_V9592.device() };
  }
  function tokenFrom(url) {
    try { const u = new URL(url, location.href); return u.searchParams.get("t") || u.searchParams.get("c") || ""; }
    catch (_) { return ""; }
  }
  function firstImage(share) {
    for (const row of Array.isArray(share?.rows) ? share.rows : []) {
      const media = Array.isArray(row?.media) ? row.media : [];
      const image = media.map((x) => x?.image_url || x?.storage_path).find(Boolean);
      if (image) return image;
      if (row?.primary_image_url) return row.primary_image_url;
    }
    return "";
  }
  async function getShare(token) {
    if (!token) return null;
    if (!cache.has(token)) cache.set(token, RF853.rpc("rr_market_share_view_v9420", { p_token: token }).catch(() => null));
    return cache.get(token);
  }
  function title(m) {
    const p = m.payload || {};
    return p.collection_display_no || p.requirement_display_no || norm(m.body).replace(/^\[REQ:[^\]]+\]\s*/i, "").split(" · ").slice(0, 2).join(" · ") || "REDZED UPDATE";
  }
  function paint(node, m, image, url) {
    const p = m.payload || {}, req = String(p.source || "").toUpperCase() === "DIRECT_MARKET_REQUIREMENT";
    const body = node.querySelector(".fsbody");
    if (!body || body.dataset.cycleCard9688 === "1") return;
    const update = Number(req ? p.requirement_update_no : p.collection_update_no || 0);
    const count = Number(p.lot_count || 0), qty = Number(p.total_qty || 0), label = req ? "REQUIREMENT" : "COLLECTION";
    body.dataset.cycleCard9688 = "1";
    body.className = "rrCycleCard9688";
    body.innerHTML = `${image ? `<img src="${esc(image)}" alt="${label} first style" loading="lazy" decoding="async">` : ""}<div><b>${esc(title(m))}</b><small>${update ? `UPDATE ${update} · ` : ""}${count} STYLE${count === 1 ? "" : "S"}${req ? ` · ${qty} PCS` : ""}</small><span>OPEN ${label} ›</span></div>`;
    if (url) {
      body.setAttribute("role", "button"); body.tabIndex = 0;
      const open = () => { location.href = url; };
      body.onclick = open;
      body.onkeydown = (e) => { if (e.key === "Enter" || e.key === " ") open(); };
    }
  }
  async function decorate() {
    if (busy || !document.querySelector("#fsMsgs .fsm")) return;
    busy = true;
    try {
      const x = await context();
      let messages = await RF853.rpc("rr_chat_customer_messages_session_v9593", { p_session_token: x.token, p_device_id: x.device, p_channel: "GROUP", p_limit: 150 });
      messages = Array.isArray(messages) ? messages.reverse() : [];
      const urls = new Map();
      messages.forEach((m) => {
        const p = m.payload || {};
        if (String(p.source || "").toUpperCase() === "DIRECT_MARKET_WINDOW" && p.direct_collection_cycle_id && p.url) urls.set(String(p.direct_collection_cycle_id), p.url);
      });
      const nodes = [...document.querySelectorAll("#fsMsgs .fsm")], unused = new Set(nodes.map((_, i) => i));
      for (const m of messages) {
        const source = String(m?.payload?.source || "").toUpperCase();
        if (!['DIRECT_MARKET_WINDOW', 'DIRECT_MARKET_REQUIREMENT'].includes(source)) continue;
        const index = [...unused].find((i) => norm(nodes[i].querySelector(".fsbody")?.textContent) === norm(m.body));
        if (index == null) continue;
        unused.delete(index);
        const cycle = String(m.payload?.direct_collection_cycle_id || "");
        const url = m.payload?.url || urls.get(cycle) || location.href;
        const share = await getShare(tokenFrom(url) || new URLSearchParams(location.search).get("t") || "");
        paint(nodes[index], m, firstImage(share), url);
      }
    } catch (_) {} finally { busy = false; }
  }
  function boot() {
    const st = document.createElement("style");
    st.id = "rrCycleCard9688Style";
    st.textContent = `.rrCycleCard9688{display:grid!important;grid-template-columns:92px minmax(0,1fr);gap:9px;align-items:stretch;margin-top:5px;border:1px solid #43536b;border-radius:11px;padding:7px;background:#101925;cursor:pointer;white-space:normal!important;word-break:normal!important}.rrCycleCard9688 img{display:block;width:92px;height:92px;object-fit:cover;border-radius:8px;background:#090d12}.rrCycleCard9688>div{min-width:0;display:flex;flex-direction:column;justify-content:center}.rrCycleCard9688 b{font-size:14px;line-height:1.2}.rrCycleCard9688 small{display:block;color:#aeb9c7;margin-top:5px;font-size:11px}.rrCycleCard9688 span{display:block;color:#8fc7ff;margin-top:8px;font-size:12px;font-weight:900}.rrCycleCard9688:not(:has(img)){grid-template-columns:1fr}`;
    document.head.appendChild(st);
    let bound = false, attempts = 0;
    const timer = setInterval(() => {
      const box = document.getElementById("fsMsgs");
      if (!box) { if (++attempts > 60) clearInterval(timer); return; }
      if (!bound) { new MutationObserver(() => setTimeout(decorate, 20)).observe(box, { childList: true }); bound = true; }
      decorate(); clearInterval(timer);
    }, 100);
    document.addEventListener("click", (e) => { if (e.target.closest?.("#fsGroup")) setTimeout(decorate, 80); }, true);
  }
  document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", boot, { once: true }) : boot();
})();
