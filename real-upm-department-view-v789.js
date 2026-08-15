(() => {
  'use strict';
  const load=(src,next)=>{const s=document.createElement('script');s.src=src;s.onload=()=>next&&next();s.onerror=()=>console.error('REAL FACTORY loader failed',src);document.head.appendChild(s)};
  load('real-upm-territory-v9119.js?v=9120',()=>load('real-upm-ui-watchdog-v9117.js?v=9120',()=>load('real-upm-department-view-v789-core-v9110.js?v=9120',()=>load('real-upm-worker-request-v9112.js?v=9120',()=>load('real-upm-alter-flow-v9114.js?v=9120',()=>load('real-upm-alter-camera-patch-v9116.js?v=9120',()=>load('real-global-voice-remark-v9115.js?v=9120',()=>load('real-mobile-action-touch-rescue-v9118.js?v=9120'))))))));
})();
