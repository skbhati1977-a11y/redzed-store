(() => {
"use strict";

const VERSION = "9141";
const STYLE_ID = "realGlobalMobileFillStyle9141";
const FOCUSABLE_SELECTOR = "input,select,textarea,[contenteditable='true']";
const PANEL_SELECTOR = [
  ".sheet-panel",
  ".pm-sheet-panel",
  ".cm-sheet-panel",
  ".sheet",
  ".modal [role='dialog']",
  ".modal"
].join(",");
const HEAD_SELECTOR = [
  ".sheet-head",
  ".pm-sheet-head",
  ".cm-sheet-head",
  ".modal-head",
  ".sheet-header",
  ".drawer-head",
  ".sticky"
].join(",");

let activePanel = null;
let activeHead = null;
let syncTimer = 0;

function byId(id) {
  return document.getElementById(id);
}

function installStyles() {
  if (byId(STYLE_ID)) return;
  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = `
    .sheet-head p:not(.kicker),
    .pm-sheet-head p:not(.kicker),
    .cm-sheet-head p:not(.kicker),
    .modal-head p:not(.kicker),
    .sheet-header p:not(.kicker),
    .drawer-head p:not(.kicker),
    .sheet-head .subtitle,
    .pm-sheet-head .subtitle,
    .cm-sheet-head .subtitle,
    .modal-head .subtitle,
    .sheet-header .subtitle,
    .drawer-head .subtitle,
    .sheet-head .description,
    .pm-sheet-head .description,
    .cm-sheet-head .description,
    .modal-head .description,
    .sheet-header .description,
    .drawer-head .description,
    .sheet-head [id$="Context"],
    .pm-sheet-head [id$="Context"],
    .cm-sheet-head [id$="Context"],
    .modal-head [id$="Context"],
    .sheet-header [id$="Context"],
    .drawer-head [id$="Context"]{
      display:none!important;
    }
    .rf-fill-hidden-head-v9141{
      display:none!important;
    }
    .rf-fill-active-panel-v9141.sheet-panel,
    .rf-fill-active-panel-v9141.pm-sheet-panel,
    .rf-fill-active-panel-v9141.cm-sheet-panel,
    .rf-fill-active-panel-v9141.sheet{
      padding-top:8px!important;
    }
  `;
  document.head.appendChild(style);
}

function isVisible(el) {
  if (!el || !el.isConnected) return false;
  const rect = el.getBoundingClientRect();
  const style = window.getComputedStyle(el);
  return rect.width > 0 && rect.height > 0 && style.display !== "none" && style.visibility !== "hidden";
}

function isHeaderCandidate(el) {
  if (!el || !isVisible(el)) return false;
  if (el.matches(".sticky") && !el.querySelector("h1,h2,h3,.top,.sheet-title")) return false;
  const rect = el.getBoundingClientRect();
  const viewportTopLimit = Math.max(220, window.innerHeight * 0.35);
  return rect.top <= viewportTopLimit;
}

function findPanel(target) {
  if (!target?.closest) return null;
  return target.closest(PANEL_SELECTOR);
}

function findHead(panel) {
  if (!panel) return null;
  const direct = Array.from(panel.querySelectorAll(HEAD_SELECTOR)).find(isHeaderCandidate);
  if (direct) return direct;
  const ownHeader = panel.matches(HEAD_SELECTOR) && isHeaderCandidate(panel) ? panel : null;
  return ownHeader;
}

function clearActive() {
  if (activeHead) activeHead.classList.remove("rf-fill-hidden-head-v9141");
  if (activePanel) activePanel.classList.remove("rf-fill-active-panel-v9141");
  document.body.classList.remove("rf-fill-active-v9141");
  activeHead = null;
  activePanel = null;
}

function applyActive(target) {
  const panel = findPanel(target);
  const head = findHead(panel);
  clearActive();
  activePanel = panel;
  activeHead = head;
  if (activePanel) activePanel.classList.add("rf-fill-active-panel-v9141");
  if (activeHead) activeHead.classList.add("rf-fill-hidden-head-v9141");
  document.body.classList.add("rf-fill-active-v9141");
}

function focusedFillTarget() {
  const el = document.activeElement;
  if (el?.matches?.(FOCUSABLE_SELECTOR)) return el;
  return null;
}

function syncFillState() {
  installStyles();
  const target = focusedFillTarget();
  if (!target) {
    clearActive();
    return;
  }
  const panel = findPanel(target);
  const head = findHead(panel);
  if (panel !== activePanel || head !== activeHead || !activeHead?.classList.contains("rf-fill-hidden-head-v9141")) {
    applyActive(target);
  }
}

function scheduleSync(delay = 80) {
  window.clearTimeout(syncTimer);
  syncTimer = window.setTimeout(syncFillState, delay);
}

function bind() {
  installStyles();
  document.addEventListener("focusin", event => {
    if (event.target?.matches?.(FOCUSABLE_SELECTOR)) applyActive(event.target);
  }, true);
  document.addEventListener("focusout", () => scheduleSync(180), true);
  document.addEventListener("input", () => scheduleSync(30), true);
  document.addEventListener("keydown", () => scheduleSync(30), true);
  document.addEventListener("pointerdown", () => scheduleSync(120), true);
  window.addEventListener("resize", () => scheduleSync(80), { passive: true });
  window.visualViewport?.addEventListener("resize", () => scheduleSync(40), { passive: true });
  new MutationObserver(() => scheduleSync(50)).observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["class", "style", "aria-hidden"]
  });
  window.setInterval(syncFillState, 500);
  scheduleSync(0);
  console.info(`Global mobile fill UX v${VERSION} loaded`);
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", bind);
else bind();
})();
