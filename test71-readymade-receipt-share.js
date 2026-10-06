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
   c.fillStyle='#fff';c.font='700 58px Arial';c.fillText('REDZED',60,85);c.font='28px Arial';c.fillText('SHORT / EXCESS PURCHASE RECEIPT',460,82);
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
   files.push(new File([blob],'REDZED-'+safe(receipt.purchase_no||receipt.bill_no)+'-'+(page+1)+'.jpg',{type:'image/jpeg'}));canvas.width=canvas.height=1;
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
 function attach(ctx,modal,receipt){
  const footer=modal.querySelector('[data-footer]'),message=modal.querySelector('[data-message]');
  const prepareButton=document.createElement('button'),shareButton=document.createElement('button'),recordButton=document.createElement('button'),links=document.createElement('div'),whatsapp=document.createElement('a'),browser=document.createElement('a');
  prepareButton.type=shareButton.type=recordButton.type='button';prepareButton.dataset.prepareJpg='';shareButton.dataset.shareJpg='';recordButton.dataset.shareOk='';
  prepareButton.textContent='Retry / Prepare JPG';shareButton.textContent='Send Receipt · Choose app';shareButton.disabled=true;recordButton.textContent='भेज दिया · OK';recordButton.hidden=true;
  whatsapp.dataset.whatsappReceipt='';whatsapp.textContent='WhatsApp · Contact चुनें · Receipt link';browser.dataset.browserReceipt='';browser.textContent='Open in browser · Share JPG';for(const a of [whatsapp,browser]){a.target='_blank';a.rel='noopener noreferrer';a.hidden=true}
  footer.dataset.receiptSend='';footer.append(shareButton,whatsapp,browser,recordButton,prepareButton,links);
  const body=modal.querySelector('[data-body]');if(body){body.before(footer);body.before(message)}
  if(!document.getElementById('rmReceiptSendStyle')){const style=document.createElement('style');style.id='rmReceiptSendStyle';style.textContent='[data-receipt-send]{display:grid!important;gap:9px;padding:14px!important;border:1px solid #3c8265;border-radius:12px;background:#102e25;margin-bottom:12px}[data-receipt-send]>button,[data-receipt-send]>a{box-sizing:border-box;width:100%;padding:13px!important;border-radius:9px;text-align:center;font:600 16px system-ui;text-decoration:none}[data-share-jpg]{background:#18794e!important;color:white!important;border:1px solid #58ac86!important}[data-receipt-send]>a{color:#d4f0e2;background:#173e32;border:1px solid #4c8068}[data-receipt-send] [hidden]{display:none!important}';document.head.appendChild(style)}
  let pack=null,busy=false,pending=null,linkData=null;const urls=[];
  const originalRemove=modal.remove.bind(modal);modal.remove=()=>{urls.forEach(url=>URL.revokeObjectURL(url));originalRemove()};
  async function load(){
   if(busy)return;busy=true;prepareButton.disabled=true;shareButton.disabled=true;message.textContent='Receipt JPG तैयार हो रही है…';
   try{
    pack=await prepare(ctx,receipt.purchase_id);if(!modal.isConnected)return;
    urls.splice(0).forEach(url=>URL.revokeObjectURL(url));links.replaceChildren();
    for(const file of pack.files){const url=URL.createObjectURL(file);urls.push(url);const a=document.createElement('a');a.href=url;a.download=file.name;a.textContent='Save JPG · '+file.name;a.style.display='block';links.appendChild(a)}
    const page=new URL('test71-readymade-supplier-receipt.html',location.href);page.hash=encodeURIComponent(JSON.stringify({title:'REDZED '+pack.receipt.purchase_no,files:pack.receipt.files.map((f,i)=>({...f,url:pack.urls[i]}))}));
    browser.href=page.href;whatsapp.href='https://wa.me/?text='+encodeURIComponent('REDZED Purchase Receipt · Bill '+pack.receipt.bill_no+'\n'+page.href);whatsapp.hidden=browser.hidden=false;
    linkData={title:'REDZED Purchase Receipt',text:'Purchase receipt · Bill '+pack.receipt.bill_no,url:page.href};
    shareButton.disabled=false;message.textContent='Purchase saved. अब Send Receipt दबाएँ—app picker में WhatsApp / दूसरी app चुनें. JPG share बंद हो तो Open in browser या WhatsApp Receipt link चुनें.'+(pack.receipt.last_shared_at?' Last shared: '+new Date(pack.receipt.last_shared_at).toLocaleString('en-IN',{timeZone:'Asia/Kolkata'}):'');
   }catch(e){message.textContent=e.message||'JPG तैयार नहीं हुई. Retry JPG दबाएँ.'}finally{busy=false;prepareButton.disabled=false}
  }
  prepareButton.onclick=load;
  const chooseExternal=()=>{if(!pack||busy||pending)return;pending=crypto.randomUUID();recordButton.hidden=false;shareButton.disabled=true;message.textContent='WhatsApp / browser खुल रहा है. भेजने के बाद वापस आकर भेज दिया · OK दबाएँ. Receipt link है; JPG attachment के लिए Open in browser चुनें.'};
  whatsapp.onclick=browser.onclick=chooseExternal;
  // Keep native share synchronous with this tap: never render/upload/fetch before share().
  shareButton.onclick=()=>{
   if(!pack||busy||pending)return;
   const policy=document.permissionsPolicy||document.featurePolicy;
   let payload={files:pack.files,title:'REDZED Purchase Receipt'};
   const allowed=!(policy?.allowsFeature&&!policy.allowsFeature('web-share'));
   let filesAllowed=allowed&&typeof navigator.share==='function';try{if(navigator.canShare)filesAllowed=filesAllowed&&navigator.canShare({files:pack.files})}catch{filesAllowed=false}
   if(!filesAllowed)payload=linkData;
   let supported=allowed&&typeof navigator.share==='function';try{if(navigator.canShare)supported=supported&&navigator.canShare(payload)}catch{supported=false}
   if(!supported){whatsapp.click();return}
   busy=true;shareButton.disabled=true;const eventId=crypto.randomUUID();let promise;
   try{promise=navigator.share(payload)}catch(e){busy=false;shareButton.disabled=false;message.textContent='Share नहीं खुला. WhatsApp · Contact चुनें से receipt link भेजें, या Open in browser से JPG share करें.';return}
   Promise.resolve(promise).then(()=>{pending=eventId;recordButton.hidden=false;message.textContent=(filesAllowed?'JPG':'Receipt link')+' share-picker से लौट आए. WhatsApp पर भेज दिया हो तो भेज दिया · OK दबाएँ.'},e=>{message.textContent=e?.name==='AbortError'?'Share cancel हुई. Receipt और Debit/Credit Note सुरक्षित हैं.':'Share बंद है. WhatsApp · Contact चुनें से receipt link भेजें, या Open in browser से JPG share करें.'}).finally(()=>{busy=false;shareButton.disabled=!!pending});
  };
    recordButton.onclick=async()=>{
   if(!pending||busy)return;busy=true;recordButton.disabled=true;
   try{await ctx.rpc('rr_rm_receipt_share_record_test71',{p_purchase_id:receipt.purchase_id,p_event_id:pending});pending=null;recordButton.hidden=true;message.textContent='Share record saved. इसी JPG को दोबारा भेज सकते हैं; नया Debit/Credit Note नहीं बनेगा.'}
   catch{message.textContent='Share record save नहीं हुआ. भेज दिया · OK दोबारा दबाएँ; file दोबारा नहीं भेजी जाएगी.'}
   finally{busy=false;recordButton.disabled=false;shareButton.disabled=!!pending}
  };
  load();
 }
 window.RRReadymadeReceipt71={render,prepare,attach};
})();
