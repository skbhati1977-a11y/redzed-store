(()=>{
'use strict';
if(window.__RR_CUTTING_REPORT_FIRE_9250__)return;
window.__RR_CUTTING_REPORT_FIRE_9250__=true;

let lastPointerFire=0;

function reportButton(event){
  return event?.target?.closest?.('[data-cba-report]')||null;
}

function fireOriginal(button,event){
  if(!button)return false;
  const handler=button.onclick;
  if(typeof handler!=='function')return false;
  event?.preventDefault?.();
  event?.stopImmediatePropagation?.();
  handler.call(button,event);
  return true;
}

window.addEventListener('pointerup',event=>{
  const button=reportButton(event);
  if(!button)return;
  if(fireOriginal(button,event)){
    lastPointerFire=Date.now();
  }
},true);

window.addEventListener('click',event=>{
  const button=reportButton(event);
  if(!button)return;
  if(Date.now()-lastPointerFire<800){
    event.preventDefault();
    event.stopImmediatePropagation();
    return;
  }
  if(fireOriginal(button,event))return;

  const type=button.dataset.cbaReport;
  Promise.resolve(window.REAL_FACTORY_CUTTING_CB_ACTIONS?.refresh?.()).finally(()=>{
    requestAnimationFrame(()=>{
      const fresh=[...document.querySelectorAll('[data-cba-report]')]
        .find(node=>node.dataset.cbaReport===type);
      if(typeof fresh?.onclick==='function')fresh.onclick();
    });
  });
},true);
})();
