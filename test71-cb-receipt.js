/* TEST71 Receipt V2.1 — RECEIPT_SINGLE_ATTACHMENT_V21. One requirement, one selected JPG/PDF. */
(function(root){
'use strict';
const W=1080,H=1528,ink='#172333',muted='#647487',red='#b42e42';
const $=id=>document.getElementById(id);
const safeName=s=>String(s||'receipt').replace(/[^a-z0-9_-]+/gi,'-').slice(0,100);
const quantity=(v,unit='PCS')=>Number(v||0).toLocaleString('en-IN',{minimumFractionDigits:unit==='KG'?3:0,maximumFractionDigits:unit==='KG'?3:0});
const count=v=>v==null||v===''?'—':quantity(v);
function eventId(){if(typeof crypto.randomUUID==='function')return crypto.randomUUID();const b=crypto.getRandomValues(new Uint8Array(16));b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;const s=Array.from(b,n=>n.toString(16).padStart(2,'0')).join('');return [s.slice(0,8),s.slice(8,12),s.slice(12,16),s.slice(16,20),s.slice(20)].join('-')}
const encoder=new TextEncoder();
const bytes=s=>encoder.encode(s);
const join=parts=>{const out=new Uint8Array(parts.reduce((n,p)=>n+p.length,0));let i=0;for(const p of parts){out.set(p,i);i+=p.length}return out};
const timeout=(p,ms,label)=>new Promise((resolve,reject)=>{const t=setTimeout(()=>reject(new Error(label)),ms);Promise.resolve(p).then(v=>{clearTimeout(t);resolve(v)},e=>{clearTimeout(t);reject(e)})});
function safeURL(raw){try{const u=new URL(raw,location.href);return u.protocol==='https:'||(u.origin===location.origin&&u.protocol==='http:')?u.href:''}catch{return''}}
function wrap(c,text,width){
 const out=[];let line='';for(const word of String(text??'—').split(/\s+/)){
  if(c.measureText(word).width>width){if(line){out.push(line);line=''}for(const ch of word){if(c.measureText(line+ch).width>width){out.push(line);line=''}line+=ch}continue}
  const trial=line?line+' '+word:word;if(line&&c.measureText(trial).width>width){out.push(line);line=word}else line=trial;
 }if(line||!out.length)out.push(line);return out;
}
function text(c,value,x,y,width,size=23,bold=false,color=ink){c.font=(bold?'700 ':'400 ')+size+'px system-ui,sans-serif';c.fillStyle=color;const lines=wrap(c,value,width),step=size*1.38;for(const line of lines){c.fillText(line,x,y);y+=step}return y}
function canvasPage(){const canvas=document.createElement('canvas');canvas.width=W;canvas.height=H;const c=canvas.getContext('2d',{alpha:false});if(!c)throw new Error('Receipt image बन नहीं सकी.');c.fillStyle='#fff';c.fillRect(0,0,W,H);return{canvas,c,links:[]}}
function head(page,d,continuation=false){const c=page.c;text(c,'REDZED',64,83,470,48,true,red);text(c,'ORDER REQUIREMENT SLIP',570,69,450,23,true);text(c,continuation?'CONTINUED · '+d.receipt_no:d.requirement_type.replaceAll('_',' '),570,104,450,18,false,muted);c.fillStyle=red;c.fillRect(64,130,W-128,3)}
function footer(page,d,index,total){const c=page.c;c.fillStyle='#d8e0e7';c.fillRect(64,H-102,W-128,1);text(c,'Please confirm availability / making status.',64,H-68,W-128,20,true);text(c,'Requirement only · Not a payment receipt',64,H-35,780,16,false,muted);text(c,(index+1)+' / '+total,W-145,H-35,100,17,false,muted)}
async function canvasJpeg(canvas){const blob=await new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(new Error('JPG receipt तैयार नहीं हुई.')),'image/jpeg',.92));return{blob,data:new Uint8Array(await blob.arrayBuffer())}}
async function loadAsset(item,index){
 const url=safeURL(item.url);if(!url)throw new Error('Reference URL invalid: '+item.label);
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),15000);let blob;
 try{const res=await fetch(url,{signal:controller.signal,credentials:'omit',cache:'no-cache'});if(!res.ok)throw new Error('Reference load failed');blob=await res.blob()}finally{clearTimeout(timer)}
 if(!blob.size||blob.size>25*1024*1024)throw new Error('Reference file size unsupported: '+item.label);
 const sig=new Uint8Array(await blob.slice(0,8).arrayBuffer());
 if(String.fromCharCode(...sig.slice(0,5))==='%PDF-')return{...item,index,url,kind:item.kind||'PDF',pdf:true,blob,pdfData:new Uint8Array(await blob.arrayBuffer()),objectURL:URL.createObjectURL(blob),file:new File([blob],String(index+1).padStart(2,'0')+'-'+safeName(item.label)+'.pdf',{type:'application/pdf'})};
 const objectURL=URL.createObjectURL(blob),img=new Image();
 try{await timeout(new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=()=>reject(new Error('Image decode failed'));img.src=objectURL}),15000,'Image load timeout');if(!img.naturalWidth)throw new Error('Invalid image')}
 catch(e){URL.revokeObjectURL(objectURL);throw e}
 const scale=Math.min(1,1800/Math.max(img.naturalWidth,img.naturalHeight));
 const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(img.naturalWidth*scale));canvas.height=Math.max(1,Math.round(img.naturalHeight*scale));
 const c=canvas.getContext('2d',{alpha:false});c.fillStyle='#fff';c.fillRect(0,0,canvas.width,canvas.height);c.drawImage(img,0,0,canvas.width,canvas.height);
 const jpeg=await canvasJpeg(canvas);return{...item,index,url,objectURL,img,width:canvas.width,height:canvas.height,jpeg:jpeg.data,file:new File([jpeg.blob],String(index+1).padStart(2,'0')+'-'+safeName(item.label)+'.jpg',{type:'image/jpeg'})};
}
function fitImage(c,a,x,y,w,h){if(a.pdf){c.fillStyle='#edf1f5';c.fillRect(x,y,w,h);text(c,'PDF REFERENCE',x+18,y+h/2,w-36,26,true,red);return}const ratio=Math.min(w/a.img.naturalWidth,h/a.img.naturalHeight),iw=a.img.naturalWidth*ratio,ih=a.img.naturalHeight*ratio;c.drawImage(a.img,x+(w-iw)/2,y+(h-ih)/2,iw,ih)}
function receiptPages(d,assets){
 const pages=[];let page=canvasPage(),c=page.c,y=0;head(page,d);
 function next(){pages.push(page);page=canvasPage();c=page.c;head(page,d,true);y=183}
 function room(h){if(y+h>H-130)next()}
 function row(label,value){c.font='400 22px system-ui';const h=Math.max(34,wrap(c,value,720).length*31+10);room(h);text(c,label,64,y,185,19,false,muted);text(c,value,260,y,756,22,true);y+=h}
 y=176;row('Receipt no.',d.receipt_no);row('Prepared',new Date(d.generated_at||Date.now()).toLocaleString('en-IN'));row('Revision / Type','R'+d.revision_no+' · '+d.send_kind);
 y+=13;room(70);y=text(c,'CB '+d.cb_no,64,y,W-128,42,true)+5;
 row('Item code',d.item_no||'—');row('Item name',d.item_name||'—');row('Mode',d.fulfilment_method||'PURCHASE');row('Supplier',d.supplier_name||'Not mapped');row('Short note',d.short_note||'Please confirm availability / making status.');
 y+=8;room(210);c.fillStyle='#f9eef1';c.fillRect(64,y,W-128,97);text(c,'REQUIRED QUANTITY',84,y+31,480,18,true,red);text(c,quantity(d.required_qty,d.unit)+' '+d.unit,84,y+77,W-168,38,true);y+=130;
 text(c,'APPX PCS',64,y,300,19,false,muted);text(c,'CUTTING PCS',405,y,300,19,false,muted);text(c,'DIFFERENCE',744,y,260,19,false,muted);
 text(c,quantity(d.appx_pcs),64,y+42,300,33,true);text(c,count(d.cutting_pcs),405,y+42,300,33,true);
 const diff=Number(d.cutting_pcs)-Number(d.appx_pcs);text(c,Number(d.cutting_pcs)>0?(diff>0?'+':'')+quantity(diff):'—',744,y+42,260,33,true);y+=95;
 row('Set / Profile',(d.profile_labels||[]).join(', ')||'—');
 for(const r of d.rows||[]){const profile=[r.profile_label,r.art_no,r.category,r.sleeves,r.sizes].filter(Boolean).join(' · ');row('Profile details',profile);if((d.rows||[]).length>1)row('Profile quantity','Appx '+quantity(r.appx_pcs)+' / Cutting '+count(r.cutting_pcs)+' / Required '+quantity(r.required_qty,d.unit)+' '+d.unit)}
 if(assets.length){room(88);y+=10;y=text(c,'REFERENCE IMAGES · TAP TO OPEN',64,y,W-128,24,true)+12;
  for(let start=0;start<assets.length;start+=3){const set=assets.slice(start,start+3);c.font='400 18px system-ui';const labelLines=Math.max(...set.map(a=>wrap(c,(a.index+1)+'. '+a.label,278).length));const height=195+labelLines*25;room(height+18);
   for(let i=0;i<set.length;i++){const a=set[i],x=64+i*316;c.strokeStyle='#d7dee6';c.lineWidth=1;c.strokeRect(x,y,296,height);fitImage(c,a,x+8,y+10,280,165);text(c,(a.index+1)+'. '+a.label,x+9,y+196,278,18,true);page.links.push({x,y,w:296,h:height,asset:a.index})}y+=height+18;
  }
 }else{row('References','No enrolled reference image available.')}
 pages.push(page);return pages;
}
function detailPage(d,a){const page=canvasPage(),c=page.c;head(page,d,true);let y=text(c,(a.index+1)+'. '+a.label,64,184,W-128,27,true)+20;fitImage(c,a,64,y,W-128,H-260-y);text(c,'← BACK TO RECEIPT',64,H-147,440,22,true,red);page.links.push({x:64,y:H-175,w:440,h:47,toSummary:true});text(c,'OPEN ORIGINAL ↗',600,H-147,420,22,true,red);page.links.push({x:600,y:H-175,w:420,h:47,url:a.url});return page}
/* PDF 1.4: UTF-8 canvas text is rasterized once; thumbnails have local GoTo links.
   No CDN PDF library, no background text-only fallback, no external image dependency. */
