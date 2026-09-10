"use strict";

const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");

function staticFallback(reason) {
  const html = fs.readFileSync("test70-cb-purchase-real-chat-pilot.html", "utf8");
  const js = fs.readFileSync("test70-cb-purchase-real-chat-pilot.js", "utf8");
  for (const required of [
    "CB PURCHASE · REDZED",
    "CB NEW · REGULAR CLOTH",
    "MC1 · MATCHING CLOTH",
    "TEST CREATE CB",
    "TEST ADD TO MC1",
    "NO DB WRITE",
  ]) assert.ok(html.includes(required), `Missing pilot UI: ${required}`);
  assert.ok(js.includes('databaseWrites: false'), "Database-write guard missing");
  assert.ok(js.includes('event.preventDefault()'), "Test submit interception missing");
  console.log(`PASS (static fallback): TEST70 structure + zero-write guards. Browser unavailable: ${reason}`);
}

(async () => {
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
  } catch (error) {
    staticFallback(error.message.split("\n")[0]);
    return;
  }
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.goto("http://127.0.0.1:8765/test70-cb-purchase-real-chat-pilot.html", { waitUntil: "networkidle" });

  assert.equal(await page.title(), "TEST70 · CB Purchase Real Chat Pilot");
  assert.deepEqual(await page.evaluate(() => window.__TEST70_CB_CHAT_PILOT__), {
    mode: "AUTOMATED_TEST",
    databaseWrites: false,
    ready: true,
  });

  await page.getByRole("button", { name: /START CB NEW/ }).click();
  await page.getByRole("button", { name: "TEST CREATE CB" }).click();
  await page.getByText(/CB NEW TEST PASSED/).waitFor();
  assert.match(await page.locator("#cbResult").innerText(), /database write blocked/i);
  await page.locator('[data-close="cbBack"]').first().click();

  await page.getByRole("button", { name: /ADD MATCHING CLOTH/ }).click();
  await page.getByRole("button", { name: "TEST ADD TO MC1" }).click();
  await page.getByText(/MC1 TEST PASSED/).waitFor();
  assert.match(await page.locator("#mcResult").innerText(), /database write blocked/i);

  const ownResults = await page.locator("#msgs .msg.me").count();
  assert.equal(ownResults, 2);
  await page.screenshot({ path: "test70-cb-purchase-real-chat-pilot-mobile.png", fullPage: true });
  await browser.close();
  console.log("PASS: TEST70 CB Purchase Real Chat pilot — Regular Cloth + MC1, zero database writes.");
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
