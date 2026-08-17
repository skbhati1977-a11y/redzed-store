(()=>{
'use strict';
if(window.__RR_CUTTING_LOADING_GUARD_9191__)return;
window.__RR_CUTTING_LOADING_GUARD_9191__=true;
const GALLERY_ID='divisionGallery';
let retryUsed=false, settled=false;
const gallery=()=>document.getElementById(GALLERY_ID);
const busy=()=>gallery()?.getAttribute('aria-busy')==='true';
function stopSpinner(message,canRetry=true){
 const g=gallery(); if(!g)return;
 g.setAttribute('aria-busy','false');
 g.innerHTML=`<article class="cm-empty" style="min-height:180px;gap:12px"><div style="font-weight:900;font-size:16px">Cutting data could not finish loading</div><div style="color:#98a2b3;font-size:13px;max-width:440px">${message||'The data request took too long.'}</div>${canRetry?'<button id="cmLoadRetry9191" class="cm-primary" type="button" style="min-height:44px;padding:0 18px;border:0;border-radius:12px;font-weight:900">Retry</button>':''}</article>`;
 document.getElementById('cmLoadRetry9191')?.addEventListener('click',()=>retry(true),{once:true});
}
async function retry(manual=false){
 const api=window.RRCuttingMasterPM;
 if(!api?.refresh){ if(manual) location.reload(); return; }
 const g=gallery(); if(g){g.setAttribute('aria-busy','true');g.innerHTML='<article class="cm-empty"><div class="cm-spinner"></div></article>';}
 try{
   await Promise.race([
     Promise.resolve(api.refresh()),
     new Promise((_,reject)=>setTimeout(()=>reject(new Error('Cutting data refresh timed out')),18000))
   ]);
   if(!busy()) settled=true;
 }catch(err){
   console.error('Cutting load guard',err);
   stopSpinner('Data request timed out. Tap Retry once connectivity/session is stable.',true);
 }
}
function arm(){
 const started=Date.now();
 const timer=setInterval(()=>{
   if(settled||!busy()){settled=true;clearInterval(timer);return;}
   if(Date.now()-started<18000)return;
   clearInterval(timer);
   if(!retryUsed){retryUsed=true;retry(false);}
   else stopSpinner('Data request is still pending.',true);
 },800);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(arm,250),{once:true});else setTimeout(arm,250);
})();