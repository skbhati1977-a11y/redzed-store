const VERSION='rz61-push-6';
self.addEventListener('install',e=>{self.skipWaiting()});
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('push',e=>{
 const work=(async()=>{let d={};try{d=e.data?e.data.json():{}}catch(_){try{d={preview:e.data?e.data.text():'New message'}}catch(__){d={preview:'New message'}}}
 const customer=String(d.customer_name||'Customer'),body=String(d.preview||'New message').slice(0,180),chatId=String(d.chat_id||''),unread=Number(d.unread_conversations||0);
 const rel='real-sales-live-chat-v9434.html?source=push61&chat='+encodeURIComponent(chatId)+'&v=61push6';
 const url=new URL(rel,self.registration.scope).href;
 try{if(unread>0&&self.navigator&&typeof self.navigator.setAppBadge==='function')await self.navigator.setAppBadge(unread)}catch(_){}
 await self.registration.showNotification('RZ · '+customer,{body,icon:new URL('rz-icon-v61.svg?v=61push6',self.registration.scope).href,badge:new URL('rz-icon-v61.svg?v=61push6',self.registration.scope).href,tag:'rz-chat-'+(chatId||Date.now()),renotify:true,requireInteraction:false,silent:false,vibrate:[220,100,220],timestamp:Date.now(),data:{chatId,url,version:VERSION}});
 })();e.waitUntil(work);
});
self.addEventListener('notificationclick',e=>{e.notification.close();const chatId=String(e.notification.data?.chatId||''),url=String(e.notification.data?.url||new URL('real-sales-live-chat-v9434.html?source=push61&chat='+encodeURIComponent(chatId)+'&v=61push6',self.registration.scope).href);e.waitUntil((async()=>{const ws=await clients.matchAll({type:'window',includeUncontrolled:true});for(const w of ws){try{const u=new URL(w.url);if(u.origin===self.location.origin&&u.pathname.endsWith('/real-sales-live-chat-v9434.html')){await w.focus();if('navigate'in w)await w.navigate(url);return}}catch(_){}}await clients.openWindow(url)})())});