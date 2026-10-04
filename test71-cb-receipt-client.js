/* Reuse the CB form's authenticated client. Standalone tabs use the existing config. */
(()=>{
 'use strict';
 function load(src){return new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=src;s.onload=resolve;s.onerror=()=>reject(new Error('Receipt connection script could not load.'));document.head.appendChild(s)})}
 try{if(window.parent!==window&&window.parent.location.origin===location.origin&&window.parent.supabaseClient){window.supabaseClient=window.parent.supabaseClient;window.RRReceiptClientReady=Promise.resolve(window.supabaseClient);return}}catch{}
 window.RRReceiptClientReady=(async()=>{
  if(!window.supabase)await load('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.117.2/dist/umd/supabase.js');
  // The standalone receipt has its own close/navigation controls, not the factory sidebar.
  window.__RR_SLICE_MENU_LOADER_9309__=true;
  if(!window.supabaseClient)await load('config.js?v=9144');
  if(!window.supabaseClient)throw new Error('Receipt login connection unavailable.');
  return window.supabaseClient;
 })();
 // Avoid an unhandled rejection before the deferred receipt renderer awaits the promise.
 window.RRReceiptClientReady.catch(()=>{});
})();
