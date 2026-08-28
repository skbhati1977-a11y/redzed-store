(()=>{
'use strict';
if(window.__RR_WS_POPUP_CLEAN_V9413__)return;
window.__RR_WS_POPUP_CLEAN_V9413__=true;
const STYLE_ID='rrWsPopupCleanV9413Style';
function installStyle(){if(document.getElementById(STYLE_ID))return;const s=document.createElement('style');s.id=STYLE_ID;s.textContent=`#rrWsModal9411 .rr-gsheet-toolbar,#rrWsModal9411 .rr-gsheet-filter-btn,#rrWsModal9411 .rr-gsheet-filter-row,#rrWsModal9411 .rr-gsheet-filter-menu,#rrWsModal9411 .rr-gsheet-menu,#rr9415modal .rr-gsheet-toolbar,#rr9415modal .rr-gsheet-filter-btn,#rr9415modal .rr-gsheet-filter-row,#rr9415modal .rr-gsheet-filter-menu,#rr9415modal .rr-gsheet-menu{display:none!important}body:has(#rrWsModal9411) #rrGsheetBottomScrollV775,body:has(#rr9415modal) #rrGsheetBottomScrollV775{display:none!important}`;document.head.appendChild(s)}
function clean(){installStyle();document.querySelectorAll('#rrWsModal9411,#rr9415modal').forEach(modal=>{modal.querySelectorAll('table').forEach(t=>{t.dataset.rrGoogleSheetReady='1';t.dataset.rrNoGsheet='1'});modal.querySelectorAll('.rr-gsheet-toolbar,.rr-gsheet-filter-btn,.rr-gsheet-filter-row,.rr-gsheet-filter-menu,.rr-gsheet-menu').forEach(n=>n.remove())})}
installStyle();new MutationObserver(clean).observe(document.documentElement,{childList:true,subtree:true});clean();
if(/\/real-finished-goods-v787\.html$/i.test(location.pathname)&&!window.__RR_WS_STOCK_V9415_LOADER__){window.__RR_WS_STOCK_V9415_LOADER__=true;const s=document.createElement('script');s.src='/redzed-store/real-ws-stock-v9415.js?v=9419';s.async=false;(document.head||document.documentElement).appendChild(s);const f=document.createElement('script');f.src='/redzed-store/real-ws-freeze-toggle-fix-v9416.js?v=9419';f.async=false;(document.head||document.documentElement).appendChild(f)}
})();