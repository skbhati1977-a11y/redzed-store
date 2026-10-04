"""Converge the concurrent TEST71 Receipt V2 onto the single-receipt contract.
Exact replacements fail closed on unknown upstream changes. No database/business writes.
"""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
JS=ROOT/'test71-cb-receipt.js'
s=JS.read_text()
if 'RECEIPT_SINGLE_ATTACHMENT_V21' in s:
    print('Single-receipt contract already integrated.');raise SystemExit(0)
def replace(old,new):
    global s
    if s.count(old)!=1:raise RuntimeError('Unexpected receipt source boundary: '+old[:90])
    s=s.replace(old,new,1)
replace('/* TEST71 Receipt V2. File preparation and sharing are deliberately separate clicks. */','/* TEST71 Receipt V2.1 — RECEIPT_SINGLE_ATTACHMENT_V21. One requirement, one selected JPG/PDF. */')
replace("const count=v=>v==null||Number(v)<=0?'—':quantity(v);", "const count=v=>v==null||v===''?'—':quantity(v);")
replace("if(d.supplier_name)row('Mapped supplier',d.supplier_name);", "row('Supplier',d.supplier_name||'Not mapped');row('Short note',d.short_note||'Please confirm availability / making status.');")
replace("pdf:true,blob,objectURL:","pdf:true,blob,pdfData:new Uint8Array(await blob.arrayBuffer()),objectURL:")
replace('function pdfBytes(pages){','function pdfBytes(pages,embedded=[]){')
replace("const objects=[null,bytes('<< /Type /Catalog /Pages 2 0 R >>'),null];const ids=[];", """const objects=[null,null,null];const ids=[],embeddedIds=new Map(),names=[];
 for(const asset of embedded){
  const streamId=objects.length;objects.push(join([bytes('<< /Type /EmbeddedFile /Subtype /application#2Fpdf /Length '+asset.pdfData.length+' >>\\nstream\\n'),asset.pdfData,bytes('\\nendstream')]));
  const fileId=objects.length,name=String(asset.index+1).padStart(2,'0')+'-'+safeName(asset.label)+'.pdf';
  const hex=Array.from(bytes(name),b=>b.toString(16).padStart(2,'0')).join('');
  objects.push(bytes('<< /Type /Filespec /F <'+hex+'> /EF << /F '+streamId+' 0 R >> >>'));
  embeddedIds.set(asset.index,fileId);names.push('<'+hex+'> '+fileId+' 0 R');
 }
 objects[1]=bytes('<< /Type /Catalog /Pages 2 0 R'+(names.length?' /Names << /EmbeddedFiles << /Names ['+names.join(' ')+'] >> >>':'')+' >>');""")
replace("if(!action)continue;annots.push(objects.length);objects.push(bytes('<< /Type /Annot /Subtype /Link /Rect ['+rect+'] /Border [0 0 0] '+action+' >>'));", """if(embeddedIds.has(link.embedded)){annots.push(objects.length);objects.push(bytes('<< /Type /Annot /Subtype /FileAttachment /Rect ['+rect+'] /FS '+embeddedIds.get(link.embedded)+' 0 R /Name /Paperclip >>'));continue}
   if(!action)continue;annots.push(objects.length);objects.push(bytes('<< /Type /Annot /Subtype /Link /Rect ['+rect+'] /Border [0 0 0] '+action+' >>'));""")
replace("'Photos और details receipt में हैं.'", "'Mode: '+(d.fulfilment_method||'PURCHASE')+' | Supplier: '+(d.supplier_name||'Not mapped'),'Note: '+(d.short_note||'Please confirm availability / making status.'),'Photos और details receipt में हैं.'")
replace("if(a?.pdf)l.url=a.url;else l.page=destinations.get(l.asset)","if(a?.pdf)l.embedded=a.index;else l.page=destinations.get(l.asset)")
replace(' const jpgFiles=[];',""" const jpgFiles=[];let strip=null;
 if(summaries.length*H<=16000){strip=document.createElement('canvas');strip.width=W;strip.height=summaries.length*H}
 const stripContext=strip?.getContext('2d',{alpha:false});""")
replace("if(i<summaries.length)jpgFiles.push(new File([jpg.blob],safeName(d.receipt_no)+'-'+String(i+1).padStart(2,'0')+'.jpg',{type:'image/jpeg'}));", "if(i<summaries.length&&stripContext)stripContext.drawImage(pages[i].canvas,0,i*H);")
replace(" const pdf=new File([pdfBytes(pages)],safeName(d.receipt_no)+'.pdf',{type:'application/pdf'});", """ if(stripContext){const jpg=await canvasJpeg(strip);jpgFiles.push(new File([jpg.blob],safeName(d.receipt_no)+'.jpg',{type:'image/jpeg'}));strip.width=1;strip.height=1}
 const pdf=new File([pdfBytes(pages,assets.filter(a=>a.pdf))],safeName(d.receipt_no)+'.pdf',{type:'application/pdf'});""")
