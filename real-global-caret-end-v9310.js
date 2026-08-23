(()=>{
 "use strict";
 if(window.__RR_GLOBAL_CARET_END_V9310__)return;
 window.__RR_GLOBAL_CARET_END_V9310__=true;
 const TEXT_TYPES=new Set(["","text","search","tel","url","email","password","number"]);
 const skip=el=>!el||el.disabled||/^(button|submit|reset|checkbox|radio|file|range|color|date|time|datetime-local|month|week|hidden)$/i.test(el.type||"");
 const isTarget=el=>el&&(el.matches?.("textarea,[contenteditable='true']")||(el.matches?.("input")&&TEXT_TYPES.has(String(el.type||"").toLowerCase())&&!skip(el)));
 function endContentEditable(el){try{const r=document.createRange();r.selectNodeContents(el);r.collapse(false);const s=getSelection();s.removeAllRanges();s.addRange(r)}catch(_e){}}
 function endInput(el){if(!isTarget(el))return;const v=String(el.value??el.textContent??"");if(!v)return;if(el.isContentEditable){endContentEditable(el);return}try{el.setSelectionRange(v.length,v.length)}catch(_e){try{const t=el.type;el.type="text";el.setSelectionRange(v.length,v.length);el.type=t}catch(_e2){try{el.value=v}catch(_e3){}}}}
 function schedule(el){if(!isTarget(el))return;requestAnimationFrame(()=>endInput(el));setTimeout(()=>endInput(el),40)}
 document.addEventListener("focusin",e=>schedule(e.target),true);
 document.addEventListener("pointerup",e=>schedule(e.target),true);
 document.addEventListener("click",e=>schedule(e.target),true);
 document.addEventListener("touchend",e=>schedule(e.target),true);
 document.addEventListener("redzed:focus-caret-end",e=>schedule(e.detail?.target||document.activeElement));
})();
(()=>{
 "use strict";
 if(window.__RR_GLOBAL_LOGOUT_CONFIRM_9329__)return;
 window.__RR_GLOBAL_LOGOUT_CONFIRM_9329__=true;
 const LOGIN_PATH=/\/real-login\.html$/i;
 const isLoginPage=()=>LOGIN_PATH.test(location.pathname||"");
 const norm=s=>String(s||"").replace(/\s+/g," ").trim().toLowerCase();
 const isLogoutEl=el=>{
  if(!el)return false;
  const id=norm(el.id), cls=norm(el.className), txt=norm(el.textContent||el.value), title=norm(el.getAttribute?.("title"));
  const href=String(el.getAttribute?.("href")||"");
  const onclick=String(el.getAttribute?.("onclick")||"");
  return id==="logoutbtn"||id.includes("logout")||id.includes("signout")||cls.includes("logout")||cls.includes("signout")||txt==="logout"||txt==="log out"||txt.includes("logout")||txt.includes("log out")||title.includes("logout")||/auth\.signOut|signOut\s*\(/i.test(onclick)||(/real-login\.html/i.test(href)&&/logout|signout/i.test(id+" "+cls+" "+txt+" "+title));
 };
 const ask=()=>window.confirm("Do you want to logout?");
 async function doLogout(){
  try{
   const c=window.supabaseClient||window.sb||window.redzedSupabase||window.supabaseDb;
   if(c?.auth)await c.auth.signOut();
  }catch(err){console.warn("Logout failed",err)}
  location.href="real-login.html";
 }
 document.addEventListener("click",e=>{
  if(isLoginPage())return;
  const el=e.target?.closest?.("button,a,[role='button'],input[type='button'],input[type='submit']");
  if(!isLogoutEl(el))return;
  e.preventDefault();
  e.stopPropagation();
  e.stopImmediatePropagation();
  if(ask())doLogout();
 },true);
 document.addEventListener("submit",e=>{
  if(isLoginPage())return;
  const form=e.target;
  if(!form||!/(logout|signout)/i.test(String(form.id||"")+" "+String(form.className||"")+" "+String(form.getAttribute?.("action")||"")))return;
  e.preventDefault();
  e.stopPropagation();
  e.stopImmediatePropagation();
  if(ask())doLogout();
 },true);
})();
