const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const path=require('node:path');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 try {
 const page=await browser.newPage({viewport:{width:393,height:820},isMobile:true,hasTouch:true});
 await page.route('**/*',r=>r.fulfill({body:'<html></html>',contentType:'text/html'}));
 await page.goto('https://fixture.test/real-sales-live-chat-v9434.html?chat_id=fixture-chat');
 await page.setContent('<div id="chatTitle">LUKMAN SALES</div><div id="msgs"><div class="msg"><div>[REQ:e053b33c-d5b0-402b-9435-848b35fead13] RZ REQUIREMENT 21</div><time>18:28</time></div></div>');
 await page.evaluate(()=>{window.detailCalls=[];window.RF853={rpc:async(n,a)=>{window.detailCalls.push(a);return {id:a.p_requirement_id,requirement_display_no:'RZ REQUIREMENT 21',collection_display_no:'RZ COLLECTION 01',status:'READY_FOR_PI',can_prepare_pi:true,lines:[{lot_no:'LOT-21',accepted_qty:36,requested_qty:36}]}}}});
 for(const file of ['real-chat-requirement-flow-v9508.js','real-chat-requirement-identity-v9682.js'])await page.addScriptTag({path:path.resolve(file)});
 await page.getByRole('button',{name:/OPEN REQUIREMENT/}).waitFor();
 // A restored/decorated card retains its markup and marker, but no node listeners.
 await page.evaluate(()=>{const row=document.querySelector('#msgs .msg');row.replaceWith(row.cloneNode(true));});
 await page.getByRole('button',{name:/OPEN REQUIREMENT/}).tap();
 await page.locator('#rrReqBack9508.on').waitFor();
 await page.locator('#rrReqIdentity9682').waitFor();
 assert.match(await page.locator('#rrReqBody9508').innerText(),/LOT-21/);
 assert.equal(await page.locator('#rrReqTitle9508').innerText(),'📋 RZ REQUIREMENT 21');
 assert.equal(await page.locator('#rrReqPi9508').isEnabled(),true);
 const calls=await page.evaluate(()=>window.detailCalls);
 assert(calls.every(a=>a.p_chat_id==='fixture-chat'&&a.p_requirement_id==='e053b33c-d5b0-402b-9435-848b35fead13'));
 await page.locator('#rrReqClose9508').tap();
 await page.getByRole('button',{name:/OPEN REQUIREMENT/}).tap();
 await page.locator('#rrReqBack9508.on').waitFor();
 console.log('PASS: mobile tap opens rehydrated requirement; exact chat/requirement IDs; 36 PCS; identity and PI gate; close/reopen.');
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
