(()=>{
'use strict';
const MODULE='market';
const ACTIONS=[
 ['market.access','Market Access'],
 ['market.customer_groups.manage','Customer Groups'],
 ['market.collection.send','Send Collection'],
 ['market.requirement.receive','Receive Requirement'],
 ['market.requirement.forward','Forward Requirement to REDZED'],
 ['market.pi.generate','PI Access / Generate'],
 ['market.ci.generate','CI Access / Generate']
];
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function client(){return window.supabaseClient||window.sb||window.supabaseDb||window.redzedSupabase||null}
function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]))}
async function rpc(name,p={}){const c=client();if(!c)throw new Error('Permission client unavailable');const r=await c.rpc(name,p);if(r.error)throw r.error;return r.data}
function users(data){return (data?.users||[]).filter(x=>x.is_active!==false&&x.profile_id||x.id).map(x=>({id:x.profile_id||x.id,name:x.full_name||x.display_name||x.name||x.email||x.username||'User',role:x.role_code||''}))}
function override(data,pid,key){return (data?.user_action_overrides||[]).find(x=>String(x.profile_id)===String(pid)&&x.action_key===key)}
async function save(pid,key,allowed){await rpc('rr_owner_set_user_action_override_v1',{p_profile_id:pid,p_action_key:key,p_is_allowed:allowed,p_valid_until:null,p_reason:'Market / PI / CI access managed from Role & Permission'});}
async function mount(){
 let host=null;
 for(let i=0;i<40&&!host;i++){host=document.getElementById('tab-overrides')||document.getElementById('tab-users');if(!host)await sleep(250)}
 if(!host)return;
 const box=document.createElement('section');box.id='marketPermissionGateV61';box.className='panel';box.style.marginTop='16px';
 box.innerHTML='<h3>MARKET · COLLECTION · REQUIREMENT · PI · CI ACCESS</h3><p class="note">Default NOT ALLOWED. Tick only the exact access you want to grant to a login ID. Field/column visibility remains controlled by the existing HIDE / VIEW / EDIT matrix.</p><div id="marketGateBody">Loading permission IDs…</div>';
 host.prepend(box);
 try{
   const data=await rpc('rr_owner_permission_console_v1',{p_module_code:null});
   const list=users(data);
   if(!list.length){document.getElementById('marketGateBody').textContent='No login IDs available.';return}
   document.getElementById('marketGateBody').innerHTML=list.map(u=>`<div style="border:1px solid #dbe2ea;border-radius:12px;padding:12px;margin:10px 0"><strong>${esc(u.name)}</strong> <small>${esc(u.role)}</small><div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:8px;margin-top:10px">${ACTIONS.map(([k,l])=>{const o=override(data,u.id,k);const yes=o?.is_allowed===true;return `<label style="display:flex;gap:8px;align-items:center"><input type="checkbox" data-market-profile="${esc(u.id)}" data-market-action="${esc(k)}" ${yes?'checked':''}> ${esc(l)}</label>`}).join('')}</div></div>`).join('');
   document.querySelectorAll('[data-market-action]').forEach(el=>el.addEventListener('change',async()=>{el.disabled=true;const old=!el.checked;try{await save(el.dataset.marketProfile,el.dataset.marketAction,el.checked)}catch(e){el.checked=old;alert(e.message||String(e))}finally{el.disabled=false}}));
 }catch(e){document.getElementById('marketGateBody').textContent='Permission load error: '+(e.message||e)}
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',mount);else mount();
})();