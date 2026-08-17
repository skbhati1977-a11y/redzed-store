(()=>{
'use strict';
const dept=String(new URLSearchParams(location.search).get('dept')||'').trim().toUpperCase();
if(dept!=='PRINTING'&&dept!=='PRINT')return;

function patchInput(root=document){
  const input=root.querySelector?.('#rr9160ChemicalCost')||document.getElementById('rr9160ChemicalCost');
  if(!input||input.dataset.rrKgDone==='1')return !!input;
  input.placeholder='KG';
  input.setAttribute('aria-label','Actual Chemical Cost in KG');
  input.dataset.rrKgDone='1';
  return true;
}

function watchCurrentModal(){
  const modal=document.getElementById('rfSubmitModal');
  if(!modal)return;
  if(patchInput(modal))return;
  const localObserver=new MutationObserver(()=>{
    if(patchInput(modal))localObserver.disconnect();
  });
  localObserver.observe(modal,{childList:true,subtree:true});
  setTimeout(()=>localObserver.disconnect(),5000);
}

document.addEventListener('click',e=>{
  const btn=e.target.closest?.('button');
  if(!btn)return;
  const t=String(btn.textContent||'').toUpperCase();
  if(!t.includes('READY TO SUBMIT'))return;
  setTimeout(watchCurrentModal,0);
},true);

watchCurrentModal();
})();
