const CACHE='redzed-test71-target-v2';
self.addEventListener('install',event=>event.waitUntil(self.skipWaiting()));
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
const READ_CACHE='rr-notification-read-test71';
let readQueue=Promise.resolve();
async function readState(){try{const cache=await caches.open(READ_CACHE),r=await cache.match('/__rr_read_notifications71');return r?await r.json():[];}catch(_){return [];}}
self.addEventListener('message',event=>{
 if(event.data?.type!=='rr:messages-read71')return;
 const ids=(event.data.ids||[]).filter(id=>typeof id==='string').slice(0,200);
 const work=readQueue=readQueue.catch(()=>{}).then(async()=>{
  const notices=await self.registration.getNotifications();
  for(const notice of notices){const id=notice.data?.message_id; if(ids.includes(id)||ids.some(x=>['rr-'+x,'rr-message-'+x,'rr-collection-'+x].includes(notice.tag)||notice.tag?.startsWith('rr-cross-'+x+'|')))notice.close();}
  try{const previous=await readState(),merged=[...new Set([...previous,...ids])].slice(-2000);const cache=await caches.open(READ_CACHE);await cache.put('/__rr_read_notifications71',new Response(JSON.stringify(merged),{headers:{'Content-Type':'application/json'}}));}catch(_){}
 });
 event.waitUntil(work);
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 event.waitUntil((async()=>{
  let target;try{
   target=new URL(event.notification.data?.url||'./s.html',self.location.href);
   if(target.protocol!=='https:'||target.origin!==self.location.origin)return;
   if(['/s.html','/index.html','/'].includes(target.pathname)){
    target.searchParams.set('notification','1');
    if(event.notification.data?.message_id)target.searchParams.set('activity_id',event.notification.data.message_id);
    if(!event.notification.data?.collection_cycle_id)target.searchParams.set('open','chat');
   }
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
  await readQueue.catch(()=>{});
  if(data.message_id&&!data.collection_cycle_id&&(await readState()).includes(data.message_id))return;
  let url;try{url=new URL(data.url||'./s.html',self.location.href);if(url.origin!==self.location.origin||url.protocol!=='https:')return;}catch(_){return;}
  const tag='rr-collection-'+String(data.event_key||data.message_id||data.chat_id||'new');
  if(self.registration.getNotifications && (await self.registration.getNotifications({tag})).length)return;
  await self.registration.showNotification(data.customer_name||'REDZED Collection',{body:String(data.preview||'नई collection update').slice(0,180),tag,renotify:false,icon:'./redzed-icon-test67.svg',data:{url:url.href,message_id:data.message_id||null,collection_cycle_id:data.collection_cycle_id||null}});
 })());
});

self.addEventListener('fetch',event=>{if(event.request.mode==='navigate')event.respondWith(fetch(event.request));});
