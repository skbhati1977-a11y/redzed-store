(() => {
  "use strict";

  const params = new URLSearchParams(location.search);
  const requested = String(params.get("dept") || "").trim().toUpperCase();
  const label = String(params.get("label") || requested || "UNIVERSAL PRODUCTION").trim();
  if (!requested) return;

  const aliases = {
    KR: ["STITCHING", "KARIGAR", "KR"],
    STICKER: ["STICKER", "STICKER_WORK"],
    ID: ["ID", "ID_WORK", "IDENTITY"],
    PRINTING: ["PRINTING", "PRINT"],
    OVERLOCK: ["OVERLOCK", "OV"],
    FOLDING: ["FOLDING", "FLD", "FLATLOCK"],
    KAAJ_BUTTON: ["KAAJ_BUTTON", "KAAJ", "KAJ", "BUTTON", "BTN"],
    TEAK_TANKI: ["TEAK_TANKI", "TEAK", "TANKI"],
    THREAD_CUT: ["THREAD_CUT", "THREAD_CUTTING", "TH_CUT"],
    QC: ["QC", "CHECKING", "QUALITY_CHECK"],
    PRESS: ["PRESS", "FINISHING"],
    PACKING: ["PACKING", "PACK"],
    DESPATCH: ["DESPATCH", "DISPATCH"]
  };
  const accepted = aliases[requested] || [requested];

  function matchOption(select) {
    return [...select.options].find(option => {
      const value = String(option.value || "").trim().toUpperCase();
      const text = String(option.textContent || "").trim().toUpperCase();
      return accepted.some(code => value === code || text === code || text.includes(code.replaceAll("_", " ")));
    });
  }

  function lockDepartment() {
    const home = document.getElementById("homeDept");
    if (!home || !home.options.length) return false;
    const option = matchOption(home);
    if (!option) return false;
    if (home.value !== option.value) {
      home.value = option.value;
      home.dispatchEvent(new Event("change", { bubbles: true }));
    }
    home.disabled = true;
    home.closest(".toolbar")?.classList.add("rf-dept-locked");
    return true;
  }

  function openAction(card, targetId) {
    card.querySelector("[data-open-lot]")?.click();
    if (!targetId) return;
    let tries = 0;
    const timer = setInterval(() => {
      const target = document.getElementById(targetId);
      const traveller = document.getElementById("traveller");
      if (target && traveller && !traveller.classList.contains("hidden")) {
        clearInterval(timer);
        target.scrollIntoView({ behavior: "smooth", block: "center" });
        target.classList.add("rf-action-focus");
        setTimeout(() => target.classList.remove("rf-action-focus"), 1800);
      } else if (++tries > 40) clearInterval(timer);
    }, 100);
  }

  function enhanceCards() {
    document.querySelectorAll(".lot-card").forEach(card => {
      if (card.querySelector(".rf-card-actions")) return;
      const old = card.querySelector(".checkin");
      if (old) old.hidden = true;
      const actions = document.createElement("div");
      actions.className = "rf-card-actions";
      actions.innerHTML = '<button type="button" data-rf-action="assign">ASSIGN</button><button type="button" data-rf-action="submit">SUBMIT</button><button type="button" data-rf-action="alter">ALTER</button>';
      actions.addEventListener("click", event => {
        event.stopPropagation();
        const action = event.target.closest("[data-rf-action]")?.dataset.rfAction;
        if (!action) return;
        openAction(card, action === "submit" ? "submitBtn" : action === "alter" ? "alterBtn" : "selectAllBtn");
      });
      card.append(actions);
    });
  }

  function applyShell() {
    document.title = `REAL FACTORY — ${label} Dashboard`;
    const kicker = document.querySelector(".top small.art-no");
    const heading = document.querySelector(".top h1");
    if (kicker) kicker.textContent = "REAL FACTORY · UPM";
    if (heading) heading.textContent = `${label} Dashboard`;
    const homeLink = document.querySelector('.top a[href*="dashboard"]');
    if (homeLink) homeLink.href = "real-dashboard.html";
    document.body.classList.add("rf-department-module");
  }

  const style = document.createElement("style");
  style.textContent = '.rf-dept-locked select{font-weight:900;border-color:#56efb2}.rf-card-actions{display:grid;grid-template-columns:repeat(3,1fr);gap:7px;margin-top:auto}.rf-card-actions button{min-height:44px;padding:8px 4px}.rf-card-actions button:nth-child(1){background:#263852;border-color:#4a78b8}.rf-card-actions button:nth-child(2){background:#174936;border-color:#318b65}.rf-card-actions button:nth-child(3){background:#493915;border-color:#8a6b2b}.rf-action-focus{animation:rfFocus .45s ease-in-out 4}@keyframes rfFocus{50%{box-shadow:0 0 0 4px #ffc857;filter:brightness(1.3)}}';
  document.head.append(style);
  applyShell();

  const observer = new MutationObserver(() => {
    lockDepartment();
    enhanceCards();
  });
  observer.observe(document.body, { childList: true, subtree: true });
  lockDepartment();
  enhanceCards();
})();
