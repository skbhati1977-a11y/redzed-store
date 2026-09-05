(() => {
  "use strict";
  if (window.__RR_MOBILE_BACK_STEP_TEST67__) return;
  window.__RR_MOBILE_BACK_STEP_TEST67__ = true;

  const path = location.pathname.toLowerCase();
  const isDirectory = path.endsWith("/real-market-distributor-test67.html");
  const isDistributorChat =
    path.endsWith("/real-market-distributor-customer-chat-test67.html") ||
    path.endsWith("/real-market-distributor-redzed-chat-test67.html");
  const isCustomerCollection = path.endsWith("/s.html");
  const logicalSteps = [];
  let restoring = false;
  let exitArmedAt = 0;
  let leaving = false;

  function visible(element) {
    if (!element || !element.isConnected) return false;
    const style = getComputedStyle(element);
    return (
      style.display !== "none" &&
      style.visibility !== "hidden" &&
      Number(style.opacity || 1) !== 0
    );
  }

  function openLayers() {
    const selector = [
      ".rrImageViewer.on",
      ".viewerBack.on",
      ".panelBack.on",
      ".modalBack.on",
      ".drawerBack.on",
      ".modalback.open",
      "#rrFSChat.on",
      "#rrMediaFiles59.on",
      "#rrDisappearPicker59.on",
      "[role='dialog'][aria-hidden='false']",
    ].join(",");
    const all = [...document.querySelectorAll(selector)];
    return all.filter(visible).sort((a, b) => {
      const za = Number.parseInt(getComputedStyle(a).zIndex, 10) || 0;
      const zb = Number.parseInt(getComputedStyle(b).zIndex, 10) || 0;
      return za === zb ? all.indexOf(a) - all.indexOf(b) : za - zb;
    });
  }

  function closeLayer(layer) {
    if (!layer) return false;
    const id = layer.id;
    const externalClose = id
      ? document.querySelector(
          `[data-close-panel="${CSS.escape(id)}"], [data-close="${CSS.escape(id)}"]`,
        )
      : null;
    const closeButton =
      externalClose ||
      layer.querySelector(
        ".rrImageViewerClose, #closeViewer, #modalClose, #modalCancel, #fsClose, #mf59Back, .rrDPCancel59, [data-close-panel], [data-close], [aria-label*='close' i]",
      );
    if (closeButton) closeButton.click();
    else {
      layer.classList.remove("on", "open");
      layer.setAttribute("aria-hidden", "true");
    }
    document.activeElement?.blur?.();
    return true;
  }

  function closeTopLayer() {
    const layers = openLayers();
    if (layers.length) return closeLayer(layers[layers.length - 1]);
    const openChain = document.querySelector(
      ".collectionChain.open [data-chain-toggle]",
    );
    if (!openChain) return false;
    openChain.click();
    return true;
  }

  function selectorFor(element) {
    if (element.id) return `#${CSS.escape(element.id)}`;
    if (element.dataset.artifact)
      return `[data-artifact="${CSS.escape(element.dataset.artifact)}"]`;
    return "";
  }

  function rememberLogicalStep(target) {
    if (restoring) return;
    let peers = [];
    if (target.matches("[data-artifact]"))
      peers = [...document.querySelectorAll("[data-artifact]")];
    else if (target.matches("#customersTab, #staffTab"))
      peers = [document.querySelector("#customersTab"), document.querySelector("#staffTab")];
    else if (target.matches("#groupLane, #directLane"))
      peers = [document.querySelector("#groupLane"), document.querySelector("#directLane")];
    const current = peers.filter(Boolean).find((item) => item.classList.contains("on"));
    if (!current || current === target) return;
    const selector = selectorFor(current);
    if (selector) logicalSteps.push(selector);
  }

  function restoreLogicalStep() {
    const selector = logicalSteps.pop();
    if (!selector) return false;
    const target = document.querySelector(selector);
    if (!target) return false;
    restoring = true;
    target.click();
    queueMicrotask(() => {
      restoring = false;
    });
    return true;
  }

  function showExitHint() {
    let hint = document.getElementById("rrBackExitHint67");
    if (!hint) {
      hint = document.createElement("div");
      hint.id = "rrBackExitHint67";
      hint.style.cssText =
        "position:fixed;left:50%;bottom:calc(88px + env(safe-area-inset-bottom));transform:translateX(-50%);z-index:2147483647;background:#fff;color:#07111d;border-radius:999px;padding:10px 16px;font:800 13px system-ui;box-shadow:0 8px 30px #0009;white-space:nowrap";
      document.body.appendChild(hint);
    }
    hint.textContent = "बाहर जाने के लिए Back फिर दबाएँ";
    hint.hidden = false;
    clearTimeout(showExitHint.timer);
    showExitHint.timer = setTimeout(() => {
      hint.hidden = true;
    }, 1800);
  }

  function rearmGuard() {
    history.pushState(
      { ...(history.state || {}), rrMobileBackGuard67: true },
      "",
      location.href,
    );
  }

  function directoryUrl() {
    return new URL("real-market-distributor-test67.html", location.href).href;
  }

  function leaveRoot() {
    leaving = true;
    removeEventListener("popstate", onPopState);
    const referrerPath = (() => {
      try {
        return new URL(document.referrer).pathname.toLowerCase();
      } catch (_) {
        return "";
      }
    })();
    history.go(
      referrerPath.endsWith("/real-market-distributor-login-test67.html")
        ? -2
        : -1,
    );
  }

  function handleRootBack() {
    const now = Date.now();
    if (now - exitArmedAt < 1800) return leaveRoot();
    exitArmedAt = now;
    showExitHint();
    rearmGuard();
  }

  function onPopState() {
    if (leaving) return;
    if (closeTopLayer() || restoreLogicalStep()) return rearmGuard();
    if (isDistributorChat) {
      location.replace(directoryUrl());
      return;
    }
    if (isDirectory || isCustomerCollection) {
      handleRootBack();
      return;
    }
    rearmGuard();
  }

  function back() {
    if (closeTopLayer() || restoreLogicalStep()) return true;
    if (isDistributorChat) {
      location.href = directoryUrl();
      return true;
    }
    history.back();
    return true;
  }

  document.addEventListener(
    "click",
    (event) => {
      const target = event.target.closest?.(
        "[data-artifact], #customersTab, #staffTab, #groupLane, #directLane",
      );
      if (target) rememberLogicalStep(target);
    },
    true,
  );

  history.replaceState(
    { ...(history.state || {}), rrMobileBackBase67: true },
    "",
    location.href,
  );
  rearmGuard();
  addEventListener("popstate", onPopState);
  window.RRMobileBackStepTest67 = { back, closeTopLayer };
})();