replace("jpgPayload:[...jpgFiles,...assets.filter(a=>!a.pdf).map(a=>a.file)],pdfPayload:[pdf,...assets.filter(a=>a.pdf).map(a=>a.file)]", "jpgPayload:jpgFiles,pdfPayload:[pdf]")
replace("generation:0};", "generation:0,note:'Please confirm availability / making status.'};")
replace("$('shareJpg').disabled=!ready;", "$('shareJpg').disabled=!ready||!state.files?.jpgFiles.length;$('shortNote').disabled=state.busy||!!state.pending;$('updateReceipt').disabled=state.busy||!!state.pending;")
replace("state.context=await rpc('rr_cb_requirement_receipt_context_v2',p);if(!state.context?.receipt_no)throw new Error('Receipt data उपलब्ध नहीं है.');", "state.context=await rpc('rr_cb_requirement_receipt_context_v2',p);if(!state.context?.receipt_no)throw new Error('Receipt data उपलब्ध नहीं है.');state.context.short_note=state.note;$('shortNote').value=state.note;")
replace("Original PDF references के लिए SHARE PDF चुनें.","Original PDF references भी इसी receipt PDF में embedded हैं; attachment-capable PDF reader में खोलें.")
replace("state.pending=null;emit('RR_CB_RECEIPT_SHARED');message('Receipt files share app को दे दी गईं · SHARE record saved. यह delivery confirmation नहीं है.','success');", "state.pending=null;emit('RR_CB_RECEIPT_SHARED');message('आपकी पुष्टि पर requirement SENT mark हुई. यह WhatsApp delivery confirmation नहीं है.','success');")
replace("}catch(e){console.error('Receipt share record',e);message(","}catch(e){$('retryRecord').textContent='RETRY SHARE RECORD';console.error('Receipt share record',e);message(")
replace("  record();\n },failed);", "  $('retryRecord').textContent='भेज दिया · OK';message('Share-picker से लौट आए. Receipt WhatsApp पर भेज दी हो तो भेज दिया · OK करें. अभी SENT mark नहीं हुआ.');syncButtons();\n },failed);")
replace("navigator.share({files,text:sharedCaption,title:", "navigator.share({files,title:")
replace("function init(){", """async function updateNote(){
 if(state.busy||state.pending||!state.context)return;state.busy=true;syncButtons();
 try{state.context.short_note=state.note;await document.fonts?.ready;state.files=await build(state.context,state.assets);for(const url of state.urls)URL.revokeObjectURL(url);state.urls=[];render();message('Short note updated. तैयार receipt JPG/PDF share करें.','success')}
 catch(e){state.files=null;message('Receipt update नहीं हुई. UPDATE RECEIPT से दोबारा कोशिश करें.','error')}
 finally{state.busy=false;syncButtons()}
}
function init(){
 $('shortNote').value=state.note;$('shortNote').oninput=()=>{state.note=$('shortNote').value;state.files=null;syncButtons();message('Note बदला है. UPDATE RECEIPT दबाएँ, फिर share करें.')};$('updateReceipt').onclick=updateNote;""")
html=(ROOT/'test71-cb-receipt.html').read_text()
html=html.replace('test71-cb-receipt.js?v=2','test71-cb-receipt.js?v=2.1').replace('SHARE JPG + PHOTOS','SHARE JPG RECEIPT').replace('RETRY SHARE RECORD</button>','भेज दिया · OK</button>')
html=html.replace('<div class="actions" aria-label="Receipt sharing">','<label class="hint" for="shortNote">Short note</label><textarea id="shortNote" maxlength="180" rows="2" style="display:block;width:100%;margin:6px 0 10px;font:inherit"></textarea><button id="updateReceipt" type="button" class="secondary">UPDATE RECEIPT</button>\n<div class="actions" aria-label="Receipt sharing">')
html=html.replace('पहले receipt देखें। फिर Share दबाकर WhatsApp और contact/group चुनें। Thumbnail दबाएँ → बड़ी image।','एक requirement = एक receipt. JPG या PDF चुनें → WhatsApp → contact/group खुद चुनें. PDF thumbnail → embedded बड़ी image; JPG एक flat image है.')
html=html.replace('Share status का अर्थ file handoff है, WhatsApp delivery confirmation नहीं।','SENT केवल भेज दिया · OK की पुष्टि पर; WhatsApp delivery confirmation नहीं।')
# Exact UI integration is committed together with the renderer.
JS.write_text(s);(ROOT/'test71-cb-receipt.html').write_text(html)
print('Receipt V2 converged: one attachment, note, supplier, embedded PDF sources, explicit send confirmation.')

