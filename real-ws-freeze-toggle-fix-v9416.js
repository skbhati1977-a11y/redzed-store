(()=>{
'use strict';
if(window.__RR_WS_FREEZE_TOGGLE_FIX_V9416__)return;
window.__RR_WS_FREEZE_TOGGLE_FIX_V9416__=true;
if(!/\/real-finished-goods-v787\.html$/i.test(location.pathname))return;

let lastTap=0,lastKey='',internal=false;
function grid(){return document.getElementById('rr9415grid')}
function isFreezeTarget(t){
  const g=grid(); if(!g||!t?.closest)return false;
  if(t.closest('[data-freeze-toggle]'))return true;
  if(!g.classList.contains('frozen')){
    const h=t.closest('.rr9415-main-head-cell');
    if(h){const a=[...h.parentElement.children];return a.indexOf(h)<2}
    const c=t.closest('.rr9415-row .rr9415-cell');
    if(c){const a=[...c.parentElement.children];return a.indexOf(c)<2}
  }
  return false;
}
function doToggle(){
  const original=document.querySelector('[data-view="stock"] [data-freeze-toggle]');
  if(!original)return;
  internal=true;
  original.dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true,view:window}));
  original.dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true,view:window}));
  internal=false;
}
document.addEventListener('click',e=>{
  if(internal||!isFreezeTarget(e.target))return;
  e.preventDefault();e.stopImmediatePropagation();
  const n=Date.now();
  const key='freeze';
  if(lastKey===key&&n-lastTap<430){lastTap=0;lastKey='';doToggle()}
  else{lastTap=n;lastKey=key}
},true);
document.addEventListener('dblclick',e=>{
  if(internal||!isFreezeTarget(e.target))return;
  e.preventDefault();e.stopImmediatePropagation();
},true);
})();