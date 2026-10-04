"""Offline receipt regression: real Chromium DOM/canvas/JPG/PDF, mocked Supabase and native share.
No production credentials, no external fetches and no WhatsApp messages are used.
Run: python tests/e2e/test71_cb_receipt_browser.py
Needs Playwright (Chromium), Pillow and PyMuPDF. CHROMIUM_PATH can select an installed browser.
Outputs go to a temporary directory; RECEIPT_QA_OUT optionally chooses a report directory.
"""
import os, pathlib, tempfile, shutil
ROOT=pathlib.Path(__file__).resolve().parents[2]
QA=pathlib.Path(os.environ.get('RECEIPT_QA_OUT',tempfile.mkdtemp(prefix='redzed-receipt-qa-')))
chromium=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
CHROMIUM={'executable_path':chromium} if chromium else {}
def make_fixtures():
 from PIL import Image,ImageDraw,ImageFont
 from pathlib import Path
 import json,fitz
 p=QA; p.mkdir(parents=True,exist_ok=True)
 try: font=ImageFont.truetype('DejaVuSans.ttf',25)
 except OSError: font=ImageFont.load_default(size=25)
 for i,kind in enumerate(['STICKER','ART','PRINT','METAL ID','COLOUR']):
  im=Image.new('RGB',(640+60*i,430+35*i),['#f4e4d6','#e8eef4','#f4ecd8','#e1e2e5','#d6e6df'][i]);dr=ImageDraw.Draw(im)
  dr.rectangle((30,30,im.width-30,im.height-30),outline='#24364c',width=8)
  dr.text((60,90),kind+' — QA IMAGE',fill='#203045',font=font)
  dr.text((60,155),'Deterministic test fixture',fill='#203045',font=font)
  dr.ellipse((im.width-160,im.height-160,im.width-55,im.height-55),fill='#b52e42')
  im.save(p/f'image{i}.jpg',quality=90)
 doc=fitz.open();pg=doc.new_page();pg.insert_text((72,100),'QA PDF REFERENCE - NOT A PRODUCT DOCUMENT');doc.save(p/'reference.pdf');doc.close()
 ctx={'ok':True,'version':'RECEIPT_V2','cb_id':'009f1334-ab36-4569-902c-359c14e554ea','cb_no':'1011','requirement_type':'STICKER','source_id':'6ca162a2-b64f-45ca-91b7-00916180bd7e','item_no':'MSTK1','item_name':'TOPS LAISE STICKER','unit':'PCS','fulfilment_method':'PURCHASE','appx_pcs':398,'cutting_pcs':None,'required_qty':398,'supplier_name':'Ram Rib','revision_no':2,'profile_labels':['S4'],'receipt_no':'CB1011-STK-6ca162a2-R2','send_kind':'FIRST','send_count':0,'generated_at':'2026-10-04T08:00:00+00:00','snapshot_token':'test-snapshot-not-live','rows':[{'profile_label':'S4','art_no':'FCL2','category':'Flat Polo Collar','sleeves':'HALF','sizes':'L,XL,XXL','appx_pcs':398,'cutting_pcs':None,'required_qty':398}], 'attachments':[]}
 for i,(kind,code) in enumerate(zip(['STICKER','ART','PRINT','METAL ID','COLOUR'],['MSTK1','FCL2','PRT07','MID1','C1'])):
  ctx['attachments'].append({'kind':kind,'code':code,'label':f'{kind} · {code} · S4','url':f'http://127.0.0.1:8750/qa/image{i}.jpg'})
 (p/'context.json').write_text(json.dumps(ctx),encoding='utf8')

