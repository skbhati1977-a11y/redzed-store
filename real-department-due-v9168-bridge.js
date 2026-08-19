(()=>{
'use strict';
const getClient=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
function install(){
 const c=getClient();
 if(!c||c.__rr9168DueBridge)return false;
 const original=c.rpc.bind(c);
 c.rpc=function(name,args,options){
  if(name==='rr_upm_department_colour_due_card_v9109') name='rr_upm_department_colour_due_card_v9167';
  return original(name,args,options);
 };
 c.__rr9168DueBridge=true;
 return true;
}
function loadScript(src,key){
 if(document.querySelector(`script[data-${key}]`))return;
 const s=document.createElement('script');s.src=src;s.setAttribute(`data-${key}`,'1');document.head.appendChild(s);
}
function loadAlterForm(){
 if(!window.__RR_UPM_ALTER_FORM_9253__)loadScript('real-upm-alter-form-v9253.js?v=9253','rr-alter-9253');
 loadScript('real-upm-alter-queue-compact-v9264.js?v=9267','rr-alter-queue-9267');
 loadScript('real-upm-alter-traveller-grid-v9268.js?v=9275','rr-alter-traveller-9275');
}
loadAlterForm();
if(!install()){
 let n=0;const t=setInterval(()=>{if(install()||++n>40)clearInterval(t)},50);
}
})();