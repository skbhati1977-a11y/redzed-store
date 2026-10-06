const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const config=fs.readFileSync(__dirname+'/../../config.js','utf8');
const marker='// TEST71: repair saved customer links at the outgoing transport boundary.';
const source=config.slice(config.indexOf(marker));
const portal='https://redzed-customer-collection.jggfab2011.chatgpt.site';
const old='https://old-8000.app.github.dev/real-customer-invite-test67.html?t=TOKEN&c=CODE&open=collection#card';
function setup(){const calls={};const listeners={};const window={open(...args){calls.open=args;}};
 const navigator={clipboard:{writeText(value){calls.clipboard=value;return Promise.resolve();}},share(data){calls.share=data;return Promise.resolve();}};
 const document={addEventListener(type,fn){listeners[type]=fn;}};
 vm.runInNewContext(source,{window,navigator,document,URL,Set,Object,String});return {window,navigator,calls,listeners,normalize:window.RRPublicCustomerLink71};}
test('saved private invites preserve token, short code, collection parameters and fragment',()=>{const {normalize}=setup();assert.equal(normalize.url(old),portal+'/real-customer-invite-test67.html?t=TOKEN&c=CODE&open=collection#card');});
test('clipboard repairs each saved customer link and leaves unrelated text intact',async()=>{const {navigator,calls}=setup();await navigator.clipboard.writeText('REDZED\n'+old+'\nhttps://example.com/a');assert.equal(calls.clipboard,'REDZED\n'+portal+'/real-customer-invite-test67.html?t=TOKEN&c=CODE&open=collection#card\nhttps://example.com/a');});
test('native share repairs both url and text without dropping attached files',async()=>{const {navigator,calls}=setup();const files=[{}];await navigator.share({url:old,text:old,title:'REDZED',files});assert.equal(calls.share.files,files);assert.equal(calls.share.title,'REDZED');assert.ok(calls.share.url.startsWith(portal));assert.ok(calls.share.text.startsWith(portal));});
test('WhatsApp and SMS outgoing messages repair encoded saved links',()=>{const {window,calls,normalize}=setup();for(const base of ['https://wa.me/919999999999','https://api.whatsapp.com/send','sms:919999999999']){const u=new URL(base);u.searchParams.set(base.startsWith('sms:')?'body':'text','REDZED '+old);window.open(u.href,'_blank');const result=new URL(calls.open[0]);assert.ok((result.searchParams.get('text')||result.searchParams.get('body')).includes(portal));assert.equal(calls.open[1],'_blank');}assert.ok(normalize.text('('+old+').').endsWith('#card).'));});
test('staff, supplier and third-party URLs remain unchanged',()=>{const {normalize}=setup();for(const raw of ['https://old-8000.app.github.dev/real-sales-live-chat-v9434.html?chat_id=staff','https://old-8000.app.github.dev/r.html?k=supplier','https://github.com/login','https://example.com/s.html?t=other',portal+'/s.html?t=public'])assert.equal(normalize.url(raw),raw);});
test('customer anchor clicks repair only the outgoing destination',()=>{const {listeners}=setup();const anchor={href:old};listeners.click({target:{closest(){return anchor;}}});assert.ok(anchor.href.startsWith(portal));});
