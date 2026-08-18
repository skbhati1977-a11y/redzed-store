(()=>{
'use strict';
if(window.__RR_CUTTING_REPORT_FIRE_9251__)return;
window.__RR_CUTTING_REPORT_FIRE_9251__=true;

let lastFireAt=0;
let lastType='';

function directReportButton(target){
  return target?.closest?.('[data-cba-report]')||null;
}

function pointReportButton(x,y){
  if(!Number.isFinite(x)||!Number.isFinite(y))return null;
  const stack=document.elementsFromPoint?.(x,y)||[];
  for(const node of stack){
    const button=node?.closest?.('[data-cba-report]');
    if(button)return button;
  }
  for(const button of document.querySelectorAll('[data-cba-report]')){
    const r=button.getBoundingClientRect();
    if(x>=r.left&&x<=r.right&&y>=r.top&&y<=r.bottom)return button;
  }
  return null;
}

function buttonForEvent(event){
  const direct=directReportButton(event?.target);
  if(direct)return direct;
  const touch=event?.changedTouches?.[0]||event?.touches?.[0];
  const x=touch?.clientX??event?.clientX;
  const y=touch?.clientY??event?.clientY;
  return pointReportButton(Number(x),Number(y));
}

function fire(button,event){
  if(!button)return false;
  const type=String(button.dataset.cbaReport||'');
  const now=Date.now();
  if(type&&type===lastType&&now-lastFireAt<900){
    event?.preventDefault?.();
    event?.stopImmediatePropagation?.();
    return true;
  }

  const handler=button.onclick;
  if(typeof handler!=='function')return false;

  event?.preventDefault?.();
  event?.stopImmediatePropagation?.();
  lastType=type;
  lastFireAt=now;
  handler.call(button,event);
  return true;
}

function capture(event){
  fire(buttonForEvent(event),event);
}

window.addEventListener('pointerdown',capture,true);
window.addEventListener('touchstart',capture,{capture:true,passive:false});
window.addEventListener('click',capture,true);
})();
