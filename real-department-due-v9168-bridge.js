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
function loadApprovedAlter(){
 loadScript('real-upm-alter-flow-v9114.js?v=9295','rr-alter-approved-9116');
 loadScript('real-upm-alter-camera-patch-v9116.js?v=9290','rr-alter-camera-9116');
}
loadApprovedAlter();
if(!install()){
 let n=0;const t=setInterval(()=>{if(install()||++n>40)clearInterval(t)},50);
}
})();