const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{JSDOM}=require('jsdom');
test('MW Art and Lot suggestions retain canonical card selection and show both identities',async()=>{
 const root=path.resolve(__dirname,'../..'),html=fs.readFileSync(path.join(root,'real-web-window-v9329.html'),'utf8').replace(/<script[\s\S]*?<\/script>/g,'');
 const d=new JSDOM(html,{url:'https://example.com/mw',runScripts:'outside-only'}),w=d.window,calls=[];
 try{w.RF853={mode:()=> 'TEST',rpc:async(n,p)=>{calls.push({n,p});return n==='rr_web_window_cards_v9329'?[{lot_no:'RM004',art_no:'DC1100',sale_rate:200,available_qty:540,item_name:'Polo',media:[]}]:{}}};
 w.eval(fs.readFileSync(path.join(root,'real-web-window-v9329.js'),'utf8'));await new Promise(r=>setTimeout(r,30));
 assert.equal(w.document.getElementById('quickSearch').getAttribute('list'),'mwArtLotOptions71');
 assert.deepEqual([...w.document.querySelectorAll('#mwArtLotOptions71 option')].map(x=>x.value),['RM004','DC1100']);
 assert.match(w.document.getElementById('cards').textContent,/RM004.*Art DC1100/);
 w.document.getElementById('quickSearch').value='DC1100';w.document.getElementById('quickSearch').dispatchEvent(new w.Event('change'));await new Promise(r=>setTimeout(r,20));
 assert.equal(calls.filter(c=>c.n==='rr_web_window_cards_v9329').at(-1).p.p_search,'DC1100');
 }finally{w.close()}
});
