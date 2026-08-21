/* V9309 — allow Owner/Admin/Manager to run FG Packing accept/algorithm/submit on behalf of assigned worker. */
(()=>{
  'use strict';
  const canManage=()=>['owner','admin','manager'].includes(String(window.__rrProfile?.role_code||window.RR_CURRENT_PROFILE?.role_code||'').toLowerCase());
  const text=x=>String(x?.textContent||'').replace(/\s+/g,' ').trim();
  const roleFromOperator=()=>/SUPER ADMIN|ADMIN|MANAGER|OWNER/i.test(text(document.getElementById('operator')));
  const isManager=()=>canManage()||roleFromOperator();
  function patch(){
    if(!/real-finished-goods-v787\.html/i.test(location.pathname))return;
    if(!isManager())return;
    const cards=[...document.querySelectorAll('[data-pack-lot]')];
    const workspace=document.getElementById('packWorkspace');
    const block=document.getElementById('workerPackBlock');
    const btn=document.getElementById('acceptPack');
    if(!workspace||!block||!btn)return;
    const meta=text(document.getElementById('selectedPackMeta'));
    if(/ASSIGNED/i.test(meta)&&!/ACCEPTED|SUBMITTED/i.test(meta)){
      block.hidden=false;
      btn.textContent='ACCEPT WORK & RUN ALGORITHM';
      if(!document.getElementById('rr9309BehalfChip')){
        const chip=document.createElement('span');chip.id='rr9309BehalfChip';chip.className='fg-chip';chip.textContent='Admin/Manager behalf';
        document.getElementById('selectedPackMeta')?.appendChild(chip);
      }
    }
  }
  const obs=new MutationObserver(()=>setTimeout(patch,0));
  document.addEventListener('DOMContentLoaded',()=>{obs.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden']});patch();setInterval(patch,1000);},{once:true});
})();
