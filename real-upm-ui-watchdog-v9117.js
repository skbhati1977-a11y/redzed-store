(() => {
'use strict';
if(window.__RF_UI_WATCHDOG_9117__) return;
window.__RF_UI_WATCHDOG_9117__=true;
const style=document.createElement('style');
style.id='rf-ui-watchdog-9117';
style.textContent=`
html:not(.rf-modal-open),body:not(.rf-modal-open){overflow-y:auto!important;touch-action:pan-y!important}
.rfcard,.rfactions button,.rfrow,.rfbar button{pointer-events:auto!important}
`;
document.head.appendChild(style);
function modalOpen(){return !!document.querySelector('.rfmodal:not(.hidden), .modal:not(.hidden)')}
function heal(){
  const open=modalOpen();
  document.documentElement.classList.toggle('rf-modal-open',open);
  document.body?.classList.toggle('rf-modal-open',open);
  if(!open){
    if(document.documentElement.style.overflow==='hidden') document.documentElement.style.overflow='';
    if(document.body?.style.overflow==='hidden') document.body.style.overflow='';
    if(document.body?.style.position==='fixed') document.body.style.position='';
    if(document.body?.style.touchAction==='none') document.body.style.touchAction='';
  }
}
window.addEventListener('pageshow',heal,{passive:true});
window.addEventListener('focus',heal,{passive:true});
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')heal()});
document.addEventListener('click',e=>{
  const btn=e.target.closest?.('[data-act="ALTER"],[data-act="SUBMIT"],[data-act="RECT"],.rfrow.assign,.rfbar button');
  if(btn) requestAnimationFrame(heal);
},true);
new MutationObserver(heal).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['class','style']});
setInterval(heal,1500);
heal();
})();
