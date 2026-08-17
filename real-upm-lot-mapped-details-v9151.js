(() => {
  "use strict";

  const VERSION = "9151";
  const CARD_SELECTOR = ".lot-card";
  const STYLE_ID = "rrUpmMappedDetailsStyle9151";
  const CACHE_TTL = 60_000;
  const lotCache = new Map();
  const artCache = new Map();
  let scanTimer = 0;

  function db() {
    return window.supabaseClient || window.supabaseDb || window.redzedSupabase || window.sb || null;
  }

  function clean(value) {
    return String(value ?? "").replace(/\s+/g, " ").trim();
  }

  function escapeHtml(value) {
    return clean(value).replace(/[&<>"']/g, ch => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;"
    })[ch]);
  }

  function installStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      .upm-mapped-details{display:grid;gap:5px;margin:8px 0;padding:8px;border:1px solid var(--line,#303641);border-radius:9px;background:rgba(255,255,255,.025)}
      .upm-map-row{display:grid;grid-template-columns:64px minmax(0,1fr);gap:7px;align-items:start;font-size:11px;line-height:1.3}
      .upm-map-label{font-weight:900;color:var(--mut,#98a2b3);letter-spacing:.03em;text-transform:uppercase}
      .upm-map-values{display:flex;flex-wrap:wrap;gap:4px;min-width:0}
      .upm-map-chip{display:inline-flex;align-items:center;max-width:100%;padding:3px 6px;border:1px solid #3b4350;border-radius:999px;background:#171b23;color:#e5e7eb;font-weight:750;overflow-wrap:anywhere}
      .upm-map-row.craft .upm-map-chip{border-color:#515b6b}
      .upm-map-row.sticker .upm-map-chip{border-color:#72591e;color:#ffe6a1;background:#2b2414}
      .upm-map-row.metal .upm-map-chip{border-color:#53657d;color:#d9e8ff;background:#16202c}
      @media(max-width:520px){.upm-map-row{grid-template-columns:58px minmax(0,1fr)}.upm-mapped-details{padding:7px}}
    `;
    document.head.appendChild(style);
  }

  function textAfterLabel(text, labels) {
    let out = clean(text);
    for (const label of labels) {
      const re = new RegExp(`^${label}\\s*[:#·•-]*\\s*`, "i");
      out = out.replace(re, "");
    }
    return clean(out);
  }

  function cardLotNo(card) {
    const node = card.querySelector(".lot-no");
    if (!node) return "";
    return textAfterLabel(node.textContent, ["LOT", "LOT NO", "LOT NO."]);
  }

  function cardArtNo(card) {
    const candidates = [...card.querySelectorAll(".art-no")];
    for (const node of candidates) {
      const raw = clean(node.textContent);
      if (!raw || /REDZED|UNIVERSAL/i.test(raw)) continue;
      const value = textAfterLabel(raw, ["ART", "ART NO", "ART NO."]);
      if (value) return value;
    }
    const text = clean(card.textContent);
    const match = text.match(/\bART\s*(?:NO\.?\s*)?[:#·•-]?\s*([A-Z0-9][A-Z0-9._/-]*)/i);
    return clean(match?.[1] || "");
  }

  function cacheGet(map, key) {
    const hit = map.get(key);
    if (!hit || Date.now() - hit.at > CACHE_TTL) return null;
    return hit.value;
  }

  function cacheSet(map, key, value) {
    map.set(key, { at: Date.now(), value });
    return value;
  }

  async function getCraft(artNo) {
    const key = clean(artNo).toUpperCase();
    if (!key) return [];
    const cached = cacheGet(artCache, key);
    if (cached) return cached;
    const client = db();
    if (!client) return [];

    const { data, error } = await client
      .from("rr_art_master")
      .select("art_no,description")
      .ilike("art_no", key)
      .limit(1);
    if (error) {
      console.warn("UPM mapped Craft read", error);
      return cacheSet(artCache, key, []);
    }
    const description = clean(data?.[0]?.description);
    const values = description
      ? description.split(/\s*[•|]\s*/).map(clean).filter(Boolean)
      : [];
    return cacheSet(artCache, key, [...new Set(values)]);
  }

  async function getAccessories(lotNo) {
    const key = clean(lotNo).toUpperCase();
    if (!key) return { stickers: [], metals: [] };
    const cached = cacheGet(lotCache, key);
    if (cached) return cached;
    const client = db();
    if (!client) return { stickers: [], metals: [] };

    const { data: reqs, error } = await client
      .from("rr_accessory_lot_requirements_v804")
      .select("item_type,sticker_master_id,metal_id_master_id,requirement_status")
      .ilike("lot_no", key)
      .neq("requirement_status", "RELEASED");

    if (error) {
      console.warn("UPM mapped accessory read", error);
      return cacheSet(lotCache, key, { stickers: [], metals: [] });
    }

    const stickerIds = [...new Set((reqs || []).filter(r => clean(r.item_type).toUpperCase() === "STICKER" && r.sticker_master_id).map(r => r.sticker_master_id))];
    const metalIds = [...new Set((reqs || []).filter(r => clean(r.item_type).toUpperCase() === "METAL_ID" && r.metal_id_master_id).map(r => r.metal_id_master_id))];

    let stickers = [];
    let metals = [];

    if (stickerIds.length) {
      const res = await client
        .from("rr_sticker_master_v803")
        .select("id,sticker_no,sticker_name,sticker_quality")
        .in("id", stickerIds);
      if (!res.error) {
        stickers = (res.data || []).map(x => {
          const no = clean(x.sticker_no);
          const name = clean(x.sticker_name);
          const quality = clean(x.sticker_quality);
          return [no, name && name.toUpperCase() !== no.toUpperCase() ? name : "", quality].filter(Boolean).join(" · ");
        }).filter(Boolean);
      } else console.warn("UPM Sticker Master read", res.error);
    }

    if (metalIds.length) {
      const res = await client
        .from("rr_metal_id_master_v803")
        .select("id,metal_id_no,metal_id_name,id_size")
        .in("id", metalIds);
      if (!res.error) {
        metals = (res.data || []).map(x => {
          const no = clean(x.metal_id_no);
          const name = clean(x.metal_id_name);
          const size = clean(x.id_size);
          return [no, name && name.toUpperCase() !== no.toUpperCase() ? name : "", size].filter(Boolean).join(" · ");
        }).filter(Boolean);
      } else console.warn("UPM Metal ID Master read", res.error);
    }

    return cacheSet(lotCache, key, {
      stickers: [...new Set(stickers)],
      metals: [...new Set(metals)]
    });
  }

  function row(label, values, className) {
    if (!values?.length) return "";
    return `<div class="upm-map-row ${className}"><span class="upm-map-label">${escapeHtml(label)}</span><span class="upm-map-values">${values.map(v => `<span class="upm-map-chip">${escapeHtml(v)}</span>`).join("")}</span></div>`;
  }

  async function decorate(card) {
    const lotNo = cardLotNo(card);
    if (!lotNo) return;
    const artNo = cardArtNo(card);
    const token = `${lotNo.toUpperCase()}|${artNo.toUpperCase()}`;
    if (card.dataset.upmMappedToken === token && card.querySelector(".upm-mapped-details")) return;
    card.dataset.upmMappedToken = token;

    const [craft, accessories] = await Promise.all([
      getCraft(artNo),
      getAccessories(lotNo)
    ]);
    if (!card.isConnected || card.dataset.upmMappedToken !== token) return;

    card.querySelector(".upm-mapped-details")?.remove();
    const html = [
      row("Craft", craft, "craft"),
      row("Sticker", accessories.stickers, "sticker"),
      row("Metal ID", accessories.metals, "metal")
    ].join("");
    if (!html) return;

    const box = document.createElement("div");
    box.className = "upm-mapped-details";
    box.innerHTML = html;

    const liveList = card.querySelector(".lot-live-list");
    const checkin = card.querySelector(".checkin");
    if (liveList) liveList.insertAdjacentElement("beforebegin", box);
    else if (checkin) checkin.insertAdjacentElement("beforebegin", box);
    else card.appendChild(box);
  }

  function scan() {
    installStyle();
    document.querySelectorAll(CARD_SELECTOR).forEach(card => decorate(card).catch(err => console.warn("UPM mapped card", err)));
  }

  function scheduleScan(delay = 80) {
    clearTimeout(scanTimer);
    scanTimer = setTimeout(scan, delay);
  }

  function boot() {
    installStyle();
    scan();
    const board = document.getElementById("board") || document.body;
    new MutationObserver(() => scheduleScan(60)).observe(board, { childList: true, subtree: true });
    document.getElementById("refresh")?.addEventListener("click", () => {
      lotCache.clear();
      artCache.clear();
      scheduleScan(600);
    });
    console.info(`UPM mapped lot details v${VERSION} loaded`);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, { once: true });
  else boot();
})();
