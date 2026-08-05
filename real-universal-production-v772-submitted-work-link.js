(()=>{
'use strict';
const VERSION='772.1';
function install(){
  if(document.getElementById('rrSubmittedWorkV772'))return;
  const button=document.createElement('button');
  button.id='rrSubmittedWorkV772';button.type='button';button.textContent='SUBMITTED WORK';button.title='Department / Worker wise submitted PCS and Assignment Actual Rate';button.dataset.version=VERSION;
  button.addEventListener('click',()=>{location.href='real-upm-submitted-work-v772.html?v=7721'});
  const bar=document.querySelector('.modulebar')||document.querySelector('.toolbar')||document.querySelector('.top');
  if(bar){bar.appendChild(button);return}
  button.style.cssText='position:fixed;right:14px;bottom:14px;z-index:45;background:#174936;border-color:#318b65';document.body.appendChild(button);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();
