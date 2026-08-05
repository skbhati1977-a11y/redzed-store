(()=>{
'use strict';

const VERSION='774.1';
const STYLE_ID='rrMobileCompatStyleV774';

function installMeta(){
  const viewport=document.querySelector('meta[name="viewport"]');
  const content='width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=yes';

  if(viewport){
    viewport.setAttribute('content',content);
  }else{
    const meta=document.createElement('meta');
    meta.name='viewport';
    meta.content=content;
    document.head.appendChild(meta);
  }

  const metas=[
    ['apple-mobile-web-app-capable','yes'],
    ['apple-mobile-web-app-status-bar-style','black-translucent'],
    ['apple-mobile-web-app-title','REDZED'],
    ['format-detection','telephone=no']
  ];

  for(const [name,value] of metas){
    let meta=document.querySelector(`meta[name="${name}"]`);

    if(!meta){
      meta=document.createElement('meta');
      meta.name=name;
      document.head.appendChild(meta);
    }

    meta.content=value;
  }
}

function installStyle(){
  if(document.getElementById(STYLE_ID))return;

  const style=document.createElement('style');
  style.id=STYLE_ID;
  style.textContent=`
  :root{
    --rr-safe-top:env(safe-area-inset-top,0px);
    --rr-safe-right:env(safe-area-inset-right,0px);
    --rr-safe-bottom:env(safe-area-inset-bottom,0px);
    --rr-safe-left:env(safe-area-inset-left,0px);
    --rr-visual-height:100vh;
    --rr-keyboard-inset:0px
  }

  html{
    min-height:100%;
    -webkit-text-size-adjust:100%;
    text-size-adjust:100%;
    -webkit-tap-highlight-color:transparent;
    touch-action:manipulation
  }

  body{
    min-height:100vh;
    min-height:100svh;
    min-height:100dvh;
    padding-left:var(--rr-safe-left);
    padding-right:var(--rr-safe-right);
    overscroll-behavior-y:none
  }

  button,
  a,
  [role="button"],
  input,
  select,
  textarea{
    touch-action:manipulation
  }

  button,
  a,
  [role="button"]{
    -webkit-user-select:none;
    user-select:none
  }

  input,
  select,
  textarea{
    -webkit-user-select:text;
    user-select:text
  }

  .table-wrap,
  .size-wrap,
  .rr-wrap,
  .collab-eval-box,
  [data-rr-scroll-area]{
    -webkit-overflow-scrolling:touch;
    overscroll-behavior-x:contain;
    scroll-behavior:smooth
  }

  .modal,
  .gallery{
    padding-top:var(--rr-safe-top);
    padding-right:var(--rr-safe-right);
    padding-bottom:var(--rr-safe-bottom);
    padding-left:var(--rr-safe-left)
  }

  .sheet{
    max-height:calc(var(--rr-visual-height) - var(--rr-safe-top));
    padding-bottom:calc(12px + var(--rr-safe-bottom))
  }

  .actions,
  .sticky{
    padding-left:var(--rr-safe-left);
    padding-right:var(--rr-safe-right)
  }

  @media(max-width:900px), (pointer:coarse){
    input,
    select,
    textarea{
      font-size:16px!important
    }

    button,
    a,
    [role="button"]{
      min-height:44px
    }

    input,
    select,
    textarea{
      min-height:44px
    }

    .toolbar,
    .modulebar,
    .top,
    .actions,
    .formbar,
    .bulk-assign{
      flex-wrap:wrap
    }

    .toolbar>*,
    .formbar>*{
      min-width:0
    }

    .modal{
      align-items:flex-end
    }

    .sheet{
      width:100%;
      height:auto;
      min-height:min(72svh,720px);
      max-height:calc(var(--rr-visual-height) - var(--rr-safe-top));
      border-radius:16px 16px 0 0
    }
  }

  @media(max-width:600px){
    .page{
      padding-left:max(8px,var(--rr-safe-left))!important;
      padding-right:max(8px,var(--rr-safe-right))!important
    }

    .modulebar{
      overflow-x:auto;
      -webkit-overflow-scrolling:touch;
      scrollbar-width:thin
    }

    .modulebar button,
    .modulebar a{
      flex:0 0 auto;
      min-width:132px
    }

    .actions button{
      flex:1 1 calc(50% - 8px)
    }

    .toolbar input,
    .toolbar select,
    .toolbar button{
      width:100%
    }
  }

  @media(orientation:landscape) and (max-height:550px){
    .sheet{
      max-height:calc(var(--rr-visual-height) - 4px);
      min-height:0
    }
  }
  `;

  document.head.appendChild(style);
}

function updateViewport(){
  const root=document.documentElement;
  const visual=window.visualViewport;

  const height=visual?.height||window.innerHeight;
  const offsetTop=visual?.offsetTop||0;
  const keyboardInset=visual
    ?Math.max(0,window.innerHeight-height-offsetTop)
    :0;

  root.style.setProperty(
    '--rr-visual-height',
    `${Math.max(320,height)}px`
  );

  root.style.setProperty(
    '--rr-keyboard-inset',
    `${keyboardInset}px`
  );

  document.body?.classList.toggle(
    'rr-mobile-keyboard-open',
    keyboardInset>100
  );
}

function boot(){
  installMeta();
  installStyle();
  updateViewport();

  window.addEventListener('resize',updateViewport,{passive:true});
  window.addEventListener('orientationchange',()=>{
    setTimeout(updateViewport,80);
    setTimeout(updateViewport,400);
  },{passive:true});

  if(window.visualViewport){
    visualViewport.addEventListener('resize',updateViewport,{passive:true});
    visualViewport.addEventListener('scroll',updateViewport,{passive:true});
  }
}

if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',boot);
}else{
  boot();
}

window.REDZED_MOBILE_COMPAT_VERSION=VERSION;
})();
