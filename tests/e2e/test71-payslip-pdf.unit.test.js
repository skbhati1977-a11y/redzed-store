const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {createCanvas}=require('@napi-rs/canvas');
function harness(){
 const drawn=[];
 const context={window:{},TextEncoder,Uint8Array,File,document:{createElement(){
  const canvas=createCanvas(1190,1684),ctx=canvas.getContext('2d');
  const draw=ctx.fillText.bind(ctx);ctx.fillText=(text,x,y)=>{drawn.push({text,x,y,align:ctx.textAlign});draw(text,x,y);};
  canvas.toBlob=callback=>callback(new Blob([canvas.toBuffer('image/jpeg')]));
  return canvas;
 }}};
 vm.runInNewContext(fs.readFileSync('test71-payslip-pdf.js','utf8'),context);
 return {create:context.window.RRPayslipPdf71.create,drawn};
}
function payload(){return {company:'JAI GIRVER GARMENTS',brand:'REDZED',payload:{header:{worker_name:'Sample Worker',worker_code:'PDF-TEST',department_code:'FABRICATION',salary_month:'September 2026'},heads:[{label:'Monthly Salary',amount:15000},{label:'Net Extra Work',amount:250,time:'5 H'},{label:'Monthly Incentive',amount:100},{label:'Claims / Recovery',amount:100}],net_payable:{amount:15250},payment:{paid_amount:15250,closing_balance:0},status:{payroll_status:'PAID',settlement_status:'PAID'}}};}
test('finalized source produces an A4 PDF with valid binary stream and xref offsets',async()=>{
 const {create,drawn}=harness(),file=await create(payload());
 assert.equal(file.type,'application/pdf');assert.match(file.name,/PDF-TEST.*September_2026/);
 const bytes=Buffer.from(await file.arrayBuffer()),text=bytes.toString('latin1');
 assert.match(text,/^%PDF-1.4/);assert.match(text,/MediaBox \[0 0 595 842\]/);
 const xref=Number(text.match(/startxref\n(\d+)/)[1]);assert.equal(text.slice(xref,xref+4),'xref');
 const offsets=text.slice(xref).split('\n').slice(3,8).map(row=>Number(row.slice(0,10)));
 offsets.forEach((offset,i)=>assert.equal(text.slice(offset,offset+7),(i+1)+' 0 obj'));
 assert.ok(drawn.some(row=>row.text==='INR 15,250.00'));assert.ok(drawn.some(row=>row.text==='INR 0.00'));
 assert.ok(drawn.every(row=>row.y<=1684-68));
 if(process.env.PAYSLIP_PDF_FIXTURE){fs.mkdirSync('tmp/pdfs',{recursive:true});fs.writeFileSync('tmp/pdfs/payslip-test71.pdf',bytes);}
});
test('draft and malformed amounts are rejected, unknown amount remains unknown',async()=>{
 const {create,drawn}=harness();const data=payload();data.payload.status.payroll_status='DRAFT';
 await assert.rejects(create(data),/Final authorized/);
 data.payload.status.payroll_status='FINAL';data.payload.heads[0].amount='invalid';
 await assert.rejects(create(data),/Invalid payslip amount/);
 data.payload.heads[0].amount=null;await create(data);assert.ok(drawn.some(row=>row.text==='—'));
});
test('overflow source is rejected rather than producing a clipped payslip',async()=>{
 const {create}=harness(),data=payload();data.payload.heads=Array.from({length:40},()=>({label:'Long source head',amount:1}));
 await assert.rejects(create(data),/page capacity/);
});
