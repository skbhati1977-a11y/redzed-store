(()=>{
'use strict';
if(window.__RR_SUPERADMIN_VIEW_AS_V172__)return;window.__RR_SUPERADMIN_VIEW_AS_V172__=true;
const KEY='rr_superadmin_preview_role',ENABLE='rr_superadmin_preview_enabled',q=new URLSearchParams(location.search);
if(/test70/i.test(location.pathname)||q.get('mode')==='TEST')sessionStorage.setItem(ENABLE,'1');
if(sessionStorage.getItem(ENABLE)!=='1')return;
const getDb=()=>window.supabaseClient||(typeof supabaseClient!=='undefined'?supabaseClient:null),preview=()=>sessionStorage.getItem(KEY)||'';
window.RR_VIEW_AS_ROLE=preview();
window.RR_EFFECTIVE_ROLE=actual=>preview()||String(actual||'').toUpperCase();
async function mount(){const db=getDb();if(!db?.auth)return;const session=(await db.auth.getSession()).data?.session;if(!session)return;const profile=(await db.from('rr_user_profiles').select('full_name,role_code,is_active').eq('auth_user_id',session.user.id).eq('is_active',true).maybeSingle()).data,actual=String(profile?.role_code||'').toUpperCase();if(!['OWNER','SUPER_ADMIN'].includes(actual))return;
 const el=document.createElement('aside');el.id='rrGlobalViewAs172';el.innerHTML=`<b>${preview()?'READ-ONLY · '+preview().replaceAll('_',' '):'VIEW AS'}</b><select aria-label="Global View As"><option value="">ACTUAL · SUPER ADMIN</option><option value="ADMIN">PREVIEW · ADMIN</option><option value="SALES">PREVIEW · SALESMAN</option><option value="PACKING_OPERATOR">PREVIEW · PACKING WORKER</option><option value="WORKER">PREVIEW · OTHER WORKER</option></select>`;el.querySelector('select').value=preview();el.querySelector('select').onchange=e=>{if(e.target.value)sessionStorage.setItem(KEY,e.target.value);else sessionStorage.removeItem(KEY);location.reload()};document.body.appendChild(el);
 const css=document.createElement('style');css.textContent=`#rrGlobalViewAs172{position:fixed;right:8px;top:8px;z-index:2147483646;display:flex;align-items:center;gap:6px;padding:6px;border:1px solid #67a9d4;border-radius:10px;background:#0d2639;color:#d9f2ff;font:800 10px system-ui;box-shadow:0 4px 16px #0008}#rrGlobalViewAs172 select{max-width:155px;padding:6px;border:1px solid #527895;border-radius:7px;background:#102b40;color:#fff;font:800 10px system-ui}html.rr-role-preview body:before{content:'READ-ONLY ROLE PREVIEW';position:fixed;left:50%;top:8px;transform:translateX(-50%);z-index:2147483645;padding:7px 10px;border-radius:9px;background:#5b390b;color:#ffe2a2;font:900 10px system-ui}`;document.head.appendChild(css);
 if(preview()){document.documentElement.classList.add('rr-role-preview');document.addEventListener('click',e=>{if(e.target.closest('#rrGlobalViewAs172'))return;const control=e.target.closest('button,input,textarea,select,[contenteditable="true"]');if(control){e.preventDefault();e.stopImmediatePropagation()}},true);document.addEventListener('submit',e=>{e.preventDefault();e.stopImmediatePropagation()},true)}
}
document.readyState==='loading'?document.addEventListener('DOMContentLoaded',mount,{once:true}):mount();
})();
