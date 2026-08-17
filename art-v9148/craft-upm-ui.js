(() => {
  "use strict";

  const isArtTest = /\/art-v9148\/?$/i.test(window.location.pathname);
  if (!isArtTest) return;

  const PRIMARY_LABELS = ["Collar","Neck","Sleeve","Placket","Panels","Stitch / Finish"];

  const css = document.createElement("style");
  css.textContent = `
    .art-craft-map-card{margin-top:16px;border:1px solid var(--art-border,#dfe3e8);border-radius:16px;background:#fff;padding:15px;box-shadow:0 5px 18px rgba(16,24,40,.04)}
    .art-craft-map-card label{display:block;margin:0 0 8px;font-weight:800;color:#20242a}
    .art-craft-map-card small{display:block;margin-top:7px;color:#697386;font-size:12px;line-height:1.45}
    .art-craft-map-select{width:100%;min-height:48px;border:1px solid #cfd4dc;border-radius:12px;background:#fff;color:#101828;padding:0 14px;font-size:16px}
    .art-craft-map-chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:10px;min-height:34px}
    .art-craft-map-chip{display:inline-flex;align-items:center;gap:6px;padding:7px 10px;border-radius:999px;background:#111;color:#fff;font-size:12px;font-weight:800}
    .art-craft-map-chip b{font-size:10px;opacity:.7;text-transform:uppercase;letter-spacing:.04em}
    .art-craft-map-empty{color:#98a2b3;font-size:12px;padding:7px 0}
    .art-craft-map-json{display:none!important}
    @media(max-width:520px){.art-craft-map-card{padding:13px}.art-craft-map-chip{width:100%;justify-content:space-between;border-radius:12px}}
  `;
  document.head.appendChild(css);

  const normalize = value => String(value || "").trim().toLowerCase().replace(/\s+/g," ");
  const groupName = group => {
    const h = normalize(group?.querySelector("h4")?.textContent);
    if (h.includes("collar")) return "Collar";
    if (h.includes("neck")) return "Neck";
    if (h.includes("sleeve")) return "Sleeve";
    if (h.includes("placket")) return "Placket";
    if (h.includes("panel")) return "Panels";
    if (h.includes("stitch") || h.includes("finish") || h.includes("construction")) return "Stitch / Finish";
    return null;
  };

  function selectedCraft() {
    const builder = document.getElementById("artCaptionBuilder");
    if (!builder) return [];
    const out = [];
    builder.querySelectorAll(".rr-caption-group").forEach(group => {
      const groupLabel = groupName(group);
      if (!groupLabel || !PRIMARY_LABELS.includes(groupLabel)) return;
      group.querySelectorAll(".rr-caption-pill.selected").forEach(button => {
        const text = String(button.textContent || "").replace(/^\s*✓\s*/,"").replace(/\s*×\s*$/,"").trim();
        if (text) out.push({ group: groupLabel, value: text, key: `${groupLabel.toLowerCase().replace(/\W+/g,"_")}::${text.toLowerCase()}` });
      });
    });
    const seen = new Set();
    return out.filter(item => !seen.has(item.key) && seen.add(item.key));
  }

  function ensureCard() {
    const itemName = document.getElementById("itemName");
    if (!itemName) return null;
    const designCard = itemName.closest(".art-field-card") || itemName.parentElement;
    if (!designCard || document.getElementById("artCraftMapCard")) return document.getElementById("artCraftMapCard");

    const card = document.createElement("div");
    card.id = "artCraftMapCard";
    card.className = "art-craft-map-card";
    card.innerHTML = `
      <label for="artCraftMapSelect">Craft Details</label>
      <select id="artCraftMapSelect" class="art-craft-map-select">
        <option value="">Select from Craft Features</option>
      </select>
      <div id="artCraftMapChips" class="art-craft-map-chips"><span class="art-craft-map-empty">Craft Features select karne par details yahan aayengi.</span></div>
      <input id="artCraftMapJson" class="art-craft-map-json" type="hidden" value="[]">
      <small>Selected detail structured form mein ready rahegi, taaki UPM mapping mein same group/value use kiya ja sake.</small>
    `;
    designCard.insertAdjacentElement("afterend", card);

    card.querySelector("#artCraftMapSelect")?.addEventListener("change", render);
    return card;
  }

  function render() {
    const card = ensureCard();
    if (!card) return;
    const select = card.querySelector("#artCraftMapSelect");
    const chips = card.querySelector("#artCraftMapChips");
    const json = card.querySelector("#artCraftMapJson");
    const items = selectedCraft();
    const current = select.value;

    select.innerHTML = `<option value="">Select from Craft Features</option>` + items.map(item =>
      `<option value="${encodeURIComponent(JSON.stringify(item))}">${item.group} — ${item.value}</option>`
    ).join("");

    if (current && [...select.options].some(o => o.value === current)) select.value = current;
    else if (items.length === 1) select.value = encodeURIComponent(JSON.stringify(items[0]));

    const selected = select.value ? (() => { try { return JSON.parse(decodeURIComponent(select.value)); } catch { return null; } })() : null;
    chips.innerHTML = selected
      ? `<span class="art-craft-map-chip"><b>${selected.group}</b>${selected.value}</span>`
      : `<span class="art-craft-map-empty">Dropdown se ek Craft Detail choose karo.</span>`;

    json.value = JSON.stringify({ selected, available: items });
    window.RR_ART_CRAFT_UPM_MAPPING = { selected, available: items };
  }

  const boot = () => {
    ensureCard();
    const builder = document.getElementById("artCaptionBuilder");
    if (builder) {
      new MutationObserver(() => setTimeout(render, 0)).observe(builder, { childList:true, subtree:true, attributes:true, attributeFilter:["class"] });
      builder.addEventListener("click", () => setTimeout(render, 0), true);
      builder.addEventListener("change", () => setTimeout(render, 0), true);
    }
    render();
  };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, { once:true });
  else boot();
})();
