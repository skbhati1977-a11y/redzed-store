(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money = (v) => new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR'}).format(Number(v||0));
  const state = { profile:null, packPlan:null, packLots:[], selectedPack:null, piId:null, piLines:[], stock:[], cpis:[], materialBoxes:[], lotMedia:null, aiSelected:new Set() };
  function msg(text,type=''){ $('message').textContent=text||''; $('message').className=`fg-msg ${type}`; }
  async function rpc(name,args={}){ const r=await supabaseClient.rpc(name,args); if(r.error) throw r.error; return r.data; }
  async function rows(table,select='*'){ const r=await supabaseClient.from(table).select(select); if(r.error) throw r.error; return r.data||[]; }
  function selected(select){ return [...select.selectedOptions].map(o=>o.value); }
  function composition(cells){ return (cells||[]).map(x=>`${x.colour_code}-${x.size_code}×${x.qty}`).join(', '); }


  async function loadMaterialBoxes(){try{const d=await rpc('rr_material_purchase_bootstrap_v805_2',{p_data_mode:'TEST'});state.materialBoxes=d.box_materials||[];ensureBoxMaterialControl();renderBoxMaterialOptions();}catch(e){console.warn(e)}}
  function ensureBoxMaterialControl(){if($('boxMaterialSelect'))return;const a=$('packSummary');if(!a)return;const w=document.createElement('div');w.id='boxMaterialWrap';w.style.cssText='margin:10px 0;padding:10px;border:1px solid #39424d;border-radius:10px;background:#10151b';w.innerHTML=`<label style="display:grid;gap:6px"><b>Box Name / Material *</b><select id="boxMaterialSelect" style="padding:10px;background:#0c1015;color:#fff;border:1px solid #39424d;border-radius:8px"></select><small id="boxMaterialMeta">Mandatory · Material Master BOX mapping</small></label>`;a.parentNode.insertBefore(w,a.nextSibling);$('boxMaterialSelect').onchange=renderSelectedBoxMaterial}
  function renderBoxMaterialOptions(){ensureBoxMaterialControl();if(!$('boxMaterialSelect'))return;$('boxMaterialSelect').innerHTML='<option value="">Select Box Name…</option>'+state.materialBoxes.map(x=>`<option value="${x.material_id}">${esc([x.material_name,x.material_no].filter(Boolean).join(' · '))}</option>`).join('');renderSelectedBoxMaterial()}
  function renderSelectedBoxMaterial(){const m=state.materialBoxes.find(x=>String(x.material_id)===String($('boxMaterialSelect')?.value));if($('boxMaterialMeta'))$('boxMaterialMeta').textContent=m?`Current Bal ${Number(m.current_balance_qty||0).toLocaleString('en-IN')} ${m.base_stock_unit} · W.Avg ${money(m.running_weighted_avg_cost_per_consumption_unit)} / Box`:'Mandatory · Material Master BOX mapping'}


  // ===== V808_2 Packing Final Image / AI Media (additive) =====
  const MEDIA_BUCKET='product-images';
  function aiAdmin(){return ['owner','admin'].includes(String(state.profile?.role_code||'').toLowerCase())}
  function mediaMsg(t,type=''){const e=$('packingMediaMsg');if(e){e.textContent=t||'';e.className=`fg-msg ${type}`}}
  function mediaStatus(t){if($('aiMediaStatus'))$('aiMediaStatus').textContent=t}
  function safeName(s){return String(s||'image').replace(/[^a-zA-Z0-9._-]+/g,'-').slice(-90)}
  function lotPath(kind,name){const lot=String(state.selectedPack?.lot_no||'UNKNOWN');return `TEST/${lot}/${kind}/${Date.now()}-${crypto.randomUUID()}-${safeName(name)}`}
  function dataUrlToBlob(dataUrl){
    const [head,b64]=String(dataUrl).split(',');const mime=(head.match(/data:([^;]+)/)||[])[1]||'image/png';
    const bin=atob(b64||''),arr=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)arr[i]=bin.charCodeAt(i);
    return new Blob([arr],{type:mime});
  }
  async function uploadBlob(path,blob,contentType){
    const r=await supabaseClient.storage.from(MEDIA_BUCKET).upload(path,blob,{contentType:contentType||blob.type,upsert:false});
    if(r.error)throw r.error;
    const p=supabaseClient.storage.from(MEDIA_BUCKET).getPublicUrl(path);
    return {path,url:p.data.publicUrl};
  }
  async function invokeFactoryAi(body){
    const r=await supabaseClient.functions.invoke('real-factory-ai',{body});
    if(r.error)throw r.error;
    if(r.data?.ok===false)throw Error(r.data.error||'AI request failed.');
    return r.data;
  }
  async function loadLotMedia(){
    if(!state.selectedPack){state.lotMedia=null;return}
    try{
      state.lotMedia=await rpc('rr_media_ai_lot_state_v808',{p_lot_no:String(state.selectedPack.lot_no),p_data_mode:'TEST'});
      state.aiSelected=new Set();
      renderLotMedia();
    }catch(e){mediaMsg(e.message,'error')}
  }
  function mediaImageUrl(m){return m.file_url||''}
  function renderLotMedia(){
    const d=state.lotMedia||{}, media=Array.isArray(d.media)?d.media:[];
    const sources=media.filter(x=>x.media_stage==='PACKING_FINAL_SOURCE');
    const variants=media.filter(x=>x.media_stage==='AI_VARIANT');
    mediaStatus(`${sources.length}/4 SOURCE`);
    $('aiVariantCount').textContent=`${variants.length} AI`;
    $('packingSourceMedia').innerHTML=sources.length?sources.map(x=>`<div class="ai-card"><img src="${esc(mediaImageUrl(x))}" alt="Packing source"><small>Source ${x.source_seq} · Lot ${esc(x.lot_no)}</small></div>`).join(''):'<div class="fg-muted">Final image pending.</div>';
    $('packingAiVariants').innerHTML=variants.length?variants.map(x=>{
      const checked=state.aiSelected.has(x.media_id);
      const cls=x.is_webstore_published?'published':x.approval_status==='APPROVED'?'approved':x.approval_status==='REGENERATE_REQUESTED'?'regenerate':'';
      return `<div class="ai-card">
        <div class="ai-media-head"><b>AI ${x.variant_no||''}</b><span class="ai-badge ${cls}">${esc(x.is_webstore_published?'PUBLISHED':x.approval_status)}</span></div>
        <img src="${esc(mediaImageUrl(x))}" alt="AI variant">
        <label class="ai-inline" style="margin-top:7px"><input type="checkbox" data-ai-media="${esc(x.media_id)}" ${checked?'checked':''}><span>Select</span></label>
        <div class="ai-actions"><button type="button" data-ai-print="${esc(x.media_id)}">Print A4</button></div>
      </div>`;
    }).join(''):'<div class="fg-muted">AI images pending.</div>';
    $('packingAiVariants').querySelectorAll('[data-ai-media]').forEach(c=>c.onchange=()=>{c.checked?state.aiSelected.add(c.dataset.aiMedia):state.aiSelected.delete(c.dataset.aiMedia)});
    $('packingAiVariants').querySelectorAll('[data-ai-print]').forEach(b=>b.onclick=()=>printAiA4([b.dataset.aiPrint]));
    $('packingAiAdminActions').hidden=!aiAdmin()||!variants.length;
    mediaMsg(`${sources.length} source · ${variants.length} AI · ${Number(d.approved_count||0)} approved · ${Number(d.published_count||0)} published.`,'ok');
  }
  async function uploadPackingFinalImages(){
    try{
      if(!state.selectedPack)throw Error('Lot select karein.');
      const files=[...($('packingFinalImages').files||[])];
      if(!files.length)throw Error('1–4 Final Images select karein.');
      const existing=Number(state.lotMedia?.source_count||0);
      if(existing+files.length>4)throw Error(`Max 4 Final Images. Existing ${existing}, selected ${files.length}.`);
      const b=$('uploadPackingFinalImages');b.disabled=true;mediaMsg('Final Images save ho rahi hain…');
      for(const f of files){
        if(!['image/jpeg','image/png','image/webp'].includes(f.type))throw Error('Only JPG/PNG/WEBP.');
        if(f.size>12*1024*1024)throw Error(`${f.name}: max 12 MB.`);
        const up=await uploadBlob(lotPath('packing-final',f.name),f,f.type);
        await rpc('rr_media_ai_add_source_v808',{
          p_lot_no:String(state.selectedPack.lot_no),p_file_url:up.url,p_storage_path:up.path,
          p_file_name:f.name,p_mime_type:f.type,p_data_mode:'TEST',p_is_mock:false,
          p_metadata:{source_module:'PACKING',lot_no:String(state.selectedPack.lot_no)}
        });
      }
      $('packingFinalImages').value='';await loadLotMedia();mediaMsg('Final Images saved · same Lot locked.','ok');b.disabled=false;
    }catch(e){$('uploadPackingFinalImages').disabled=false;mediaMsg(e.message,'error')}
  }
  async function generatePackingAi(){
    try{
      if(!state.selectedPack)throw Error('Lot select karein.');
      const sources=(state.lotMedia?.media||[]).filter(x=>x.media_stage==='PACKING_FINAL_SOURCE');
      if(!sources.length)throw Error('Pehle Final Image save karein.');
      const b=$('generatePackingAi');b.disabled=true;mediaMsg('AI 5 promotion images generate kar raha hai…');
      const group=crypto.randomUUID(), made=[];
      // Use uploaded source set across the five outputs (round-robin). Existing AI backend remains untouched.
      for(let i=0;i<5;i++){
        const src=sources[i%sources.length];
        const a=await invokeFactoryAi({
          action:'IMAGE_VARIANTS_GENERATE',data_mode:'TEST',variant_count:1,
          source_image_url:src.file_url,
          product_context:{lot_no:String(state.selectedPack.lot_no),source_module:'PACKING_FINAL_IMAGE'},
          image_context:{workflow:'PACKING_TO_WEBSTORE',source_number:src.source_seq,requested_variant:i+1}
        });
        const v=(a.variants||[])[0];if(!v)throw Error(`AI ${i+1} image return nahi hui.`);
        const blob=dataUrlToBlob(`data:${v.mime_type||'image/png'};base64,${v.base64}`);
        const up=await uploadBlob(`TEST/${state.selectedPack.lot_no}/ai/${group}/variant-${i+1}.png`,blob,v.mime_type||'image/png');
        made.push({variant_no:i+1,file_url:up.url,storage_path:up.path,file_name:`variant-${i+1}.png`,mime_type:v.mime_type||'image/png',openai_response_id:v.openai_response_id||null,prompt_version:'REAL_FACTORY_AI_V2_2',metadata:{source_media_id:src.media_id,source_seq:src.source_seq}});
      }
      await rpc('rr_media_ai_register_variants_v808',{
        p_lot_no:String(state.selectedPack.lot_no),
        p_source_media_ids:sources.map(x=>x.media_id),
        p_variants:made,p_data_mode:'TEST',p_generation_group:group
      });
      await loadLotMedia();mediaMsg('5 AI images ready · Admin approval notification created.','ok');b.disabled=false;
    }catch(e){$('generatePackingAi').disabled=false;mediaMsg(e.message,'error')}
  }
  function selectedAiRows(){const ids=[...state.aiSelected];return (state.lotMedia?.media||[]).filter(x=>ids.includes(String(x.media_id)))}
  async function acceptPackingAi(){
    try{if(!aiAdmin())throw Error('Admin required.');const ids=[...state.aiSelected];if(!ids.length)throw Error('AI image select karein.');
      await rpc('rr_media_ai_admin_decide_v808',{p_lot_no:String(state.selectedPack.lot_no),p_accept_media_ids:ids,p_regenerate_media_ids:[],p_data_mode:'TEST'});
      await loadLotMedia();mediaMsg(`${ids.length} image accepted.`,'ok');
    }catch(e){mediaMsg(e.message,'error')}
  }
  async function regeneratePackingAi(){
    try{
      if(!aiAdmin())throw Error('Admin required.');const old=selectedAiRows();if(!old.length)throw Error('Regenerate image select karein.');
      await rpc('rr_media_ai_admin_decide_v808',{p_lot_no:String(state.selectedPack.lot_no),p_accept_media_ids:[],p_regenerate_media_ids:old.map(x=>x.media_id),p_data_mode:'TEST'});
      const sources=(state.lotMedia?.media||[]).filter(x=>x.media_stage==='PACKING_FINAL_SOURCE');if(!sources.length)throw Error('Source image missing.');
      const group=crypto.randomUUID(), made=[];
      for(let i=0;i<old.length;i++){
        const src=sources[i%sources.length];
        const a=await invokeFactoryAi({action:'IMAGE_VARIANT_REGENERATE',data_mode:'TEST',variant_count:1,source_image_url:src.file_url,regenerate_instruction:'Create a different premium promotional alternative. Preserve exact garment identity.',product_context:{lot_no:String(state.selectedPack.lot_no)},image_context:{workflow:'PACKING_TO_WEBSTORE_REGENERATE'}});
        const v=(a.variants||[])[0];if(!v)throw Error('Replacement image missing.');
        const blob=dataUrlToBlob(`data:${v.mime_type||'image/png'};base64,${v.base64}`);
        const up=await uploadBlob(`TEST/${state.selectedPack.lot_no}/ai/${group}/variant-${i+1}.png`,blob,v.mime_type||'image/png');
        made.push({variant_no:i+1,file_url:up.url,storage_path:up.path,file_name:`regen-${i+1}.png`,mime_type:v.mime_type||'image/png',openai_response_id:v.openai_response_id||null,prompt_version:'REAL_FACTORY_AI_V2_2',metadata:{regenerated_from:old[i].media_id,source_media_id:src.media_id}});
      }
      await rpc('rr_media_ai_register_variants_v808',{p_lot_no:String(state.selectedPack.lot_no),p_source_media_ids:sources.map(x=>x.media_id),p_variants:made,p_data_mode:'TEST',p_generation_group:group});
      await loadLotMedia();mediaMsg(`${made.length} replacement image ready · approval pending.`,'ok');
    }catch(e){mediaMsg(e.message,'error')}
  }
  async function publishPackingAi(){
    try{if(!aiAdmin())throw Error('Admin required.');const rows=selectedAiRows().filter(x=>x.approval_status==='APPROVED');if(!rows.length)throw Error('Approved image select karein.');
      await rpc('rr_media_ai_publish_v808',{p_lot_no:String(state.selectedPack.lot_no),p_media_ids:rows.map(x=>x.media_id),p_data_mode:'TEST'});
      await loadLotMedia();mediaMsg(`${rows.length} image Webstore published.`,'ok');
    }catch(e){mediaMsg(e.message,'error')}
  }
  function comparePackingAi(){
    const src=(state.lotMedia?.media||[]).filter(x=>x.media_stage==='PACKING_FINAL_SOURCE'), ai=selectedAiRows().length?selectedAiRows():(state.lotMedia?.media||[]).filter(x=>x.media_stage==='AI_VARIANT');
    $('aiCompareBody').innerHTML=src.map(x=>`<div class="ai-card"><b>SOURCE ${x.source_seq}</b><img src="${esc(x.file_url)}"></div>`).join('')+ai.map(x=>`<div class="ai-card"><b>AI ${x.variant_no||''}</b><img src="${esc(x.file_url)}"><small>${esc(x.approval_status)}</small></div>`).join('');
    const d=$('aiCompareDialog');typeof d.showModal==='function'?d.showModal():d.setAttribute('open','');
  }
  function printAiA4(ids){
    const rows=(state.lotMedia?.media||[]).filter(x=>ids.includes(String(x.media_id)));if(!rows.length){mediaMsg('Print ke liye image select karein.','error');return}
    const lot=state.selectedPack?.lot_no||'—', pages=rows.map(x=>`<section class="p"><header><b>REAL FACTORY</b><b>LOT ${esc(lot)}</b></header><div class="m">AI ${x.variant_no||''} · ${esc(x.approval_status)}</div><div class="photo"><img src="${esc(x.file_url)}"></div><footer>Packing Final Image based · Admin controlled</footer></section>`).join('');
    const w=window.open('','_blank');if(!w){mediaMsg('Browser pop-up allow karein.','error');return}
    w.document.write(`<!doctype html><html><head><title>Lot ${esc(lot)} A4</title><style>@page{size:A4 portrait;margin:10mm}body{margin:0;font-family:Arial}.p{width:190mm;min-height:277mm;page-break-after:always;display:flex;flex-direction:column}.p:last-child{page-break-after:auto}header{display:flex;justify-content:space-between;border-bottom:2px solid;padding-bottom:6mm}.m{padding:5mm 0;font-weight:bold}.photo{flex:1;display:grid;place-items:center;border:1px solid #bbb}.photo img{max-width:100%;max-height:230mm;object-fit:contain}footer{margin-top:5mm;font-size:10px}</style></head><body>${pages}</body></html>`);w.document.close();setTimeout(()=>w.print(),500);
  }
  function printSelectedPackingAi(){const ids=[...state.aiSelected];printAiA4(ids)}

  async function boot(){
    const auth=await RR.requireRoles(['owner','admin','manager','packing','store','sales','accounts']); state.profile=auth.profile; const role=String(auth.profile.role_code||'').toLowerCase();$('operator').textContent=['owner','admin'].includes(role)?'SUPER ADMIN':(auth.profile.full_name||'Authorized User');
    bind(); await Promise.allSettled([loadPackLots(),loadPackWorkers(),loadReadyBoxes(),loadChallans(),loadStock(),loadCpis(),loadSuggestions(),loadMaterialBoxes()]);
  }
  function bind(){
    $('tabs').addEventListener('click',e=>{const b=e.target.closest('[data-tab]');if(!b)return;document.querySelectorAll('[data-tab]').forEach(x=>x.classList.toggle('active',x===b));document.querySelectorAll('[data-view]').forEach(x=>x.hidden=x.dataset.view!==b.dataset.tab);msg('');});
    const requestedView=new URLSearchParams(location.search).get('view');
    if(requestedView){const b=document.querySelector(`[data-tab="${requestedView}"]`);if(b){b.click();document.querySelectorAll('[data-tab]').forEach(x=>x.hidden=x!==b);const names={packing:'Packing',despatch:'Despatch',receive:'Store Receive',stock:'Webstore / Store Stock',sale:'Sales · PI / CPI',verify:'Sales Qty Verify',returns:'Sales Return'};document.querySelector('h1').textContent=`${names[requestedView]||'Finished Goods'} Dashboard`;document.title=`REAL FACTORY — ${names[requestedView]||'Finished Goods'} Dashboard`;}}
    $('refreshPackLots').onclick=loadPackLots;$('packLotSearch').oninput=renderPackLots;$('closePackLot').onclick=closePackLot;$('assignPack').onclick=assignPack;$('acceptPack').onclick=acceptPack;$('submitPack').onclick=submitPack;$('loadReadyBoxes').onclick=loadReadyBoxes;$('submitDispatch').onclick=submitDispatch;
    $('loadChallans').onclick=loadChallans;$('receiveChallan').onchange=renderReceiveBoxes;$('acceptReceive').onclick=acceptReceive;$('loadStock').onclick=loadStock;
    $('saleLot').onchange=showSaleBalance;$('addPiLine').onclick=addPiLine;$('savePi').onclick=()=>savePi(false);$('submitCpi').onclick=()=>savePi(true);
    $('loadCpis').onclick=loadCpis;$('verifyQty').onclick=verifyQty;$('returnMode').onchange=toggleReturnMode;$('returnCpi').onchange=loadReturnLines;$('returnLine').onchange=fillReturnRate;$('postReturn').onclick=postReturn;
    $('valueAdded').oninput=renderPi;$('packingOther').oninput=renderPi;
    $('uploadPackingFinalImages').onclick=uploadPackingFinalImages;
    $('generatePackingAi').onclick=generatePackingAi;
    $('refreshPackingMedia').onclick=loadLotMedia;
    $('acceptPackingAi').onclick=acceptPackingAi;
    $('regeneratePackingAi').onclick=regeneratePackingAi;
    $('comparePackingAi').onclick=comparePackingAi;
    $('printPackingAi').onclick=printSelectedPackingAi;
    $('publishPackingAi').onclick=publishPackingAi;
    $('closeAiCompare').onclick=()=>{const d=$('aiCompareDialog');if(d?.close)d.close();else d?.removeAttribute('open')};
  }
  async function loadSuggestions(){
    try{const [lots,buyers]=await Promise.all([rows('rr_fg_stock_balance_v787'),rows('rr_buyers_v787')]);$('saleLotSuggestions').innerHTML=lots.filter(x=>Number(x.available_qty)>0).map(x=>`<option value="${esc(x.lot_no)}">${esc(x.short_item_name||'')}</option>`).join('');$('buyerSuggestions').innerHTML=buyers.map(x=>`<option value="${esc(x.buyer_name)}">${esc(x.gst_no||'')}</option>`).join('');}catch(e){console.warn(e);}
  }
  function canAssign(){return ['owner','admin','manager'].includes(String(state.profile?.role_code||'').toLowerCase());}
  async function loadPackLots(){try{msg('Press se Ready Lots fetch ho rahe hain…');state.packLots=await rpc('rr_fg_ready_packing_cards_v788',{p_data_mode:'TEST'});renderPackLots();msg(`${state.packLots.length} Ready Packing Lot cards loaded.`,'ok');}catch(e){$('packLotCards').innerHTML='<p class="fg-warning">Ready lots load nahi hue. V788 SQL run karein.</p>';msg(e.message,'error');}}
  function renderPackLots(){const q=$('packLotSearch').value.trim().toLowerCase(),list=state.packLots.filter(x=>String(x.lot_no).toLowerCase().includes(q));$('packLotCards').innerHTML=list.length?list.map(x=>`<button class="fg-lot-card" data-pack-lot="${esc(x.lot_no)}"><div class="fg-card-line"><strong>${esc(x.lot_no)}</strong><span class="fg-status ${x.is_mine?'mine':x.assignment_id?'':'open'}">${esc(x.status_label)}</span></div><div class="fg-card-line"><span>Ready PCS</span><b>${x.ready_qty}</b></div><div class="fg-card-line"><span>Colours / Sizes</span><span>${x.colours} / ${x.sizes}</span></div><div class="fg-card-line"><span>Packer</span><span>${esc(x.worker_name||'Not Assigned')}</span></div></button>`).join(''):'<p class="fg-muted">Koi matching Ready Lot nahi hai.</p>';$('packLotCards').querySelectorAll('[data-pack-lot]').forEach(b=>b.onclick=()=>openPackLot(b.dataset.packLot));}
  async function loadPackWorkers(){try{const data=await rpc('rr_fg_packing_workers_v788');$('packWorker').innerHTML='<option value="">Select Packing Worker…</option>'+data.map(x=>`<option value="${x.user_id}">${esc(x.display_name)}${x.worker_code?' · '+esc(x.worker_code):''}</option>`).join('');}catch(e){console.warn(e);}}
  function openPackLot(lot){const x=state.packLots.find(v=>String(v.lot_no)===String(lot));if(!x)return;state.selectedPack=x;state.packPlan=null;$('packWorkspace').hidden=false;$('selectedPackLot').textContent=`Lot ${x.lot_no}`;$('selectedPackMeta').innerHTML=`<span class="fg-chip">Ready PCS <b>${x.ready_qty}</b></span><span class="fg-chip">Status <b>${esc(x.status_label)}</b></span>${x.worker_name?`<span class="fg-chip">Packer <b>${esc(x.worker_name)}</b></span>`:''}`;$('assignPackBlock').hidden=!canAssign()||Boolean(x.assignment_id);$('workerPackBlock').hidden=!(x.is_mine&&x.assignment_status==='ASSIGNED');$('submitPack').disabled=true;$('packRows').innerHTML='';$('packSummary').innerHTML='';ensureBoxMaterialControl();if($('boxMaterialSelect'))$('boxMaterialSelect').value='';renderSelectedBoxMaterial();loadLotMedia();$('packWorkspace').scrollIntoView({behavior:'smooth',block:'start'});if(x.is_mine&&x.assignment_status==='ACCEPTED')generatePack();}
  function closePackLot(){$('packWorkspace').hidden=true;state.selectedPack=null;state.packPlan=null;state.lotMedia=null;state.aiSelected=new Set();}
  async function assignPack(){try{if(!state.selectedPack)throw Error('Lot card select karein.');const worker=$('packWorker').value;if(!worker)throw Error('Packing Worker select karein.');await rpc('rr_fg_assign_packing_v788',{p_lot_no:state.selectedPack.lot_no,p_worker_user_id:worker,p_data_mode:'TEST'});msg(`Lot ${state.selectedPack.lot_no} packing worker ko assigned.`,'ok');closePackLot();await loadPackLots();}catch(e){msg(e.message,'error');}}
  async function acceptPack(){try{if(!state.selectedPack?.assignment_id)throw Error('Assigned Lot required.');await rpc('rr_fg_accept_packing_v788',{p_assignment_id:state.selectedPack.assignment_id});state.selectedPack.assignment_status='ACCEPTED';$('workerPackBlock').hidden=true;msg('Work accepted. Algorithm auto-run ho raha hai…','ok');await generatePack();}catch(e){msg(e.message,'error');}}
  async function generatePack(){try{const x=state.selectedPack;if(!x)throw Error('Lot card select karein.');msg('Packing algorithm chal raha hai…');state.packPlan=await rpc('rr_fg_generate_assigned_pack_v788',{p_assignment_id:x.assignment_id});const detail=await rpc('rr_fg_pack_plan_detail_v787',{p_plan_id:state.packPlan.plan_id});$('packRows').innerHTML=(detail.boxes||[]).map(v=>`<tr><td>${esc(v.box_code)}</td><td>${esc(v.box_type)}</td><td>${v.qty}</td><td>${esc(composition(v.cells))}</td></tr>`).join('');$('packSummary').innerHTML=`<span class="fg-chip">Boxes <b>${detail.boxes.length}</b></span><span class="fg-chip">PCS <b>${detail.total_qty}</b></span>`;$('submitPack').disabled=false;msg('Algorithm ready; physical boxes verify karke Submit Packing karein.','ok');}catch(e){msg(e.message,'error');}}
  async function submitPack(){try{if(!state.packPlan)throw Error('Packing plan required.');ensureBoxMaterialControl();const boxMaterialId=$('boxMaterialSelect')?.value;if(!boxMaterialId)throw Error('Box Name / Material mandatory hai.');const lotNo=state.selectedPack.lot_no,planId=state.packPlan.plan_id;const r=await rpc('rr_fg_submit_assigned_pack_v788',{p_assignment_id:state.selectedPack.assignment_id,p_plan_id:planId});const bc=await rpc('rr_material_record_box_consumption_v805_2',{p_material_id:boxMaterialId,p_box_count:r.total_boxes,p_packed_good_pcs:r.total_qty,p_lot_no:lotNo,p_source_record_id:String(planId),p_data_mode:'TEST'});const ac=await rpc('rr_material_auto_consume_for_lot_v805_2',{p_lot_no:lotNo,p_good_pcs:r.total_qty,p_event:'PACKING_SUBMIT',p_source_record_id:String(planId),p_data_mode:'TEST'});msg(`${r.total_boxes} boxes / ${r.total_qty} PCS Ready · Box Cost ${money(bc.total_box_cost)} · Auto Materials ${(ac.consumed||[]).length}.`,'ok');$('submitPack').disabled=true;closePackLot();await Promise.all([loadPackLots(),loadReadyBoxes(),loadMaterialBoxes()]);}catch(e){msg(e.message,'error');}}
  async function loadReadyBoxes(){try{const data=await rows('rr_fg_ready_box_v787');$('dispatchBoxes').innerHTML=data.map(x=>`<option value="${x.box_id}">${esc(x.box_code)} · ${esc(x.lot_no)} · ${esc(x.box_type)} · ${x.qty} PCS</option>`).join('');}catch(e){console.warn(e);}}
  async function submitDispatch(){try{const ids=selected($('dispatchBoxes'));if(!ids.length)throw Error('Kam se kam ek Box select karein.');const r=await rpc('rr_fg_create_despatch_v787',{p_box_ids:ids,p_destination:$('dispatchDestination').value,p_remarks:$('dispatchRemarks').value,p_data_mode:'TEST'});msg(`Challan ${r.challan_no} locked: ${r.total_boxes} boxes / ${r.total_qty} PCS In Transit.`,'ok');await Promise.all([loadReadyBoxes(),loadChallans()]);}catch(e){msg(e.message,'error');}}
  async function loadChallans(){try{const data=await rows('rr_fg_receive_pending_v787');$('receiveChallan').innerHTML='<option value="">Select…</option>'+data.map(x=>`<option value="${x.despatch_id}" data-boxes='${esc(JSON.stringify(x.boxes))}'>${esc(x.challan_no)} · ${esc(x.destination)} · ${x.total_qty} PCS</option>`).join('');renderReceiveBoxes();}catch(e){console.warn(e);}}
  function renderReceiveBoxes(){const o=$('receiveChallan').selectedOptions[0];let boxes=[];try{boxes=JSON.parse(o?.dataset.boxes||'[]')}catch(_){}$('receiveBoxes').innerHTML=boxes.map(x=>`<option selected value="${x.box_id}">${esc(x.box_code)} · ${x.qty} PCS</option>`).join('');}
  async function acceptReceive(){try{const id=$('receiveChallan').value;if(!id)throw Error('Challan select karein.');const r=await rpc('rr_fg_receive_despatch_v787',{p_despatch_id:id,p_accepted_box_ids:selected($('receiveBoxes')),p_remarks:$('receiveRemarks').value});msg(`Store received ${r.accepted_qty} PCS; Webstore stock updated.`,'ok');await Promise.all([loadChallans(),loadStock(),loadSuggestions()]);}catch(e){msg(e.message,'error');}}
  async function loadStock(){try{state.stock=await rows('rr_fg_stock_balance_v787');$('stockRows').innerHTML=state.stock.map(x=>`<tr><td>${esc(x.lot_no)}</td><td>${esc(x.short_item_name||'')}</td><td>${esc(x.stock_type)}</td><td>${esc(x.location_code||'')}</td><td>${x.available_qty}</td><td>${x.available_qty<=0?'OUT':x.available_qty<=72?'LOW STOCK':'IN STOCK'}</td></tr>`).join('');}catch(e){msg(e.message,'error');}}
  function stockFor(lot,type){return state.stock.find(x=>String(x.lot_no)===String(lot)&&x.stock_type===type);}
  async function showSaleBalance(){if(!state.stock.length)await loadStock();const lot=$('saleLot').value.trim(),r=stockFor(lot,'REGULAR'),a=stockFor(lot,'ASST');$('saleBalance').innerHTML=`<span class="fg-chip">Regular Balance <b>${r?.available_qty||0}</b></span><span class="fg-chip">ASST Balance <b>${a?.available_qty||0}</b></span><span class="fg-chip">Regular Rate <b>${money(r?.sale_rate||0)}</b></span>`;if(!$('asstRate').value)$('asstRate').value=r?.sale_rate||0;}
  async function addPiLine(){try{await showSaleBalance();const lot=$('saleLot').value.trim(),rq=Number($('regularQty').value||0),aq=Number($('asstQty').value||0),reg=stockFor(lot,'REGULAR'),asst=stockFor(lot,'ASST');if(!lot||rq+aq<=0)throw Error('Lot aur quantity required.');if(rq>Number(reg?.available_qty||0)||aq>Number(asst?.available_qty||0))throw Error('Available stock se jyada quantity blocked.');const push=(type,qty,rate,item)=>{if(!qty)return;const old=state.piLines.find(x=>x.lot_no===lot&&x.stock_type===type&&x.rate===rate);if(old)old.qty+=qty;else state.piLines.push({lot_no:lot,stock_type:type,qty,rate,short_item_name:item||lot});};push('REGULAR',rq,Number(reg?.sale_rate||0),reg?.short_item_name);push('ASST',aq,Number($('asstRate').value||reg?.sale_rate||0),asst?.short_item_name||reg?.short_item_name);renderPi();}catch(e){msg(e.message,'error');}}
  function totals(){const sub=state.piLines.reduce((n,x)=>n+x.qty*x.rate,0),va=sub*Number($('valueAdded').value||0)/100,po=Math.max(0,Number($('packingOther').value||0)),raw=sub+va+po,grand=Math.round(raw/10)*10;return{sub,va,po,round:grand-raw,grand};}
  function renderPi(){
    const groups=[];state.piLines.forEach(x=>{const other=state.piLines.find(y=>y!==x&&y.lot_no===x.lot_no&&y.rate===x.rate);if(other){if(groups.some(g=>g.keys?.includes(x)))return;groups.push({keys:[x,other],lot_no:x.lot_no,stock_type:'REGULAR + ASST',qty:x.qty+other.qty,rate:x.rate,short_item_name:`${x.short_item_name} ASST`});}else groups.push({...x,keys:[x]});});
    $('piRows').innerHTML=groups.map((x,i)=>`<tr><td>${esc(x.lot_no)}</td><td class="fg-short">${esc(x.short_item_name)}</td><td>${esc(x.stock_type)}</td><td>${x.qty}</td><td>${money(x.rate)}</td><td>${money(x.qty*x.rate)}</td><td><button class="fg-btn" data-remove="${i}">×</button></td></tr>`).join('');$('piRows').querySelectorAll('[data-remove]').forEach((b)=>b.onclick=()=>{groups[Number(b.dataset.remove)].keys.forEach(k=>state.piLines.splice(state.piLines.indexOf(k),1));renderPi();});const t=totals();$('piTotals').innerHTML=`<span class="fg-chip">Sub Total <b>${money(t.sub)}</b></span><span class="fg-chip">Value Added <b>${money(t.va)}</b></span><span class="fg-chip">Packing & Other <b>${money(t.po)}</b></span><span class="fg-chip">Round Off <b>${money(t.round)}</b></span><span class="fg-chip">Grand Total <b>${money(t.grand)}</b></span>`;
  }
  async function savePi(finalize){try{if(!state.piLines.length)throw Error('PI me item line required.');const t=totals(),buyer=$('buyerSearch').value.trim();if(!buyer)throw Error('Buyer required.');const r=await rpc('rr_fg_save_pi_v787',{p_pi_id:state.piId,p_buyer_name:buyer,p_dispatch_details:$('buyerDispatch').value,p_lines:state.piLines,p_value_added_pct:Number($('valueAdded').value||0),p_packing_other:t.po,p_finalize:finalize,p_data_mode:'TEST'});state.piId=r.pi_id;msg(finalize?`CPI ${r.cpi_no} final; stock OUT locked.`:`PI ${r.pi_no} saved; stock par koi effect nahi.`, 'ok');if(finalize){state.piLines=[];state.piId=null;renderPi();await Promise.all([loadStock(),loadCpis(),loadSuggestions()]);}}catch(e){msg(e.message,'error');}}
  async function loadCpis(){try{state.cpis=await rows('rr_fg_final_cpi_v787');const opts='<option value="">Select…</option>'+state.cpis.map(x=>`<option value="${x.cpi_id}">${esc(x.cpi_no)} · ${esc(x.buyer_name)} · ${x.total_qty} PCS</option>`).join('');$('verifyCpi').innerHTML=opts;$('returnCpi').innerHTML=opts;}catch(e){console.warn(e);}}
  async function verifyQty(){try{const id=$('verifyCpi').value;if(!id)throw Error('CPI select karein.');const r=await rpc('rr_fg_verify_cpi_qty_v787',{p_cpi_id:id,p_remarks:$('verifyRemarks').value});msg(`${r.cpi_no} QTY VERIFIED; customer send/dispatch unlocked.`,'ok');await loadCpis();}catch(e){msg(e.message,'error');}}
  function toggleReturnMode(){const anon=$('returnMode').value==='ANONYMOUS';document.querySelectorAll('.anonymous').forEach(x=>x.hidden=!anon);document.querySelectorAll('.known').forEach(x=>x.hidden=anon);$('returnRate').value=anon?'100':'';}
  async function loadReturnLines(){try{const id=$('returnCpi').value;if(!id)return;$('returnLine').innerHTML=(await rpc('rr_fg_returnable_lines_v787',{p_cpi_id:id})).map(x=>`<option value="${x.line_id}" data-rate="${x.final_rate}">${esc(x.lot_no)} · ${esc(x.stock_type)} · Balance ${x.returnable_qty}</option>`).join('');fillReturnRate();}catch(e){msg(e.message,'error');}}
  function fillReturnRate(){$('returnRate').value=$('returnLine').selectedOptions[0]?.dataset.rate||'';}
  async function postReturn(){try{const anon=$('returnMode').value==='ANONYMOUS';const r=await rpc('rr_fg_post_return_v787',{p_mode:anon?'ANONYMOUS':'KNOWN',p_cpi_line_id:anon?null:$('returnLine').value||null,p_condition:anon?$('anonymousCondition').value:null,p_new_lot_no:anon?$('returnNewLot').value.trim()||null:null,p_qty:Number($('returnQty').value),p_remarks:$('returnRemarks').value,p_data_mode:'TEST'});msg(`Return ${r.return_no} posted: ${r.qty} PCS @ ${money(r.rate)}. Reverse record locked.`,'ok');await Promise.all([loadStock(),loadCpis(),loadSuggestions()]);}catch(e){msg(e.message,'error');}}
  document.addEventListener('DOMContentLoaded',()=>boot().catch(e=>msg(e.message,'error')));
})();
