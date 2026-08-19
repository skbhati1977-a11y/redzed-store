(()=>{
'use strict';
if(window.__RR_UPM_ALTER_FORM_9253__)return;
window.__RR_UPM_ALTER_FORM_9253__=true;

const q=new URLSearchParams(location.search);
const raw=String(q.get('dept')||'').trim().toUpperCase();
const ALIAS={KR:'STITCHING',KARIGAR:'STITCHING',STITCH:'STITCHING',STITCHING:'STITCHING',OV:'OVERLOCK',OVERLOCK:'OVERLOCK',FLD:'FOLDING',FLATLOCK:'FOLDING',FOLDING:'FOLDING',KAAJ:'KAAJ',KAJ:'KAAJ',BUTTON:'BUTTON',BTN:'BUTTON',KAAJ_BUTTON:'KAAJ_BUTTON',TEAK:'TEAK_TANKI',TANKI:'TEAK_TANKI',TEAK_TANKI:'TEAK_TANKI',THREAD_CUT:'THREAD_CUT',THREAD_CUTTING:'THREAD_CUT',TH_CUT:'THREAD_CUT',QC:'QC',CHECKING:'QC',PRESS:'PRESS',FINISHING:'PRESS',PRINT:'PRINTING',PRINTING:'PRINTING',STICKER:'STICKER',ID:'METAL_ID',ID_WORK:'METAL_ID',METAL_ID:'METAL_ID',PACK:'PACKING',PACKING:'PACKING',DESPATCH:'DESPATCH',DISPATCH:'DESPATCH',CUT:'CUTTING',CUTTING:'CUTTING'};
const dept=ALIAS[raw]||raw;
if(!dept)return;

const up=v=>String(v||'').trim().toUpperCase();
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const client=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb||null;
const uid=()=>globalThis.crypto?.randomUUID?.()||`${Date.now()}-${Math.random().toString(16).slice(2)}`;
let busy=false;

function injectStyle(){
 if(document.getElementById('rrUpmAlter9253Style'))return;
 const s=document.createElement('style');s.id='rrUpmAlter9253Style';s.textContent=`
 .rr-alt9253{position:fixed;inset:0;z-index:2147483000;background:#000d;display:flex;align-items:flex-end;justify-content:center}
 .rr-alt9253.hidden{display:none!important}.rr-alt9253-sheet{width:min(760px,100%);max-height:97vh;overflow:auto;background:#10131a;border:1px solid #3a414d;border-radius:20px 20px 0 0;padding:14px;color:#fff}
 .rr-alt9253-head{display:flex;justify-content:space-between;gap:10px;align-items:flex-start;position:sticky;top:-14px;z-index:3;background:#10131af5;padding:8px 0 10px}.rr-alt9253-head h2{margin:2px 0}.rr-alt9253-meta{color:#9ec5ff;font-weight:850}.rr-alt9253-close{width:44px;height:44px;border-radius:12px}
 .rr-alt9253-note,.rr-alt9253-msg{padding:10px;border-radius:10px;background:#1b2029;margin:8px 0;color:#cfd6e0}.rr-alt9253-msg.err{background:#3b171c;color:#ffb1ba}.rr-alt9253-msg.ok{background:#14331f;color:#b9efc8}
 .rr-alt9253-group{border:1px solid #303641;border-radius:13px;background:#151922;padding:10px;margin:9px 0}.rr-alt9253-ghead{display:grid;grid-template-columns:58px 1fr;gap:9px;align-items:center;margin-bottom:8px}.rr-alt9253-ghead img,.rr-alt9253-ph{width:56px;height:56px;border-radius:9px;object-fit:cover;border:1px solid #43516a;background:#222a34}.rr-alt9253-ph{display:grid;place-items:center;font-size:9px;color:#98a2b3}.rr-alt9253-ghead b{font-size:17px}.rr-alt9253-ghead small{display:block;color:#98a2b3;margin-top:3px}
 .rr-alt9253-sizes{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:7px}.rr-alt9253-size{display:grid;gap:4px;padding:8px;border:1px solid #303641;border-radius:10px;background:#0d1015}.rr-alt9253-size span{font-size:11px;color:#cbd5e1}.rr-alt9253-size small{color:#56efb2}.rr-alt9253-size input{width:100%;min-height:42px;font-size:16px;background:#202632}
 .rr-alt9253-field{display:grid;gap:5px;margin:10px 0}.rr-alt9253-field>span{font-size:12px;color:#aab4c2;font-weight:850}.rr-alt9253-field select,.rr-alt9253-field input,.rr-alt9253-field textarea{width:100%;min-height:48px;font-size:16px;background:#202632;color:#fff;border:1px solid #3b4554;border-radius:11px;padding:10px}.rr-alt9253-field textarea{min-height:78px}
 .rr-alt9253-check{display:flex;align-items:center;gap:10px;padding:11px;border:1px solid #3a414d;border-radius:10px;background:#171c25;margin:10px 0}.rr-alt9253-check input{width:22px;height:22px}.rr-alt9253-save{width:100%;min-height:56px;background:#493915!important;border:1px solid #8a6b2b!important;color:#ffe29b!important;font-size:16px;font-weight:950;position:sticky;bottom:0;z-index:4}.rr-alt9253-save:disabled{opacity:.55}
 @media(max-width:560px){.rr-alt9253-sizes{grid-template-columns:repeat(2,minmax(0,1fr))}.rr-alt9253-sheet{padding:11px}.rr-alt9253-head{top:-11px}}
 `;document.head.appendChild(s);
}

async function rpc(name,args={}){const c=client();if(!c)throw new Error('Supabase client not ready.');const r=await c.rpc(name,args);if(r.error)throw r.error;return r.data}
function message(text='',type=''){const el=document.getElementById('rrAlt9253Msg');if(!el)return;el.textContent=text;el.className=`rr-alt9253-msg ${type}`.trim()}
function close(){document.getElementById('rrAlt9253')?.remove();document.body.style.overflow='';busy=false}

function normalizeSizes(value){
 let rows=value;
 if(typeof rows==='string'){try{rows=JSON.parse(rows)}catch(_){rows=[]}}
 if(!Array.isArray(rows))return [];
 return rows.map(x=>({size_code:up(x?.size_code||x?.size||x?.code),qty:Number(x?.qty??x?.quantity??x?.cutting_qty??0)})).filter(x=>x.size_code);
}

async function resolveLot(lotNo){
 let snap=null;
 try{snap=await rpc('rr_upm_department_colour_due_card_v9167',{p_department_code:dept})}catch(_){snap=await rpc('rr_upm_department_colour_due_card_v9109',{p_department_code:dept})}
 const lot=(snap?.lots||[]).find(x=>up(x.lot_no)===up(lotNo));
 if(!lot)throw new Error('Lot no longer available in this department. Refresh and try again.');
 return lot;
}

async function loadFormContext(lot){
 const [form,universal,receiver]=await Promise.all([
  rpc('rr_upm_alter_new_form_v9114',{p_canonical_lot_id:lot.canonical_lot_id,p_department_code:dept}),
  rpc('rr_upm_universal_form_v741',{p_canonical_lot_id:lot.canonical_lot_id,p_department_code:dept}),
  rpc('rr_upm_alter_receiver_context_v770',{p_canonical_lot_id:lot.canonical_lot_id})
 ]);
 return {form:form||{},universal:universal||{},receiver:receiver||{}};
}

function goodMap(universal){
 const map=new Map();
 for(const r of universal?.rows||[]){map.set(`${up(r.colour_code)}|${up(r.size_code)}`,Math.max(0,Number(r.good_qty??0)))}
 return map;
}
function activeLineMen(receiver){
 const seen=new Set();
 return (receiver?.line_man_candidates||[]).filter(x=>{
  const id=String(x?.worker_id||x?.person_id||'');
  const role=up(x?.role_code||x?.worker_role_code||x?.role||'LINE_MAN').replace(/[^A-Z0-9]+/g,'_');
  const status=up(x?.access_status||x?.status||'ACTIVE');
  if(!id||role!=='LINE_MAN'||x?.is_active===false||['INACTIVE','DISABLED','CLOSED','DELETED'].includes(status)||seen.has(id))return false;
  seen.add(id);return true;
 });
}

function renderModal(lot,ctx){
 injectStyle();
 const gmap=goodMap(ctx.universal);
 const rows=ctx.form?.rows||[];
 const lms=activeLineMen(ctx.receiver);
 const actor=ctx.receiver?.actor_line_man||null;
 const actorId=String(actor?.worker_id||actor?.person_id||'');
 const actorRole=up(ctx.receiver?.actor_role||'').replace(/[^A-Z0-9]+/g,'_');
 const options=lms.map(x=>{const id=String(x.worker_id||x.person_id);const label=[x.worker_name||x.person_name_snapshot||x.name,x.worker_code].filter(Boolean).join(' · ');return `<option value="${esc(id)}" ${actorId&&id===actorId?'selected':''}>${esc(label||'Line Man')}</option>`}).join('');
 const groups=rows.map((r,gi)=>{
  const colour=up(r.colour_code),sizes=normalizeSizes(r.size_breakup);
  return `<section class="rr-alt9253-group" data-group="${gi}" data-colour="${esc(colour)}">
   <div class="rr-alt9253-ghead">${r.thumbnail_url?`<img src="${esc(r.thumbnail_url)}" alt="${esc(colour)}">`:'<span class="rr-alt9253-ph">COLOUR</span>'}<div><b>${esc(colour)}</b><small>${esc(r.worker_name||'Worker')} · Assigned ${esc(r.qty||0)} PCS</small></div></div>
   <div class="rr-alt9253-sizes">${sizes.map((s,si)=>{const good=gmap.get(`${colour}|${s.size_code}`)??Math.max(0,s.qty);return `<label class="rr-alt9253-size"><span>${esc(s.size_code)}</span><small>Good ${esc(good)} PCS</small><input class="rr-alt9253-qty" data-colour="${esc(colour)}" data-size="${esc(s.size_code)}" data-max="${esc(good)}" type="number" min="0" max="${esc(good)}" step="1" inputmode="numeric" placeholder="Alter Qty"></label>`}).join('')||'<div class="rr-alt9253-note">Size breakup unavailable.</div>'}</div>
  </section>`
 }).join('');
 const modal=document.createElement('div');modal.id='rrAlt9253';modal.className='rr-alt9253';modal.dataset.canonical=lot.canonical_lot_id;modal.innerHTML=`<section class="rr-alt9253-sheet">
  <header class="rr-alt9253-head"><div><small style="color:#ffc857;font-weight:900">UNIVERSAL PRODUCT MASTER · ALTER</small><h2>ALTER FILL</h2><div class="rr-alt9253-meta">${esc(lot.lot_no)} · ${esc(dept.replaceAll('_',' '))}</div></div><button class="rr-alt9253-close" type="button" data-alt-close>×</button></header>
  <div class="rr-alt9253-note">Colour/Size में केवल वही Qty भरें जो Alter में जा रही है. 1–3 live evidence images और physical piece confirmation mandatory है.</div>
  ${groups||'<div class="rr-alt9253-msg err">No active production rows available for ALTER.</div>'}
  <label class="rr-alt9253-field"><span>ALTER RECEIVER · LINE MAN *</span><select id="rrAlt9253Lm" ${actorRole==='LINE_MAN'&&actorId?'disabled':''}><option value="">Select active Line Man</option>${options}</select></label>
  <label class="rr-alt9253-field"><span>LIVE CAMERA EVIDENCE · 1–3 IMAGES *</span><input id="rrAlt9253Files" type="file" accept="image/jpeg,image/png,image/webp" capture="environment" multiple></label>
  <div id="rrAlt9253FilesInfo" class="rr-alt9253-note">No image selected.</div>
  <label class="rr-alt9253-check"><input id="rrAlt9253Physical" type="checkbox"><span>Physical Alter piece selected Line Man को handover / submit किया है.</span></label>
  <label class="rr-alt9253-field"><span>REMARKS</span><textarea id="rrAlt9253Remarks" placeholder="Optional Alter note"></textarea></label>
  <div id="rrAlt9253Msg" class="rr-alt9253-msg"></div>
  <button id="rrAlt9253Save" class="rr-alt9253-save" type="button">SAVE ALTER · EXIT</button>
 </section>`;
 document.body.appendChild(modal);document.body.style.overflow='hidden';
 modal.querySelector('[data-alt-close]').onclick=close;
 modal.addEventListener('click',e=>{if(e.target===modal)close()});
 const sel=modal.querySelector('#rrAlt9253Lm');if(actorRole==='LINE_MAN'&&actorId)sel.value=actorId;
 modal.querySelector('#rrAlt9253Files').onchange=e=>{const files=[...(e.target.files||[])].slice(0,3);modal.querySelector('#rrAlt9253FilesInfo').textContent=files.length?files.map(f=>f.name).join(' · '):'No image selected.'};
 modal.querySelector('#rrAlt9253Save').onclick=()=>save(lot,ctx);
}

async function uploadEvidence(lot,files){
 if(files.length<1||files.length>3)throw new Error('Minimum 1 and maximum 3 evidence images required.');
 const c=client(),paths=[];
 for(const file of files){
  if(!/^image\/(jpeg|png|webp)$/i.test(file.type||''))throw new Error(`Unsupported image: ${file.name}`);
  const ext=(file.name?.split('.').pop()||'jpg').toLowerCase();
  const path=`${lot.canonical_lot_id}/${dept}/${Date.now()}-${uid()}.${ext}`;
  const r=await c.storage.from('production-evidence').upload(path,file,{upsert:false,contentType:file.type});
  if(r.error)throw r.error;paths.push(path);
 }
 return paths;
}

async function save(lot,ctx){
 if(busy)return;
 const modal=document.getElementById('rrAlt9253');if(!modal)return;
 const lm=String(modal.querySelector('#rrAlt9253Lm')?.value||ctx.receiver?.actor_line_man?.worker_id||ctx.receiver?.actor_line_man?.person_id||'');
 const physical=Boolean(modal.querySelector('#rrAlt9253Physical')?.checked);
 const files=[...(modal.querySelector('#rrAlt9253Files')?.files||[])].slice(0,3);
 const remarks=String(modal.querySelector('#rrAlt9253Remarks')?.value||'').trim();
 const rows=[];
 modal.querySelectorAll('.rr-alt9253-qty').forEach(input=>{const qty=Number(input.value||0),max=Number(input.dataset.max||0);if(qty>0){if(qty>max)throw new Error(`${input.dataset.colour} / ${input.dataset.size}: Alter Qty ${qty} exceeds Good Qty ${max}.`);rows.push({colour_code:input.dataset.colour,colour_name:input.dataset.colour,size_code:input.dataset.size,qty})}});
 if(!rows.length)return message('Enter Alter Qty in at least one Colour / Size.','err');
 if(!lm)return message('Select active Line Man.','err');
 if(!physical)return message('Confirm physical Alter piece handover.','err');
 if(files.length<1||files.length>3)return message('Select 1–3 evidence images.','err');
 const btn=modal.querySelector('#rrAlt9253Save');busy=true;btn.disabled=true;btn.textContent='SAVING ALTER…';
 try{
  message('Uploading evidence and saving ALTER…');
  const paths=await uploadEvidence(lot,files);
  const data=await rpc('rr_upm_alter_fill_request_v9114',{p_canonical_lot_id:lot.canonical_lot_id,p_department_code:dept,p_rows:rows,p_evidence_urls:paths,p_physical_confirmed:true,p_line_man_id:lm,p_remarks:remarks||'Universal Product Master ALTER'});
  message(`${data?.rows_saved||rows.length} Alter row(s) saved. ${data?.selected_line_man_name||'Line Man'} acceptance pending.`,'ok');
  await new Promise(r=>setTimeout(r,700));close();document.getElementById('refresh')?.click();
 }catch(e){console.error('UPM ALTER save failed',e);message([e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(' — ')||String(e),'err')}
 finally{busy=false;if(document.body.contains(btn)){btn.disabled=false;btn.textContent='SAVE ALTER · EXIT'}}
}

async function open(lotNo){
 if(busy)return;
 busy=true;
 try{
  const lot=await resolveLot(lotNo);
  const ctx=await loadFormContext(lot);
  renderModal(lot,ctx);
 }catch(e){alert([e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(' — ')||String(e))}
 finally{busy=false}
}

// Current department view owns the card. Capture ALTER before its legacy fallback
// attempts to call a missing overview-only RealFactoryUPM bridge.
document.addEventListener('click',e=>{
 const b=e.target.closest?.('#rfsubmit .rfactions [data-act="ALTER"]');
 if(!b)return;
 const card=b.closest('.rfcard');const lotNo=card?.dataset?.lot;
 if(!lotNo)return;
 e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();
 open(lotNo);
},true);
})();
