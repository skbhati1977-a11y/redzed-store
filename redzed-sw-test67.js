const CUSTOMER_ORIGIN='https://redzed-customer-collection.jggfab2011.chatgpt.site';
function notificationRoute71(value){
 const u=new URL(value||'./s.html',self.location.href);
 if(u.pathname.endsWith('/s.html'))return new URL(CUSTOMER_ORIGIN+'/s.html'+u.search);
 if(u.protocol!=='https:'||u.origin!==self.location.origin)throw Error('Invalid notification destination');
 return u;
}
const CACHE='redzed-test71-notification-events-v3';
const READ_CACHE='rr-notification-read-test71';
let readQueue=Promise.resolve();
const activeChats=new Map();
self.addEventListener('install',event=>event.waitUntil(self.skipWaiting()));
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
async function readState(){try{const c=await caches.open(READ_CACHE),r=await c.match('/__rr_read_state72');return r?await r.json():{events:[],chats:{}};}catch(_){return {events:[],chats:{}};}}
async function writeState(state){const c=await caches.open(READ_CACHE);await c.put('/__rr_read_state72',new Response(JSON.stringify(state),{headers:{'Content-Type':'application/json'}}));}
self.addEventListener('message',event=>{
 if(event.data?.type!=='rr:messages-read71')return;
 const ids=(event.data.ids||[]).filter(id=>typeof id==='string').slice(0,200),chat=event.data.chat_id||'';
 if(event.source?.id&&chat)activeChats.set(event.source.id,{chat,time:Date.now()});
 const work=readQueue=readQueue.catch(()=>{}).then(async()=>{
  const notices=await self.registration.getNotifications();
  for(const notice of notices){if(ids.includes(notice.data?.message_id)||(chat&&notice.data?.chat_id===chat))notice.close();}
  const state=await readState();state.events=[...new Set([...state.events,...(event.data.events||[])])].slice(-2000);
  if(chat)state.chats[chat]=Date.now();const chats=Object.entries(state.chats).sort((a,b)=>b[1]-a[1]).slice(0,100);state.chats=Object.fromEntries(chats);await writeState(state);
 });event.waitUntil(work);
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 event.waitUntil((async()=>{
  let target;try{target=notificationRoute71(event.notification.data?.url);
   if(target.pathname.endsWith('/s.html')){target.searchParams.set('notification','1');if(event.notification.data?.message_id)target.searchParams.set('activity_id',event.notification.data.message_id);target.searchParams.set('open','chat');}
  }catch(_){return;}
  const notices=await self.registration.getNotifications();for(const n of notices){if(event.notification.data?.chat_id&&n.data?.chat_id===event.notification.data.chat_id)n.close();}
  const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
  const exact=windows.find(c=>c.url===target.href);if(exact){await exact.focus();return;}
  const chat=windows.find(c=>{try{const u=new URL(c.url);return u.origin===target.origin&&u.pathname===target.pathname;}catch(_){return false;}});
  if(chat){const moved=await chat.navigate(target.href);await moved?.focus();return;}await self.clients.openWindow(target.href);
 })());
});
self.addEventListener('push',event=>{
 const work=readQueue=readQueue.catch(()=>{}).then(async()=>{
  let data;try{data=event.data.json();}catch(_){data={preview:event.data?.text()||'New activity'};}
  let url;try{url=notificationRoute71(data.url);
  }catch(_){return;}
  const key=String(data.event_key||data.message_id||data.event_revision||data.chat_id||'new'),state=await readState();
  if(state.events.includes(key))return;
  const at=Date.parse(data.event_revision||'');
  if(data.chat_id&&Number.isFinite(at)&&state.chats[data.chat_id]>=at)return;
  const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
  if(data.chat_id&&windows.some(c=>c.visibilityState==='visible'&&activeChats.get(c.id)?.chat===data.chat_id&&Date.now()-activeChats.get(c.id).time<20000))return;
  const tag='rr-chat-'+String(data.chat_id||data.message_id||key);
  await self.registration.showNotification(data.customer_name||'REDZED Chat',{body:String(data.preview||'नई activity').slice(0,180),tag,renotify:true,icon:'./redzed-icon-test67.svg',data:{url:url.href,message_id:data.message_id||null,chat_id:data.chat_id||null,collection_cycle_id:data.collection_cycle_id||null,event_key:key,event_revision:data.event_revision||null}});
  state.events=[...state.events,key].slice(-2000);await writeState(state);
 });event.waitUntil(work);
});
self.addEventListener('fetch',event=>{if(event.request.mode==='navigate')event.respondWith(fetch(event.request));});
