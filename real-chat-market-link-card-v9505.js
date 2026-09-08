(() => {
  "use strict";
  if (window.__RR_CHAT_MARKET_LINK_CARD_V9680__) return;
  window.__RR_CHAT_MARKET_LINK_CARD_V9680__ = true;
  const rx = /https:\/\/[^\s<]+\/s\.html\?[^\s<]+/i;
  const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[char]);

  function tokenFrom(url) {
    try {
      const parsed = new URL(url, location.href);
      return parsed.searchParams.get("t") || parsed.searchParams.get("c") || "";
    } catch (_) {
      return "";
    }
  }

  function ensureStaffViewer() {
    let viewer = document.getElementById("rrStaffCollection9680");
    if (viewer) return viewer;
    const style = document.createElement("style");
    style.id = "rrStaffCollectionCss9680";
    style.textContent = `#rrStaffCollection9680{position:fixed;inset:0;z-index:12050;display:none;flex-direction:column;background:#0b1119;color:#fff;font-family:system-ui}#rrStaffCollection9680.on{display:flex}.rrScHead9680{display:flex;align-items:center;gap:10px;padding:10px 12px;border-bottom:1px solid #334155;background:#101722}.rrScHead9680 button{width:42px;height:42px;border:1px solid #53677f;border-radius:10px;background:#182535;color:#fff;font-size:24px}.rrScHead9680 div{min-width:0;flex:1}.rrScHead9680 b,.rrScHead9680 small{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.rrScHead9680 small{color:#9fb0c2}.rrScBody9680{flex:1;overflow:auto;padding:12px}.rrScNote9680{padding:10px;border:1px solid #465b73;border-radius:11px;background:#14202d;color:#cbd7e5;margin-bottom:10px}.rrScGrid9680{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:9px}.rrScLot9680{min-width:0;border:1px solid #33465d;border-radius:13px;overflow:hidden;background:#131c27}.rrScLot9680 img{display:block;width:100%;aspect-ratio:4/5;object-fit:cover;background:#080d13}.rrScLot9680 div{padding:9px}.rrScLot9680 b,.rrScLot9680 small{display:block;overflow-wrap:anywhere}.rrScLot9680 small{color:#aeb9c7;margin-top:3px}@media(min-width:760px){.rrScGrid9680{grid-template-columns:repeat(4,minmax(0,1fr))}}`;
    document.head.appendChild(style);
    document.body.insertAdjacentHTML("beforeend", `<section id="rrStaffCollection9680" aria-hidden="true"><div class="rrScHead9680"><button id="rrScBack9680" type="button" aria-label="Back">&#8249;</button><div><b id="rrScTitle9680">REDZED COLLECTION</b><small id="rrScParty9680">STAFF VIEW</small></div></div><div id="rrScBody9680" class="rrScBody9680">Loading collection...</div></section>`);
    viewer = document.getElementById("rrStaffCollection9680");
    document.getElementById("rrScBack9680").onclick = closeStaffCollection;
    window.addEventListener("popstate", () => {
      if (viewer.classList.contains("on")) closeStaffCollection(false);
    });
    return viewer;
  }

  function closeStaffCollection(stepBack = true) {
    const viewer = document.getElementById("rrStaffCollection9680");
    if (!viewer?.classList.contains("on")) return;
    viewer.classList.remove("on");
    viewer.setAttribute("aria-hidden", "true");
    document.documentElement.style.overflow = "";
    if (stepBack && history.state?.rrStaffCollection9680) history.back();
  }

  async function openStaffCollection(url) {
    const token = tokenFrom(url);
    const viewer = ensureStaffViewer();
    const body = document.getElementById("rrScBody9680");
    const party = (document.getElementById("chatTitle")?.textContent || "Customer").trim();
    document.getElementById("rrScParty9680").textContent = `${party} · STAFF VIEW · EXISTING CHAT`;
    viewer.classList.add("on");
    viewer.setAttribute("aria-hidden", "false");
    document.documentElement.style.overflow = "hidden";
    history.pushState({ rrStaffCollection9680: true }, "");
    body.textContent = "Loading collection...";
    try {
      if (!token) throw Error("Collection token missing.");
      const data = await RF853.rpc("rr_market_share_view_v9420", { p_token: token });
      const rows = Array.isArray(data?.rows) ? data.rows : [];
      document.getElementById("rrScTitle9680").textContent = data?.collection_display_no || "REDZED COLLECTION";
      body.innerHTML = `<div class="rrScNote9680">यह collection ${esc(party)} की इसी existing staff chat में read-only खुली है। Customer login/name/mobile दोबारा नहीं माँगा जाएगा।</div><div class="rrScGrid9680">${rows.map((row) => {
        const media = Array.isArray(row.media) ? row.media : [];
        const image = media[0]?.image_url || media[0]?.storage_path || row.primary_image_url || "";
        return `<article class="rrScLot9680">${image ? `<img loading="lazy" src="${esc(image)}" alt="${esc(row.lot_no)}">` : ""}<div><b>${esc(row.lot_no || "-")}</b><small>${esc(row.category || row.item_name || row.cloth_name || "-")}</small><small>${esc(row.size_text || "-")} · AVL ${Number(row.available_qty || 0)}</small></div></article>`;
      }).join("") || "<div>No collection lots found.</div>"}</div>`;
    } catch (error) {
      body.innerHTML = `<div class="rrScNote9680">${esc(error?.message || "Collection unavailable.")}</div>`;
    }
  }

  function card(node) {
    if (!node || node.dataset.rrMarketCard === "1") return;
    const text = node.textContent || "";
    const match = text.match(rx);
    if (!match) return;
    const url = match[0].replace(/[),.;]+$/, "");
    const styles = (text.match(/REDZED(?:\s+COLLECTION)?\s*[·•]\s*(\d+)\s*(?:selected\s*)?styles?/i) || text.match(/REDZED\s*•\s*(\d+)\s*styles?/i) || [])[1] || "";
    const box = document.createElement("button");
    box.type = "button";
    box.className = "rrMarketLinkCard9505";
    box.innerHTML = `<span class="rrMkIcon9505">🛍️</span><span class="rrMkText9505"><b>REDZED COLLECTION</b><small>${styles ? `${styles} selected styles · ` : ""}Tap to view designs</small></span><span class="rrMkGo9505">OPEN ›</span>`;
    box.onclick = (event) => {
      event.preventDefault();
      event.stopPropagation();
      openStaffCollection(url);
    };
    node.dataset.rrMarketCard = "1";
    [...node.children].filter((child) => child.tagName === "DIV" && (child.textContent || "").match(rx)).forEach((child) => { child.style.display = "none"; });
    node.insertBefore(box, node.querySelector("time") || null);
  }

  function scan() { document.querySelectorAll("#msgs .msg,.rr-msgs .rr-msg").forEach(card); }
  function loadScript(id, src) {
    if (document.getElementById(id)) return;
    const script = document.createElement("script");
    script.id = id;
    script.src = src;
    document.head.appendChild(script);
  }
  function loadExtras() {
    if (!/\/real-sales-live-chat-v9434\.html$/i.test(location.pathname)) return;
    loadScript("rrChatAutoOpen9507", "real-chat-auto-open-refresh-v9507.js?v=9507");
  }
  function css() {
    if (document.getElementById("rrMarketLinkCss9505")) return;
    const style = document.createElement("style");
    style.id = "rrMarketLinkCss9505";
    style.textContent = ".rrMarketLinkCard9505{width:100%;display:flex;align-items:center;gap:10px;margin:7px 0 3px;padding:11px 12px;border:1px solid #49627d;border-radius:13px;background:#101923;color:#fff;text-align:left;cursor:pointer}.rrMkIcon9505{font-size:25px;flex:0 0 auto}.rrMkText9505{display:block;min-width:0;flex:1}.rrMkText9505 b,.rrMkText9505 small{display:block}.rrMkText9505 b{font-size:14px}.rrMkText9505 small{font-size:11px;color:#9fb0c2;margin-top:2px}.rrMkGo9505{font-weight:900;color:#8fc8ff;white-space:nowrap}";
    document.head.appendChild(style);
  }
  function init() { css(); loadExtras(); scan(); new MutationObserver(scan).observe(document.body, { childList: true, subtree: true }); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();
