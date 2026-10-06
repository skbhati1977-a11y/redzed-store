const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{JSDOM}=require('jsdom');
const root=path.resolve(__dirname,'../..'),source=fs.readFileSync(path.join(root,'test71-business-uppercase.js'),'utf8');
test('Readymade dynamically inserted business inputs normalize typed and pasted values before local handlers',()=>{
 const dom=new JSDOM('<body></body>',{runScripts:'outside-only'}),w=dom.window;try{w.eval(source);
 w.document.body.innerHTML='<input data-field="art_no"><input data-field="item_name"><input data-bill><input data-master-name><input data-field="colours_text"><input data-field="cloth_name">';
 for(const input of w.document.querySelectorAll('input')){let seen;input.addEventListener('input',()=>seen=input.value);input.value='dc1101 redzed polo';input.setSelectionRange(3,3);input.dispatchEvent(new w.Event('input',{bubbles:true}));assert.equal(input.value,'DC1101 REDZED POLO');assert.equal(seen,input.value);assert.equal(input.selectionStart,3);}
 }finally{w.close()}
});
test('Canonical uppercase exclusions preserve URL, notes, search and return reasons',()=>{
 const dom=new JSDOM('<body></body>',{runScripts:'outside-only'}),w=dom.window;try{w.eval(source);w.eval(source);
 w.document.body.innerHTML='<input type="url"><input type="search"><input aria-label="Return reason"><textarea data-rr-uppercase="off"></textarea><input type="email">';
 for(const input of w.document.querySelectorAll('input,textarea')){input.value='MixedCase/value';input.dispatchEvent(new w.Event('input',{bubbles:true}));assert.equal(input.value,'MixedCase/value');}
 assert.equal(w.document.documentElement.dataset.rrBusinessUppercaseReady,'1');
 }finally{w.close()}
});
test('Pilot loads canonical CAPS adapter before dynamic Readymade forms',()=>{
 const html=fs.readFileSync(path.join(root,'test70-cb-purchase-real-chat-pilot.html'),'utf8');assert.ok(html.indexOf('test71-business-uppercase.js')<html.indexOf('test71-readymade-real-chat.js'));
 assert.match(fs.readFileSync(path.join(root,'test71-readymade-real-chat.js'),'utf8'),/textarea data-field="caption_note" data-rr-uppercase="off"/);
});
