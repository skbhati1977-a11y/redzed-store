(()=>{
'use strict';
if(window.__RR_CUTTING_FOCUS_FIX_9195__)return;
window.__RR_CUTTING_FOCUS_FIX_9195__=true;

/*
  Android keyboard stability for Cutting Master.

  real-global-mobile-fill-v9144 intentionally hides a sheet header while an input
  is focused. Its 500ms sync then treats that hidden header as missing, clears the
  state, shows it again, and repeats. The result is the visible up/down jump loop
  while the keyboard is open.

  Keep the Cutting Master sheet header geometrically stable while the global
  helper owns its focus class. The class may still be toggled by the helper, but
  it no longer changes layout, so its sync sees the same visible header and stops
  oscillating.
*/
const style=document.createElement('style');
style.id='rrCuttingFocusStability9195';
style.textContent=`
  body .cm-sheet-panel .cm-sheet-head.rf-fill-hidden-head-v9144{
    display:flex!important;
  }
  body .cm-sheet-panel.rf-fill-active-panel-v9144{
    padding-top:14px!important;
  }
`;
(document.head||document.documentElement).appendChild(style);

/* Android/WebView can still move the panel once when the keyboard opens.
   Keep the focused control visible without smooth-scroll feedback loops. */
let settleTimer=0;
function settleFocusedControl(){
  const el=document.activeElement;
  if(!el?.matches?.('.cm-sheet-panel input,.cm-sheet-panel select,.cm-sheet-panel textarea'))return;
  const panel=el.closest('.cm-sheet-panel');
  if(!panel)return;
  const rect=el.getBoundingClientRect();
  const vv=window.visualViewport;
  const top=vv?.offsetTop||0;
  const bottom=top+(vv?.height||window.innerHeight);
  const safeTop=top+72;
  const safeBottom=bottom-28;
  if(rect.top<safeTop||rect.bottom>safeBottom){
    el.scrollIntoView({block:'center',inline:'nearest',behavior:'auto'});
  }
}
function scheduleSettle(delay=90){
  clearTimeout(settleTimer);
  settleTimer=setTimeout(settleFocusedControl,delay);
}
document.addEventListener('focusin',e=>{
  if(e.target?.matches?.('.cm-sheet-panel input,.cm-sheet-panel select,.cm-sheet-panel textarea')){
    scheduleSettle(140);
  }
},true);
window.visualViewport?.addEventListener('resize',()=>scheduleSettle(120),{passive:true});

console.info('Cutting Master Android focus stability v9195 loaded');
})();
