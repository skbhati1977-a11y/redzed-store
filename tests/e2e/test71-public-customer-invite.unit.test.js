const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const source=fs.readFileSync(path.resolve(__dirname,'../../real-chat-add-customer-test67.js'),'utf8');
test('both single and queued invites use the public customer base even from a private Codespace',()=>{
 const expressions=[...source.matchAll(/new URL\('real-customer-invite-test67.html',[^;]+\)/g)].map(x=>x[0]);assert.equal(expressions.length,2);
 for(const expression of expressions){for(const configured of [undefined,'https://redzed-customer-collection.jggfab2011.chatgpt.site/']){
 const url=vm.runInNewContext(expression,{URL,window:{RR_CUSTOMER_SHARE_BASE:configured},location:{href:'https://private-8000.app.github.dev/staff.html?chat_id=secret'}});
 assert.equal(url.hostname,'redzed-customer-collection.jggfab2011.chatgpt.site');assert.equal(url.pathname,'/real-customer-invite-test67.html');assert.equal(url.search,'');
 }}
 assert.doesNotMatch(source,/new URL\('real-customer-invite-test67.html',location.href\)/);
});
test('customer origin is locked against later staff/private URL overrides',()=>{
 const config=fs.readFileSync(path.resolve(__dirname,'../../config.js'),'utf8');const start=config.indexOf('Object.defineProperty(window,"RR_CUSTOMER_SHARE_BASE"'),end=config.indexOf(';',start)+1;
 assert.ok(start>=0);const window={};vm.runInNewContext(config.slice(start,end),{window});assert.equal(window.RR_CUSTOMER_SHARE_BASE,'https://redzed-customer-collection.jggfab2011.chatgpt.site/');
 for(const privateUrl of ['https://private-8000.app.github.dev/','https://github.com/login','http://localhost:8000/']){window.RR_CUSTOMER_SHARE_BASE=privateUrl;assert.equal(window.RR_CUSTOMER_SHARE_BASE,'https://redzed-customer-collection.jggfab2011.chatgpt.site/');}
 assert.equal(Object.getOwnPropertyDescriptor(window,'RR_CUSTOMER_SHARE_BASE').configurable,false);
});
