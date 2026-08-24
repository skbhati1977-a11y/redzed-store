(()=>{
'use strict';
/* Disable the older submit-sync IIFE inside photo-first before that file loads. */
window.__RR_PACK_SUBMIT_SYNC_9356__=true;
if(window.__RR_PACK_READY_RPC_FIX_9364__)return;window.__RR_PACK_READY_RPC_FIX_9364__=true;
const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function fetchish(e){return /failed to fetch|networkerror|functionsfetcherror|load failed/i.test(String(e?.message||e||''));}
function installRpcRetry(){
  const c=db();if(!c?.rpc||c.__rrPackRpcRetry9364)return false;
  const orig=c.rpc.bind(c);
  c.rpc=async function(name,args,options){let last;for(let i=0;i<3;i++){try{const r=await orig(name,args,options);if(!r?.error||!fetchish(r.error))return r;last=r.error;}catch(e){last=e;if(!fetchish(e))throw e;}if(i<2)await sleep(450*(i+1));}return {data:null,error:last||new Error('Network request failed after retry')};};
  c.__rrPackRpcRetry9364=true;return true;
}
[0,100,300,700,1400].forEach(ms=>setTimeout(installRpcRetry,ms));
setInterval(installRpcRetry,2000);
})();