const CACHE='redzed-test71-target-v2';
self.addEventListener('install',event=>event.waitUntil(self.skipWaiting()));
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 event.waitUntil((async()=>{
  let target;try{
   target=new URL(event.notification.data?.url||'./s.html',self.location.href);
   if(target.protocol!=='https:'||target.origin!==self.location.origin)return;
  }catch(_){return;}
  const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
  const exact=windows.find(client=>client.url===target.href);
  if(exact){await exact.focus();return;}
  const chat=windows.find(client=>{try{const u=new URL(client.url);return u.origin===target.origin&&u.pathname===target.pathname;}catch(_){return false;}});
  if(chat){const navigated=await chat.navigate(target.href);await navigated?.focus();return;}
  await self.clients.openWindow(target.href);
 })());
});

self.addEventListener('push',event=>{
 event.waitUntil((async()=>{
  let data;try{data=event.data.json()}catch(_){data={preview:event.data?.text()||'New collection update'}}
  let url;try{url=new URL(data.url||'./s.html',self.location.href);if(url.origin!==self.location.origin||url.protocol!=='https:')return;}catch(_){return;}
  const tag='rr-collection-'+String(data.event_key||data.message_id||data.chat_id||'new');
  await self.registration.showNotification(data.customer_name||'REDZED Collection',{body:String(data.preview||'नई collection update').slice(0,180),tag,renotify:false,icon:'./redzed-icon-test67.svg',data:{url:url.href}});
 })());
});

self.addEventListener('fetch',event=>{if(event.request.mode==='navigate')event.respondWith(fetch(event.request));});
