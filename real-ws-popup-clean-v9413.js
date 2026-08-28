(()=>{
'use strict';
if(window.__RR_WS_POPUP_CLEAN_V9413__)return;
window.__RR_WS_POPUP_CLEAN_V9413__=true;

const STYLE_ID='rrWsPopupCleanV9413Style';
function installStyle(){
  if(document.getElementById(STYLE_ID))return;
  const s=document.createElement('style');
  s.id=STYLE_ID;
  s.textContent=`
    #rrWsModal9411 .rr-gsheet-toolbar,
    #rrWsModal9411 .rr-gsheet-filter-btn,
    #rrWsModal9411 .rr-gsheet-filter-row,
    #rrWsModal9411 .rr-gsheet-filter-menu,
    #rrWsModal9411 .rr-gsheet-menu{display:none!important}
    body:has(#rrWsModal9411) #rrGsheetBottomScrollV775{display:none!important}
  `;
  document.head.appendChild(s);
}
function clean(){
  installStyle();
  const modal=document.getElementById('rrWsModal9411');
  if(!modal)return;
  modal.querySelectorAll('table').forEach(t=>{
    t.dataset.rrGoogleSheetReady='1';
    t.dataset.rrNoGsheet='1';
  });
  modal.querySelectorAll('.rr-gsheet-toolbar,.rr-gsheet-filter-btn,.rr-gsheet-filter-row,.rr-gsheet-filter-menu,.rr-gsheet-menu').forEach(n=>n.remove());
  document.getElementById('rrGsheetBottomScrollV775')?.classList.remove('rr-visible');
  document.body.classList.remove('rr-gsheet-bottom-active');
}
installStyle();
new MutationObserver(clean).observe(document.documentElement,{childList:true,subtree:true});
document.addEventListener('pointerdown',e=>{if(e.target.closest?.('#rrWsModal9411'))queueMicrotask(clean)},true);
clean();
})();