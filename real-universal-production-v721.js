(()=>{
'use strict';
const $=id=>document.getElementById(id);
const state={client:null,auth:null,user:null,depts:[],lots:[],alters:[],entrySummary:null,workFiles:[],visuals:new Map(),viewerItems:[],viewerIndex:0,alterMode:'ALTER'};
const safe=v=>window.RR?.safeText?RR.safeText(v):String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
const num=v=>Number(v||0);
function msg(t,type='info'){$('message').innerHTML=t?`<div class="msg ${safe(type)}">${safe(t)}</div>`:''}
function open(id){$(id)?.classList.remove('hidden')}
function close(id){$(id)?.classList.add('hidden')}
async function rpc(name,args){const{data,error}=await state.client.rpc(name,args);if(error)throw error;return data}
function colours(l){return Array.isArray(l?.colours)?l.colours:[]}
function currentLot(id){return state.lots.find(x=>x.canonical_lot_id===id)}
function lotAlterQty(lotNo){return state.alters.filter(a=>a.lot_no===lotNo).reduce((n,a)=>n+num(a.pending_qty),0)}
function category(){return String(state.user?.user_category||state.auth?.role||'WORKER').toUpperCase().replace(/ /g,'_')}
function isHeadFor(dept){return ['OWNER','ADMIN'].includes(category())||(category()==='DEPARTMENT_HEAD'&&String(state.user?.department_code||'').toUpperCase()===String(dept||'').toUpperCase())}
function money(v){return v==null?'—':Number(v).toFixed(2)}

function uniqUrls(values){return [...new Set((values||[]).flat(Infinity).filter(v=>typeof v==='string'&&/^https?:\/\//i.test(v.trim())).map(v=>v.trim()))]}
function normalizeVisuals(raw,l){
  const r=raw||{}, meta=l?.metadata||{};
  const garment=uniqUrls([r.garment_url,r.garment_image_url,l?.garment_image_url,l?.art_image_url,l?.product_image_url,l?.image_url,meta.garment_image_url,meta.art_image_url,meta.product_image_url,meta.image_url]);
  const prints=uniqUrls([r.print_urls,r.print_image_urls,l?.print_image_urls,l?.print_images,l?.artwork_images,meta.print_image_urls,meta.print_images,meta.artwork_images]);
  return {garment:garment.slice(0,4),prints:prints.slice(0,12)};
}
async function loadLotVisual(l){
  try{const x=await rpc('rr_upm_get_lot_visuals_v6',{p_canonical_lot_id:l.canonical_lot_id,p_art_no:l.art_no||null});state.visuals.set(l.canonical_lot_id,normalizeVisuals(Array.isArray(x)?x[0]:x,l));}
  catch(_){state.visuals.set(l.canonical_lot_id,normalizeVisuals(null,l));}
}
function visualItems(l){const v=state.visuals.get(l.canonical_lot_id)||normalizeVisuals(null,l);return [...v.garment.map((url,i)=>({url,label:`Garment${v.garment.length>1?' '+(i+1):''}`})),...v.prints.map((url,i)=>({url,label:`Print${v.prints.length>1?' '+(i+1):''}`}))]}
function visualPanel(l,compact=false){
  const v=state.visuals.get(l.canonical_lot_id)||normalizeVisuals(null,l), all=visualItems(l);
  const panel=(label,items,offset)=>`<div class="visual-panel"><span class="visual-label">${label}</span>${items.length?`<div class="visual-thumb-row">${items.map((x,i)=>`<button type="button" class="visual-thumb" data-view-lot="${safe(l.canonical_lot_id)}" data-view-index="${offset+i}"><img src="${safe(x.url)}" loading="lazy" alt="${safe(x.label)}"><span>${safe(x.label)}</span></button>`).join('')}</div>`:`<div class="visual-empty">${label} image not mapped</div>`}</div>`;
  return `<div class="visual-strip ${compact?'compact':''}">${panel('Garment / Art',v.garment.map((url,i)=>({url,label:`Garment${v.garment.length>1?' '+(i+1):''}`})),0)}${panel('Print Reference',v.prints.map((url,i)=>({url,label:`Print${v.prints.length>1?' '+(i+1):''}`})),v.garment.length)}</div>`;
}
function bindVisualButtons(scope=document){scope.querySelectorAll('[data-view-lot]').forEach(b=>b.onclick=()=>{const l=currentLot(b.dataset.viewLot);if(l)openViewer(visualItems(l),Number(b.dataset.viewIndex||0),l.lot_no)});}
function openViewer(items,index=0,title='Reference Images'){if(!items.length)return;state.viewerItems=items;state.viewerIndex=Math.max(0,Math.min(index,items.length-1));$('viewerTitle').textContent=title;renderViewer();$('imageViewer').classList.remove('hidden');document.body.style.overflow='hidden'}
function closeViewer(){$('imageViewer').classList.add('hidden');document.body.style.overflow='';}
function moveViewer(delta){if(!state.viewerItems.length)return;state.viewerIndex=(state.viewerIndex+delta+state.viewerItems.length)%state.viewerItems.length;renderViewer()}
function renderViewer(){const x=state.viewerItems[state.viewerIndex];if(!x)return;$('viewerImage').src=x.url;$('viewerCaption').textContent=`${x.label} · ${state.viewerIndex+1}/${state.viewerItems.length}`;$('viewerDots').innerHTML=state.viewerItems.map((it,i)=>`<button type="button" class="viewer-dot ${i===state.viewerIndex?'active':''}" data-viewer-dot="${i}"><img src="${safe(it.url)}" alt="${safe(it.label)}"></button>`).join('');$('viewerDots').querySelectorAll('[data-viewer-dot]').forEach(b=>b.onclick=()=>{state.viewerIndex=Number(b.dataset.viewerDot);renderViewer()});$('viewerPrev').disabled=state.viewerItems.length<2;$('viewerNext').disabled=state.viewerItems.length<2;}

async function loadUser(){
  try{state.user=await rpc('rr_up_user_context_v2',{});}catch(_){
    state.user={user_category:String(state.auth?.role||'WORKER').toUpperCase(),department_code:state.auth?.department_code||state.auth?.profile?.department_code||'',display_name:state.auth?.name||state.auth?.email||''};
  }
}

async function load(){
  msg('Loading…');
  const [d,l,a,e]=await Promise.all([
    state.client.from('rr_upm_departments').select('*').eq('is_active',true).order('sequence_no'),
    state.client.from('rr_upm_lot_board_v1').select('*').order('board_updated_at',{ascending:false}),
    state.client.from('rr_up_alter_card_v1').select('*').not('status','in','("CLOSED","CANCELLED")').order('created_at',{ascending:false}),
    state.client.from('rr_upm_entries').select('id,created_at').gte('created_at',new Date(new Date().setHours(0,0,0,0)).toISOString())
  ]);
  for(const r of[d,l,a,e])if(r.error)throw r.error;
  state.depts=d.data||[];state.lots=l.data||[];state.alters=a.data||[];
  await Promise.all(state.lots.map(loadLotVisual));
  fillSelects();render();
  $('sLots').textContent=state.lots.filter(x=>!['CLOSED','CANCELLED'].includes(String(x.status).toUpperCase())).length;
  $('sColours').textContent=state.lots.reduce((n,x)=>n+colours(x).length,0);
  $('sAlters').textContent=state.alters.length;
  $('sToday').textContent=(e.data||[]).length;
  msg('');
}

function fillSelects(){
  const opts=state.depts.map(d=>`<option value="${safe(d.department_code)}">${safe(d.department_name)}</option>`).join('');
  $('eDept').innerHTML=opts;
  $('deptFilter').innerHTML='<option value="">All departments</option>'+opts;
}

function render(){
  const q=$('search').value.trim().toLowerCase(),df=$('deptFilter').value;
  const rows=state.lots.filter(l=>{const text=[l.lot_no,l.art_no,l.item_name].join(' ').toLowerCase();return(!q||text.includes(q))&&(!df||colours(l).some(c=>c.current_department_code===df))});
  $('board').innerHTML=rows.length?rows.map(l=>{
    const pending=lotAlterQty(l.lot_no);
    const meta=l.metadata||{}, cbNo=l.cb_no||meta.cb_no||meta.cb_number||'—', printNo=l.print_no||meta.print_no||meta.print_code||'—';
    return `<article class="card upm-lot-card" data-lot-id="${safe(l.canonical_lot_id)}" data-lot-no="${safe(l.lot_no)}">
      <div class="lot-card-head lot-card-highlight"><div><div class="lot-number">LOT ${safe(l.lot_no)}</div><div class="lot-caption">CB ${safe(cbNo)} · ART ${safe(l.art_no||'—')} · PRINT ${safe(printNo)}</div></div><span class="chip cut-highlight">TOTAL CUT ${num(l.total_qty)} PCS</span></div>
      ${visualPanel(l,true)}
      <div class="muted">${safe(l.item_name||'Item not named')} · ${safe(l.status)}</div>
      ${pending>0?`<div class="alter-alert">ALTER : ${pending} PCS</div>`:''}
      <div>${colours(l).map(c=>`<span class="chip ${c.status==='COMPLETED'?'done':c.status==='PARTIAL'?'partial':''}">${safe(c.colour_name||c.colour_code)} → ${safe(c.current_department_code)} · ${safe(c.status)}</span>`).join('')||'<span class="muted">No colour state</span>'}</div>
      <div class="lot-traveller-actions" role="group" aria-label="Lot traveller actions">
        <button data-work-assign-placeholder="${safe(l.canonical_lot_id)}">Assign Work</button>
        <button data-entry="${safe(l.canonical_lot_id)}">Submit Work</button>
        <button data-alter="${safe(l.canonical_lot_id)}">Alter</button>
        <button data-remake="${safe(l.canonical_lot_id)}">Remake</button>
        <button data-damage="${safe(l.canonical_lot_id)}">Damage</button>
      </div>
    </article>`;
  }).join(''):'<div class="empty">No production lots found.</div>';
  document.querySelectorAll('[data-entry]').forEach(b=>b.onclick=()=>openEntry(b.dataset.entry));
  document.querySelectorAll('[data-alter]').forEach(b=>b.onclick=()=>openAlterModule(b.dataset.alter,'ALTER'));
  document.querySelectorAll('[data-remake]').forEach(b=>b.onclick=()=>openAlterModule(b.dataset.remake,'REMAKE'));
  document.querySelectorAll('[data-damage]').forEach(b=>b.onclick=()=>openAlterModule(b.dataset.damage,'DAMAGE'));
  bindVisualButtons($('board'));
}

function setColourSelect(id,l){
  $(id).innerHTML=colours(l).map(c=>`<option value="${safe(c.colour_code)}">${safe(c.colour_name||c.colour_code)}</option>`).join('')||'<option value="GENERAL">General</option>';
}

async function openEntry(id){
  const l=currentLot(id);if(!l)return;
  $('eLot').value=id;
  $('eLotNo').textContent=l.lot_no||'—';
  $('eArtItem').textContent=[l.art_no,l.item_name].filter(Boolean).join(' · ')||'—';
  $('eCutQty').textContent=`${num(l.total_qty)} PCS`;
  $('entryReferenceVisuals').innerHTML=visualPanel(l);bindVisualButtons($('entryReferenceVisuals'));
  setColourSelect('eColour',l);
  const first=colours(l)[0];
  const lockedDept=state.user?.department_code;
  if(lockedDept&&state.depts.some(d=>d.department_code===lockedDept))$('eDept').value=lockedDept;
  else if(first?.current_department_code)$('eDept').value=first.current_department_code;
  $('eSize').value='ALL';$('eRemarks').value='';$('eRate').value='';
  state.workFiles=[];renderWorkPreview();open('entryModal');await refreshEntrySummary();
}

async function refreshEntrySummary(){
  try{
    $('entryStatus').textContent='Calculating…';
    const rows=await rpc('rr_upm_submit_summary_v2',{
      p_canonical_lot_id:$('eLot').value,
      p_department_code:$('eDept').value,
      p_colour_code:$('eColour').value,
      p_size_code:$('eSize').value||'ALL'
    });
    const s=Array.isArray(rows)?rows[0]:rows;state.entrySummary=s||null;
    if(!s)throw new Error('Submit summary unavailable.');
    $('eCutQty').textContent=`${num(s.cutting_qty)} PCS`;
    $('eAlterQty').textContent=`${num(s.alter_qty)} PCS`;
    $('eRepairAssignedQty').textContent=`${num(s.repair_assigned_qty)} PCS`;
    $('eRepairSubmittedQty').textContent=`${num(s.repair_submitted_qty)} PCS`;
    $('eRepairAcceptedQty').textContent=`${num(s.repair_accepted_qty)} PCS`;
    $('eReRepairQty').textContent=`${num(s.re_repair_pending_qty)} PCS`;
    $('eRemakeQty').textContent=`${num(s.remake_qty)} PCS`;
    $('eRemakeCompletedQty').textContent=`${num(s.remake_completed_qty)} PCS`;
    $('eDamageQty').textContent=`${num(s.damage_qty)} PCS`;
    $('ePendingQty').textContent=`${num(s.pending_alter_qty)} PCS`;
    $('eAlreadyQty').textContent=`${num(s.already_submitted_qty)} PCS`;
    $('eReadyQty').textContent=`${num(s.submit_ready_qty)} PCS`;
    $('eImageWrap').classList.toggle('hidden',!s.image_required);
    $('eImageRequiredText').textContent=s.image_required?'Live work image mandatory for this department.':'Work image optional.';
    const canRate=isHeadFor($('eDept').value);
    $('eRate').readOnly=!canRate;
    $('eRate').value=s.actual_rate==null?'':s.actual_rate;
    $('eRateHelp').textContent=s.actual_rate==null?(canRate?'Enter and save Actual Rate before submit.':'Actual Rate pending from Department Head.'):`Rate locked: ₹${money(s.actual_rate)}${s.rate_filled_by?' · '+s.rate_filled_by:''}`;
    $('saveRateBtn').classList.toggle('hidden',!canRate);
    $('entryStatus').textContent=num(s.submit_ready_qty)>0?'Ready for production submit':'No quantity ready to submit';
    $('submitBtn').disabled=num(s.submit_ready_qty)<=0||s.actual_rate==null;
    await loadRecentSubmits();
  }catch(e){console.error(e);$('entryStatus').textContent=e.message;$('submitBtn').disabled=true}
}

async function saveRate(){
  try{
    const rate=Number($('eRate').value);
    if(!Number.isFinite(rate)||rate<0)throw new Error('Enter a valid Actual Rate.');
    await rpc('rr_upm_set_department_rate_v2',{p_canonical_lot_id:$('eLot').value,p_department_code:$('eDept').value,p_actual_rate:rate});
    await refreshEntrySummary();alert('Actual Rate saved.');
  }catch(e){alert(e.message)}
}

function renderWorkPreview(){
  $('workPreview').innerHTML=state.workFiles.map((f,i)=>`<div class="work-thumb"><img src="${URL.createObjectURL(f)}" alt="Work evidence"><button type="button" data-remove-work="${i}">×</button></div>`).join('');
  document.querySelectorAll('[data-remove-work]').forEach(b=>b.onclick=()=>{state.workFiles.splice(Number(b.dataset.removeWork),1);renderWorkPreview()});
}

function onWorkImages(ev){
  const files=[...(ev.target.files||[])].filter(f=>f.type.startsWith('image/'));
  state.workFiles=[...state.workFiles,...files].slice(0,5);renderWorkPreview();ev.target.value='';
}

async function uploadWorkImages(){
  const paths=[];
  for(const f of state.workFiles){
    const ext=(f.name.split('.').pop()||'jpg').replace(/[^a-z0-9]/gi,'').toLowerCase();
    const path=`${$('eLot').value}/${$('eDept').value}/${Date.now()}-${crypto.randomUUID()}.${ext}`;
    const {error}=await state.client.storage.from('redzed-production-work').upload(path,f,{contentType:f.type||'image/jpeg',upsert:false});
    if(error)throw error;paths.push(path);
  }
  return paths;
}


async function loadRecentSubmits(){
  const box=$('recentSubmits'); if(!box)return;
  const {data,error}=await state.client.from('rr_upm_submit_ledger_v2').select('id,submitted_qty,department_code,colour_code,size_code,submitted_by_name,created_at,submit_status,reverse_reason').eq('canonical_lot_id',$('eLot').value).eq('department_code',$('eDept').value).eq('colour_code',$('eColour').value).order('created_at',{ascending:false}).limit(8);
  if(error){box.textContent=error.message;return}
  box.innerHTML=(data||[]).length?(data||[]).map(x=>`<div style="padding:7px 0;border-bottom:1px solid #383842"><b>${num(x.submitted_qty)} PCS</b> · ${safe(x.submit_status)} · ${safe(x.submitted_by_name||'')} · ${new Date(x.created_at).toLocaleString()} ${x.submit_status==='ACTIVE'&&isHeadFor(x.department_code)?`<button type="button" data-reverse="${x.id}" style="margin-left:8px">Reverse</button>`:''}${x.reverse_reason?`<div class="muted">Reason: ${safe(x.reverse_reason)}</div>`:''}</div>`).join(''):'No submissions yet.';
  box.querySelectorAll('[data-reverse]').forEach(b=>b.onclick=()=>reverseSubmit(b.dataset.reverse));
}
async function reverseSubmit(id){
  const reason=prompt('Reverse reason mandatory:'); if(!reason?.trim())return;
  if(!confirm('This will reverse the submission and restore the previous balance. Continue?'))return;
  try{await rpc('rr_upm_reverse_submit_v3',{p_submit_id:id,p_reason:reason.trim()});await refreshEntrySummary();await load();alert('Submission reversed with audit history.')}catch(e){alert(e.message)}
}

async function saveEntry(ev){
  ev.preventDefault();let paths=[];
  try{
    const s=state.entrySummary;if(!s)throw new Error('Submit summary unavailable.');
    if(s.image_required&&state.workFiles.length<1)throw new Error('Live work image is mandatory for Printing/Stitching.');
    if(s.actual_rate==null)throw new Error('Actual Rate pending from Department Head.');
    const ok=confirm(`Confirm Submit\n\nLot: ${$('eLotNo').textContent}\nDepartment: ${$('eDept').value}\nColour: ${$('eColour').value}\nSubmit Ready Qty: ${num(s.submit_ready_qty)} PCS\n\nThis quantity will open for the next department.`);
    if(!ok)return;
    $('submitBtn').disabled=true;$('submitBtn').textContent='Submitting…';
    paths=await uploadWorkImages();
    await rpc('rr_upm_submit_ready_v2',{
      p_canonical_lot_id:$('eLot').value,
      p_department_code:$('eDept').value,
      p_colour_code:$('eColour').value,
      p_size_code:$('eSize').value||'ALL',
      p_remarks:$('eRemarks').value||null,
      p_evidence_paths:paths
    });
    close('entryModal');state.workFiles=[];await load();alert('Production submitted and next department opened.');
  }catch(e){
    if(paths.length)await Promise.all(paths.map(p=>state.client.storage.from('redzed-production-work').remove([p]).catch(()=>null)));
    alert(e.message);
  }finally{$('submitBtn').textContent='SUBMIT';$('submitBtn').disabled=false}
}

function prepareAlterUser(l){
  window.REDZED_USER={
    id:state.user?.user_id||state.auth?.id||state.auth?.user?.id,
    name:state.user?.display_name||state.auth?.name||state.auth?.email||'User',
    role:category(),
    department_id:null,
    department_name:state.user?.department_name||state.user?.department_code||colours(l)[0]?.current_department_code||'',
    line_man_id:state.user?.line_man_id||null,line_man_name:state.user?.line_man_name||'',
    cutting_master_id:state.user?.cutting_master_id||null,cutting_master_name:state.user?.cutting_master_name||''
  };
}
function openAlterModule(id,mode='ALTER'){
  const l=currentLot(id);if(!l)return;prepareAlterUser(l);state.alterMode=mode;
  $('alterModuleTitle').textContent=`${mode==='ALTER'?'Alter':mode==='REMAKE'?'Remake':'Damage'} — LOT ${l.lot_no}`;open('alterModuleModal');
  try{window.RedzedAlter.mount('#alterRoot',{lotId:l.canonical_lot_id,lotNo:l.lot_no,mode,departmentName:window.REDZED_USER.department_name,colours:colours(l),referenceVisualHtml:visualPanel(l),onReferenceBind:()=>bindVisualButtons($('alterRoot'))})}catch(e){console.error(e);alert(e.message)}
}

async function register(ev){ev.preventDefault();try{let cs=[];if($('rColours').value.trim())cs=JSON.parse($('rColours').value);await rpc('rr_upm_register_lot_v1',{p_canonical_lot_id:$('rId').value.trim(),p_lot_no:$('rLotNo').value.trim(),p_source_table:'MANUAL',p_source_id:null,p_art_no:$('rArt').value||null,p_item_name:$('rItem').value||null,p_total_qty:Number($('rQty').value||0),p_colours:cs,p_metadata:{registered_from:'UPM_UI'}});close('registerModal');ev.target.reset();await load()}catch(e){alert(e.message)}}

async function boot(){
  try{
    state.client=window.supabaseClient||window.sb;if(!state.client)throw new Error('Supabase client unavailable');
    state.auth=await RR.requireRoles(['owner','admin','production','manager','line_manager','worker','department_head','cutting_master']);
    await loadUser();
    $('refresh').onclick=load;$('registerBtn').onclick=()=>open('registerModal');$('search').oninput=render;$('deptFilter').onchange=render;
    $('entryForm').onsubmit=saveEntry;$('registerForm').onsubmit=register;$('saveRateBtn').onclick=saveRate;
    $('eDept').onchange=refreshEntrySummary;$('eColour').onchange=refreshEntrySummary;$('eSize').onchange=refreshEntrySummary;
    $('eWorkImages').onchange=onWorkImages;
    $('viewerClose').onclick=closeViewer;$('viewerPrev').onclick=()=>moveViewer(-1);$('viewerNext').onclick=()=>moveViewer(1);
    let touchX=null;$('viewerStage').addEventListener('touchstart',e=>{touchX=e.changedTouches[0].clientX},{passive:true});$('viewerStage').addEventListener('touchend',e=>{if(touchX==null)return;const dx=e.changedTouches[0].clientX-touchX;if(Math.abs(dx)>45)moveViewer(dx<0?1:-1);touchX=null},{passive:true});
    document.addEventListener('keydown',e=>{if($('imageViewer').classList.contains('hidden'))return;if(e.key==='Escape')closeViewer();if(e.key==='ArrowLeft')moveViewer(-1);if(e.key==='ArrowRight')moveViewer(1)});
    document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>close(b.dataset.close));
    await load();
  }catch(e){console.error(e);msg(e.message,'error')}
}
window.RedzedUPM={openEntry,openAlterModule,reload:load,getLot:currentLot};
document.readyState==='loading'?document.addEventListener('DOMContentLoaded',boot):boot();
})();