make_fixtures()
import asyncio,json,pathlib,copy,time,re,base64
from playwright.async_api import async_playwright
CTX=json.loads((QA/'context.json').read_text());RESULT=[]
URL='about:blank?cb_id='+CTX['cb_id']+'&type=STICKER&source_id='+CTX['source_id']
async def setup(browser, ctx=None, mode='success', supported=True, slow=False):
 p=await browser.new_page(viewport={'width':393,'height':852},device_scale_factor=1)
 errors=[];p.on('pageerror',lambda e:errors.append(str(e)))
 context=copy.deepcopy(ctx or CTX)
 for a in context["attachments"]:a["url"]=a["url"].replace("http://127.0.0.1:8750/","https://fixture.invalid/")
 await p.add_init_script('''window.calls=[];window.records=[];window.nativeMode=%s;window.recordFail=false;window.recordMismatch=false;window.supported=%s;
 Object.defineProperty(window,'isSecureContext',{value:true,configurable:true});Object.defineProperty(document,'permissionsPolicy',{value:{allowsFeature:()=>true},configurable:true});
 Object.defineProperty(navigator,'canShare',{value:({files})=>window.supported&&!!files?.length,configurable:true});
 Object.defineProperty(navigator,'share',{value:function(x){window.calls.push({activation:navigator.userActivation.isActive,types:x.files.map(f=>f.type),names:x.files.map(f=>f.name),sizes:x.files.map(f=>f.size),text:x.text});window.lastShared=x;return window.nativeMode==='cancel'?Promise.reject(new DOMException('cancel','AbortError')):window.nativeMode==='error'?Promise.reject(new DOMException('blocked','NotAllowedError')):new Promise(r=>setTimeout(r,150));},configurable:true});'''%(json.dumps(mode),str(supported).lower()))
 cfg='window.fixture='+json.dumps(context)+';window.supabaseClient={rpc:async(n,p)=>{if(n.includes("context"))return{data:window.fixture,error:null};window.records.push(p);if(window.recordFail)return{data:null,error:{message:"test record unavailable"}};return{data:{ok:true,recorded:!window.recordMismatch,receipt_no:window.fixture.receipt_no},error:null}}};'
 fixtures={f.name:base64.b64encode(f.read_bytes()).decode() for f in (QA).iterdir() if f.name.startswith('image') or f.name=='reference.pdf'}
 fetch='window.fixtureBytes='+json.dumps(fixtures)+';window.fetch=async (url)=>{const k=new URL(url).pathname.split("/").pop();'+('if(k==="image0.jpg")await new Promise(r=>setTimeout(r,6200));' if slow else '')+'const data=window.fixtureBytes[k];if(!data)return new Response("missing",{status:404});const raw=atob(data),out=new Uint8Array(raw.length);for(let i=0;i<raw.length;i++)out[i]=raw.charCodeAt(i);return new Response(out,{headers:{"Content-Type":k.endsWith("pdf")?"application/pdf":"image/jpeg"}})};'
 await p.goto(URL)
 html=(ROOT/'test71-cb-receipt.html').read_text()
 html=re.sub(r'<script[^>]*>.*?</script>','',html,flags=re.S)
 html=re.sub(r'<link[^>]*>','',html)
 await p.set_content(html)
 await p.add_style_tag(content=(ROOT/'test71-cb-receipt.css').read_text())
 await p.add_script_tag(content=cfg+fetch)
 await p.add_script_tag(content=(ROOT/'test71-cb-receipt.js').read_text())
 await p.wait_for_function('window.RRReceiptV2 && !RRReceiptV2.state.busy',timeout=30000)
 return p,errors

def ok(name,cond,extra=None):
 assert cond,(name,extra)
 RESULT.append({'test':name,'pass':True,**({'details':extra} if extra else {})})

