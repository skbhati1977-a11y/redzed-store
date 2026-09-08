(() => {
  "use strict";
  if (window.__RR_CHAT_LIST_DEFAULT_V9690__) return;
  window.__RR_CHAT_LIST_DEFAULT_V9690__ = true;

  const isWorkflowReturn = (() => {
    try {
      return /\/(?:real-web-window-v9329|real-pi-specimen-v9514|real-market-shared-invoice-test67)\.html$/i.test(
        new URL(document.referrer).pathname,
      );
    } catch (_) {
      return false;
    }
  })();

  if (isWorkflowReturn) return;
  const url = new URL(location.href);
  if (!url.searchParams.has("chat") && !url.searchParams.has("chat_id")) return;
  url.searchParams.delete("chat");
  url.searchParams.delete("chat_id");
  history.replaceState(history.state, "", url.pathname + url.search + url.hash);
})();
