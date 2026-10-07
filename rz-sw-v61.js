const VERSION='rz61-universal-action-focus-test71';
self.addEventListener('install',e=>{self.skipWaiting()});
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('push',e=>{
 const work=(async()=>{let d={};try{d=e.data?e.data.json():{}}catch(_){try{d={preview:e.data?e.data.text():'New message'}}catch(__){d={preview:'New message'}}}
 const customer=String(d.customer_name||'Customer'),body=String(d.preview||'New message').slice(0,180),chatId=String(d.chat_id||''),unread=Number(d.unread_conversations||0);
 const rel=String(d.url||('real-sales-live-chat-v9434.html?source=push61&chat='+encodeURIComponent(chatId)+'&v=61push8'));
 const destination=new URL(rel,self.registration.scope);
 const loginRequestId=String(d.login_request_id||destination.searchParams.get('rc_login_request')||'');
 if(loginRequestId){destination.pathname=new URL('test70-cb-purchase-real-chat-pilot.html',self.registration.scope).pathname;destination.search='';for(const [key,value] of Object.entries({rc_view:'chat',rc_kind:'group',rc_id:'ADMIN',rc_parent:'ADMIN',rc_status:'OPEN',rc_login_request:loginRequestId,source:'customer_login_approval',v:'TEST71'}))destination.searchParams.set(key,value);}
 const url=destination.href;
 try{if(unread>0&&self.navigator&&typeof self.navigator.setAppBadge==='function')await self.navigator.setAppBadge(unread)}catch(_){}
 await self.registration.showNotification('RZ · '+customer,{body,icon:new URL('rz-icon-v61.svg?v=61push6',self.registration.scope).href,badge:new URL('rz-icon-v61.svg?v=61push6',self.registration.scope).href,tag:d.login_request_id?'rz-login-approval-'+String(d.login_request_id):d.notice_id?'rz-notice-'+String(d.notice_id):'rz-chat-'+(chatId||Date.now()),renotify:!d.notice_id,requireInteraction:false,silent:false,vibrate:[220,100,220],timestamp:Date.now(),data:{chatId,url,loginRequestId,noticeId:String(d.notice_id||''),materialAlertId:String(d.material_alert_id||''),version:VERSION}});
 })();e.waitUntil(work);
});
self.addEventListener('notificationclick',e=>{e.notification.close();e.waitUntil((async()=>{
 const data=e.notification.data||{},chatId=String(data.chatId||''),materialAlertId=String(data.materialAlertId||'');
 const target=new URL(String(data.url||(materialAlertId?'test70-cb-purchase-real-chat-pilot.html?source=material_push&rc_material_alert='+encodeURIComponent(materialAlertId):'real-sales-live-chat-v9434.html?source=push61&chat='+encodeURIComponent(chatId)+'&v=61push6')),self.registration.scope);
 const requestId=String(data.loginRequestId||data.login_request_id||target.searchParams.get('rc_login_request')||(String(e.notification.tag||'').startsWith('rz-login-approval-')?String(e.notification.tag).slice('rz-login-approval-'.length):''));
 if(requestId){target.pathname=new URL('test70-cb-purchase-real-chat-pilot.html',self.registration.scope).pathname;target.search='';for(const [key,value] of Object.entries({rc_view:'chat',rc_kind:'group',rc_id:'ADMIN',rc_parent:'ADMIN',rc_status:'OPEN',rc_login_request:requestId,source:'customer_login_approval',v:'TEST71'}))target.searchParams.set(key,value);}
 if(target.origin!==self.location.origin)return;
 const url=target.href,ws=await clients.matchAll({type:'window',includeUncontrolled:true});
 for(const w of ws){try{const u=new URL(w.url);if(u.origin!==self.location.origin||!(u.pathname.endsWith('/real-sales-live-chat-v9434.html')||u.pathname.endsWith('/test70-cb-purchase-real-chat-pilot.html')))continue;
 if(!requestId&&!target.searchParams.has('rc_notice')&&!target.searchParams.has('rc_bridge')){if(typeof w.navigate==='function'){const navigated=await w.navigate(url);if(navigated){await navigated.focus();return;}}continue;}
 if(typeof w.navigate!=='function')continue;const navigated=await w.navigate(url);if(!navigated)continue;await navigated.focus();return;
 }catch(_){}}
 const opened=await clients.openWindow(url);if(opened&&typeof opened.focus==='function')await opened.focus();
 })());});

self.addEventListener('message',e=>{if(e.data?.type!=='RZ_NOTICE_READ71')return;e.waitUntil((async()=>{const ids=new Set(e.data.ids||[]);for(const n of await self.registration.getNotifications())if(ids.has(n.data?.noticeId))n.close();})());});
