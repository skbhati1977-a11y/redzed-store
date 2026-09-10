"use strict";
const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");

function staticFallback(reason) {
  const html = fs.readFileSync("test70-cb-purchase-real-chat-pilot.html", "utf8");
  const js = fs.readFileSync("test70-cb-purchase-real-chat-pilot.js", "utf8");
  for (const required of ["Real Chat","Department Group","Personal Chat","Stitching Department Group","Lot No. या Worker खोजें","काम देना बाकी","काम चल रहा है","काम पूरा","Worker का काम देखें","काम स्वीकार करें","काम की तस्वीरें","सिर्फ TEST"]) assert.ok(html.includes(required), `जरूरी भाग नहीं मिला: ${required}`);
  assert.ok(!html.includes(">सभी काम<") && !html.includes(">काम की Chat<"), "पुराना heading/status अभी मौजूद है");
  for (const removed of ["काम की बात इसी समूह में रखें","खुली बातचीत बंद","फोन की गैलरी नहीं खुलेगी","इसी Department का काम","इस Department के Worker","केवल काम की Chat","· Personal Chat</small>"]) assert.ok(!html.includes(removed) && !js.includes(removed), `Extra direction अभी मौजूद है: ${removed}`);
  for (const required of ["Printer Group","Sticker Group","Metal ID Group","Kaaj Button Group","Packing Group"]) assert.ok(js.includes(required), `Department Group नहीं मिला: ${required}`);
  assert.ok(html.includes("bubble mine") && html.includes("card mine"), "बाएँ-दाएँ संदेश नहीं मिले");
  assert.ok((html.match(/data-react=/g) || []).length >= 12, "काम के बटन कम हैं");
  for (const required of ["databaseWrites:false","freeChat:false","deviceGallery:false","PRIVATE_BUSINESS"]) assert.ok(js.includes(required), `Missing guard: ${required}`);
  assert.ok(!html.includes('type="file"'), "Device file picker must not exist");
  console.log(`PASS (static fallback): सरल हिंदी, बाएँ-दाएँ बातचीत, काम के बटन और बिना लिखे जाँच सुरक्षित। Browser unavailable: ${reason}`);
}

(async () => {
  let browser;
  try { browser = await chromium.launch({headless:true}); }
  catch (error) { staticFallback(error.message.split("\n")[0]); return; }
  const page = await browser.newPage({viewport:{width:390,height:844}});
  await page.goto("http://127.0.0.1:8765/test70-cb-purchase-real-chat-pilot.html", {waitUntil:"networkidle"});
  assert.deepEqual(await page.evaluate(() => window.__TEST70_CONTROLLED_CHAT__), {mode:"AUTOMATED_TEST",databaseWrites:false,freeChat:false,deviceGallery:false,lanes:["STAFF_GROUP","PRIVATE_BUSINESS"],ready:true});
  await page.getByRole("button", {name:"Staff की सूची"}).click();
  await page.getByRole("button", {name:/शैलेन्दर/}).click();
  await page.getByRole("button", {name:"नई काम की बात"}).click();
  await page.locator('select[name="category"]').selectOption({label:"मंज़ूरी याद दिलाएँ"});
  await page.locator('input[name="reference"]').fill("CB-TEST70");
  await page.locator('select[name="receiver"]').selectOption({label:"शैलेन्दर · सुपर एडमिन"});
  await page.locator('textarea[name="remarks"]').fill("सामान की मंज़ूरी चाहिए");
  await page.getByRole("button", {name:"बात भेजें"}).click();
  await page.getByText(/मंज़ूरी याद दिलाएँ · CB-TEST70/).waitFor();
  await page.getByRole("button", {name:"अंदर की तस्वीरें"}).click();
  assert.equal(await page.locator('input[type="file"]').count(), 0);
  await page.getByRole("button", {name:/लॉट 2606 · सुधार की तस्वीर/}).click();
  await page.getByText("तस्वीर जोड़ी गई").waitFor();
  await page.getByRole("button", {name:"Department Group चुनें"}).click();
  await page.getByRole("button", {name:/Printer Group/}).click();
  assert.equal(await page.locator("#chatTitle").innerText(), "Printer Group");
  await page.screenshot({path:"test70-controlled-workflow-chat-mobile.png",fullPage:true});
  await browser.close();
  console.log("PASS: TEST70 सरल हिंदी काम की बातचीत — समूह/निजी, उत्तर, अंदर की तस्वीरें, कोई असली लिखाई नहीं।");
})().catch(error => { console.error(error); process.exitCode=1; });
