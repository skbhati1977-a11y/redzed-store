(()=>{
  'use strict';
  if(window.__RF_PACK_BOOT_FIX_9354__) return;
  window.__RF_PACK_BOOT_FIX_9354__=true;

  function stuck(){
    const cards=document.getElementById('packLotCards');
    return !!cards && /Ready lots load ho rahe hain/i.test(cards.textContent||'');
  }
  function recover(){
    if(!stuck()) return;
    const refresh=document.getElementById('refreshPackLots');
    if(typeof refresh?.onclick==='function'){
      try{ refresh.click(); }catch(e){ console.warn('Packing refresh recovery failed',e); }
      return;
    }
    // Core script can be injected after DOMContentLoaded on mobile/wrapped routes.
    // Re-fire only when its bind/boot never ran and the initial loader is still untouched.
    try{ document.dispatchEvent(new Event('DOMContentLoaded')); }
    catch(e){ console.warn('Packing boot recovery failed',e); }
  }
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',()=>setTimeout(recover,350),{once:true});
  else setTimeout(recover,350);
  setTimeout(recover,1400);
})();
