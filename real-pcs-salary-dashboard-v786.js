(()=>{
'use strict';
const $=id=>document.getElementById(id);
const err=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(' — ')||'Unknown error';
async function boot(){
  try{
    const client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
    if(!client)throw new Error('Supabase client unavailable.');
    if(window.RR?.requireOwner)await RR.requireOwner();
    if(window.RRDataModeReadyPromise)await window.RRDataModeReadyPromise;
    if(window.RRDataMode)await RRDataMode.refresh();
    $('accessBadge').textContent='ACCESS OK';
  }catch(error){
    $('accessBadge').textContent='ACCESS ERROR';
    $('message').textContent=err(error);
  }
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);
else boot();
})();
