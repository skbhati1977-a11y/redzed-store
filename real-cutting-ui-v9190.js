(()=>{
'use strict';
if(window.__RR_CUTTING_UI_9190__)return;window.__RR_CUTTING_UI_9190__=true;
if(!/\/real-cutting-master\.html$/i.test(location.pathname))return;
const style=document.createElement('style');style.id='rrCuttingUi9190';style.textContent=`
/* Dynamic PM form: professional compact source-level presentation */
#cmComboPanel{border:1px solid #2d3542!important;background:#12161d!important;border-radius:16px!important;padding:12px!important;margin:0 0 10px!important;box-shadow:none!important}
#cmComboPanel>.cm-matrix-head{display:flex!important;align-items:center!important;justify-content:space-between!important;gap:10px!important;margin:0 0 10px!important;padding:0 0 9px!important;border-bottom:1px solid #2d3542!important}
#cmComboPanel>.cm-matrix-head h3{margin:0!important;font-size:16px!important}#cmSelectedMode{display:inline-flex!important;align-items:center!important;min-height:30px!important;padding:0 9px!important;border-radius:999px!important;background:#202735!important;border:1px solid #384252!important;font-size:11px!important;color:#cfe0ff!important;white-space:nowrap!important}
#cmComboPanel p,.cm-rule-note{display:none!important}
#cmComboPanel .cm-grid-2,#cmComboPanel .cm-grid-3{display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:8px!important}
#cmComboPanel label{min-width:0!important}#cmComboPanel label>span{display:block!important;margin:0 0 5px!important;font-size:10px!important;line-height:1.2!important;color:#aeb8c7!important;font-weight:800!important;text-transform:none!important}
#cmComboPanel input,#cmComboPanel select{width:100%!important;min-height:44px!important;border-radius:11px!important;border:1px solid #333c49!important;background:#0c1016!important;color:#fff!important;padding:9px 10px!important;font-size:15px!important}
#cmComboPanel .cm-primary-input-row{margin:0 0 8px!important}#cmComboPanel .cm-primary-input-row input{min-height:48px!important;font-weight:850!important}
#cmSinglePanel,#cmMultiPanel{display:grid;gap:8px}#cmSinglePanel.cm-hidden,#cmMultiPanel.cm-hidden{display:none!important}
#cmComboPanel .cm-mode-actions{display:grid!important;grid-template-columns:1fr 1fr!important;gap:8px!important;margin:0 0 10px!important}#cmComboPanel .cm-mode-actions button{min-height:42px!important;border-radius:11px!important}
#cmComboPanel .cm-matrix-card{padding:10px!important;border-radius:13px!important;background:#0e1218!important;border:1px solid #2c3440!important}
#lotSheet .cm-sheet-panel{width:min(680px,100%)!important}#lotSheet .cm-form{gap:9px!important}#lotSheet .cm-form-card{padding:11px!important}#lotSheet .cm-form-card h3{font-size:14px!important;margin:0 0 9px!important;color:#f7f8fb!important}
#lotSheet .cm-sheet-head p,#lotSheet .cm-sheet-head small,#lotSheet .cm-form-title p{display:none!important}
#lotSheet .cm-notes textarea{min-height:70px!important}
.rr-cba-panel .rr-cba-head p,.rr-cba-panel .rr-cba-list>small,.rr-cba-dialog header p,.rr-cba-dialog header small,#rrCbaBody .cm-form-card>p{display:none!important}
@media(max-width:600px){#cmComboPanel .cm-grid-2,#cmComboPanel .cm-grid-3{grid-template-columns:1fr 1fr!important}#lotSheet .cm-grid-2,#lotSheet .cm-grid-3{grid-template-columns:1fr!important}#cmComboPanel{padding:10px!important}.cm-sheet-panel{padding-inline:10px!important}}
@media(max-width:380px){#cmComboPanel .cm-grid-2,#cmComboPanel .cm-grid-3{grid-template-columns:1fr!important}}
`;document.head.appendChild(style);
function clean(){
 const panel=document.getElementById('cmComboPanel');
 if(panel){
  const h=panel.querySelector(':scope > .cm-matrix-head h3');if(h)h.textContent='Lot Details';
  panel.querySelectorAll('p').forEach(p=>{p.hidden=true;p.setAttribute('aria-hidden','true')});
 }
 const lotHead=document.querySelector('#lotSheet .cm-sheet-head h2');if(lotHead)lotHead.textContent='Release Lot';
 document.querySelectorAll('#lotSheet .cm-sheet-head p,#lotSheet .cm-sheet-head small,#lotSheet .cm-form-title p,.cm-rule-note').forEach(el=>{el.hidden=true;el.setAttribute('aria-hidden','true')});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',clean,{once:true});else clean();
const obs=new MutationObserver(()=>clean());obs.observe(document.documentElement,{childList:true,subtree:true});
})();