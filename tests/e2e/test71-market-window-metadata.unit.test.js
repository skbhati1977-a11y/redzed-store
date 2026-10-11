const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync(require('node:path').resolve(__dirname,'../../real-web-window-v9329.js'),'utf8');
const {JSDOM}=require('jsdom');
async function render(rows,colours={},search=''){
 const dom=new JSDOM(fs.readFileSync('real-web-window-v9329.html','utf8'),{url:'https://example.test/real-web-window-v9329.html'+search,runScripts:'outside-only'}),w=dom.window,calls=[];
 try{
 w.RF853={mode:()=> 'TEST',rpc:async(name,args)=>{calls.push({name,args});return name==='rr_market_window_colours_v1'?colours:rows}};
 w.eval(source);await new Promise(resolve=>setTimeout(resolve,20));return {html:w.document.getElementById('cards').innerHTML,calls,msg:w.document.getElementById('msg').textContent};
 }finally{w.close()}
}
test('missing and zero sale rates stay outside Market Window',async()=>{
 const {html,msg}=await render([{lot_no:'missing',sale_rate:null,available_qty:5},{lot_no:'zero',sale_rate:0,available_qty:5}]);
 assert.ok(!html.includes('data-card='));assert.equal(msg,'0 lots loaded');
});
test('approved rate, released sizes and colour metadata render without changing available pcs',async()=>{
 const {html,calls}=await render([{lot_no:'lot',sale_rate:125,size_text:'2XL / 3XL / 4XL',category:'Round Neck',available_qty:54}],{lot:'Red / Blue'});
 for(const value of ['₹125','2XL / 3XL / 4XL','Round Neck','Red / Blue','AVL <b>54'])assert.ok(html.includes(value),value);
 assert.equal(calls[1].name,'rr_market_window_colours_v1');
 assert.equal(calls[1].args.p_data_mode,'TEST');
});

test('Readymade handoff preselects all requested available lots for the existing outside share flow',async()=>{
 const {html}=await render([{lot_no:'RM1',available_qty:20,sale_rate:150},{lot_no:'RM2',available_qty:12,sale_rate:null},{lot_no:'RM3',available_qty:0}],{},'?share_mode=chooser&from=READYMADE&selected_lot=RM1&selected_lot=RM2&selected_lot=RM3');
 assert.match(html,/data-select="RM1" checked/);assert.ok(!html.includes('data-select="RM2"')); assert.ok(!html.includes('data-select="RM3" checked'));
});
