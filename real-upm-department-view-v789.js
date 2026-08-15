(() => {
  'use strict';
  const load=(src,next)=>{const s=document.createElement('script');s.src=src;s.onload=()=>next&&next();s.onerror=()=>console.error('REAL FACTORY loader failed',src);document.head.appendChild(s)};
  load('real-upm-department-view-v789-core-v9110.js?v=9112',()=>load('real-upm-worker-request-v9112.js?v=9112',()=>load('real-upm-alter-flow-v9114.js?v=9114')));
})();
