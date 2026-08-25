(()=>{
  'use strict';
  if(window.__RR_PACK_RRQ_CLEAN_ERROR_V9357__)return;
  window.__RR_PACK_RRQ_CLEAN_ERROR_V9357__=true;
  const clean=t=>{
    const raw=String(t||'');
    if(/user aborted|abort|aborted|AbortError/i.test(raw))return 'Request saved. WhatsApp status check ke liye Refresh dabayein.';
    if(/133010|Account not registered|OAuthException/i.test(raw))return 'WhatsApp sender account registration issue. Request queue me saved hai.';
    return raw;
  };
  function tick(){
    ['message','rrPicLocalMsg'].forEach(id=>{
      const n=document.getElementById(id);if(!n)return;
      const next=clean(n.textContent);
      if(next&&next!==n.textContent){n.textContent=next;n.className='fg-msg error';}
    });
  }
  document.addEventListener('click',e=>{if(e.target?.closest?.('#rrRequestRate,#rrRateRefresh'))setTimeout(tick,900);},true);
  setInterval(tick,3000);
})();