(()=>{
'use strict';
if(window.__RR_SALES_CHAT_BACK_NAV_V9478__)return;
window.__RR_SALES_CHAT_BACK_NAV_V9478__=true;
const $=id=>document.getElementById(id);
let exiting=false,ready=false;
const isMobile=()=>matchMedia('(max-width:760px)').matches;
const level=()=>String(location.hash||'').replace('#rr-','')||'inbox';
function show(lv){$('memberBack')?.classList.remove('on');$('callBack')?.classList.remove('on');if(!isMobile())return;if(lv==='inbox'||lv==='base')$('inbox')?.classList.remove('hide');else $('inbox')?.classList.add('hide')}
function go(lv,replace=false){const h='#rr-'+lv;if(location.hash===h){show(lv);return}if(replace)history.replaceState({rrChat:true,level:lv},'',h);else history.pushState({rrChat:true,level:lv},'',h);show(lv)}
function exitNow(){exiting=true;try{window.close()}catch(_){}setTimeout(()=>{try{history.go(-(Math.max(1,history.length-1)))}catch(_){}},20)}
function init(){const clean=location.pathname+location.search;history.replaceState({rrChat:true,level:'base'},'',clean+'#rr-base');history.pushState({rrChat:true,level:'inbox'},'',clean+'#rr-inbox');ready=true;show('inbox')}
window.addEventListener('popstate',()=>{if(!ready||exiting)return;const lv=level();if(lv==='base'){if(confirm('Real Chat से बाहर निकलना है?'))exitNow();else go('inbox');return}show(lv)});
document.addEventListener('click',e=>{const t=e.target.closest?.('button,[data-chat]');if(!t)return;if(t.matches?.('[data-chat]')&&isMobile()){setTimeout(()=>go('chat'),0);return}if(t.id==='groupInfo'){setTimeout(()=>{if($('memberBack')?.classList.contains('on'))go('member')},0);return}if(t.id==='callBtn'){setTimeout(()=>{if($('callBack')?.classList.contains('on'))go('call')},0);return}if(t.id==='memberClose'){e.preventDefault();e.stopImmediatePropagation();if(level()==='member')history.back();else $('memberBack')?.classList.remove('on');return}if(t.id==='callClose'){e.preventDefault();e.stopImmediatePropagation();if(level()==='call')history.back();else $('callBack')?.classList.remove('on');return}if(t.id==='backInbox'){if(window.__RR_CHAT_LOCAL_SLICE_V9463__||window.__RR_CHAT_LOCAL_SLICE_V9462__||window.__RR_CHAT_LOCAL_SLICE_V9465__)return;e.preventDefault();e.stopImmediatePropagation();if(['chat','member','call'].includes(level()))go('inbox');else $('inbox')?.classList.remove('hide')}},true);
const obs=new MutationObserver(ms=>{if(!ready)return;for(const m of ms){const el=m.target;if(el.id==='memberBack'&&el.classList.contains('on')&&level()!=='member')go('member');if(el.id==='callBack'&&el.classList.contains('on')&&level()!=='call')go('call')}});
function start(){init();if($('memberBack'))obs.observe($('memberBack'),{attributes:true,attributeFilter:['class']});if($('callBack'))obs.observe($('callBack'),{attributes:true,attributeFilter:['class']})}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();