(()=>{
'use strict';
const qs=new URLSearchParams(location.search);
const dept=String(qs.get('dept')||'').trim().toUpperCase();
if(dept!=='PRINTING'&&dept!=='PRINT')return;

function applyToModal(modal){
  if(!modal||modal.dataset.rrKgPatched==='1')return false;
  const input=modal.querySelector('#rr9160ChemicalCost');
  if(!input)return false;
  input.placeholder='KG';
  input.setAttribute('aria-label','Actual Chemical Cost in KG');
  modal.dataset.rrKgPatched='1';
  return true;
}

function scan(){
  const modal=document.getElementById('rfSubmitModal');
  if(modal)applyToModal(modal);
}

const observer=new MutationObserver(records=>{
  for(const record of records){
    for(const node of record.addedNodes){
      if(!(node instanceof Element))continue;
      if(node.id==='rfSubmitModal'){applyToModal(node);continue;}
      const modal=node.querySelector?.('#rfSubmitModal');
      if(modal)applyToModal(modal);
    }
  }
});
observer.observe(document.body,{childList:true,subtree:true});
scan();
})();
