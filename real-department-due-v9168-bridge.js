(()=>{
'use strict';
const getClient=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
function install(){
 const c=getClient();
 if(!c||c.__rr9168DueBridge)return false;
 const original=c.rpc.bind(c);
 c.rpc=function(name,args,options){
  if(name==='rr_upm_department_colour_due_card_v9109') name='rr_upm_department_colour_due_card_v9168';
  return original(name,args,options);
 };
 c.__rr9168DueBridge=true;
 return true;
}
if(!install()){
 let n=0;const t=setInterval(()=>{if(install()||++n>40)clearInterval(t)},50);
}
})();