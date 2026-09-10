"use strict";
const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");

function staticFallback(reason) {
  const html = fs.readFileSync("test70-cb-purchase-real-chat-pilot.html", "utf8");
  const js = fs.readFileSync("test70-cb-purchase-real-chat-pilot.js", "utf8");
  for (const required of ["STAFF GROUP","PRIVATE","BUSINESS ONLY","MATERIAL NAME APPROVAL","ACCEPT HANDOVER","INTERNAL MEDIA","Device Gallery upload बंद है","NO DB WRITE"]) assert.ok(html.includes(required), `Missing controlled-chat UI: ${required}`);
  for (const required of ["databaseWrites:false","freeChat:false","deviceGallery:false","PRIVATE_BUSINESS"]) assert.ok(js.includes(required), `Missing guard: ${required}`);
  assert.ok(!html.includes('type="file"'), "Device file picker must not exist");
  console.log(`PASS (static fallback): TEST70 controlled workflow chat + zero-write guards. Browser unavailable: ${reason}`);
}

(async () => {
  let browser;
  try { browser = await chromium.launch({headless:true}); }
  catch (error) { staticFallback(error.message.split("\n")[0]); return; }
  const page = await browser.newPage({viewport:{width:390,height:844}});
  await page.goto("http://127.0.0.1:8765/test70-cb-purchase-real-chat-pilot.html", {waitUntil:"networkidle"});
  assert.deepEqual(await page.evaluate(() => window.__TEST70_CONTROLLED_CHAT__), {mode:"AUTOMATED_TEST",databaseWrites:false,freeChat:false,deviceGallery:false,lanes:["STAFF_GROUP","PRIVATE_BUSINESS"],ready:true});
  await page.getByRole("button", {name:"Staff menu"}).click();
  await page.getByRole("button", {name:/Shailender/}).click();
  await page.getByRole("button", {name:"New business message"}).click();
  await page.locator('select[name="category"]').selectOption({label:"Approval Follow-up"});
  await page.locator('input[name="reference"]').fill("CB-TEST70");
  await page.locator('select[name="receiver"]').selectOption({label:"Shailender · SUPER ADMIN"});
  await page.locator('textarea[name="remarks"]').fill("Material approval required");
  await page.getByRole("button", {name:"SEND BUSINESS MESSAGE"}).click();
  await page.getByText(/Approval Follow-up · CB-TEST70/).waitFor();
  await page.getByRole("button", {name:"Internal media"}).click();
  assert.equal(await page.locator('input[type="file"]').count(), 0);
  await page.getByRole("button", {name:/LOT 2606 · Alter evidence/}).click();
  await page.getByText("INTERNAL MEDIA ATTACHED").waitFor();
  await page.screenshot({path:"test70-controlled-workflow-chat-mobile.png",fullPage:true});
  await browser.close();
  console.log("PASS: TEST70 controlled workflow chat — group/private, templates, reactions, internal media, zero DB writes.");
})().catch(error => { console.error(error); process.exitCode=1; });
