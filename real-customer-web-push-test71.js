(() => {
 'use strict'; if(window.__RR_CUSTOMER_WEB_PUSH71__)return;window.__RR_CUSTOMER_WEB_PUSH71__=true;
 const staff=!!document.getElementById('inboxRows');let staffToken='',busy=false,lastAttempt=0;const q=new URLSearchParams(location.search),share=q.get('t')||q.get('c')||'';
 function session(){if(staff)return staffToken?{session_token:staffToken}:null;try{const s=JSON.parse(localStorage.getItem('rr_customer_secure_session_v9592')||'null');return s?.share_token===share&&s.session_token?s:null}catch(_){return null}}
 async function api(body){const r=await fetch(SUPABASE_URL+'/functions/v1/rr-web-push-v61',{method:'POST',headers:{'Content-Type':'application/json',apikey:SUPABASE_ANON_KEY,...(staffToken?{Authorization:'Bearer '+staffToken}:{})},body:JSON.stringify(body)});const d=await r.json();if(!r.ok)throw Error(d.error||'Notifications enable नहीं हुईं');return d}
 function key(value){const str=atob(value.replace(/-/g,'+').replace(/_/g,'/'));return Uint8Array.from(str,c=>c.charCodeAt(0))}
 async function enable(gesture=false){
  if(busy||!session())return;busy=true;lastAttempt=Date.now();const button=document.getElementById('rrCustomerPush71');
  try{
   if(gesture&&Notification.permission==='default')await (window.RRRequestNotificationPermissionV69?window.RRRequestNotificationPermissionV69():Notification.requestPermission());
   if(Notification.permission!=='granted')throw Error(Notification.permission==='denied'?'Browser settings में Notifications Allow करें':'नई activity की notification के लिए Allow करें');
   if(button){button.disabled=true;button.textContent='Enabling notifications…'}
   const registration=await navigator.serviceWorker.register('./redzed-sw-test67.js?v=TEST71-READ-CLEAR-20261005');await navigator.serviceWorker.ready;
   let sub=await registration.pushManager.getSubscription();
   if(!sub){const config=await api({action:'config'});if(!config.public_key)throw Error('Notifications temporarily unavailable');sub=await registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:key(config.public_key)})}
   const identity=session();if(!identity)throw Error('Customer login दोबारा करें');
   await api({action:'subscribe',subscription:sub.toJSON(),session_token:identity.session_token,device_id:localStorage.getItem('rr_customer_device_v9592'),device_key:localStorage.getItem('rr_customer_device_v9592'),route_url:staff?location.origin+'/real-sales-live-chat-v9434.html':location.origin+'/s.html?t='+encodeURIComponent(share)+'&open=collection'});
   window.__RR_CUSTOMER_PUSH_REGISTERED71__=true;
   if(button){button.textContent='Notifications ON ✓';button.disabled=true;setTimeout(()=>button.remove(),1800);}
  }catch(e){const retry=button||showButton();retry.textContent=e.message;retry.disabled=false;}finally{busy=false;}
 }
 function showButton(){
  let b=document.getElementById('rrCustomerPush71');
  if(!b){b=document.createElement('button');b.id='rrCustomerPush71';b.type='button';b.textContent='🔔 नई activity की notifications ON करें';b.style.cssText='position:fixed;top:48px;right:10px;max-width:calc(100vw - 24px);z-index:2147483603;padding:9px 12px;border-radius:10px;border:1px solid #50647e;background:#14202d;color:#fff';b.onclick=()=>enable(true);document.body.appendChild(b)}
  return b;
 }
 function mount(){
  if(window.__RR_CUSTOMER_PUSH_REGISTERED71__||!session()||!window.isSecureContext||!('serviceWorker' in navigator)||!('PushManager'in window)||!('Notification'in window))return;
  if(Notification.permission==='granted'){enable(false);return;}
  showButton();
 }
 window.addEventListener('online',()=>{if(window.Notification?.permission==='granted')mount();});
 document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible'&&!window.__RR_CUSTOMER_PUSH_REGISTERED71__&&Date.now()-lastAttempt>30000)mount();});
 document.addEventListener('rr:customer-secure-session-ready',mount);if(staff){window.supabaseClient?.auth.getSession().then(({data})=>{staffToken=data?.session?.access_token||'';mount()}).catch(()=>{});}else mount();
 window.RRCustomerWebPush71={enable,mount};
})();
