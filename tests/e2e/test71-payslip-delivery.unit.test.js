const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {JSDOM}=require('jsdom');
const settle=()=>new Promise(resolve=>setTimeout(resolve,20));
async function page({share=true,denied=false,cancel=false}={}){
 const dom=new JSDOM(fs.readFileSync('real-monthly-payroll-v779.html','utf8'),{runScripts:'outside-only',url:'https://test.example/real-monthly-payroll-v779.html'});
 const w=dom.window,calls=[],shared=[],revoked=[];
 w.URL.createObjectURL=()=> 'blob:https://test.example/payslip';w.URL.revokeObjectURL=url=>revoked.push(url);
 w.RRPayslipPdf71={create:async()=>new File(['%PDF-1.4'], 'Payslip-TEST.pdf',{type:'application/pdf'})};
 if(share){w.navigator.canShare=()=>true;w.navigator.share=async data=>{shared.push(data);if(cancel)throw Object.assign(new Error('cancel'),{name:'AbortError'});};}
 w.supabaseClient={auth:{getUser:async()=>({data:{user:{id:'test-worker'}}})},from:()=>({select(){return this;},eq(){return this;},limit(){return this;},maybeSingle:async()=>({data:{role_code:'worker'}})}),rpc:async(name,args)=>{
  calls.push({name,args});
  if(name==='rr_get_my_payroll_history_v779_3')return {data:{payroll_history:[{payroll_id:'test-payroll',salary_month:'September 2026',payroll_status:'FINAL',pdf_available:true,whatsapp_available:true}]}};
  if(denied)return {error:{message:'Not authorized'}};
  if(name==='rr_get_whatsapp_payslip_payload_v779_3')return {data:{message_text:'Sample finalized payslip'}};
  if(name==='rr_get_payslip_payload_v779_3')return {data:{payload:{net_payable:{amount:15000}}}};
  throw Error('Unexpected mutation '+name);
 }};
 w.eval(fs.readFileSync('real-monthly-payroll-v779.js','utf8'));await settle();
 return {dom,w,calls,shared,revoked};
}
test('PDF action offers real download and closing sheet revokes its object URL',async()=>{
 const h=await page();try{
 h.w.document.querySelector('[data-pdf]').click();await settle();
 const link=h.w.document.querySelector('#detailsBody a[download]');assert.equal(link.download,'Payslip-TEST.pdf');assert.match(link.href,/^blob:/);
 h.w.document.querySelector('[data-close="detailsSheet"]').click();assert.equal(h.revoked.length,1);
 assert.equal(h.shared.length,0);
 }finally{h.dom.window.close();}
});
test('preparation never sends; explicit share uses the PDF file and cancellation is neutral',async()=>{
 const h=await page({cancel:true});try{
 h.w.document.querySelector('[data-wa]').click();await settle();assert.equal(h.shared.length,0);
 h.w.document.querySelector('#sharePayslipFile').click();await settle();
 assert.equal(h.shared.length,1);assert.equal(h.shared[0].files[0].type,'application/pdf');assert.equal(h.shared[0].text,'Sample finalized payslip');
 assert.match(h.w.document.getElementById('message').textContent,/cancelled/);
 assert.ok(h.calls.every(c=>!c.name.includes('confirm_sent')&&!c.name.includes('payment')));
 }finally{h.dom.window.close();}
});
test('unsupported share retains download; denied source exposes no download',async()=>{
 const h=await page({share:false});try{h.w.document.querySelector('[data-wa]').click();await settle();assert.ok(h.w.document.querySelector('#detailsBody a[download]'));assert.equal(h.w.document.querySelector('#sharePayslipFile'),null);}finally{h.dom.window.close();}
 const denied=await page({denied:true});try{denied.w.document.querySelector('[data-pdf]').click();await settle();assert.equal(denied.w.document.querySelector('#detailsBody a[download]'),null);assert.match(denied.w.document.getElementById('message').textContent,/Not authorized/);}finally{denied.dom.window.close();}
});
