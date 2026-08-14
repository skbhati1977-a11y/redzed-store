// REAL FACTORY V9058
// Compatibility fix for the live Open Random Queue assignment panel.
// The deployed queue calls scrollIntoFilter; the browser API is scrollIntoView.
(() => {
  if (typeof Element === 'undefined') return;
  if (typeof Element.prototype.scrollIntoFilter !== 'function') {
    Element.prototype.scrollIntoFilter = function (options) {
      return this.scrollIntoView(options || { behavior: 'smooth', block: 'center' });
    };
  }
})();
