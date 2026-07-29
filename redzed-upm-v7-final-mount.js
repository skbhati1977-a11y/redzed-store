(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const cuttingTab = $('cuttingTab');
  const productionTab = $('productionTab');
  const refreshActive = $('refreshActive');
  const cuttingFrame = $('cuttingFrame');
  const productionFrame = $('productionFrame');
  let active = 'cutting';

  function reloadFrame(frame) {
    try {
      const doc = frame.contentDocument;
      const btn = doc?.getElementById('refresh') || doc?.getElementById('refreshCutting');
      if (btn) return btn.click();
      frame.contentWindow.location.reload();
    } catch (_) {
      frame.src = frame.src;
    }
  }

  function show(name) {
    active = name === 'production' ? 'production' : 'cutting';
    const cutting = active === 'cutting';
    cuttingFrame.hidden = !cutting;
    productionFrame.hidden = cutting;
    cuttingTab.classList.toggle('is-active', cutting);
    productionTab.classList.toggle('is-active', !cutting);
    if (!cutting) reloadFrame(productionFrame);
    try { sessionStorage.setItem('redzed_upm_v7_active', active); } catch (_) {}
  }

  cuttingTab.onclick = () => show('cutting');
  productionTab.onclick = () => show('production');
  refreshActive.onclick = () => reloadFrame(active === 'cutting' ? cuttingFrame : productionFrame);

  let saved = 'cutting';
  try { saved = sessionStorage.getItem('redzed_upm_v7_active') || 'cutting'; } catch (_) {}
  show(saved);
})();
