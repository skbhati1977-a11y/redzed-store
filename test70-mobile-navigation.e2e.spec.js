"use strict";
const {test,expect}=require("playwright/test");

test.use({viewport:{width:390,height:844}});

test("mobile reaches both list ends and restores department after group/person chat",async({page})=>{
  const departments=Array.from({length:18},(_,i)=>({
    department_code:`D${i}`,department_name:`Department ${i}`,worker_count:i===4?15:2,staff_count:3,
    working_count:i,open_count:0,close_count:0,
    workers:Array.from({length:i===4?15:2},(_,j)=>({worker_id:`w${i}_${j}`,worker_name:`Worker ${i}-${j}`,role_code:"WORKER",linked_login:true})),
    staff:Array.from({length:3},(_,j)=>({worker_id:`s${i}_${j}`,worker_name:`Staff ${i}-${j}`,role_code:"ADMIN",linked_login:true,source_rule:"UNIVERSAL_REDZED_STAFF"}))
  }));
  const people=departments.flatMap(d=>d.workers);
  await page.addInitScript(({departments,people})=>{
    window.supabaseClient={
      auth:{getUser:async()=>({data:{user:{id:"audit-user"}}})},
      rpc:async name=>({data:name==="rr_real_chat_directory_v71"?{departments,people,actor:{name:"Audit",role:"OWNER"}}:{cards:[]},error:null}),
      from:()=>({select:()=>({limit:async()=>({data:[],error:null})})})
    };
  },{departments,people});
  await page.route("**/config.js*",route=>route.fulfill({contentType:"application/javascript",body:""}));
  await page.goto("/test70-cb-purchase-real-chat-pilot.html");
  await expect(page.locator("[data-department]")).toHaveCount(18);

  const inbox=page.locator("#rows");
  await inbox.evaluate(el=>{el.scrollTop=el.scrollHeight});
  await expect(page.locator(".list-end")).toBeInViewport();

  await page.locator('[data-department="D4"]').click();
  await expect(page.getByText("WORKER SIDE · 15")).toBeVisible();
  const messages=page.locator("#messages");
  await messages.evaluate(el=>{el.scrollTop=el.scrollHeight});
  await expect(page.locator('[data-person="s4_2"]')).toBeInViewport();

  await page.locator('[data-dept-group="D4"]').click();
  await expect(page.locator("#kind")).toHaveText("GROUP CHAT");
  await page.goBack();
  await expect(page.locator("#kind")).toHaveText("DEPARTMENT DIRECTORY");

  await page.locator('[data-person="w4_0"]').click();
  await expect(page.locator("#kind")).toHaveText("PERSONAL CHAT");
  await page.goBack();
  await expect(page.locator("#kind")).toHaveText("DEPARTMENT DIRECTORY");
  await page.goBack();
  await expect(page.getByText("ALL DEPARTMENTS")).toBeVisible();
});
