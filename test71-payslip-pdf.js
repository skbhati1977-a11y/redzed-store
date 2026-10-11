(()=>{
 'use strict';
 const W=1190,H=1684,margin=80;
 const number=value=>value===null||value===undefined?'—':Number.isFinite(Number(value))?'INR '+Number(value).toLocaleString('en-IN',{minimumFractionDigits:2,maximumFractionDigits:2}):(()=>{throw Error('Invalid payslip amount');})();
 const clean=value=>String(value??'—').replace(/[\u0000-\u001f]/g,' ').slice(0,250);
 const bytes=value=>new TextEncoder().encode(value);
 function jpegPdf(jpeg){
  const chunks=[],offsets=[0];let size=0;
  const add=value=>{const part=typeof value==='string'?bytes(value):value;chunks.push(part);size+=part.length;};
  const object=(id,value)=>{offsets[id]=size;add(id+' 0 obj\n'+value+'\nendobj\n');};
  add('%PDF-1.4\n');
  object(1,'<< /Type /Catalog /Pages 2 0 R >>');
  object(2,'<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  object(3,'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /XObject << /Slip 4 0 R >> >> /Contents 5 0 R >>');
  offsets[4]=size;add('4 0 obj\n<< /Type /XObject /Subtype /Image /Width '+W+' /Height '+H+' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length '+jpeg.length+' >>\nstream\n');add(jpeg);add('\nendstream\nendobj\n');
  const stream='q\n595 0 0 842 0 0 cm\n/Slip Do\nQ\n';object(5,'<< /Length '+bytes(stream).length+' >>\nstream\n'+stream+'endstream');
  const xref=size;add('xref\n0 6\n0000000000 65535 f \n');for(let id=1;id<=5;id++)add(String(offsets[id]).padStart(10,'0')+' 00000 n \n');
  add('trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n'+xref+'\n%%EOF\n');
  const result=new Uint8Array(size);let at=0;for(const part of chunks){result.set(part,at);at+=part.length;}return result;
 }
 async function create(documentData){
  const p=documentData?.payload;
  if(!p?.header||!Array.isArray(p.heads)||!['FINAL','PAID'].includes(p.status?.payroll_status))throw Error('Final authorized payslip required.');
  const canvas=document.createElement('canvas');canvas.width=W;canvas.height=H;const c=canvas.getContext('2d');if(!c)throw Error('PDF rendering unavailable.');
  c.fillStyle='#ffffff';c.fillRect(0,0,W,H);let y=margin;
  const text=(value,x,y,size=28,bold=false)=>{c.fillStyle='#182532';c.font=(bold?'700 ':'400 ')+size+'px sans-serif';c.fillText(clean(value),x,y);};
  const line=()=>{c.strokeStyle='#d7dfe5';c.beginPath();c.moveTo(margin,y);c.lineTo(W-margin,y);c.stroke();};
  function wrapped(value,size=28,width=W-2*margin){
   const lines=[];let current='';c.font=size+'px sans-serif';
   for(const word of clean(value).split(/\s+/)){
    const next=current?current+' '+word:word;
    if(c.measureText(next).width<=width){current=next;continue;}
    if(current){lines.push(current);current='';}
    for(const char of word){if(current&&c.measureText(current+char).width>width){lines.push(current);current='';}current+=char;}
   }
   if(current)lines.push(current);return lines.length?lines:['—'];
  }

  text(documentData.company||'JAI GIRVER GARMENTS',margin,y,36,true);y+=45;text((documentData.brand||'REDZED')+' · MONTHLY PAYSLIP',margin,y,26);y+=65;
  for(const value of [p.header.worker_name,'Worker code: '+clean(p.header.worker_code),'Department: '+clean(p.header.department_code),'Salary month: '+clean(p.header.salary_month)]){for(const row of wrapped(value)){text(row,margin,y,28);y+=39;}y+=7;}
  y+=15;line();y+=55;text('Salary heads',margin,y,28,true);c.textAlign='right';text('Amount',W-margin,y,28,true);c.textAlign='left';y+=45;
  for(const head of p.heads){const rows=wrapped(head.label||head.code,26,W-2*margin-350);text(rows[0],margin,y,26);c.textAlign='right';text(number(head.amount),W-margin,y,26);c.textAlign='left';y+=40;for(const row of rows.slice(1)){text(row,margin,y,24);y+=35;}if(head.time){text('Time: '+clean(head.time),margin,y,23);y+=35;}y+=10;}
  y+=10;line();y+=55;
  for(const [label,value]of [['NET PAYABLE SALARY',p.net_payable?.amount],['Paid amount',p.payment?.paid_amount],['Closing balance',p.payment?.closing_balance]]){text(label,margin,y,28,label==='NET PAYABLE SALARY');c.textAlign='right';text(number(value),W-margin,y,28,true);c.textAlign='left';y+=60;}
  y+=20;text('Payroll status: '+p.status.payroll_status,margin,y,25);y+=39;text('Settlement status: '+clean(p.status.settlement_status),margin,y,25);
  if(y>H-160)throw Error('Payslip exceeds page capacity. Review source details before export.');
  text('Generated from the authorized finalized payroll record.',margin,H-105,23);text('Page 1 / 1',margin,H-68,21);
  const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',0.96));if(!blob)throw Error('Payslip image rendering failed.');
  const pdf=jpegPdf(new Uint8Array(await blob.arrayBuffer()));const name='Payslip-'+clean(p.header.worker_code||p.header.worker_name).replace(/[^a-z0-9_-]/gi,'_')+'-'+clean(p.header.salary_month).replace(/[^a-z0-9_-]/gi,'_')+'.pdf';
  return new File([pdf],name,{type:'application/pdf'});
 }
 window.RRPayslipPdf71={create};
})();
