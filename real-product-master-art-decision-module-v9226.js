(() => {
  "use strict";
  if (window.__RR_PM_ART_DECISION_MODULE_9226__) return;
  window.__RR_PM_ART_DECISION_MODULE_9226__ = true;

  const $ = id => document.getElementById(id);
  const state = { module: "child", childView: "overview" };
  let galleryObserver = null;

  function ensureStyles() {
    if ($("rrPmModuleStyle9226")) return;
    const style = document.createElement("style");
    style.id = "rrPmModuleStyle9226";
    style.textContent = `
      #rrPmModuleNav9226{display:flex;gap:8px;flex-wrap:wrap;margin:14px 0 10px;padding:10px;border:1px solid var(--line,#30303a);border-radius:16px;background:var(--panel,#141419)}
      #rrPmModuleNav9226 button,#rrPmChildTabs9226 button{border:1px solid var(--line,#30303a);border-radius:12px;background:#1c1c23;color:#ddd;padding:10px 13px;font-weight:900}
      #rrPmModuleNav9226 button.active,#rrPmChildTabs9226 button.active{border-color:#c84c5d;background:#4a2028;color:#fff;box-shadow:0 0 0 2px rgba(200,76,93,.12) inset}
      #rrPmChildTabs9226{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 12px}
      .rr-pm-module-hidden-9226{display:none!important}
      .rr-pm-decision-action-hidden-9226{display:none!important}
      #rrPmModuleHint9226{margin:0 0 10px;color:var(--muted,#a3a3ad);font-size:12px;line-height:1.45}
      @media(max-width:680px){#rrPmModuleNav9226,#rrPmChildTabs9226{display:grid;grid-template-columns:repeat(2,minmax(0,1fr))}#rrPmModuleNav9226 button,#rrPmChildTabs9226 button{min-height:46px}}
    `;
    document.head.appendChild(style);
  }

  function ensureNav() {
    const toolbar = $("filters")?.closest(".toolbar");
    if (!toolbar) return false;

    if (!$("rrPmModuleNav9226")) {
      const nav = document.createElement("section");
      nav.id = "rrPmModuleNav9226";
      nav.setAttribute("aria-label", "Product Master modules");
      nav.innerHTML = `
        <button type="button" data-pm-module="child" class="active">CB / CHILD MASTER</button>
        <button type="button" data-pm-module="matching">MATCHING CLOTH</button>
      `;
      toolbar.insertAdjacentElement("beforebegin", nav);
      nav.addEventListener("click", event => {
        const button = event.target.closest("[data-pm-module]");
        if (!button) return;
        state.module = button.dataset.pmModule;
        if (state.module === "matching") clickBaseFilter("mc");
        else clickBaseFilter("all");
        applyView();
      });
    }

    if (!$("rrPmChildTabs9226")) {
      const tabs = document.createElement("section");
      tabs.id = "rrPmChildTabs9226";
      tabs.setAttribute("aria-label", "Child Master tabs");
      tabs.innerHTML = `
        <button type="button" data-pm-child-view="overview" class="active">CHILD OVERVIEW</button>
        <button type="button" data-pm-child-view="decision">ART DECISION MASTER</button>
      `;
      $("rrPmModuleNav9226").insertAdjacentElement("afterend", tabs);
      tabs.addEventListener("click", event => {
        const button = event.target.closest("[data-pm-child-view]");
        if (!button) return;
        state.module = "child";
        state.childView = button.dataset.pmChildView;
        clickBaseFilter("all");
        applyView();
      });
    }

    if (!$("rrPmModuleHint9226")) {
      const hint = document.createElement("p");
      hint.id = "rrPmModuleHint9226";
      $("rrPmChildTabs9226").insertAdjacentElement("afterend", hint);
    }

    return true;
  }

  function clickBaseFilter(name) {
    const button = document.querySelector(`#filters [data-filter="${name}"]`);
    if (button && !button.classList.contains("active")) button.click();
  }

  function setButtonActive(selector, value, attr) {
    document.querySelectorAll(selector).forEach(button => {
      button.classList.toggle("active", button.dataset[attr] === value);
    });
  }

  function setFilterVisibility() {
    const allowed = state.module === "matching"
      ? new Set(["mc"])
      : state.childView === "decision"
        ? new Set(["all", "art_due", "print_due", "sticker_due", "metal_id_due", "ready"])
        : new Set(["all", "cb"]);

    document.querySelectorAll("#filters [data-filter]").forEach(button => {
      button.classList.toggle("rr-pm-module-hidden-9226", !allowed.has(button.dataset.filter));
    });
  }

  function setHeroActions() {
    const cb = $("openCbNew");
    const mc = $("openMcNew");
    if (cb) cb.classList.toggle("rr-pm-module-hidden-9226", state.module === "matching");
    if (mc) mc.classList.toggle("rr-pm-module-hidden-9226", state.module !== "matching");
  }

  function setSectionTitle() {
    const section = document.querySelector(".section-title");
    if (!section) return;
    const small = section.querySelector("small");
    const heading = section.querySelector("h2");
    const hint = $("rrPmModuleHint9226");

    if (state.module === "matching") {
      if (small) small.textContent = "MATCHING CLOTH MASTER";
      if (heading) heading.textContent = "MC1 Consolidated Matching Cloth";
      if (hint) hint.textContent = "Matching Cloth is isolated here. Child Art / Print / Sticker / Metal ID decisions are not shown in this module.";
      return;
    }

    if (state.childView === "decision") {
      if (small) small.textContent = "ART DECISION MASTER";
      if (heading) heading.textContent = "Child-wise Art → Print → Sticker → Metal ID";
      if (hint) hint.textContent = "Har D child ka complete decision flow yahin chalega: ART → PRINT → STICKER → METAL ID → SAVE & EXIT.";
    } else {
      if (small) small.textContent = "CB / CHILD MASTER";
      if (heading) heading.textContent = "CB Children & Production Identity";
      if (hint) hint.textContent = "Child overview. Art Decision editing dedicated Art Decision Master tab mein rakha gaya hai.";
    }
  }

  function applyGalleryScope() {
    const gallery = $("gallery");
    if (!gallery) return;

    gallery.querySelectorAll(".card").forEach(card => {
      const isMc = card.dataset.kind === "mc" || card.classList.contains("mc-card");
      const allow = state.module === "matching" ? isMc : !isMc;
      card.classList.toggle("rr-pm-module-hidden-9226", !allow);

      card.querySelectorAll("[data-assign]").forEach(button => {
        const showDecision = state.module === "child" && state.childView === "decision";
        button.classList.toggle("rr-pm-decision-action-hidden-9226", !showDecision);
        if (showDecision) button.textContent = "Open Art Decision";
      });
    });
  }

  function observeGallery() {
    const gallery = $("gallery");
    if (!gallery || galleryObserver) return;
    galleryObserver = new MutationObserver(mutations => {
      if (mutations.some(m => m.type === "childList")) requestAnimationFrame(applyGalleryScope);
    });
    galleryObserver.observe(gallery, { childList: true, subtree: false });
  }

  function applyView() {
    if (!ensureNav()) return;
    ensureStyles();

    setButtonActive("#rrPmModuleNav9226 [data-pm-module]", state.module, "pmModule");
    setButtonActive("#rrPmChildTabs9226 [data-pm-child-view]", state.childView, "pmChildView");

    const childTabs = $("rrPmChildTabs9226");
    if (childTabs) childTabs.classList.toggle("rr-pm-module-hidden-9226", state.module === "matching");

    setFilterVisibility();
    setHeroActions();
    setSectionTitle();
    applyGalleryScope();
    observeGallery();
  }

  function boot() {
    ensureStyles();
    if (!ensureNav()) {
      setTimeout(boot, 120);
      return;
    }
    applyView();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, { once: true });
  else boot();
})();
