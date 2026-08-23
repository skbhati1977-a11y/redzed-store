/* V9329 — Global logout rule: logout only via Logout button/link with confirmation. */
(()=>{
  'use strict';
  if(window.__RR_GLOBAL_LOGOUT_CONFIRM_9329__)return;
  window.__RR_GLOBAL_LOGOUT_CONFIRM_9329__=true;
  const LOGIN_PATH=/\/real-login\.html$/i;
  const isLoginPage=()=>LOGIN_PATH.test(location.pathname||'');
  const norm=s=>String(s||'').replace(/\s+/g,' ').trim().toLowerCase();
  const isLogoutEl=el=>{
    if(!el)return false;
    const id=norm(el.id), cls=norm(el.className), txt=norm(el.textContent), title=norm(el.getAttribute?.('title'));
    const href=String(el.getAttribute?.('href')||'');
    const onclick=String(el.getAttribute?.('onclick')||'');
    return id==='logoutbtn'||id.includes('logout')||cls.includes('logout')||txt==='logout'||txt.includes('log out')||title.includes('logout')||/auth\.signOut|signOut\s*\(/i.test(onclick)||/real-login\.html/i.test(href)&&/logout|signout/i.test(id+' '+cls+' '+txt+' '+title);
  };
  const ask=()=>window.confirm('Do you want to logout?');
  async function doLogout(){
    try{
      const c=window.supabaseClient||window.sb||window.redzedSupabase||window.supabaseDb;
      if(c?.auth)await c.auth.signOut();
    }catch(err){console.warn('Logout failed',err)}
    location.href='real-login.html';
  }
  document.addEventListener('click',e=>{
    if(isLoginPage())return;
    const el=e.target?.closest?.('button,a,[role="button"],input[type="button"],input[type="submit"]');
    if(!isLogoutEl(el))return;
    e.preventDefault();
    e.stopPropagation();
    e.stopImmediatePropagation();
    if(ask())doLogout();
  },true);
  document.addEventListener('submit',e=>{
    if(isLoginPage())return;
    const form=e.target;
    if(!form||!/(logout|signout)/i.test(String(form.id||'')+' '+String(form.className||'')+' '+String(form.getAttribute?.('action')||'')))return;
    e.preventDefault();
    e.stopPropagation();
    e.stopImmediatePropagation();
    if(ask())doLogout();
  },true);
})();