function pdfBytes(pages,embedded=[]){
 const objects=[null,null,null];const ids=[],embeddedIds=new Map(),names=[];
 for(const asset of embedded){
  const streamId=objects.length;objects.push(join([bytes('<< /Type /EmbeddedFile /Subtype /application#2Fpdf /Length '+asset.pdfData.length+' >>\nstream\n'),asset.pdfData,bytes('\nendstream')]));
  const fileId=objects.length,name=String(asset.index+1).padStart(2,'0')+'-'+safeName(asset.label)+'.pdf';
  const hex=Array.from(bytes(name),b=>b.toString(16).padStart(2,'0')).join('');
  objects.push(bytes('<< /Type /Filespec /F <'+hex+'> /EF << /F '+streamId+' 0 R >> >>'));
  embeddedIds.set(asset.index,fileId);names.push('<'+hex+'> '+fileId+' 0 R');
 }
 objects[1]=bytes('<< /Type /Catalog /Pages 2 0 R'+(names.length?' /Names << /EmbeddedFiles << /Names ['+names.join(' ')+'] >> >>':'')+' >>');
 for(let i=0;i<pages.length;i++){ids.push(objects.length);objects.push(null,null,null)}
 objects[2]=bytes('<< /Type /Pages /Count '+pages.length+' /Kids ['+ids.map(id=>id+' 0 R').join(' ')+'] >>');
 for(let i=0;i<pages.length;i++){
  const page=pages[i],id=ids[i],annots=[];
  for(const link of page.links||[]){const rect=[link.x, H-link.y-link.h,link.x+link.w,H-link.y].map(v=>(v*595.28/W).toFixed(3)).join(' ');let action='';
   if(Number.isInteger(link.page)&&ids[link.page])action='/Dest ['+ids[link.page]+' 0 R /Fit]';
   else if(link.url){const url=safeURL(link.url);if(url)action='/A << /S /URI /URI <'+Array.from(bytes(url),b=>b.toString(16).padStart(2,'0')).join('')+'> >>'}
   if(embeddedIds.has(link.embedded)){annots.push(objects.length);objects.push(bytes('<< /Type /Annot /Subtype /FileAttachment /Rect ['+rect+'] /FS '+embeddedIds.get(link.embedded)+' 0 R /Name /Paperclip >>'));continue}
   if(!action)continue;annots.push(objects.length);objects.push(bytes('<< /Type /Annot /Subtype /Link /Rect ['+rect+'] /Border [0 0 0] '+action+' >>'));
  }
  const pw=595.28,ph=H*pw/W,stream=bytes('q '+pw+' 0 0 '+ph.toFixed(3)+' 0 0 cm /Im0 Do Q');
  objects[id]=bytes('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 '+pw+' '+ph.toFixed(3)+'] /Resources << /XObject << /Im0 '+(id+1)+' 0 R >> >> /Contents '+(id+2)+' 0 R'+(annots.length?' /Annots ['+annots.map(a=>a+' 0 R').join(' ')+']':'')+' >>');
  objects[id+1]=join([bytes('<< /Type /XObject /Subtype /Image /Width '+W+' /Height '+H+' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length '+page.jpeg.length+' >>\nstream\n'),page.jpeg,bytes('\nendstream')]);
  objects[id+2]=join([bytes('<< /Length '+stream.length+' >>\nstream\n'),stream,bytes('\nendstream')]);
 }
 const parts=[bytes('%PDF-1.4\n%REDZED\n')],offsets=[0];let offset=parts[0].length;
 for(let i=1;i<objects.length;i++){offsets[i]=offset;const part=join([bytes(i+' 0 obj\n'),objects[i],bytes('\nendobj\n')]);parts.push(part);offset+=part.length}
 const xref=offset;parts.push(bytes('xref\n0 '+objects.length+'\n0000000000 65535 f \n'+offsets.slice(1).map(o=>String(o).padStart(10,'0')+' 00000 n \n').join('')+'trailer\n<< /Size '+objects.length+' /Root 1 0 R >>\nstartxref\n'+xref+'\n%%EOF\n'));return join(parts);
}
function caption(d){return['REDZED · Requirement Receipt',d.receipt_no,'CB '+d.cb_no+' · '+[d.item_no,d.item_name].filter(Boolean).join(' · '),'Set: '+(d.profile_labels||[]).join(', '),'Appx '+quantity(d.appx_pcs)+' PCS | Cutting '+count(d.cutting_pcs),'Required: '+quantity(d.required_qty,d.unit)+' '+d.unit,'Mode: '+(d.fulfilment_method||'PURCHASE')+' | Supplier: '+(d.supplier_name||'Not mapped'),'Note: '+(d.short_note||'Please confirm availability / making status.'),'Photos और details receipt में हैं.'].join('\n')}
async function build(d,assets){
 const summaries=receiptPages(d,assets),pages=summaries.slice(),destinations=new Map(),summaryForAsset=new Map();
 summaries.forEach((p,i)=>p.links.forEach(l=>summaryForAsset.set(l.asset,i)));
 for(const a of assets){if(!a.pdf){destinations.set(a.index,pages.length);pages.push({detailAsset:a})}}
 summaries.forEach(p=>p.links.forEach(l=>{const a=assets.find(x=>x.index===l.asset);if(a?.pdf)l.embedded=a.index;else l.page=destinations.get(l.asset)}));
 const jpgFiles=[];let strip=null;
 if(summaries.length*H<=16000){strip=document.createElement('canvas');strip.width=W;strip.height=summaries.length*H}
 const stripContext=strip?.getContext('2d',{alpha:false});
 for(let i=0;i<pages.length;i++){if(pages[i].detailAsset){const a=pages[i].detailAsset;pages[i]=detailPage(d,a);pages[i].links.forEach(l=>{if(l.toSummary)l.page=summaryForAsset.get(a.index)||0})}footer(pages[i],d,i,pages.length);const jpg=await canvasJpeg(pages[i].canvas);pages[i].jpeg=jpg.data;pages[i].blob=jpg.blob;if(i<summaries.length&&stripContext)stripContext.drawImage(pages[i].canvas,0,i*H);pages[i].canvas.width=1;pages[i].canvas.height=1;pages[i].canvas=null;pages[i].c=null}
 if(stripContext){const jpg=await canvasJpeg(strip);jpgFiles.push(new File([jpg.blob],safeName(d.receipt_no)+'.jpg',{type:'image/jpeg'}));strip.width=1;strip.height=1}
 const pdf=new File([pdfBytes(pages,assets.filter(a=>a.pdf))],safeName(d.receipt_no)+'.pdf',{type:'application/pdf'});
 return{summaries,pages,jpgFiles,pdf,jpgPayload:jpgFiles,pdfPayload:[pdf],caption:caption(d)};
}
const state={context:null,assets:[],files:null,busy:false,pending:null,viewer:0,urls:[],returnFocus:null,generation:0,note:'Please confirm availability / making status.'};
function message(text,kind=''){const el=$('receiptMessage');el.textContent=text;el.className=kind}
function emit(type,extra={}){if(root.parent!==root)root.parent.postMessage({type,cb_id:state.context?.cb_id,...extra},location.origin)}
function client(){try{if(root.parent!==root&&root.parent.location.origin===location.origin&&root.parent.supabaseClient)return root.parent.supabaseClient}catch{}return root.supabaseClient}
async function rpc(name,args){if(root.RRReceiptClientReady)await root.RRReceiptClientReady;const c=client();if(!c?.rpc)throw new Error('Login connection उपलब्ध नहीं है. CB से receipt दोबारा खोलें.');const r=await c.rpc(name,args);if(r.error)throw r.error;return r.data}
function args(){const q=new URLSearchParams(location.search);return{p_cb_id:q.get('cb_id'),p_requirement_type:q.get('type'),p_source_id:q.get('source_id')}}
function fileShareSupported(files){try{const policy=document.permissionsPolicy||document.featurePolicy;if(policy?.allowsFeature&&!policy.allowsFeature('web-share'))return false;return root.isSecureContext&&typeof navigator.share==='function'&&typeof navigator.canShare==='function'&&navigator.canShare({files})}catch{return false}}
function syncButtons(){const ready=!!state.files&&!state.busy&&!state.pending;$('shareJpg').disabled=!ready||!state.files?.jpgFiles.length;$('shortNote').disabled=state.busy||!!state.pending;$('updateReceipt').disabled=state.busy||!!state.pending;$('sharePdf').disabled=!ready;$('shareImage').disabled=!ready;$('retryRecord').hidden=!state.pending;$('retryRecord').disabled=state.busy}
function revoke(){for(const url of state.urls)URL.revokeObjectURL(url);state.urls=[];for(const a of state.assets)if(a.objectURL)URL.revokeObjectURL(a.objectURL);state.assets=[]}
function downloadLink(file,label){const a=document.createElement('a'),url=URL.createObjectURL(file);state.urls.push(url);a.href=url;a.download=file.name;a.textContent=label||file.name;return a}
function render(){
 const pack=state.files;const target=$('receiptPages');target.replaceChildren();
 for(const page of pack.summaries){const div=document.createElement('div');div.className='paper';const img=document.createElement('img'),url=URL.createObjectURL(page.blob);state.urls.push(url);img.src=url;img.alt='Requirement receipt '+state.context.receipt_no;div.append(img);
  for(const l of page.links){const a=state.assets.find(x=>x.index===l.asset);if(!a)continue;const b=document.createElement('button');b.type='button';b.className='hotspot';b.setAttribute('aria-label','Open '+a.label);Object.assign(b.style,{left:l.x/W*100+'%',top:l.y/H*100+'%',width:l.w/W*100+'%',height:l.h/H*100+'%'});b.onclick=()=>openViewer(a.index,b);div.append(b)}target.append(div);
 }
 $('referenceSection').hidden=!state.assets.length;const grid=$('referenceGrid');grid.replaceChildren();
 for(const a of state.assets){const b=document.createElement('button');b.type='button';b.className='reference';const img=document.createElement(a.pdf?'span':'img');if(a.pdf){img.className='pdfIcon';img.textContent='PDF'}else{img.src=a.objectURL;img.alt=a.label}const label=document.createElement('span');label.textContent=(a.index+1)+'. '+a.label;b.append(img,label);b.onclick=()=>openViewer(a.index,b);grid.append(b)}
 const downloads=$('downloadFiles');downloads.replaceChildren(downloadLink(pack.pdf,'SAVE RECEIPT PDF'),...pack.jpgFiles.map((f,i)=>downloadLink(f,'SAVE RECEIPT JPG '+(i+1))));
 $('downloadOptions').hidden=false;const u=new URL(location.href);u.searchParams.delete('embed');$('openFullReceipt').href=u.href;
 $('receiptIdentity').textContent=state.context.receipt_no+' · '+state.assets.length+' reference file(s) · V2';
 syncButtons();
}
async function prepare(){
 if(state.busy||state.pending)return;state.busy=true;state.files=null;syncButtons();$('retryReceipt').hidden=true;message('Receipt और सभी enrolled तस्वीरें तैयार हो रही हैं…');revoke();const generation=++state.generation;
 try{
  const p=args();if(!p.p_cb_id||!p.p_source_id||!['MATERIAL','STICKER','METAL_ID'].includes(p.p_requirement_type))throw new Error('CB से सही requirement खोलें.');
  state.context=await rpc('rr_cb_requirement_receipt_context_v2',p);if(!state.context?.receipt_no)throw new Error('Receipt data उपलब्ध नहीं है.');state.context.short_note=state.note;$('shortNote').value=state.note;
  const items=state.context.attachments||[],loaded=new Array(items.length),errors=[];let cursor=0;
  await Promise.all(Array.from({length:Math.min(3,items.length)},async()=>{while(cursor<items.length){const i=cursor++;try{loaded[i]=await loadAsset(items[i],i)}catch(e){errors.push(items[i].label||'Reference '+(i+1));console.warn('Receipt media load',e)}}}));
  state.assets=loaded.filter(Boolean);if(errors.length)throw new Error(errors.length+' तस्वीरें load नहीं हुईं: '+errors.join(', ')+'. RETRY दबाएँ; बिना तस्वीरों के share नहीं किया गया.');
  if(generation!==state.generation)return;await document.fonts?.ready;state.files=await build(state.context,state.assets);render();
  message('Receipt तैयार है · '+state.assets.length+' reference file(s). Thumbnail दबाकर बड़ी image देखें; फिर SHARE JPG या SHARE PDF दबाएँ.'+(state.assets.some(a=>a.pdf)?' Original PDF references भी इसी receipt PDF में embedded हैं; attachment-capable PDF reader में खोलें.':''),'success');
 }catch(e){console.error('Receipt prepare',e);const msg=String(e?.message||'');message(/तस्वीरें load|CB से|Login connection|Receipt data/.test(msg)?msg:'Receipt तैयार नहीं हुई. Connection/Login check करके RETRY दबाएँ.','error');$('retryReceipt').hidden=false}
 finally{state.busy=false;syncButtons()}
}
function openViewer(index,origin){state.viewer=index;state.returnFocus=origin;showViewer();if(!$('imageViewer').open)$('imageViewer').showModal()}
function showViewer(){const a=state.assets.find(x=>x.index===state.viewer);if(!a)return;const stage=$('imageStage');stage.replaceChildren();stage.classList.remove('zoomed');$('zoomImage').textContent='ZOOM 2×';$('zoomImage').hidden=!!a.pdf;const img=document.createElement(a.pdf?'object':'img');if(a.pdf){img.type='application/pdf';img.data=a.objectURL}else{img.src=a.objectURL;img.alt=a.label}stage.append(img);$('imageTitle').textContent=a.label;$('imageNumber').textContent=(state.assets.indexOf(a)+1)+' / '+state.assets.length;$('originalImage').href=a.url;$('shareImage').textContent=a.pdf?'SHARE PDF FILE':'SHARE IMAGE'}
function closeViewer(){$('imageViewer').close();state.returnFocus?.focus()}
function moveViewer(delta){const i=state.assets.findIndex(a=>a.index===state.viewer);state.viewer=state.assets[(i+delta+state.assets.length)%state.assets.length].index;showViewer()}
async function record(){
 const pending=state.pending;if(!pending||state.busy)return;state.busy=true;syncButtons();
 try{
  const d=await rpc('rr_cb_requirement_receipt_record_v2',pending);
  if(!d.recorded){message('Files share हो गईं, लेकिन requirement इस बीच बदली है. नया receipt खोलें; पुरानी quantity को SENT नहीं किया.','error');state.pending=null;state.files=null;$('retryReceipt').hidden=false;return}
  state.pending=null;emit('RR_CB_RECEIPT_SHARED');message('आपकी पुष्टि पर requirement SENT mark हुई. यह WhatsApp delivery confirmation नहीं है.','success');
 }catch(e){$('retryRecord').textContent='RETRY SHARE RECORD';console.error('Receipt share record',e);message('Files share app को दे दी गईं, पर record save नहीं हुआ. RETRY SHARE RECORD दबाएँ—files दोबारा नहीं भेजी जाएँगी.','error')}
 finally{state.busy=false;syncButtons()}
}
/* Must remain synchronous until navigator.share(): no fetch, await, confirmation dialog or PDF work here. */
function share(format,singleAsset=null){
 if(!state.files||state.busy||state.pending)return;
 const files=singleAsset?[singleAsset.file]:format==='PDF'?state.files.pdfPayload:state.files.jpgPayload;
 if(!fileShareSupported(files)){message('इस window में file sharing उपलब्ध नहीं है. Receipt नए browser tab में खोलें, या SAVE RECEIPT PDF से file लें. केवल text नहीं भेजा गया.','error');$('downloadOptions').open=true;return}
 state.busy=true;syncButtons();const sharedCaption=state.files.caption+(singleAsset?'\nPhoto: '+singleAsset.label:'');let promise;
 try{promise=navigator.share({files,title:'REDZED '+state.context.receipt_no})}
 catch(e){failed(e);return}
 Promise.resolve(promise).then(()=>{
  state.busy=false;
  if(singleAsset){message('Reference file share app को दी गई. पूरी receipt का SENT count नहीं बदला.','success');syncButtons();return}
  state.pending={...args(),p_share_event_id:eventId(),p_snapshot_token:state.context.snapshot_token,p_format:format,p_caption:sharedCaption,p_files:files.map(f=>({name:f.name,type:f.type,size:f.size}))};
  $('retryRecord').textContent='भेज दिया · OK';message('Share-picker से लौट आए. Receipt WhatsApp पर भेज दी हो तो भेज दिया · OK करें. अभी SENT mark नहीं हुआ.');syncButtons();
 },failed);
 function failed(e){state.busy=false;message(e?.name==='AbortError'?'Share cancel हुई. SENT count नहीं बढ़ा.':'File share नहीं खुली. दोबारा Share दबाएँ या receipt नए tab में खोलें; SENT नहीं किया गया.',e?.name==='AbortError'?'':'error');syncButtons()}
}
async function updateNote(){
 if(state.busy||state.pending||!state.context)return;state.busy=true;syncButtons();
 try{state.context.short_note=state.note;await document.fonts?.ready;state.files=await build(state.context,state.assets);for(const url of state.urls)URL.revokeObjectURL(url);state.urls=[];render();message('Short note updated. तैयार receipt JPG/PDF share करें.','success')}
 catch(e){state.files=null;message('Receipt update नहीं हुई. UPDATE RECEIPT से दोबारा कोशिश करें.','error')}
 finally{state.busy=false;syncButtons()}
}
function init(){
 $('shortNote').value=state.note;$('shortNote').oninput=()=>{state.note=$('shortNote').value;state.files=null;syncButtons();message('Note बदला है. UPDATE RECEIPT दबाएँ, फिर share करें.')};$('updateReceipt').onclick=updateNote;
 $('shareJpg').onclick=()=>share('JPG');$('sharePdf').onclick=()=>share('PDF');$('retryReceipt').onclick=prepare;$('retryRecord').onclick=record;
 $('closeReceipt').onclick=()=>{if(state.busy)return;if(root.parent!==root)emit('RR_CB_RECEIPT_CLOSE');else history.back()};
 $('closeImage').onclick=closeViewer;$('previousImage').onclick=()=>moveViewer(-1);$('nextImage').onclick=()=>moveViewer(1);$('zoomImage').onclick=()=>{$('imageStage').classList.toggle('zoomed');$('zoomImage').textContent=$('imageStage').classList.contains('zoomed')?'FIT IMAGE':'ZOOM 2×'};
 $('shareImage').onclick=()=>{const a=state.assets.find(x=>x.index===state.viewer);share(a.pdf?'PDF':'IMAGES',a)};
 document.addEventListener('keydown',e=>{if(!$('imageViewer').open)return;if(e.key==='ArrowRight')moveViewer(1);if(e.key==='ArrowLeft')moveViewer(-1)});
 root.addEventListener('pagehide',revoke,{once:true});prepare();
}
root.RRReceiptV2={build,caption,pdfBytes,loadAsset,state,share,prepare};
if(typeof document!=='undefined'&&$('receiptApp'))init();
})(globalThis);
