(()=>{
'use strict';
if(window.__REDZED_GOOGLE_TABLES_V775__)return;
window.__REDZED_GOOGLE_TABLES_V775__=true;

/* TEST62: legacy global table controls are permanently removed.
   Each module keeps its own native horizontal/vertical scrolling and its own
   existing sticky header / sticky first-column behavior. */
function cleanup(){
  document.querySelectorAll('.rr-gsheet-toolbar,#rrGsheetBottomScrollV775,.rr-gsheet-menu,.rr-gsheet-filter-btn').forEach(el=>el.remove());
  document.body.classList.remove('rr-gsheet-bottom-active');
}
cleanup();
new MutationObserver(cleanup).observe(document.documentElement,{childList:true,subtree:true});
})();
