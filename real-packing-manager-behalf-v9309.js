/* V9309/V9328 — locked FG Packing algorithm: manager behalf, assign→accept focus, submitted reset locked. */
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
  function addChip(id,label){
    const meta=document.getElementById('selectedPackMeta');
    if(!meta||document.getElementById(id))return;
    const chip=document.createElement('span');chip.id=id;chip.className='fg-chip';chip.textContent=label;meta.appendChild(chip);
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
    const workspace=document.getElementById('packWorkspace');
    const block=document.getElementById('workerPackBlock');
    const accept=document.getElementById('acceptPack');
    const run=document.getElementById('runPackAlgo');
    const pcs=document.getElementById('packPcsPerBox');
    if(!workspace)return;
    const meta=text(document.getElementById('selectedPackMeta'));
    if(isManager()&&block&&accept&&/ASSIGNED/i.test(meta)&&!/ACCEPTED|SUBMITTED/i.test(meta)){
      block.hidden=false;
      accept.textContent='ACCEPT WORK & RUN ALGORITHM';
      addChip('rr9309BehalfChip','Admin/Manager behalf');
      if(pendingAssignedLot&&selectedLot()===pendingAssignedLot)focusAccept();
    }
    if(/ACCEPTED|SUBMITTED|ALGORITHM READY/i.test(meta))addChip('rr9328AlgoLockChip','Algorithm rule locked');
    if(/SUBMITTED/i.test(meta)){
      if(run){run.disabled=true;run.textContent='PACKING SUBMITTED · ALGORITHM LOCKED';}
      if(pcs)pcs.readOnly=true;
    }else if(run&&run.textContent==='PACKING SUBMITTED · ALGORITHM LOCKED'){
      run.disabled=false;run.textContent='RESET / RUN EQUAL PACKING ALGORITHM';
      if(pcs)pcs.readOnly=false;
    }
    reopenAssignedLot();
  }
  const obs=new MutationObserver(()=>setTimeout(patch,0));
  document.addEventListener('DOMContentLoaded',()=>{obs.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden','disabled']});patch();setInterval(patch,1000);},{once:true});
})();
