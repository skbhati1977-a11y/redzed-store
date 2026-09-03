const CACHE='redzed-test67-v1';
const SHELL=['./s.html','./real-customer-invite-test67.html','./redzed-manifest-test67.webmanifest','./redzed-icon-test67.svg'];
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)).catch(()=>{})));
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('notificationclick',event=>{
  event.notification.close();
  event.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(list=>{
    const open=list.find(client=>client.url.includes('/redzed-store/'))||list[0];
    return open?open.focus():clients.openWindow('./s.html?v=67');
  }));
});
