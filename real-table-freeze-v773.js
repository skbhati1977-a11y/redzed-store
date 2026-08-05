(()=>{
'use strict';
const VERSION='773.1';
const STYLE_ID='rrTableFreezeStyleV773';
const KEY_PREFIX='rr-table-freeze:';
let counter=0;

function installStyle(){
  if(document.getElementById(STYLE_ID))return;
  const s=document.createElement('style');
  s.id=STYLE_ID;
  s.textContent=`
  .rr-freeze-control{display:flex;justify-content:flex-end;gap:8px;margin:0 0 7px;position:relative;z-index:6}
  .rr-freeze-toggle{background:#26324a!important;border:1px solid #49618d!important;color:#fff!important;border-radius:9px!important;padding:7px 10px!important;font:700 12px system-ui,-apple-system,"Segoe UI",Arial,sans-serif!important;cursor:pointer!important;width:auto!important}
  .rr-freeze-toggle.rr-on{background:#174936!important;border-color:#318b65!important}
  .rr-freeze-disabled table thead th{position:static!important;top:auto!important}
  .rr-freeze-enabled{position:relative!important;overflow:auto!important}
  .rr-freeze-enabled table thead th{position:sticky!important;top:0!important;z-index:30!important;background:#20252e!important}
  .rr-freeze-enabled table th:first-child,
  .rr-freeze-enabled table td:first-child{position:sticky!important;left:0!important;z-index:20!important;background:#151922!important;box-shadow:2px 0 0 #303641}
  .rr-freeze-enabled table thead th:first-child{z-index:40!important;background:#20252e!important}
  .rr-freeze-enabled table tbody tr:hover td:first-child{background:#1b2029!important}
  `;
  document.head.appendChild(s);
}
function targetFor(table){
  return table.closest('.table-wrap,.size-wrap,.rr-wrap')||table.parentElement;
}
function keyFor(target){
  if(!target.dataset.rrFreezeKey){
    counter+=1;
    target.dataset.rrFreezeKey=`${location.pathname}:${counter}`;
  }
  return KEY_PREFIX+target.dataset.rrFreezeKey;
}
function setMode(target,button,on){
  target.classList.toggle('rr-freeze-enabled',on);
  target.classList.toggle('rr-freeze-disabled',!on);
  button.classList.toggle('rr-on',on);
  button.textContent=on?'FREEZE ON · HEADER + FIRST COLUMN':'FREEZE OFF · HEADER + FIRST COLUMN';
  try{localStorage.setItem(keyFor(target),on?'1':'0')}catch{}
}
function enhance(table){
  if(!table||table.dataset.rrFreezeReady==='1')return;
  const target=targetFor(table);
  if(!target)return;
  table.dataset.rrFreezeReady='1';
  const control=document.createElement('div');
  control.className='rr-freeze-control';
  const button=document.createElement('button');
  button.type='button';
  button.className='rr-freeze-toggle';
  button.title='Table header row aur first column ko freeze/unfreeze karein';
  control.appendChild(button);
  target.parentNode.insertBefore(control,target);
  let on=true;
  try{const saved=localStorage.getItem(keyFor(target)); if(saved!==null)on=saved==='1'}catch{}
  setMode(target,button,on);
  button.addEventListener('click',()=>setMode(target,button,!target.classList.contains('rr-freeze-enabled')));
}
function scan(){document.querySelectorAll('table').forEach(enhance)}
function boot(){installStyle();scan();new MutationObserver(scan).observe(document.body,{childList:true,subtree:true})}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
window.REDZED_TABLE_FREEZE_VERSION=VERSION;
})();
