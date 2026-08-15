// REAL FACTORY V9058 + V9096
// Compatibility fix for the live Open Random Queue assignment panel.
// V9096 also keeps the current due cards visible while background auth/data refresh runs.
(() => {
  if (typeof Element !== 'undefined' && typeof Element.prototype.scrollIntoFilter !== 'function') {
    Element.prototype.scrollIntoFilter = function (options) {
      return this.scrollIntoView(options || { behavior: 'smooth', block: 'center' });
    };
  }

  const style = document.createElement('style');
  style.id = 'rr-v9096-no-flicker';
  style.textContent = `
    html.rf-v9095-loading #board{visibility:visible!important;opacity:1!important}
    html.rf-v9095-loading .lot-card{visibility:visible!important}
  `;
  document.head.appendChild(style);

  const recover = async () => {
    try { await window.RRRefreshSupabaseSession?.(false); } catch (_) {}
  };
  window.addEventListener('focus', recover, {passive:true});
  window.addEventListener('online', recover, {passive:true});
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') recover();
  });
})();