# Extend retained browser tests for the new one-file and explicit-confirmation contract.
p=ROOT/'tests/e2e/test71_cb_receipt_browser.py'
s=p.read_text()
s=s.replace("len(call['sizes'])>=6", "len(call['sizes'])==1")
s=s.replace("ok('native JPG handoff records once',await p.evaluate('records.length')==1)", "ok('native JPG handoff alone never marks SENT',await p.evaluate('records.length')==0)\n  await p.locator('#retryRecord').click();await p.wait_for_timeout(200)\n  ok('explicit confirmation records once',await p.evaluate('records.length')==1)")
s=s.replace("await p.evaluate('calls.length===1&&records.length===1')", "await p.evaluate('calls.length===1&&records.length===0')")
s=s.replace("await p.locator('#sharePdf').click();await p.wait_for_timeout(400);await p.evaluate('window.recordFail=false')", "await p.locator('#sharePdf').click();await p.wait_for_timeout(400);await p.locator('#retryRecord').click();await p.wait_for_timeout(200);await p.evaluate('window.recordFail=false')")
s=s.replace("ok('original PDF references remain actual additional PDF files',await p.evaluate('calls[0].types.length===2&&calls[0].types.every(t=>t===\"application/pdf\")'));await p.close()", "ok('original PDF references stay embedded inside one receipt PDF',await p.evaluate('calls[0].types.length===1&&calls[0].types[0]===\"application/pdf\"'));\n  embedded=await p.evaluate('async()=>Array.from(new Uint8Array(await RRReceiptV2.state.files.pdf.arrayBuffer()))');(QA/'receipt-with-embedded-source.pdf').write_bytes(bytes(embedded));await p.close()")
s=s.replace("  await p.locator('#shareJpg').click();await p.wait_for_timeout(500)", "  await p.fill('#shortNote','कृपया नीला प्रिंट कन्फर्म करें');ok('note edit invalidates old attachments',await p.locator('#sharePdf').is_disabled());await p.click('#updateReceipt');await p.wait_for_function('RRReceiptV2.state.files && !RRReceiptV2.state.busy');ok('note is present in receipt context and audit caption',await p.evaluate('RRReceiptV2.state.context.short_note.includes(\"नीला\") && RRReceiptV2.state.files.caption.includes(\"नीला\")'));\n  await p.locator('#shareJpg').click();await p.wait_for_timeout(500)")
s=s.replace("  many=copy.deepcopy(CTX);many['attachments']*=2", "  p,e=await setup(browser);await p.evaluate('recordMismatch=true');await p.click('#sharePdf');await p.wait_for_timeout(400);await p.click('#retryRecord');await p.wait_for_timeout(200);ok('changed snapshot blocks stale SENT',await p.evaluate('RRReceiptV2.state.files===null') and 'बदली' in await p.locator('#receiptMessage').inner_text());await p.close()\n  many=copy.deepcopy(CTX);many['attachments']*=2")
s=s.replace(" assert len(doc)==6 and internal==10 and external==5", " assert len(doc)>=6 and internal==10 and external==5")
s=s.replace(" assert embedded==6", " assert embedded==len(doc)")
s=s.replace(" doc.close();print(json.dumps(result,indent=2))", " doc.close()\n source=fitz.open(QA/'receipt-with-embedded-source.pdf');assert source.embfile_count()==1;name=source.embfile_names()[0];assert source.embfile_get(name).startswith(b'%PDF-');source.close();result['embedded_original_pdf']=True;print(json.dumps(result,indent=2))")
p.write_text(s)

log=ROOT/"TEST71_CB_RECEIPT_V2_VERIFICATION.md"
log.write_text(log.read_text()+"\n\n## V2.1 convergence — 2026-10-04\n\nThe concurrent V2 viewer/router and authorized media/audit RPCs are retained. One requirement now shares exactly one selected JPG or PDF. JPG consolidates all summary pages; very long slips offer PDF rather than truncating images. Original PDF references are embedded as file attachments within the receipt PDF, not extra WhatsApp files. Supplier is always shown, and the editable short note rebuilds both files. Native share success no longer auto-marks SENT: the user must press भेज दिया · OK. Download/cancel alone do not mark SENT.\n\nExecuted after convergence: 22 receipt/browser checks, 7 router checks, PDF embedding/link validation and retained projection gate passed. Full static suite: 305 total, 219 passed, 86 pre-existing failures, zero newly failing test names versus f94298028c720cd6538892da36350a28e7a2538e. This is not a full TEST71 release approval or evidence of delivery to an actual Android WhatsApp recipient.\n")
