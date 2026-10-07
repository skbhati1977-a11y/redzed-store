(() => {
  'use strict';
  if (window.__RR_REQ_LAYOUT_V9645__) return;
  window.__RR_REQ_LAYOUT_V9645__ = 1;
  const ids = ['rrReqAvg9641', 'rrReqQty9641', 'rrReqAmt9641', 'rrAllAvg9641'];
  const labels = ['AVG RATE', 'TOTAL PCS', 'AMOUNT', 'ALL TIME AVG'];
  function css() {
    if (document.getElementById('rrReqLayout9645Style')) return;
    const style = document.createElement('style');
    style.id = 'rrReqLayout9645Style';
    style.textContent = `
body.rr-customer-v9619{padding-top:46px!important}
#rrCustomerCollectionHeaderV9619{height:46px!important;min-height:46px!important;box-sizing:border-box!important;padding:0 8px!important}
#rrAvgWrap9641{display:none!important}
body.rr-customer-v9619 #rrFSChat{top:46px!important;bottom:0!important;height:calc(100vh - 46px)!important;min-height:0!important}
@supports(height:100dvh){body.rr-customer-v9619 #rrFSChat{height:calc(100dvh - 46px)!important}}
body.rr-customer-v9619 #rrFSChat .fshead{top:-46px!important;height:46px!important;min-height:46px!important;align-items:center!important}
#rrFSChat .fstabs{display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:5px!important;padding:5px 8px!important;flex:0 0 auto!important}
#rrFSChat .fstabs>button{min-width:0!important;padding:6px!important;font-size:10px!important}
#rrCustomerSummary71{display:grid!important;grid-template-columns:repeat(4,minmax(0,1fr))!important;gap:5px!important;padding:3px 8px 7px!important;flex:0 0 auto!important;box-sizing:border-box!important;width:100%!important}
#rrCustomerSummary71>div{display:flex!important;flex-direction:column!important;justify-content:center!important;align-items:center!important;width:100%!important;min-width:0!important;max-width:none!important;height:44px!important;min-height:44px!important;margin:0!important;padding:4px!important;box-sizing:border-box!important;border:1px solid #40536b!important;border-radius:9px!important;background:#121c29!important;color:#fff!important;text-align:center!important;overflow:hidden!important}
#rrCustomerSummary71 small{display:block!important;font-size:8px!important;line-height:1.2!important;white-space:nowrap!important}
#rrCustomerSummary71 b{display:block!important;max-width:100%!important;font-size:11px!important;line-height:1.2!important;margin-top:4px!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important}
#rrFSChat .fsmsgs{min-height:0!important}
body.rr-customer-v9619 #rrFSChat .fscomp{padding:7px 10px max(7px,env(safe-area-inset-bottom))!important}
@media(max-width:350px){#rrCustomerSummary71{gap:3px!important}#rrCustomerSummary71 small{font-size:7px!important}#rrCustomerSummary71 b{font-size:10px!important}}
`;
    document.head.appendChild(style);
  }
  function align() {
    const chat = document.getElementById('rrFSChat');
    const tabs = chat?.querySelector('.fstabs');
    const stats = ids.map(id => document.getElementById(id));
    if (!tabs || stats.some(stat => !stat)) return false;
    let row = document.getElementById('rrCustomerSummary71');
    if (!row) { row = document.createElement('div'); row.id = 'rrCustomerSummary71'; }
    if (tabs.nextElementSibling !== row) tabs.insertAdjacentElement('afterend', row);
    stats.forEach((stat, index) => {
      if (row.children[index] !== stat) row.insertBefore(stat, row.children[index] || null);
      const label = stat.querySelector('small');
      if (label && label.textContent !== labels[index]) label.textContent = labels[index];
    });
    return true;
  }
  function boot() {
    css(); align();
    // One layout owner restores the row when chat/header widgets are recreated.
    let queued = false;
    new MutationObserver(() => {
      if (queued) return;
      queued = true;
      requestAnimationFrame(() => { queued = false; align(); });
    }).observe(document.body, {childList:true, subtree:true});
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, {once:true}); else boot();
})();
