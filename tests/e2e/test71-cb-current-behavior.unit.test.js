'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {installFunctions,functionSource}=require('./helpers/source-functions');
const cb=fs.readFileSync('real-cb-new-v9130-fix2.html','utf8');
const categories=['self-collar','crew-neck','drop-shoulder','flat-polo'].map(category_code=>({id:category_code,category_code}));
const families=['L, XL, XXL','2XL, 3XL, 4XL','3XL, 4XL, 5XL','M, L, XL, XXL','M, L, XL','L, XL','L, XXL','FREE SIZE'];
test('confirmed CB hydrates without the retired add-material button and preserves DUE editing',()=>{
 const nodes=Object.fromEntries(['bootMsg','cbNo','divisionCount','colourCount','remarks','saveBtn','draftBtn'].map(id=>[id,{style:{},classList:{add(){}}}]));
 const s=installFunctions(cb,{$:id=>nodes[id]||null,cbState:'WORKING',materials:[{state:'DUE'}]},['applyConfirmedCbFreeze']);
 s.applyConfirmedCbFreeze();assert.match(nodes.bootMsg.textContent,/CB review confirmed/);assert.equal(nodes.cbNo.disabled,true);assert.equal(nodes.saveBtn.hidden,true);assert.equal(nodes.draftBtn.disabled,false);
 s.materials=[];s.cbState='CLOSE';s.applyConfirmedCbFreeze();assert.match(nodes.bootMsg.textContent,/SENT TO CUTTING/);assert.equal(nodes.draftBtn.disabled,true);
});
function scope(extra={},names=[]){return installFunctions(cb,{setRequirements:{},artCategories:categories,arts:[],SIZE_FAMILIES:families,categoryDefaults:new Map(),...extra},['rootSetNoForKey','structuralSetCategoryIds','categoryForId','normalizeBorderPounchi','normalizeSharedFinish','canonicalSizeFamilyDisplay','categoryDefaultsFor',...names]);}
test('S1 Self Collar, S2/S3 Round Drop and S4 Flat remain exact category authorities for child profiles',()=>{
 const s=scope({setRequirements:{'22':{rootSetNo:2}}});
 for(const [key,allowed] of [['1',['self-collar']],['2',['crew-neck','drop-shoulder']],['3',['crew-neck','drop-shoulder']],['4',['flat-polo']],['22',['crew-neck','drop-shoulder']]])assert.deepEqual(Array.from(s.structuralSetCategoryIds(key)),allowed);
});
test('Art picker excludes wrong category and inactive newcomers, retaining the previously saved Art',()=>{
 const s=scope({arts:[{id:'wrong',art_no:'1',art_category_id:'flat-polo'},{id:'good',art_no:'10',art_category_id:'crew-neck'},{id:'old',art_no:'2',art_category_id:'crew-neck',is_active:false},{id:'none',art_no:'3'}],esc:String},['artOptionsForSet']);
 const html=s.artOptionsForSet('2','old');assert.ok(html.includes('value="good"'));assert.ok(html.includes('value="old" selected'));assert.ok(!html.includes('value="wrong"'));assert.ok(!html.includes('value="none"'));assert.ok(!s.artOptionsForSet('2').includes('value="old"'));
});
test('wrong-category or missing Art cannot issue a mutation; valid selection uses exact child unit',async()=>{
 const calls=[],s=scope({setRequirements:{2:{unitId:'child-2'}},arts:[{id:'wrong',art_category_id:'flat-polo'},{id:'right',art_category_id:'crew-neck'}],sb:()=>({rpc:async(n,a)=>{calls.push({n,a});return {data:{ok:true}}}})},['saveCbArtSelection']);
 await assert.rejects(s.saveCbArtSelection(2,'wrong'),/not allowed/);await assert.rejects(s.saveCbArtSelection(2,'missing'),/not found/);assert.equal(calls.length,0);
 await s.saveCbArtSelection(2,'right');assert.equal(calls[0].n,'rr_cb_select_art_v1');assert.equal(calls[0].a.p_cb_unit_id,'child-2');assert.equal(calls[0].a.p_art_id,'right');
});
test('category defaults use half sleeve, plain Round Drop finish and cuff collar finish',()=>{
 const s=scope();for(const id of ['crew-neck','drop-shoulder']){const d=s.categoryDefaultsFor(id);assert.equal(d.sleeveType,'HALF');assert.equal(d.sleeveFinish,'PLAIN');assert.equal(d.borderPounchi,'WITHOUT_BORDER_POUNCHI');assert.equal(d.sizeFamily,'L, XL, XXL');}
 for(const id of ['self-collar','flat-polo'])assert.equal(s.categoryDefaultsFor(id).sleeveFinish,'CUFF');
});
test('changing future defaults leaves already saved profile values intact',()=>{
 const saved={sleeveType:'FULL',sleeveFinish:'RIB',sizeFamily:'2XL, 3XL, 4XL',borderPounchi:'WITH_BORDER_POUNCHI'},defaults=new Map([['crew-neck',{default_sleeve_type:'HALF',default_sleeve_finish:'PLAIN',default_size_family:'L,XL,XXL'}]]);
 const s=scope({setRequirements:{2:saved},categoryDefaults:defaults},['applyCategoryDefaults']);const future={};s.applyCategoryDefaults(future,'crew-neck');assert.equal(future.sleeveType,'HALF');assert.equal(saved.sleeveType,'FULL');assert.equal(saved.sizeFamily,'2XL, 3XL, 4XL');
});
test('eight size families normalize spacing and case without inventing a ninth family',()=>{
 const s=scope({},['sizeFamilyOptions']);for(const family of families)assert.equal(s.canonicalSizeFamilyDisplay(family.toLowerCase().replaceAll(' ','')),family);
 assert.equal(s.canonicalSizeFamilyDisplay('unknown'),'L, XL, XXL');assert.equal((s.sizeFamilyOptions('2xl,3xl,4xl').match(/<option /g)||[]).length,8);assert.equal((s.sizeFamilyOptions('2xl,3xl,4xl').match(/ selected/g)||[]).length,1);
});
test('Cuff Tape aliases consolidate; Plain Rib and border stay separate',()=>{
 const s=scope();for(const alias of ['TAPE','WITH_CUFF','CUFF_TAPE','CUFF'])assert.equal(s.normalizeSharedFinish(alias),'CUFF');
 assert.equal(s.normalizeSharedFinish('RIB'),'RIB');for(const alias of ['SELF_CUFF','WITHOUT_CUFF','N_A'])assert.equal(s.normalizeSharedFinish(alias),'PLAIN');
 assert.equal(s.normalizeBorderPounchi('WITH_BORDER_POUNCHI'),'WITH_BORDER_POUNCHI');assert.equal(s.normalizeBorderPounchi(''),'WITHOUT_BORDER_POUNCHI');
});
test('Self Collar material is N/A, Flat Collar uses collar/cuff and Round Drop uses Rib',()=>{
 const s=scope({},['expectedMaterialLabel']);assert.match(s.expectedMaterialLabel({artCategoryId:'self-collar'}),/MATERIAL N\/A/);assert.match(s.expectedMaterialLabel({artCategoryId:'flat-polo'}),/COLLAR & CUFF/);assert.match(s.expectedMaterialLabel({artCategoryId:'crew-neck'}),/RIB/);
});
test('garment payload carries the exact child, parent Set, Art, sleeve, border and size',()=>{
 const s=scope({setRequirements:{22:{unitId:'unit-22',rootSetNo:2,artId:'ART',artCategoryId:'crew-neck',sleeveType:'FULL',sleeveFinish:'TAPE',borderPounchi:'WITH_BORDER_POUNCHI',sizeFamily:'2XL, 3XL, 4XL'}}},['setRequirementPayload']);
 assert.deepEqual(JSON.parse(JSON.stringify(s.setRequirementPayload(22))),{cb_unit_id:'unit-22',set_no:2,art_id:'ART',art_category_id:'crew-neck',sleeve_type:'FULL',sleeve_finish:'CUFF',border_pounchi:'WITH_BORDER_POUNCHI',size_family:'2XL, 3XL, 4XL'});
});
test('current mapping writer sends one exact child to v6 and propagates a failed save',async()=>{
 const calls=[],s=scope({cbId:'CB',setRequirements:{2:{unitId:'unit-2'}},sb:()=>({rpc:async(n,a)=>{calls.push({n,a});return {error:Error('mapping rejected')}}})},['setRequirementPayload','syncSetRequirementNow']);
 await assert.rejects(s.syncSetRequirementNow(2),/mapping rejected/);assert.equal(calls[0].n,'rr_cb_set_requirement_sync_v6');assert.equal(calls[0].a.p_cb_id,'CB');assert.equal(calls[0].a.p_rows.length,1);assert.equal(calls[0].a.p_rows[0].cb_unit_id,'unit-2');
});
test('Cutting lock checks the exact unit and propagates failed backend authorization',async()=>{
 let args;const s=scope({sb:()=>({rpc:async(n,a)=>{args={n,a};return {data:true}}})},['cbArtCuttingLocked']);assert.equal(await s.cbArtCuttingLocked('unit-2'),true);assert.equal(args.n,'rr_cb_unit_has_final_cutting_v1');assert.equal(args.a.p_cb_unit_id,'unit-2');assert.equal(await s.cbArtCuttingLocked(null),false);
 s.sb=()=>({rpc:async()=>({error:Error('permission denied')})});await assert.rejects(s.cbArtCuttingLocked('unit-2'),/permission denied/);
});
test('reconciliation preserves Party Bill Qty and marks prior decision stale after physical change',()=>{
 const material={qty:100},s=scope({materials:[material],rollTotal:()=>90,reconciliation:{bill_qty:100,physical_roll_qty:95,status:'ACTIVE',decision:'DEBIT_NOTE',accepted_financial_qty:95}},['reconciliationLocal']);
 const r=s.reconciliationLocal();assert.equal(r.bill_qty,100);assert.equal(r.physical_roll_qty,90);assert.equal(r.difference_qty,-10);assert.equal(r.status,'RECHECK_REQUIRED');assert.equal(r.decision,null);assert.equal(r.accepted_financial_qty,null);assert.equal(material.qty,100);
});
test('Short renders Debit Note; Excess renders Credit Note; both keep reporting separate',()=>{
 const s=scope({materials:[{qty:100}],rollTotal:()=>90,reconciliation:null,reconciliationHistory:[],esc:String},['reconciliationLocal','reconciliationPanel']);
 const short=s.reconciliationPanel();assert.match(short,/MAKE DEBIT NOTE/);assert.doesNotMatch(short,/MAKE CREDIT NOTE/);assert.match(short,/REPORT SHORT \/ EXCESS/);
 s.rollTotal=()=>110;const excess=s.reconciliationPanel();assert.match(excess,/MAKE CREDIT NOTE/);assert.doesNotMatch(excess,/MAKE DEBIT NOTE/);
});
test('reconciliation history contains server previous/current projection without reversal amounts',()=>{
 const s=scope({materials:[{qty:100}],rollTotal:()=>100,reconciliation:null,reconciliationHistory:[{view_role:'PREVIOUS',decision_date:'2026-10-01',decision:'ACCEPT_PARTY_BILL',status:'REVERSED',amount:999}],esc:String},['reconciliationLocal','reconciliationPanel']);const html=s.reconciliationPanel();assert.match(html,/PREVIOUS/);assert.match(html,/REVERSED/);assert.doesNotMatch(html,/999/);
});
test('confirmed CB disables reconciliation decisions while OPEN remains editable',()=>{
 const buttons=[{},{}],s=scope({cbState:'WORKING',document:{querySelectorAll:()=>buttons}},['applyReconciliationFreeze']);s.applyReconciliationFreeze();assert.ok(buttons.every(b=>b.disabled));s.cbState='OPEN';buttons.forEach(b=>b.disabled=false);s.applyReconciliationFreeze();assert.ok(buttons.every(b=>!b.disabled));
});
test('retry retains the action ID; changed payload or CB identity gets a different ID',()=>{
 const store=new Map();let count=0;const s=scope({cbId:'CB-1',cbClientKey:'client',localStorage:{getItem:k=>store.get(k),setItem:(k,v)=>store.set(k,v)},crypto:{randomUUID:()=>String(++count)}},['pendingAction']);
 const first=s.pendingAction('SAVE','same'),retry=s.pendingAction('SAVE','same');assert.equal(first.actionId,retry.actionId);assert.notEqual(s.pendingAction('SAVE','changed').actionId,first.actionId);s.cbId='CB-2';assert.notEqual(s.pendingAction('SAVE','same').actionId,first.actionId);
});
test('first share, revised share and reshare use their own truthful labels',()=>{
 const s=scope({},['requirementSendLabel']);assert.equal(s.requirementSendLabel({send_count:0}),'SHARE RECEIPT');assert.equal(s.requirementSendLabel({send_count:1,revision_no:2,last_sent_revision:1}),'SHARE REVISED');assert.equal(s.requirementSendLabel({send_count:1,revision_no:1,last_sent_revision:1}),'RESHARE #2');
});
test('technical backend errors show safe action guidance; normal permission errors remain actionable',()=>{
 const s=scope({},['isTechnicalError','friendlyUserError']);assert.equal(s.friendlyUserError(Error('null value in column salary'),'Retry save'),'Retry save');assert.match(s.friendlyUserError(Error('permission denied')),/permission/);assert.equal(s.friendlyUserError(Error('Bill No required')),'Bill No required');
});
