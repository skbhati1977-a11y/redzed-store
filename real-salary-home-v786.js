(()=>{
'use strict';
const $=id=>document.getElementById(id);
const errorText=error=>[
  error?.message,error?.details,error?.hint,error?.code
].filter(Boolean).join(' — ')||'Unknown error';

async function boot(){
  try{
    const client=
      window.supabaseClient||
      window.supabaseDb||
      window.redzedSupabase||
      window.sb;

    if(!client)throw new Error('Supabase client unavailable.');

    if(window.RR?.requireOwner){
      await RR.requireOwner();
    }

    if(window.RRDataModeReadyPromise){
      await window.RRDataModeReadyPromise;
    }

    const modeState=window.RRDataMode
      ?await RRDataMode.refresh()
      :{lifecycle_phase:'TESTING',default_mode:'TEST',protected_mode:'REAL'};

    $('modeTitle').textContent=
      `${modeState.default_mode} DEFAULT · ${modeState.protected_mode} PROTECTED`;

    $('modeHelp').textContent=
      modeState.lifecycle_phase==='REAL_LIVE'
        ?'Main/REAL data feed active है. TEST permission और confirmation पर खुलेगा.'
        :'Testing phase active है. सभी salary modules TEST में खुलेंगे.';

    $('accessBadge').textContent='ACCESS OK';
  }catch(error){
    $('accessBadge').textContent='ACCESS ERROR';
    $('message').textContent=errorText(error);
    $('message').style.color='#ff8e98';
  }
}

if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',boot);
}else{
  boot();
}
})();
