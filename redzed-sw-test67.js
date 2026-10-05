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
