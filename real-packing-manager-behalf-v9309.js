/* V9309/V9327 — allow Owner/Admin/Manager to run FG Packing accept/algorithm/submit on behalf of assigned worker; keep focus on Accept after assignment. */
(()=>{
  'use strict';
  const canManage=()=>['owner','admin','manager'].includes(String(window.__rrProfile?.role_code||window.RR_CURRENT_PROFILE?.role_code||'').toLowerCase());
  const text=x=>String(x?.textContent||'').replace(/\s+/g,' ').trim();
  const roleFromOperator=()=>/SUPER ADMIN|ADMIN|MANAGER|OWNER/i.test(text(document.getElementById('operator')));
  const isManager=()=>canManage()||roleFromOperator();
  let pendingAssignedLot='';
  function selectedLot(){return text(document.getElementById('selectedPackLot')).replace(/^Lot\s+/i,'').trim();}
  function focusAccept(){
    const btn=document.getElementById('acceptPack');
    if(!btn||btn.closest('[hidden]')||btn.hidden)return false;
    btn.scrollIntoView({behavior:'smooth',block:'center'});
    setTimeout(()=>btn.focus({preventScroll:true}),80);
    return true;
  }
  function reopenAssignedLot(){
    if(!pendingAssignedLot)return;
    const workspace=document.getElementById('packWorkspace');
    const current=selectedLot();
    if(workspace&&!workspace.hidden&&current===pendingAssignedLot){
      if(focusAccept())pendingAssignedLot='';
      return;
    }
    const card=[...document.querySelectorAll('[data-pack-lot]')].find(x=>String(x.dataset.packLot||'')===pendingAssignedLot);
    if(card){card.click();setTimeout(()=>{if(focusAccept())pendingAssignedLot='';},350);}
  }
  document.addEventListener('click',e=>{
    const btn=e.target?.closest?.('#assignPack');
    if(!btn||!/real-finished-goods-v787\.html/i.test(location.pathname))return;
    const worker=document.getElementById('packWorker')?.value;
    const lot=selectedLot();
    if(worker&&lot){
      pendingAssignedLot=lot;
      [450,900,1400,2200,3200].forEach(ms=>setTimeout(reopenAssignedLot,ms));
    }
  },true);
  function patch(){
    if(!/real-finished-goods-v787\.html/i.test(location.pathname))return;
    if(!isManager())return;
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
      if(pendingAssignedLot&&selectedLot()===pendingAssignedLot)focusAccept();
    }
    reopenAssignedLot();
  }
  const obs=new MutationObserver(()=>setTimeout(patch,0));
  document.addEventListener('DOMContentLoaded',()=>{obs.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden']});patch();setInterval(patch,1000);},{once:true});
})();
