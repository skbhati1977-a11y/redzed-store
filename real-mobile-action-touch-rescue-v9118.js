(() => {
  'use strict';
  if (window.__RF_MOBILE_ACTION_TOUCH_RESCUE_9118__) return;
  window.__RF_MOBILE_ACTION_TOUCH_RESCUE_9118__ = true;

  const isAction = (b) => {
    if (!b || b.disabled) return false;
    const t = String(b.textContent || '').replace(/\s+/g,' ').trim().toUpperCase();
    return t === 'ALTER' || t === 'RECTIFICATION' || t.includes('READY TO SUBMIT');
  };

  const buttonAt = (x,y) => {
    const buttons = [...document.querySelectorAll('button')].filter(isAction);
    let best = null;
    for (const b of buttons) {
      const r = b.getBoundingClientRect();
      if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) {
        const area = Math.max(1, r.width * r.height);
        if (!best || area < best.area) best = {b,area};
      }
    }
    return best?.b || null;
  };

  document.addEventListener('touchend', (e) => {
    if (!e.changedTouches?.length) return;
    const t = e.changedTouches[0];
    const b = buttonAt(t.clientX,t.clientY);
    if (!b) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    try {
      b.dataset.rfTouchRescue = String(Date.now());
      b.click();
    } catch (err) {
      console.error('RF touch rescue failed', err);
    }
  }, {capture:true, passive:false});

  document.addEventListener('pointerup', (e) => {
    if (e.pointerType !== 'touch') return;
    const b = buttonAt(e.clientX,e.clientY);
    if (!b) return;
    const last = Number(b.dataset.rfTouchRescue || 0);
    if (Date.now() - last < 700) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    try {
      b.dataset.rfTouchRescue = String(Date.now());
      b.click();
    } catch (err) {
      console.error('RF pointer rescue failed', err);
    }
  }, true);
})();
