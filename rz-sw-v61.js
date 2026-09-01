const VERSION='rz61-push-5';
self.addEventListener('install',e=>{self.skipWaiting()});
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('push',e=>{
 const work=(async()=>{let d={};try{d=e.data?e.data.json():{}}catch(_){try{d={preview:e.data?e.data.text():'New message'}}catch(__){d={preview:'New message'}}}
 const customer=String(d.customer_name||'Customer'),body=String(d.preview||'New message').slice(0,180),chatId=String(d.chat_id||'');
 const url=d.url||('real-sales-live-chat-v9434.html?source=push61&chat='+encodeURIComponent(chatId));
 try{if(self.navigator&&typeof self.navigator.setAppBadge==='function')await self.navigator.setAppBadge(1)}catch(_){}
 await self.registration.showNotification('RZ · '+customer,{body,icon:new URL('rz-icon-v61.svg?v=61push5',self.registration.scope).href,badge:new URL('rz-icon-v61.svg?v=61push5',self.registration.scope).href,tag:'rz-chat-'+(chatId||Date.now()),renotify:true,requireInteraction:false,silent:false,vibrate:[220,100,220],timestamp:Date.now(),data:{chatId,url,version:VERSION}});
 })();e.waitUntil(work);
});
self.addEventListener('notificationclick',e=>{e.notification.close();const chatId=e.notification.data?.chatId||'',url=new URL(e.notification.data?.url||('real-sales-live-chat-v9434.html?source=push61&chat='+encodeURIComponent(chatId)),self.registration.scope).href;e.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(ws=>{for(const w of ws){if('focus'in w){w.postMessage({type:'RZ_OPEN_CHAT',chatId});return w.focus()}}return clients.openWindow(url)}))});