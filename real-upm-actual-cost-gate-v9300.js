(()=>{
 'use strict';
 const qs=new URLSearchParams(location.search);
 if(!/real-department-lite-v9127\.html$/i.test(location.pathname))return;
 const raw=String(qs.get('dept')||'').trim().toUpperCase();
 const key=raw.replace(/[^A-Z0-9]+/g,'');
 const protectedDepartments=new Set(['PRINTING','PRINT','STICKER','METALID','ID']);
 if(!protectedDepartments.has(key))return;

 function attach(m){
  if(!m||m.dataset.rr9300==='1')return;
  // The canonical modal already owns rate gate + receiver handover. The
  // retired browser-supplied direct-cost engine must never wrap it.
  if(m.querySelector('#rfSubmitLM')){m.dataset.rr9300='1';return}
  m.dataset.rr9300='1';
  const submit=m.querySelector('#rfDoSubmit');
  if(submit){submit.disabled=true;submit.textContent='REFRESH CANONICAL SUBMIT'}
  const warning=document.createElement('div');
  warning.className='rfmsg err';
  warning.textContent='Secure canonical receiver workflow required. Close this window, refresh, and reopen Submit.';
  (m.querySelector('#rfSubmitMsg')||m).appendChild(warning);
 }
 const observer=new MutationObserver(()=>attach(document.getElementById('rfSubmitModal')));
 observer.observe(document.body,{childList:true,subtree:true});
 attach(document.getElementById('rfSubmitModal'));
})();
