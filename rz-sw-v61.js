const CACHE='rz61-push-2';
self.addEventListener('install',e=>{self.skipWaiting()});
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('push',e=>{
 let d={};try{d=e.data?e.data.json():{}}catch(_){d={preview:e.data?.text()||'New message'}}
 const customer=String(d.customer_name||'Customer');
 const body=String(d.preview||'New message').slice(0,180);
 const chatId=String(d.chat_id||'');
 const url=d.url||('real-sales-live-chat-v9434.html?source=push61&chat='+encodeURIComponent(chatId));
 e.waitUntil(self.registration.showNotification('RZ · '+customer,{body,icon:'rz-icon-v61.svg',badge:'rz-icon-v61.svg',tag:'rz-chat-'+chatId,renotify:true,vibrate:[180,80,180],data:{chatId,url}}));
});
self.addEventListener('notificationclick',e=>{
 e.notification.close();const chatId=e.notification.data?.chatId||'';const url=new URL(e.notification.data?.url||('real-sales-live-chat-v9434.html?source=push61&chat='+encodeURIComponent(chatId)),self.registration.scope).href;
 e.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(ws=>{for(const w of ws){if('focus'in w){w.postMessage({type:'RZ_OPEN_CHAT',chatId});return w.focus()}}return clients.openWindow(url)}));
});