async def main():
 async with async_playwright() as pw:
  browser=await pw.chromium.launch(**CHROMIUM,headless=True,args=['--no-sandbox'])
  p,errs=await setup(browser)
  ok('receipt prepares with five enrolled media types',await p.locator('.reference').count()==5,errs)
  ok('mobile page has no horizontal overflow',await p.evaluate('document.documentElement.scrollWidth<=innerWidth'))
  await p.screenshot(path=str(QA/'receipt-mobile.png'),full_page=True)
  pdf=await p.evaluate('async()=>Array.from(new Uint8Array(await RRReceiptV2.state.files.pdf.arrayBuffer()))')
  (QA/'receipt-fixture.pdf').write_bytes(bytes(pdf))
  jpg=await p.evaluate('async()=>Array.from(new Uint8Array(await RRReceiptV2.state.files.jpgFiles[0].arrayBuffer()))')
  (QA/'receipt-fixture.jpg').write_bytes(bytes(jpg))
  await p.locator('.hotspot').first.click();ok('receipt thumbnail opens full image',await p.locator('#imageViewer').evaluate('(d)=>d.open'))
  await p.locator('#zoomImage').click();ok('image zoom works',await p.locator('#imageStage').evaluate('(x)=>x.classList.contains("zoomed")'))
  await p.locator('#nextImage').click();ok('gallery advances to next reference',await p.locator('#imageNumber').inner_text()=='2 / 5')
  await p.locator('#closeImage').click()
  await p.locator('#shareJpg').click();await p.wait_for_timeout(500)
  call=await p.evaluate('calls[0]');ok('JPG share attaches actual files and user gesture',call['activation'] and len(call['sizes'])>=6 and all(n>1000 for n in call['sizes']) and set(call['types'])=={'image/jpeg'},call)
  ok('native JPG handoff records once',await p.evaluate('records.length')==1)
  await p.locator('#sharePdf').click();await p.wait_for_timeout(400)
  call=await p.evaluate('calls[1]');ok('PDF shared separately, not mixed with image MIME',call['types']==['application/pdf'] and call['sizes'][0]>1000)
  ok('no browser runtime errors',not errs,errs)
  await p.close()
  for mode in ['cancel','error']:
   p,e=await setup(browser,mode=mode);await p.locator('#shareJpg').click();await p.wait_for_timeout(300)
   ok(mode+' does not increment SENT or auto-fallback',await p.evaluate('records.length')==0 and await p.evaluate('calls.length')==1)
   await p.close()
  p,e=await setup(browser,supported=False);await p.locator('#shareJpg').click();await p.wait_for_timeout(100)
  ok('unsupported file share blocks text-only fallback',await p.evaluate('calls.length===0&&records.length===0') and await p.locator('#downloadOptions').evaluate('(d)=>d.open'))
  await p.close()
  missing=copy.deepcopy(CTX);missing['attachments'][0]['url']='http://127.0.0.1:8750/no-image.jpg'
  p,e=await setup(browser,ctx=missing);ok('missing approved image is reported, never silently skipped',await p.locator('#shareJpg').is_disabled() and 'तस्वीरें load नहीं हुईं' in await p.locator('#receiptMessage').inner_text());await p.close()
  noPhone=copy.deepcopy(CTX);noPhone['supplier_name']=None
  p,e=await setup(browser,ctx=noPhone);await p.locator('#sharePdf').click();await p.wait_for_timeout(400);ok('missing supplier phone/name does not block file handoff',await p.evaluate('calls.length===1&&records.length===1'));await p.close()
  p,e=await setup(browser,slow=True);await p.locator('#shareJpg').click();await p.wait_for_timeout(400);ok('slow media preparation preserves fresh Share click activation',await p.evaluate('calls[0].activation'));await p.close()
  p,e=await setup(browser);await p.evaluate('window.recordFail=true');await p.locator('#sharePdf').click();await p.wait_for_timeout(400);await p.evaluate('window.recordFail=false');await p.locator('#retryRecord').click();await p.wait_for_timeout(200)
  ok('retry log does not re-share files and reuses idempotency event',await p.evaluate('calls.length===1&&records.length===2&&records[0].p_share_event_id===records[1].p_share_event_id'));await p.close()
  many=copy.deepcopy(CTX);many['attachments']*=2
  p,e=await setup(browser,ctx=many);ok('more than eight references are retained',await p.locator('.reference').count()==10);await p.close()
  docs=copy.deepcopy(CTX);docs['attachments'].append({'kind':'PRINT','label':'PRINT · source PDF','url':'http://127.0.0.1:8750/qa/reference.pdf'})
  p,e=await setup(browser,ctx=docs);await p.locator('#sharePdf').click();await p.wait_for_timeout(400);ok('original PDF references remain actual additional PDF files',await p.evaluate('calls[0].types.length===2&&calls[0].types.every(t=>t==="application/pdf")'));await p.close()
  await browser.close()
 (QA/'browser-results.json').write_text(json.dumps(RESULT,indent=2,ensure_ascii=False))
 print(json.dumps({'passed':len(RESULT),'tests':[r['test'] for r in RESULT]},ensure_ascii=False,indent=2))


