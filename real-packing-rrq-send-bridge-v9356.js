(()=>{
  'use strict';
  if(window.__RR_PACK_RRQ_SEND_BRIDGE_V9356_LIGHT__)return;
  window.__RR_PACK_RRQ_SEND_BRIDGE_V9356_LIGHT__=true;
  const clean=t=>{
    const raw=String(t||'');
    if(/AI service connect nahi ho pa raha/i.test(raw))return 'Rate request saved. WhatsApp/Admin approval status Refresh se check karein.';
    if(/user aborted|abort|aborted|AbortError/i.test(raw))return 'Request saved. WhatsApp status check ke liye Refresh dabayein.';
    if(/133010|Account not registered|OAuthException/i.test(raw))return 'WhatsApp sender account registration issue. Request queue me saved hai.';
    if(/FunctionsFetchError|Failed to fetch|NetworkError|Failed to send|Failed to send a request/i.test(raw))return 'WhatsApp sender network retry pending. Refresh se retry karein.';
    return raw;
  };
  function tick(){
    ['message','rrPicLocalMsg'].forEach(id=>{
      const n=document.getElementById(id);if(!n)return;
      const next=clean(n.textContent);
      if(next&&next!==n.textContent){n.textContent=next;n.className='fg-msg error';}
    });
  }
  document.addEventListener('click',e=>{if(e.target?.closest?.('#rrRequestRate,#rrRateRefresh'))[250,800,1600,3000].forEach(ms=>setTimeout(tick,ms));},true);
  setTimeout(tick,700);
  setInterval(tick,3000);
})();