const assert=require('node:assert/strict');
const vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../../redzed-sw-test67.js'),'utf8');
const edge=fs.readFileSync(path.join(__dirname,'../../supabase/functions/rr-web-push-dispatch-v61/index.ts'),'utf8');
const routeCode=edge.slice(edge.indexOf('function customerPushRoute71'),edge.indexOf('Deno.serve')).replaceAll(': string | null','').replaceAll('): string {','){');
const normalizeRoute=new Function(routeCode+';return customerPushRoute71;')();
assert.equal(normalizeRoute('https://redzed-customer-collection.jggfab2011.chatgpt.site/s.html?t=NEW','https://pilot-8000.app.github.dev/s.html?t=OLD'),'https://pilot-8000.app.github.dev/s.html?t=NEW');
const handlers={},storage=new Map(),notices=new Map(),shown=[],windows=[];
const self={location:{href:'https://pilot-8000.app.github.dev/redzed-sw-test67.js',origin:'https://pilot-8000.app.github.dev'},
 addEventListener:(name,fn)=>handlers[name]=fn,skipWaiting:async()=>{},
 clients:{claim:async()=>{},matchAll:async()=>windows,openWindow:async()=>{}},
 registration:{getNotifications:async()=>[...notices.values()],showNotification:async(title,options)=>{shown.push({title,...options});notices.set(options.tag,{...options,close(){notices.delete(options.tag);}});}}};
const context={self,URL,Response,Date,console,caches:{open:async()=>({match:async key=>storage.has(key)?new Response(storage.get(key)):null,put:async(key,response)=>storage.set(key,await response.text())})}};
vm.runInNewContext(source,context);
async function event(type,data,extra={}){let pending;handlers[type]({...extra,data:type==='push'?{json:()=>data}:data,waitUntil:p=>pending=p});await pending;}
const at=Date.now()-10000;
const base={message_id:'m1',chat_id:'chat1',event_revision:new Date(at).toISOString(),event_key:'m1:'+new Date(at).toISOString(),collection_cycle_id:'cycle1',url:'https://redzed-customer-collection.jggfab2011.chatgpt.site/s.html?t=NEW',preview:'Collection update'};
(async()=>{
 await Promise.all([event('push',base),event('push',base)]);
 assert.equal(shown.length,1,'one alert for repeated/concurrent event');
 assert.equal(shown[0].data.url,'https://pilot-8000.app.github.dev/s.html?t=NEW','collection route uses installed origin');
 assert.equal(notices.size,1);
 await event('message',{type:'rr:messages-read71',ids:['m1'],chat_id:'chat1',events:[base.event_key]},{source:{id:'window1'}});
 assert.equal(notices.size,0,'open chat closes matching notification');
 await event('push',base);assert.equal(shown.length,1,'read event stays dismissed');
 const next={...base,event_key:'m1:next',event_revision:new Date(Date.now()+1000).toISOString()};
 await event('push',next);assert.equal(shown.length,2,'next update of same workflow message alerts again');
 await event('push',{...next,event_key:'m2:new',message_id:'m2'});assert.equal(notices.size,1,'one notification slot per chat');
 const count=shown.length;
 await event('push',{...next,event_key:'bad',url:'https://unrelated.example/s.html?t=X'});assert.equal(shown.length,count,'unrelated target rejected');
 windows.push({id:'window1',visibilityState:'visible'});
 await event('push',{...next,event_key:'visible'});assert.equal(shown.length,count,'visible current chat suppresses extra system alert');
 console.log('PASS: repeated/concurrent event dedup, installed-origin route, one chat alert, dismissal, delayed suppression, next update, origin guard, visible chat');
})().catch(e=>{console.error(e);process.exitCode=1;});
