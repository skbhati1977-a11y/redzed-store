(()=>{
'use strict';
if(window.__RR_SALES_CHAT_BACK_NAV_V9440__)return;
window.__RR_SALES_CHAT_BACK_NAV_V9440__=true;
const $=id=>document.getElementById(id);
let ready=false,exiting=false,suppressPush=false;
const isMobile=()=>matchMedia('(max-width:760px)').matches;
const currentLevel=()=>history.state?.rrSalesChatLevel||'inbox';
function setUI(level){
 suppressPush=true;
 $('memberBack')?.classList.remove('on');
 $('callBack')?.classList.remove('on');
 if(isMobile()){
   if(level==='inbox'||level==='base') $('inbox')?.classList.remove('hide');
   else $('inbox')?.classList.add('hide');
 }
 setTimeout(()=>{suppressPush=false},0);
}
function push(level){
 if(!ready||suppressPush||currentLevel()===level)return;
 history.pushState({rrSalesChat:true,rrSalesChatLevel:level},'',location.href);
}
function confirmExit(){
 return confirm('Real Chat से बाहर निकलना है?');
}
function initHistory(){
 history.replaceState({...history.state,rrSalesChat:true,rrSalesChatLevel:'base'},'',location.href);
 history.pushState({rrSalesChat:true,rrSalesChatLevel:'inbox'},'',location.href);
 ready=true;
 setUI('inbox');
}
window.addEventListener('popstate',()=>{
 if(exiting)return;
 const level=currentLevel();
 if(level==='base'){
   if(confirmExit()){
     exiting=true;
     setTimeout(()=>history.back(),0);
   }else{
     history.pushState({rrSalesChat:true,rrSalesChatLevel:'inbox'},'',location.href);
     setUI('inbox');
   }
   return;
 }
 setUI(level);
});
document.addEventListener('click',e=>{
 const t=e.target.closest?.('button,[data-chat]'); if(!t)return;
 if(t.id==='memberClose'){
   e.preventDefault();e.stopImmediatePropagation();
   if(currentLevel()==='member')history.back();else $('memberBack')?.classList.remove('on');
   return;
 }
 if(t.id==='callClose'){
   e.preventDefault();e.stopImmediatePropagation();
   if(currentLevel()==='call')history.back();else $('callBack')?.classList.remove('on');
   return;
 }
 if(t.id==='backInbox'){
   e.preventDefault();e.stopImmediatePropagation();
   if(currentLevel()!=='inbox')history.back();else $('inbox')?.classList.remove('hide');
   return;
 }
 if(t.matches?.('[data-chat]')&&isMobile()) setTimeout(()=>push('chat'),0);
 if(t.id==='groupInfo') setTimeout(()=>{if($('memberBack')?.classList.contains('on'))push('member')},0);
 if(t.id==='callBtn') setTimeout(()=>{if($('callBack')?.classList.contains('on'))push('call')},0);
},true);
const obs=new MutationObserver(ms=>{
 if(!ready||suppressPush)return;
 for(const m of ms){
   const el=m.target;
   if(el.id==='memberBack'&&el.classList.contains('on'))push('member');
   if(el.id==='callBack'&&el.classList.contains('on'))push('call');
 }
});
function start(){
 initHistory();
 if($('memberBack'))obs.observe($('memberBack'),{attributes:true,attributeFilter:['class']});
 if($('callBack'))obs.observe($('callBack'),{attributes:true,attributeFilter:['class']});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();