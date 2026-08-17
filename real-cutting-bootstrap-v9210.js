(()=>{
'use strict';

if(window.__RR_CUTTING_BOOTSTRAP_9210__)return;
window.__RR_CUTTING_BOOTSTRAP_9210__=true;

const VERSION='9210';
const gallery=()=>document.getElementById('divisionGallery');
const message=()=>document.getElementById('cmMessage');

function setMessage(text,type='info'){
  const box=message();
  if(!box)return;
  box.textContent=text||'';
  box.className='rr-message'+(text?' '+type:'');
}

function setStage(text){
  const box=gallery();
  if(!box)return;
  const p=box.querySelector('.cm-empty p');
  if(p)p.textContent=text;
}

function showFailure(title,detail){
  const box=gallery();
  if(!box)return;
  box.setAttribute('aria-busy','false');
  box.innerHTML=`<article class="cm-empty"><h3>${title}</h3><p>${detail}</p><button type="button" class="cm-primary" data-cutting-bootstrap-retry>Retry</button></article>`;
  const retry=box.querySelector('[data-cutting-bootstrap-retry]');
  if(retry)retry.addEventListener('click',()=>location.reload());
}

function loadScript(src,timeoutMs){
  return new Promise((resolve,reject)=>{
    const script=document.createElement('script');
    let done=false;
    const finish=(error)=>{
      if(done)return;
      done=true;
      clearTimeout(timer);
      script.onload=null;
      script.onerror=null;
      if(error){
        try{script.remove();}catch(_){}
        reject(error);
      }else{
        resolve();
      }
    };
    const timer=setTimeout(()=>finish(new Error(`Script timeout: ${src}`)),timeoutMs);
    script.async=false;
    script.src=src;
    script.onload=()=>finish();
    script.onerror=()=>finish(new Error(`Script failed: ${src}`));
    document.head.appendChild(script);
  });
}

async function ensureSupabase(){
  if(window.supabase&&typeof window.supabase.createClient==='function')return;

  const sources=[
    'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.111.0/dist/umd/supabase.js',
    'https://unpkg.com/@supabase/supabase-js@2.111.0/dist/umd/supabase.js'
  ];

  let lastError=null;
  for(const src of sources){
    try{
      await loadScript(src,5000);
      if(window.supabase&&typeof window.supabase.createClient==='function')return;
      lastError=new Error('Supabase global unavailable after load');
    }catch(error){
      lastError=error;
    }
  }
  throw lastError||new Error('Supabase library unavailable');
}

window.addEventListener('error',(event)=>{
  if(!event||!event.message)return;
  setMessage(`CUTTING JS ERROR: ${event.message}`,'error');
});
window.addEventListener('unhandledrejection',(event)=>{
  const reason=event&&event.reason;
  const text=reason&&reason.message?reason.message:String(reason||'Unknown promise error');
  setMessage(`CUTTING PROMISE ERROR: ${text}`,'error');
});

setTimeout(()=>{
  const box=gallery();
  if(!box||box.getAttribute('aria-busy')!=='true'||box.querySelector('.cm-card'))return;
  const text=(box.textContent||'').toLowerCase();
  if(!text.includes('loading cutting master')&&!text.includes('connecting')&&!text.includes('loading inline product cards'))return;
  showFailure('Cutting Master connection delayed','Data connection did not finish. Tap Retry.');
},18000);

(async()=>{
  try{
    setStage('Connecting data engine…');
    await ensureSupabase();

    setStage('Opening factory config…');
    await loadScript(`config.js?v=${VERSION}`,7000);
    if(!window.supabaseClient&&!window.supabaseDb&&!window.redzedSupabase&&!window.sb){
      throw new Error('Factory data client was not created');
    }

    await loadScript(`real-common.js?v=${VERSION}`,7000);
    await loadScript(`real-cutting-runtime-v9194.js?v=${VERSION}`,7000);

    setStage('Starting Cutting Master…');
    await loadScript(`real-cutting-master-pm.V719.3.js?v=${VERSION}`,7000);
    await loadScript(`redzed-cutting-cb-actions-v72035.js?v=${VERSION}`,7000);
  }catch(error){
    console.error('[Cutting Bootstrap]',error);
    setMessage(`CUTTING BOOT ERROR: ${error&&error.message?error.message:String(error)}`,'error');
    showFailure('Cutting Master could not connect','Bootstrap failed. Tap Retry.');
  }
})();
})();
