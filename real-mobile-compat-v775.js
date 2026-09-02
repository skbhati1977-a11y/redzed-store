(()=>{
'use strict';

if(window.__REDZED_MOBILE_COMPAT_V775__)return;
window.__REDZED_MOBILE_COMPAT_V775__=true;

const VERSION='775.2';
const STYLE_ID='rrMobileCompatStyleV775';

function installMeta(){
  const content='width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=yes';
  let viewport=document.querySelector('meta[name="viewport"]');
  if(viewport){viewport.setAttribute('content',content);}else{viewport=document.createElement('meta');viewport.name='viewport';viewport.content=content;document.head.appendChild(viewport);}
  const metas=[['apple-mobile-web-app-capable','yes'],['apple-mobile-web-app-status-bar-style','black-translucent'],['apple-mobile-web-app-title','REDZED'],['format-detection','telephone=no']];
  for(const [name,value] of metas){let meta=document.querySelector(`meta[name="${name}"]`);if(!meta){meta=document.createElement('meta');meta.name=name;document.head.appendChild(meta);}meta.content=value;}
}

function installStyle(){
  if(document.getElementById(STYLE_ID))return;
  const style=document.createElement('style');
  style.id=STYLE_ID;
  style.textContent=`
  :root{--rr-safe-top:env(safe-area-inset-top,0px);--rr-safe-right:env(safe-area-inset-right,0px);--rr-safe-bottom:env(safe-area-inset-bottom,0px);--rr-safe-left:env(safe-area-inset-left,0px);--rr-visual-height:100vh;--rr-keyboard-inset:0px}
  html{min-height:100%;-webkit-text-size-adjust:100%;text-size-adjust:100%;-webkit-tap-highlight-color:transparent;touch-action:manipulation}
  body{min-height:100vh;min-height:100svh;min-height:100dvh;padding-left:var(--rr-safe-left);padding-right:var(--rr-safe-right);overscroll-behavior-y:none}
  button,a,[role="button"],input,select,textarea{touch-action:manipulation}
  input,select,textarea{-webkit-user-select:text;user-select:text}
  .table-wrap,.size-wrap,.rr-wrap,.collab-eval-box,.rr-gsheet-wrap,[data-table-wrap]{-webkit-overflow-scrolling:touch;overscroll-behavior-x:contain}
  .modal,.gallery{padding-top:var(--rr-safe-top);padding-right:var(--rr-safe-right);padding-bottom:var(--rr-safe-bottom);padding-left:var(--rr-safe-left)}
  .sheet{max-height:calc(var(--rr-visual-height) - var(--rr-safe-top));padding-bottom:calc(12px + var(--rr-safe-bottom))}
  @media(max-width:900px),(pointer:coarse){
    input,select,textarea{font-size:16px!important}
    button,a,[role="button"],input,select,textarea{min-height:44px}
    .toolbar,.modulebar,.top,.actions,.formbar,.bulk-assign{flex-wrap:wrap}
    .modal{align-items:flex-end}
    .sheet{width:100%;height:auto;min-height:min(72svh,720px);max-height:calc(var(--rr-visual-height) - var(--rr-safe-top));border-radius:16px 16px 0 0}
  }
  @media(max-width:600px){
    .page{padding-left:max(8px,var(--rr-safe-left))!important;padding-right:max(8px,var(--rr-safe-right))!important}
    .modulebar{overflow-x:auto;-webkit-overflow-scrolling:touch;scrollbar-width:thin}
    .modulebar button,.modulebar a{flex:0 0 auto;min-width:132px}
    .actions button{flex:1 1 calc(50% - 8px)}
    .rr-gsheet-wrap table{table-layout:fixed!important;min-width:100%!important;width:max-content!important}
    .rr-gsheet-wrap table th,.rr-gsheet-wrap table td{box-sizing:border-box!important;width:calc((100vw - 16px) / 3)!important;min-width:calc((100vw - 16px) / 3)!important;max-width:calc((100vw - 16px) / 3)!important;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
  }
  `;
  document.head.appendChild(style);
}

function updateViewport(){
  const root=document.documentElement,visual=window.visualViewport,height=visual?.height||window.innerHeight,offsetTop=visual?.offsetTop||0,keyboardInset=visual?Math.max(0,window.innerHeight-height-offsetTop):0;
  root.style.setProperty('--rr-visual-height',`${Math.max(320,height)}px`);
  root.style.setProperty('--rr-keyboard-inset',`${keyboardInset}px`);
}

function installCbRemarksVoice(){
  if(!location.pathname.includes('real-cb-new-v9130-fix2.html'))return;
  const box=document.getElementById('remarks');if(!box||document.getElementById('rrCbRemarksVoice'))return;
  const Recognition=window.SpeechRecognition||window.webkitSpeechRecognition,wrap=document.createElement('div');wrap.style.cssText='display:flex;gap:8px;align-items:stretch;margin-top:6px';
  const btn=document.createElement('button');btn.id='rrCbRemarksVoice';btn.type='button';btn.textContent='🎤 Voice Typing';btn.style.cssText='border:1px solid #4b4b58;background:#1c1c23;color:#fff;border-radius:11px;padding:10px 13px;font-weight:850;min-height:44px';
  const status=document.createElement('span');status.style.cssText='align-self:center;color:#a3a3ad;font-size:12px';status.textContent='Tap mic to speak';wrap.append(btn,status);box.insertAdjacentElement('afterend',wrap);
  if(!Recognition){btn.disabled=true;status.textContent='Voice typing not supported in this browser';return;}
  const rec=new Recognition();rec.lang='hi-IN';rec.continuous=true;rec.interimResults=true;let listening=false,base='';
  rec.onstart=()=>{listening=true;base=box.value.trim();btn.textContent='⏹ Stop Voice';btn.style.borderColor='#e25869';status.textContent='Listening…';};
  rec.onresult=(event)=>{let finalText='',interim='';for(let i=event.resultIndex;i<event.results.length;i++){const text=event.results[i][0]?.transcript||'';if(event.results[i].isFinal)finalText+=text+' ';else interim+=text;}const spoken=(finalText+interim).trim();box.value=[base,spoken].filter(Boolean).join(base&&spoken?' ':'');box.dispatchEvent(new Event('input',{bubbles:true}));};
  rec.onerror=(event)=>{status.textContent=event.error==='not-allowed'?'Microphone permission required':`Voice error: ${event.error}`;};
  rec.onend=()=>{listening=false;btn.textContent='🎤 Voice Typing';btn.style.borderColor='#4b4b58';status.textContent='Tap mic to speak';};
  btn.addEventListener('click',()=>{try{if(listening)rec.stop();else rec.start();}catch(_){}});
}

function boot(){installMeta();installStyle();updateViewport();installCbRemarksVoice();window.addEventListener('resize',updateViewport,{passive:true});window.addEventListener('orientationchange',()=>{setTimeout(updateViewport,80);setTimeout(updateViewport,400);},{passive:true});if(window.visualViewport){visualViewport.addEventListener('resize',updateViewport,{passive:true});visualViewport.addEventListener('scroll',updateViewport,{passive:true});}}
if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',boot);}else{boot();}
window.REDZED_MOBILE_COMPAT_VERSION=VERSION;
})();
