const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const root=path.resolve(__dirname,'../..');
const config=fs.readFileSync(path.join(root,'config.js'),'utf8');
const html=fs.readFileSync(path.join(root,'real-sales-live-chat-v9434.html'),'utf8');
const loader=config.split('\n').find(line=>line.includes("add67=document.createElement('script')"));
test('staff page claims loader before config and loads fresh version once',()=>{
 assert(html.indexOf('__RR_CONTACT_INVITE_PAGE_LOADER_71__ = true')<html.indexOf('src="config.js'));
 assert.equal((html.match(/src="real-chat-add-customer-test67\.js/g)||[]).length,1);
 assert(html.includes('config.js?v=TEST71-INVITE-LOADER-20261005'));
 const scripts=[];vm.runInNewContext(loader,{window:{__RR_CONTACT_INVITE_PAGE_LOADER_71__:true},document:{createElement:()=>({}),head:{appendChild:s=>scripts.push(s)}}});assert.equal(scripts.length,0);
});
test('other chat pages get fresh config loader instead of cached v67',()=>{
 const scripts=[];vm.runInNewContext(loader,{window:{},document:{createElement:()=>({}),head:{appendChild:s=>scripts.push(s)}}});assert.equal(scripts.length,1);assert.equal(scripts[0].src,'real-chat-add-customer-test67.js?v=TEST71-INVITE-LOADER-20261005');assert.equal(scripts[0].async,false);
});
