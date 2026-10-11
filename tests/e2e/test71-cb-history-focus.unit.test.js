'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {installFunctions}=require('./helpers/source-functions');
const source=fs.readFileSync('test70-real-chat-live-v70.js','utf8');
function render(S){
  const buttons=['OPEN','WORKING','CLOSE'].map(status=>({dataset:{chatStatus:status},classList:{toggle(){}},hidden:false}));
  const scope=installFunctions(source,{S,document:{querySelectorAll:()=>buttons}},['syncStatusButtons']);
  scope.syncStatusButtons();return buttons;
}
test('focused closed CB link keeps canonical history while CLOSE tab stays hidden',()=>{
  const S={status:'CLOSE',cbHistoryFocus:true,active:{kind:'group',id:'PURCHASE'}};
  const buttons=render(S);assert.equal(S.status,'CLOSE');assert.equal(buttons[2].hidden,true);
});
test('ordinary closed navigation keeps the existing WORKING default',()=>{
  const S={status:'CLOSE',active:{kind:'group',id:'PURCHASE'}};render(S);assert.equal(S.status,'WORKING');
});
test('CB history focus cannot change another department or personal chat',()=>{
  for(const active of [{kind:'group',id:'STITCHING'},{kind:'person',id:'worker',parentDepartment:'PURCHASE'},null]){
    const S={status:'CLOSE',cbHistoryFocus:true,active};render(S);assert.equal(S.status,'WORKING');
  }
});
