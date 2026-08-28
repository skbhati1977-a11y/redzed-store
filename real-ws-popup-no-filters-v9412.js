(() => {
  'use strict';
  if (window.__RR_WS_POPUP_NO_FILTERS_V9412__) return;
  window.__RR_WS_POPUP_NO_FILTERS_V9412__ = true;
  if (!/\/real-finished-goods-v787\.html$/i.test(location.pathname)) return;

  const STYLE_ID = 'rrWsPopupNoFilters9412Style';
  function installStyle(){
    if(document.getElementById(STYLE_ID)) return;
    const s=document.createElement('style');
    s.id=STYLE_ID;
    s.textContent=`
      #rrWsModal9411 .rr-gsheet-toolbar,
      #rrWsModal9411 .rr-gsheet-filter-btn,
      #rrWsModal9411 .rr-gsheet-filter-row,
      #rrWsModal9411 .rr-gsheet-menu{display:none!important}
    `;
    document.head.appendChild(s);
  }

  function cleanPopup(){
    const modal=document.getElementById('rrWsModal9411');
    if(!modal) return;
    modal.querySelectorAll('table').forEach(table=>{
      table.dataset.rrNoGsheet='1';
      table.dataset.rrGoogleSheetReady='1';
    });
    modal.querySelectorAll('.rr-gsheet-toolbar,.rr-gsheet-filter-btn,.rr-gsheet-filter-row,.rr-gsheet-menu').forEach(node=>node.remove());
  }

  installStyle();
  new MutationObserver(cleanPopup).observe(document.documentElement,{childList:true,subtree:true});
  document.addEventListener('click',()=>setTimeout(cleanPopup,0),true);
  document.addEventListener('dblclick',()=>setTimeout(cleanPopup,0),true);
  setTimeout(cleanPopup,0);
})();
