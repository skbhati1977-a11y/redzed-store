(()=>{
'use strict';
if(window.__REAL_FACTORY_MOBILE_COMPAT_V775__)return;
const current=document.currentScript?.src||location.href;
const script=document.createElement('script');
script.src=new URL('real-mobile-compat-v775.js?v=884',current).href;
script.async=false;
document.head.appendChild(script);
})();
