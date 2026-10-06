const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {JSDOM}=require('jsdom');
test('Closed collection retains required qty with no editable fields or submit action',async()=>{
 const dom=new JSDOM('<body></body>',{url:'https://example.com/s.html?t=closed-token'}),w=dom.window,calls=[];
 const rpc=async(name,args)=>{calls.push({name,args});return name==='rr_market_share_view_v9420'?{rows:[{lot_no:'RM1',item_name:'Readymade',media:[]},{lot_no:'MFG1',item_name:'Manufacturing',media:[]}]}:{lines:[{lot_no:'RM1',requested_qty:24},{lot_no:'MFG1',requested_qty:0}]}};
 try{
 vm.runInNewContext(fs.readFileSync('real-customer-chat-collection-card-v9605.js','utf8'),{window:w,document:w.document,location:w.location,URLSearchParams,RF853:{rpc},setInterval:()=>1,clearInterval:()=>{},setTimeout:()=>1,console});
 await w.RRCustomerCollectionViewer71.open({collection_display_no:'COL16',collection_update_no:4});
 const dialog=w.document.getElementById('rrCollectionReadOnly71');assert.ok(dialog);assert.match(dialog.textContent,/Required qty · 24 PCS/);assert.match(dialog.textContent,/Required qty · 0 PCS/);assert.equal(dialog.querySelectorAll('input,textarea,select').length,0);assert.equal(dialog.querySelector('#fcSubmit'),null);assert.ok(calls.every(c=>c.args.p_token==='closed-token'));dialog.querySelector('button').click();assert.equal(w.document.getElementById('rrCollectionReadOnly71'),null);
 }finally{w.close()}
});
