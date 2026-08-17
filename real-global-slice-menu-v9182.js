(()=>{
'use strict';
if(window.__RR_SLICE_BOOT_9187__)return;window.__RR_SLICE_BOOT_9187__=true;
const BASE='/redzed-store/';
const load=(src,key)=>{if(window[key])return;window[key]=true;const s=document.createElement('script');s.src=src;s.async=false;(document.head||document.documentElement).appendChild(s)};
load(`${BASE}real-global-slice-menu-v9185.js?v=9187`,'__RR_SLICE_9185_LOADER__');
if(/\/real-cutting-master\.html$/i.test(location.pathname)){
 load(`${BASE}real-cutting-ui-v9186.js?v=9187`,'__RR_CUTTING_UI_9186_LOADER__');
 load(`${BASE}real-cutting-ui-clean-v9187.js?v=9187`,'__RR_CUTTING_CLEAN_9187_LOADER__');
}
})();