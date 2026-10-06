(() => {
 'use strict';
 const safe=v=>String(v||'receipt').replace(/[^a-z0-9_-]/gi,'_').slice(0,100);
 const amount=v=>'₹'+Number(v||0).toLocaleString('en-IN',{maximumFractionDigits:2});
 const digest=async blob=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await blob.arrayBuffer())),b=>b.toString(16).padStart(2,'0')).join('');
 function text(c,value,x,y,width,size=27,bold=false){
  c.font=(bold?'700 ':'400 ')+size+'px Arial, sans-serif';c.fillStyle='#132131';
  const paragraphs=String(value??'—').split('\n');
  for(const paragraph of paragraphs){let line='';for(const word of paragraph.split(/\s+/)){const test=line?line+' '+word:word;if(line&&c.measureText(test).width>width){c.fillText(line,x,y);y+=size*1.35;line=word}else line=test}c.fillText(line,x,y);y+=size*1.35}
  return y;
 }
 async function photo(url){
  if(!/^https?:\/\//i.test(url||''))return null;
  let objectURL;
  try{
   const response=await fetch(url,{signal:AbortSignal.timeout(10000)});if(!response.ok)throw Error('Photo unavailable');
   const blob=await response.blob();if(!blob.type.startsWith('image/')||blob.size>10*1024*1024)return null;
   objectURL=URL.createObjectURL(blob);const img=new Image();img.src=objectURL;await img.decode();return{img,objectURL};
  }catch{if(objectURL)URL.revokeObjectURL(objectURL);return null}
 }
 async function render(receipt){
  if(receipt.status!=='POSTED'||!receipt.lines?.length)throw Error('Confirmed purchase receipt required.');
  const files=[],chunks=[];for(let i=0;i<receipt.lines.length;i+=2)chunks.push(receipt.lines.slice(i,i+2));
  for(let page=0;page<chunks.length;page++){
   const canvas=document.createElement('canvas');canvas.width=1400;canvas.height=650+chunks[page].length*790;
   const c=canvas.getContext('2d',{alpha:false});if(!c)throw Error('JPG receipt इस browser में नहीं बन सकी.');
   c.fillStyle='#fff';c.fillRect(0,0,canvas.width,canvas.height);c.fillStyle='#142738';c.fillRect(0,0,1400,150);
   c.fillStyle='#fff';c.font='700 58px Arial';c.fillText('REDZED',60,85);c.font='28px Arial';c.fillText('PROFORMA DR/CR NOTE',460,82);
   let y=text(c,'Purchase: '+receipt.purchase_no+'   |   Bill: '+receipt.bill_no,60,210,1280,30,true);
   y=text(c,'Supplier: '+receipt.supplier_name,60,y+8,1280);
   y=text(c,'Bill date: '+receipt.purchase_date+'   |   Receipt prepared: '+new Date(receipt.prepared_at||Date.now()).toLocaleString('en-IN',{timeZone:'Asia/Kolkata'}),60,y+8,1280,25);
   for(const line of chunks[page]){
    const top=y+28;c.fillStyle='#eff3f6';c.fillRect(40,top,1320,750);let rightY=top+62;
    rightY=text(c,'Lot '+line.lot_no+'   |   Art '+(line.art_no||'—'),400,rightY,930,30,true);
    rightY=text(c,line.item_name,400,rightY+8,930,32,true);
    rightY=text(c,'Category: '+(line.category||'—')+'   |   Size: '+(line.size_text||'—'),400,rightY+8,930,25);
    rightY=text(c,'Colours: '+(line.colours_text||'—'),400,rightY+8,930,25);
    const image=await photo(line.image_url);
    if(image){try{const scale=Math.min(300/image.img.naturalWidth,310/image.img.naturalHeight);c.drawImage(image.img,70,top+70,image.img.naturalWidth*scale,image.img.naturalHeight*scale)}finally{URL.revokeObjectURL(image.objectURL)}}
    else text(c,'Garment photo unavailable',70,top+170,280,23);
    rightY=text(c,'Party Bill Qty: '+line.bill_qty+' PCS\nReceived Qty: '+line.received_qty+' PCS\nPurchase Rate: '+amount(line.purchase_rate)+' / PCS',400,rightY+14,930,29);
    rightY=text(c,(line.note_type==='DEBIT_NOTE'?'SHORT · DEBIT NOTE':line.note_type==='CREDIT_NOTE'?'EXCESS · CREDIT NOTE':'MATCHED')+'   |   '+Math.abs(Number(line.difference_qty))+' PCS   |   '+amount(line.note_amount),70,Math.max(top+435,rightY+20),1250,32,true);
    rightY=text(c,'Accounts voucher: '+(line.voucher_no||'No adjustment required'),70,rightY+12,1250,27);
    rightY=text(c,'Party bill value '+amount(line.bill_value)+'   |   Net received value '+amount(line.received_value),70,rightY+12,1250,27);
    y=top+760;
   }
   y=text(c,'Original Bill: '+amount(receipt.bill_value)+'   |   Net Supplier Payable: '+amount(receipt.received_value),60,y+65,1280,29,true);
   text(c,'Linked to original bill and purchase-rate snapshot. Page '+(page+1)+' / '+chunks.length,60,y+22,1280,22);
   const blob=await new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(Error('JPG receipt नहीं बनी.')),'image/jpeg',.92));
   files.push(new File([blob],'REDZED-Proforma-DR-CR-Note-'+safe(receipt.purchase_no||receipt.bill_no)+'-'+(page+1)+'.jpg',{type:'image/jpeg'}));canvas.width=canvas.height=1;
  }
  return files;
 }
 async function prepare(ctx,purchaseId){
  let receipt=await ctx.rpc('rr_rm_receipt_prepare_test71',{p_purchase_id:purchaseId});
  const storage=ctx.s.db.storage.from('redzed-media');
  if(!receipt.files?.length){
   const files=await render(receipt),metadata=[];
   for(const file of files){
    const path='readymade/test71/receipts/'+purchaseId+'/'+crypto.randomUUID()+'.jpg';
    const upload=await storage.upload(path,file,{contentType:'image/jpeg',upsert:false});if(upload.error)throw Error('Purchase confirmed है. JPG upload नहीं हुई—Retry JPG दबाएँ.');
    metadata.push({name:file.name,path,sha256:await digest(file)});
   }
   receipt=await ctx.rpc('rr_rm_receipt_files_save_test71',{p_purchase_id:purchaseId,p_files:metadata});
  }
  const files=[];
  for(const f of receipt.files||[]){
   const url=storage.getPublicUrl(f.path).data.publicUrl;
   const response=await fetch(url,{signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error('Saved receipt JPG नहीं खुली. Retry JPG दबाएँ.');
   const blob=await response.blob();if(await digest(blob)!==f.sha256)throw Error('Saved JPG verification failed. Please retry.');
   files.push(new File([blob],f.name,{type:'image/jpeg'}));
  }
  if(!files.length)throw Error('Receipt JPG अभी तैयार नहीं है.');
  return{receipt,files,urls:(receipt.files||[]).map(f=>storage.getPublicUrl(f.path).data.publicUrl)};
 }
 function proforma(receipt,photos=[]){
  if(!receipt.lines?.length)throw Error('Proforma note के लिए garment details भरें.');
  const canvas=document.createElement('canvas');canvas.width=1080;canvas.height=430+receipt.lines.length*600;
  const c=canvas.getContext('2d');if(!c)throw Error('JPG इस browser में नहीं बनी.');c.fillStyle='#fff';c.fillRect(0,0,canvas.width,canvas.height);c.fillStyle='#b42335';c.fillRect(0,0,1080,130);c.fillStyle='#fff';c.font='700 44px Arial';c.fillText('REDZED',45,58);c.font='700 34px Arial';c.fillText('PROFORMA DR/CR NOTE',45,106);
  let y=text(c,'Supplier: '+receipt.supplier_name+'   |   Bill: '+receipt.bill_no,45,185,990,26,true);y=text(c,'Bill date: '+receipt.purchase_date,45,y+8,990,24);
  for(let i=0;i<receipt.lines.length;i++){const l=receipt.lines[i],top=y+20;c.fillStyle='#eff3f6';c.fillRect(30,top,1020,575);let yy=text(c,'Art '+(l.art_no||'—')+' · '+l.item_name,300,top+50,710,28,true);yy=text(c,'Lot '+l.lot_no+' · '+(l.category||'—')+' · '+(l.size_text||'—'),300,yy+8,710,24);
   const img=photos[i];if(img?.complete&&img.naturalWidth){try{const scale=Math.min(230/img.naturalWidth,230/img.naturalHeight);c.drawImage(img,45,top+45,img.naturalWidth*scale,img.naturalHeight*scale)}catch{}}
   yy=text(c,'Party Bill Qty: '+l.bill_qty+' PCS\nReceived Qty: '+l.received_qty+' PCS\nPurchase Rate: '+amount(l.purchase_rate)+' / PCS',300,yy+10,710,26);
   yy=text(c,(l.note_type==='DEBIT_NOTE'?'SHORT · DEBIT NOTE':l.note_type==='CREDIT_NOTE'?'EXCESS · CREDIT NOTE':'MATCHED')+' · '+Math.abs(Number(l.difference_qty||0))+' PCS · '+amount(l.note_amount),45,Math.max(top+340,yy+15),990,28,true);
   yy=text(c,'Party bill '+amount(l.bill_value)+' · Net received '+amount(l.received_value),45,yy+12,990,24);text(c,'Proforma · Linked to supplier bill; Accounts posting follows purchase confirmation.',45,yy+18,980,20);y=top+585;
  }
  text(c,'Party bill: '+amount(receipt.bill_value)+' · Net supplier payable: '+amount(receipt.received_value),45,y+55,990,27,true);
  const bytes=type=>{const raw=atob(canvas.toDataURL(type,.92).split(',')[1]);return Uint8Array.from(raw,ch=>ch.charCodeAt(0))};
  const name='REDZED-Proforma-DR-CR-Note-'+safe(receipt.purchase_no||receipt.bill_no);const jpg=new File([bytes('image/jpeg')],name+'.jpg',{type:'image/jpeg'});
  return{files:[jpg],png:()=>new File([bytes('image/png')],name+'.png',{type:'image/png'})};
 }
 function shareNow(files,png){
  if(typeof navigator.share!=='function')throw Error('इस window में image picker नहीं है. JPG save करके Gallery के Share से WhatsApp चुनें.');
  // CB shares a synchronous PNG File. Use that same picker payload; keep JPG for saving.
  let payloadFiles=png?[png()]:files;
  try{if(navigator.canShare&&!navigator.canShare({files:payloadFiles})&&navigator.canShare({files}))payloadFiles=files}catch{}
  const promise=navigator.share({files:payloadFiles,title:'Proforma DR/CR Note'});
  return Promise.resolve(promise).then(()=>({shared:true}),e=>({shared:false,error:e?.name==='AbortError'?null:e}));
 }
 function attach(ctx,modal,receipt,options={}){
  const footer=modal.querySelector('[data-footer]'),message=modal.querySelector('[data-message]'),body=modal.querySelector('[data-body]');
  const share=document.createElement('button'),retry=document.createElement('button'),links=document.createElement('div');share.type=retry.type='button';share.dataset.shareJpg='';share.textContent='Save & Send · Proforma DR/CR Note';share.disabled=true;retry.textContent='Retry JPG';retry.hidden=true;footer.append(share,retry,links);if(body)body.before(footer);
  let pack=null,busy=false;const urls=[];const oldRemove=modal.remove.bind(modal);modal.remove=()=>{urls.forEach(u=>URL.revokeObjectURL(u));oldRemove()};
  async function ready(){if(busy)return;busy=true;share.disabled=true;message.textContent='Proforma DR/CR Note JPG तैयार हो रही है…';try{
   const snapshot=await ctx.rpc('rr_rm_receipt_prepare_test71',{p_purchase_id:receipt.purchase_id});const images=await Promise.all(snapshot.lines.map(async l=>{const p=await photo(l.image_url);return p}));
   try{pack=proforma(snapshot,images.map(p=>p?.img))}finally{images.forEach(p=>{if(p)URL.revokeObjectURL(p.objectURL)})}
   if(!modal.isConnected)return;links.replaceChildren();for(const f of pack.files){const a=document.createElement('a');a.href=URL.createObjectURL(f);urls.push(a.href);a.download=f.name;a.textContent='Save JPG · Proforma DR/CR Note';links.appendChild(a)}share.disabled=false;retry.hidden=true;message.textContent=options.shareStarted?'Purchase saved. Proforma image भेज दी हो तो यही JPG दुबारा save कर सकते हैं.':'Save & Send दबाएँ—नीचे image picker से WhatsApp/contact चुनें. JPG पर long-press करके भी Share / Save कर सकते हैं.';
   const preview=document.createElement('img');preview.src=urls[urls.length-1];preview.alt='Proforma DR/CR Note';preview.style.width='100%';preview.dataset.proformaPreview='';body?.prepend(preview);
  }catch(e){message.textContent=e.message||'JPG नहीं बनी. Retry दबाएँ.';retry.hidden=false}finally{busy=false}}
  retry.onclick=ready;share.onclick=()=>{if(!pack||busy)return;busy=true;let result;try{result=shareNow(pack.files,pack.png)}catch(e){message.textContent=e.message;busy=false;return}result.then(async r=>{if(r.shared){message.textContent='Proforma image share app को दी गई. WhatsApp में contact चुनकर Send करें.';try{await prepare(ctx,receipt.purchase_id);await ctx.rpc('rr_rm_receipt_share_record_test71',{p_purchase_id:receipt.purchase_id,p_event_id:crypto.randomUUID()})}catch{message.textContent+=' Share record save नहीं हुआ; purchase सुरक्षित है.'}}else message.textContent=r.error?'Image share नहीं खुला. JPG save करें या preview पर long-press करके Share चुनें.':'Share cancel हुई. फिर से Save & Send दबा सकते हैं.'}).finally(()=>busy=false)};
  ready();
 }
 async function prime(receipt){const photos=await Promise.all(receipt.lines.map(l=>photo(l.image_url||l.final_image_url)));try{return proforma(receipt,photos.map(p=>p?.img))}finally{photos.forEach(p=>{if(p)URL.revokeObjectURL(p.objectURL)})}}
 window.RRReadymadeReceipt71={render,prepare,attach,proforma,shareNow,prime};
})();