def test_router():
 from playwright.sync_api import sync_playwright
 from pathlib import Path
 import json
 code=(ROOT/'test70-action-return-v110.js').read_text();res=[]
 with sync_playwright() as pw:
  b=pw.chromium.launch(**CHROMIUM,headless=True,args=['--no-sandbox']);p=b.new_page()
  p.set_content('<p id="msg"></p><button id="refreshDerivedRequirement">Refresh</button><div id="derivedRequirementSummary"><button class="wa-send" data-type="STICKER" data-source-id="6ca162a2-b64f-45ca-91b7-00916180bd7e">SEND WHATSAPP</button></div>')
  p.evaluate("window.oldSend=0;window.flushed=0;document.querySelector('.wa-send').onclick=()=>oldSend++;document.getElementById('refreshDerivedRequirement').onclick=async()=>{await new Promise(r=>setTimeout(r,120));window.flushed++;document.getElementById('msg').className='message ok'};void 0")
  p.evaluate('(code)=>new Function("location",code)({pathname:"/real-cb-new-v9130-fix2.html",search:"?cb_id=009f1334-ab36-4569-902c-359c14e554ea",href:"https://fixture.invalid/real-cb-new-v9130-fix2.html?cb_id=009f1334-ab36-4569-902c-359c14e554ea",origin:"https://fixture.invalid"})',code)
  p.locator('.wa-send').click();p.wait_for_timeout(400)
  checks={
  'old text-only callback disconnected':p.evaluate('oldSend===0'),
  'original autosave refresh awaited':p.evaluate('flushed===1'),
  'new receipt page opened':p.locator('dialog iframe').get_attribute('src').startswith('https://fixture.invalid/test71-cb-receipt.html?'),
  'nested receipt delegates web-share': 'web-share' in p.locator('dialog iframe').get_attribute('allow')}
  p.evaluate("document.querySelector('.wa-send').dispatchEvent(new MouseEvent('click',{bubbles:true}))")
  checks['double tap creates only one receipt']=p.locator('dialog').count()==1
  p.locator('dialog button').click();checks['close returns to same form']=p.locator('dialog').count()==0 and p.locator('#derivedRequirementSummary').count()==1
  for name,good in checks.items():assert good,name;res.append({'test':name,'pass':True})
  p.close();p=b.new_page();p.set_content('<p>Other form</p>');p.evaluate('(code)=>new Function("location",code)({pathname:"/other.html",search:"",href:"https://fixture.invalid/other.html",origin:"https://fixture.invalid"})',code)
  assert p.evaluate('!window.__CB_RECEIPT_ROUTER_V2__');res.append({'test':'router leaves unrelated forms untouched','pass':True});b.close()
 (QA/'router-results.json').write_text(json.dumps(res,indent=2));print(json.dumps({'passed':len(res),'checks':res},indent=2))

def test_pdf():
 import fitz,json,re
 doc=fitz.open(QA/'receipt-fixture.pdf')
 page_refs={p.xref for p in doc}
 internal=external=0
 for page in doc:
  for link in page.get_links():
   raw=doc.xref_object(link['xref'])
   dest=re.search(r'/Dest\s*\[\s*(\d+)\s+0\s+R',raw)
   if dest:
    assert int(dest.group(1)) in page_refs,raw
    internal+=1
   elif '/URI' in raw:external+=1
 assert len(doc)==6 and internal==10 and external==5
 embedded=sum(len(page.get_images()) for page in doc)
 assert embedded==6
 doc[0].get_pixmap(matrix=fitz.Matrix(1,1)).save(QA/'pdf-page-1.png')
 doc[1].get_pixmap(matrix=fitz.Matrix(1,1)).save(QA/'pdf-page-2.png')
 result={'pages':len(doc),'embedded_images':embedded,'internal_links':internal,
 'external_original_links':external,'all_destinations_valid':True,'parser':'PyMuPDF '+fitz.VersionBind}
 (QA/'pdf-results.json').write_text(json.dumps(result,indent=2))
 doc.close();print(json.dumps(result,indent=2))

if __name__=='__main__':
 asyncio.run(main())
 test_router()
 test_pdf()
 print('Reports: '+str(QA))
