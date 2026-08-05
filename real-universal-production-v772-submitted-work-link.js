(()=>{
'use strict';

const VERSION='772.7';
const $=id=>document.getElementById(id);
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({
  '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'
}[c]));
const upper=v=>String(v||'').trim().toUpperCase();
const money=v=>Number(v||0).toLocaleString('en-IN',{
  minimumFractionDigits:2,
  maximumFractionDigits:4
});
const qty=v=>Number(v||0).toLocaleString('en-IN',{
  minimumFractionDigits:0,
  maximumFractionDigits:3
});
const errorText=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(' — ')||'Unknown error';

const state={
  client:null,
  rows:[],
  filtered:[],
  loading:false,
  lotMetaByCanonical:new Map(),
  lotMetaByLotNo:new Map()
};

function getClient(){
  return window.supabaseClient||
    window.supabaseDb||
    window.redzedSupabase||
    window.sb||
    window.supabase?.client||
    null;
}

async function rpc(name,payload={}){
  const client=state.client||getClient();
  if(!client)throw new Error('Supabase client unavailable. Check config.js.');
  const r=await client.rpc(name,payload);
  if(r.error)throw r.error;
  return r.data;
}

function currentLotNo(){
  const identity=$('identity');
  if(identity){
    const boxes=[...identity.querySelectorAll('.box')];
    for(const box of boxes){
      const label=upper(box.querySelector('small')?.textContent);
      if(label==='LOT NO'){
        const clone=box.cloneNode(true);
        clone.querySelector('small')?.remove();
        const value=clone.textContent.trim();
        if(value)return upper(value);
      }
    }
    const m=identity.textContent.match(/LOT\s*NO\s*([A-Z0-9-]+)/i);
    if(m?.[1])return upper(m[1]);
  }
  const search=$('search')?.value?.trim();
  return search?upper(search):'';
}

function firstValue(obj,keys){
  for(const key of keys){
    const value=obj?.[key];
    if(value!==null&&value!==undefined&&String(value).trim()!=='')return value;
  }
  return '';
}

function normalizeImageUrl(value){
  const url=String(value||'').trim();
  if(!url)return '';
  if(/^(https?:|data:|blob:)/i.test(url))return url;
  if(url.startsWith('//'))return `https:${url}`;
  return '';
}

function findImageDeep(value,depth=0){
  if(depth>4||value===null||value===undefined)return '';
  if(typeof value==='string')return normalizeImageUrl(value);
  if(Array.isArray(value)){
    for(const item of value){
      const found=findImageDeep(item,depth+1);
      if(found)return found;
    }
    return '';
  }
  if(typeof value==='object'){
    const preferred=[];
    const rest=[];
    for(const [key,item] of Object.entries(value)){
      if(/(art.*image|image.*art|thumbnail|thumb|photo|image|media.*url|url.*media)/i.test(key)){
        preferred.push(item);
      }else if(/(metadata|payload|details|media|images|art)/i.test(key)){
        rest.push(item);
      }
    }
    for(const item of [...preferred,...rest]){
      const found=findImageDeep(item,depth+1);
      if(found)return found;
    }
  }
  return '';
}

function domImageForLot(lotNo){
  const wanted=upper(lotNo);
  for(const card of document.querySelectorAll('.lot-card')){
    const cardLot=upper(card.querySelector('.lot-no')?.textContent);
    if(cardLot===wanted){
      return card.querySelector('img')?.src||'';
    }
  }
  return '';
}

function normalizeLotMeta(row){
  return {
    artNo:String(firstValue(row,[
      'art_no','article_no','article_code','art_code','style_no','style_code'
    ])||'').trim(),
    itemName:String(firstValue(row,[
      'item_name','product_name','item','product','style_name','article_name',
      'garment_name','description'
    ])||'').trim(),
    imageUrl:normalizeImageUrl(firstValue(row,[
      'art_image_url','art_media_url','art_photo_url','thumbnail_url',
      'image_url','photo_url','art_image','thumbnail'
    ]))||findImageDeep(row)
  };
}

function metaFor(row){
  const byCanonical=state.lotMetaByCanonical.get(String(row.canonical_lot_id||''));
  const byLot=state.lotMetaByLotNo.get(upper(row.lot_no));
  const meta=byCanonical||byLot||{};
  return {
    artNo:meta.artNo||'—',
    itemName:meta.itemName||'Item name unavailable',
    imageUrl:meta.imageUrl||domImageForLot(row.lot_no)||''
  };
}

async function loadLotMetadata(){
  state.lotMetaByCanonical.clear();
  state.lotMetaByLotNo.clear();

  const canonicalIds=[...new Set(
    state.rows.map(x=>String(x.canonical_lot_id||'').trim()).filter(Boolean)
  )];
  const lotNos=[...new Set(
    state.rows.map(x=>String(x.lot_no||'').trim()).filter(Boolean)
  )];

  const client=state.client||getClient();
  if(!client)return;

  let metadataRows=[];

  // Primary lookup by canonical lot identity.
  for(let i=0;i<canonicalIds.length;i+=100){
    const chunk=canonicalIds.slice(i,i+100);
    const result=await client
      .from('rr_upm_lot_registry')
      .select('*')
      .in('canonical_lot_id',chunk);
    if(!result.error)metadataRows.push(...(result.data||[]));
  }

  // Fallback by visible Lot No where canonical identity is absent.
  if(!metadataRows.length&&lotNos.length){
    for(let i=0;i<lotNos.length;i+=100){
      const chunk=lotNos.slice(i,i+100);
      const result=await client
        .from('rr_upm_lot_registry')
        .select('*')
        .in('lot_no',chunk);
      if(!result.error)metadataRows.push(...(result.data||[]));
    }
  }

  for(const row of metadataRows){
    const meta=normalizeLotMeta(row);
    if(row.canonical_lot_id){
      state.lotMetaByCanonical.set(String(row.canonical_lot_id),meta);
    }
    if(row.lot_no){
      state.lotMetaByLotNo.set(upper(row.lot_no),meta);
    }
  }
}

function installStyles(){
  if($('rrV7722Styles'))return;
  const style=document.createElement('style');
  style.id='rrV7722Styles';
  style.textContent=`
  #rrActiveRateModalV7722{
    position:fixed;inset:0;background:#000d;z-index:9999;
    display:flex;align-items:flex-end;justify-content:center;
  }
  #rrActiveRateModalV7722.rr-hidden{display:none!important}
  #rrActiveRateModalV7722 .rr-sheet{
    width:min(1600px,100%);height:min(97vh,1150px);
    background:#10131a;border:1px solid #39414d;
    border-radius:18px 18px 0 0;padding:12px;overflow:auto;color:#fff;
  }
  #rrActiveRateModalV7722 .rr-head,
  #rrActiveRateModalV7722 .rr-tools{
    display:flex;align-items:center;justify-content:space-between;gap:8px;flex-wrap:wrap;
  }
  #rrActiveRateModalV7722 .rr-tools{
    position:sticky;top:-12px;z-index:3;background:#10131af5;padding:10px 0;
  }
  #rrActiveRateModalV7722 input,
  #rrActiveRateModalV7722 select,
  #rrActiveRateModalV7722 button{
    background:#242934;color:#fff;border:1px solid #39414d;
    border-radius:9px;padding:10px;font:inherit;
  }
  #rrActiveRateModalV7722 button{font-weight:800;cursor:pointer}
  #rrActiveRateModalV7722 button:disabled{opacity:.5;cursor:not-allowed}
  #rrActiveRateModalV7722 .rr-load{background:#174936;border-color:#318b65}
  #rrActiveRateModalV7722 .rr-close{background:#481d24;border-color:#8c3c49}
  #rrActiveRateModalV7722 .rr-search{flex:1;min-width:240px}
  #rrActiveRateModalV7722 .rr-note{
    padding:9px 10px;border-left:3px solid #ffc857;
    background:#281f0d;border-radius:8px;color:#ffe3a0;margin:8px 0;
  }
  #rrActiveRateModalV7722 .rr-enter-note{
    padding:8px 10px;border-left:3px solid #56efb2;
    background:#10261c;border-radius:8px;color:#baf7da;margin:8px 0;
  }
  #rrActiveRateModalV7722 .rr-msg{min-height:24px;padding:8px 0;color:#56efb2}
  #rrActiveRateModalV7722 .rr-msg.rr-error{color:#ff8d95}
  #rrActiveRateModalV7722 .rr-wrap{
    overflow:auto;border:1px solid #303641;border-radius:12px;max-height:59vh
  }
  #rrActiveRateModalV7722 table{width:100%;border-collapse:separate;border-spacing:0;min-width:1450px}
  #rrActiveRateModalV7722 th,
  #rrActiveRateModalV7722 td{
    padding:10px 8px;border-bottom:1px solid #2a303a;text-align:left;
    white-space:nowrap;vertical-align:middle;background:#10131a
  }
  #rrActiveRateModalV7722 th{
    position:sticky;top:0;background:#20252e;z-index:4
  }
  #rrActiveRateModalV7722 th:first-child,
  #rrActiveRateModalV7722 td:first-child{
    position:sticky;left:0;z-index:3;background:#151a23
  }
  #rrActiveRateModalV7722 th:first-child{z-index:6;background:#20252e}
  #rrActiveRateModalV7722 .rr-bad{color:#ff8d95;font-weight:900}
  #rrActiveRateModalV7722 .rr-ok{color:#56efb2;font-weight:900}
  #rrActiveRateModalV7722 .rr-rate-editor{display:flex;gap:6px;align-items:center}
  #rrActiveRateModalV7722 .rr-rate-editor input{width:115px}
  #rrActiveRateModalV7722 .rr-rate-editor button{
    background:#174936;border-color:#318b65;min-width:118px
  }
  #rrActiveRateModalV7722 .rr-rate-editor input:focus{
    outline:2px solid #56efb2;box-shadow:0 0 0 4px #56efb233
  }
  #rrActiveRateModalV7722 .rr-art-cell{
    display:flex;gap:9px;align-items:center;min-width:220px
  }
  #rrActiveRateModalV7722 .rr-art-img,
  #rrActiveRateModalV7722 .rr-art-placeholder{
    width:52px;height:52px;flex:0 0 52px;border-radius:8px;
    border:1px solid #39414d;background:#080a0f;object-fit:cover
  }
  #rrActiveRateModalV7722 .rr-art-placeholder{
    display:flex;align-items:center;justify-content:center;
    color:#98a2b3;font-size:9px;text-align:center
  }
  #rrActiveRateModalV7722 .rr-art-info{
    display:grid;gap:3px;white-space:normal;max-width:210px
  }
  #rrActiveRateModalV7722 .rr-art-info b{color:#ffc857}
  #rrActiveRateModalV7722 .rr-art-info span{color:#d9e1ec}
  #rrActiveRateModalV7722 .rr-group-list{
    max-width:270px;white-space:normal;line-height:1.35;color:#d9e1ec
  }
  #rrActiveRateModalV7722 .rr-group-list b{color:#fff}
  #rrActiveRateModalV7722 .rr-conflict{color:#ffb45f;font-weight:900}
  #rrActiveRateModalV7722 .rr-missing-count{color:#ff8d95;font-weight:850;font-size:11px}
  #rrActiveRateModalV7722 .rr-stats{display:flex;gap:8px;flex-wrap:wrap;margin:8px 0}
  #rrActiveRateModalV7722 .rr-stat{
    background:#171b23;border:1px solid #303641;border-radius:10px;padding:8px 10px
  }
  #rrActiveRateModalV7722 .rr-stat small{display:block;color:#98a2b3}
  #rrActiveRateModalV7722 .rr-stat b{font-size:18px}
  #rrActiveRateV7722{background:#493915;border-color:#8a6b2b}
  @media(max-width:700px){
    #rrActiveRateModalV7722 .rr-sheet{height:99vh}
    #rrActiveRateModalV7722 .rr-tools{align-items:stretch}
    #rrActiveRateModalV7722 .rr-search{width:100%}
  }`;
  document.head.appendChild(style);
}

function installModal(){
  if($('rrActiveRateModalV7722'))return;
  const modal=document.createElement('div');
  modal.id='rrActiveRateModalV7722';
  modal.className='rr-hidden';
  modal.innerHTML=`
    <section class="rr-sheet">
      <div class="rr-head">
        <div>
          <h2 style="margin:0">ASSIGNMENT ACTUAL RATE · V${VERSION}</h2>
          <div style="color:#98a2b3;margin-top:3px">
            Active + submitted + completed · Exact Lot + Department + Worker + Colour assignment rate
          </div>
        </div>
        <button id="rrCloseActiveRateV7722" class="rr-close" type="button">CLOSE</button>
      </div>

      <div class="rr-note">
        यह Costing Department Rate नहीं है। Submit और PCS salary के लिए केवल exact
        Assignment Actual Rate save होगी। Standard Rate या Department Rate fallback नहीं लगेगा।
      </div>

      <div class="rr-enter-note">
        <b>ONE ROW = ONE LOT + ONE DEPARTMENT:</b>
        इस list में एक ही Lot–Department की सभी Colours, bound Sizes और Workers एक group में रहेंगी।
        Rate लिखकर <b>Enter</b> या <b>SAVE GROUP + NEXT</b> दबाते ही पूरी group में वही rate लगेगी,
        group list से हटेगी और cursor अगली unresolved Lot–Department row पर जाएगा।
      </div>

      <div class="rr-tools">
        <input id="rrActiveRateSearchV7722" class="rr-search"
          placeholder="Search Lot / Art / Item / Department / Worker / Colour">
        <select id="rrAssignmentScopeV7724" title="Assignment status filter">
          <option value="ALL">ALL RELEVANT STATUS</option>
          <option value="ACTIVE">ACTIVE ONLY</option>
          <option value="COMPLETED">SUBMITTED / COMPLETED</option>
        </select>
        <label style="display:flex;gap:7px;align-items:center">
          <input id="rrMissingOnlyV7722" type="checkbox" checked style="width:20px;height:20px">
          Missing / Conflict only
        </label>
        <button id="rrLoadActiveRateV7722" class="rr-load" type="button">LOAD ASSIGNMENTS</button>
      </div>

      <div id="rrActiveRateStatsV7722" class="rr-stats"></div>
      <div id="rrActiveRateMsgV7722" class="rr-msg"></div>

      <div class="rr-wrap">
        <table>
          <thead>
            <tr>
              <th>Lot</th><th>Art Image / Item</th><th>Department</th><th>Workers</th>
              <th>Colours</th><th>Status</th><th>Assignments</th><th>Assigned PCS</th>
              <th>Group Actual Rate</th><th>Rate Filled By</th><th>Fill / Edit</th>
            </tr>
          </thead>
          <tbody id="rrActiveRateBodyV7722"></tbody>
        </table>
      </div>
    </section>`;
  document.body.appendChild(modal);

  $('rrCloseActiveRateV7722').onclick=()=>modal.classList.add('rr-hidden');
  modal.addEventListener('click',e=>{
    if(e.target===modal)modal.classList.add('rr-hidden');
  });
  $('rrLoadActiveRateV7722').onclick=()=>loadAssignments();
  $('rrActiveRateSearchV7722').addEventListener('input',()=>renderAssignments());
  $('rrMissingOnlyV7722').addEventListener('change',()=>renderAssignments());
  $('rrAssignmentScopeV7724').addEventListener('change',()=>renderAssignments());
}

function installButtons(){
  if(!$('rrSubmittedWorkV772')){
    const submitted=document.createElement('button');
    submitted.id='rrSubmittedWorkV772';
    submitted.type='button';
    submitted.textContent='SUBMITTED WORK';
    submitted.title='Department / Worker wise submitted PCS and Assignment Actual Rate';
    submitted.dataset.version=VERSION;
    submitted.onclick=()=>{location.href='real-upm-submitted-work-v772.html?v=7727'};
    const bar=document.querySelector('.modulebar')||document.querySelector('.toolbar')||document.querySelector('.top');
    if(bar)bar.appendChild(submitted);
    else{
      submitted.style.cssText='position:fixed;right:14px;bottom:14px;z-index:45;background:#174936;border-color:#318b65';
      document.body.appendChild(submitted);
    }
  }

  if(!$('rrActiveRateV7722')){
    const active=document.createElement('button');
    active.id='rrActiveRateV7722';
    active.type='button';
    active.textContent='ASSIGNMENT RATE';
    active.title='Active, submitted और completed assignments का exact Actual Rate fill/edit करें';
    active.dataset.version=VERSION;
    active.onclick=openAssignmentRate;
    const bar=document.querySelector('.modulebar')||document.querySelector('.toolbar')||document.querySelector('.top');
    if(bar)bar.appendChild(active);
    else{
      active.style.cssText='position:fixed;right:14px;bottom:64px;z-index:45';
      document.body.appendChild(active);
    }
  }
}

function say(text,type=''){
  const el=$('rrActiveRateMsgV7722');
  if(!el)return;
  el.textContent=text||'';
  el.className=`rr-msg ${type==='error'?'rr-error':''}`.trim();
}

function openAssignmentRate(){
  const modal=$('rrActiveRateModalV7722');
  modal.classList.remove('rr-hidden');
  const lot=currentLotNo();
  if(lot)$('rrActiveRateSearchV7722').value=lot;
  loadAssignments({focusFirst:true});
}

async function loadAssignments(options={}){
  if(state.loading)return;
  state.loading=true;
  const button=$('rrLoadActiveRateV7722');

  try{
    button.disabled=true;
    say('Assignments aur Art/Item details load ho rahe hain…');
    state.client=getClient();
    if(!state.client)throw new Error('Supabase client unavailable. Check config.js.');

    const result=await state.client
      .from('rr_upm_work_assignments_v8')
      .select('id,canonical_lot_id,lot_no,department_code,worker_id,worker_code,worker_name_snapshot,colour_code,colour_name,assigned_qty,status,actual_rate,rate_filled_by_name,rate_filled_at,assigned_at')
      .order('assigned_at',{ascending:false})
      .limit(5000);

    if(result.error)throw result.error;
    state.rows=result.data||[];

    try{
      await loadLotMetadata();
    }catch(metaError){
      console.warn('Lot metadata load skipped:',metaError);
    }

    renderAssignments(options);
    say(`${state.rows.length} assignment rows loaded. Missing Rate module अब Lot + Department group-wise चल रही है.`);
  }catch(e){
    say(errorText(e),'error');
  }finally{
    state.loading=false;
    button.disabled=false;
  }
}

function groupKey(row){
  return `${upper(row.lot_no)}||${upper(row.department_code)}`;
}

function scopedRows(){
  const scope=$('rrAssignmentScopeV7724')?.value||'ALL';
  const activeStatuses=new Set(['ASSIGNED','IN_PROGRESS']);
  const completedStatuses=new Set(['COMPLETED','SUBMITTED','DONE','CLOSED']);
  const excludedStatuses=new Set(['CANCELLED','CANCELED','VOID','REJECTED']);

  return state.rows.filter(row=>{
    const status=upper(row.status);
    if(excludedStatuses.has(status))return false;
    if(scope==='ACTIVE'&&!activeStatuses.has(status))return false;
    if(scope==='COMPLETED'&&!completedStatuses.has(status))return false;
    return true;
  });
}

function buildGroups(){
  const map=new Map();

  for(const row of scopedRows()){
    const key=groupKey(row);
    if(!map.has(key)){
      map.set(key,{
        key,
        lotNo:row.lot_no||'—',
        departmentCode:row.department_code||'—',
        rows:[],
        assignedQty:0,
        workers:new Map(),
        colours:new Map(),
        statuses:new Set(),
        positiveRates:new Set(),
        rateFilledBy:new Set(),
        missingAssignments:0,
        representativeRow:row
      });
    }

    const group=map.get(key);
    group.rows.push(row);
    group.assignedQty+=Number(row.assigned_qty||0);

    const workerKey=String(row.worker_id||row.worker_code||row.worker_name_snapshot||'—');
    group.workers.set(
      workerKey,
      String(row.worker_name_snapshot||row.worker_code||'—')
    );

    const colourKey=String(row.colour_code||row.colour_name||'—');
    group.colours.set(
      colourKey,
      String(row.colour_code||row.colour_name||'—')
    );

    group.statuses.add(upper(row.status)||'—');

    const rate=Number(row.actual_rate||0);
    if(rate>0)group.positiveRates.add(rate.toFixed(4));
    else group.missingAssignments+=1;

    if(row.rate_filled_by_name){
      group.rateFilledBy.add(String(row.rate_filled_by_name));
    }

    if(rate<=0&&Number(group.representativeRow?.actual_rate||0)>0){
      group.representativeRow=row;
    }
  }

  return [...map.values()].map(group=>{
    group.rateValues=[...group.positiveRates]
      .map(Number)
      .sort((a,b)=>a-b);

    group.hasConflict=group.rateValues.length>1;
    group.hasIssue=group.missingAssignments>0||group.hasConflict;
    group.groupRate=group.rateValues.length===1?group.rateValues[0]:0;
    group.assignmentCount=group.rows.length;
    group.workerNames=[...group.workers.values()].sort();
    group.colourCodes=[...group.colours.values()].sort();
    group.statusNames=[...group.statuses].sort();

    const missingRepresentative=group.rows.find(
      row=>Number(row.actual_rate||0)<=0
    );
    group.representativeRow=missingRepresentative||group.rows[0];

    return group;
  });
}

function filteredGroups(){
  const q=$('rrActiveRateSearchV7722').value.trim().toLowerCase();
  const issueOnly=$('rrMissingOnlyV7722').checked;

  return buildGroups().filter(group=>{
    if(issueOnly&&!group.hasIssue)return false;

    if(!q)return true;

    const meta=metaFor(group.representativeRow);
    return JSON.stringify([
      group.lotNo,
      meta.artNo,
      meta.itemName,
      group.departmentCode,
      group.workerNames,
      group.colourCodes,
      group.statusNames,
      group.rateValues
    ]).toLowerCase().includes(q);
  }).sort((a,b)=>{
    if(a.hasIssue!==b.hasIssue)return a.hasIssue?-1:1;
    const lotCompare=String(a.lotNo).localeCompare(
      String(b.lotNo),
      undefined,
      {numeric:true,sensitivity:'base'}
    );
    if(lotCompare)return lotCompare;
    return String(a.departmentCode).localeCompare(
      String(b.departmentCode),
      undefined,
      {sensitivity:'base'}
    );
  });
}

function artCell(row){
  const meta=metaFor(row);
  const image=meta.imageUrl
    ?`<a href="${safe(meta.imageUrl)}" target="_blank" rel="noopener">
        <img class="rr-art-img" src="${safe(meta.imageUrl)}"
          alt="${safe(meta.artNo)}"
          onerror="this.closest('a').outerHTML='<div class=&quot;rr-art-placeholder&quot;>NO IMAGE</div>'">
      </a>`
    :'<div class="rr-art-placeholder">NO IMAGE</div>';

  return `<div class="rr-art-cell">
    ${image}
    <div class="rr-art-info">
      <b>ART ${safe(meta.artNo)}</b>
      <span>${safe(meta.itemName)}</span>
    </div>
  </div>`;
}

function compactNames(values,limit=4){
  const list=[...values];
  const shown=list.slice(0,limit);
  const remaining=list.length-shown.length;
  return `${shown.map(safe).join(', ')}${remaining>0?` <b>+${remaining}</b>`:''}`;
}

function groupRateHtml(group){
  if(group.hasConflict){
    return `<span class="rr-conflict">CONFLICT · ${
      group.rateValues.map(rate=>`₹${money(rate)}`).join(' / ')
    }</span>`;
  }

  if(group.groupRate>0){
    return `<span class="rr-ok">₹${money(group.groupRate)}</span>${
      group.missingAssignments>0
        ?`<div class="rr-missing-count">${group.missingAssignments} assignment(s) missing</div>`
        :''
    }`;
  }

  return `<span class="rr-bad">MISSING</span>`;
}

function renderAssignments(options={}){
  const groups=filteredGroups();
  state.filtered=groups;

  const missingAssignments=groups.reduce(
    (sum,group)=>sum+group.missingAssignments,
    0
  );
  const conflictGroups=groups.filter(group=>group.hasConflict).length;
  const totalQty=groups.reduce(
    (sum,group)=>sum+group.assignedQty,
    0
  );

  $('rrActiveRateStatsV7722').innerHTML=[
    ['Lot–Dept Groups',groups.length],
    ['Missing Assignments',missingAssignments],
    ['Conflict Groups',conflictGroups],
    ['Assigned PCS',qty(totalQty)],
    ['Departments',new Set(groups.map(group=>upper(group.departmentCode))).size],
    ['Workers',new Set(groups.flatMap(group=>[...group.workers.keys()])).size],
    ['Colours',new Set(groups.flatMap(group=>[...group.colours.keys()])).size]
  ].map(([label,value])=>
    `<div class="rr-stat"><small>${safe(label)}</small><b>${safe(value)}</b></div>`
  ).join('');

  $('rrActiveRateBodyV7722').innerHTML=groups.length?groups.map(group=>{
    const row=group.representativeRow;
    const inputValue=group.groupRate>0&&!group.hasConflict
      ?safe(group.groupRate)
      :'';

    const buttonText=group.groupRate>0||group.hasConflict
      ?'UPDATE GROUP + NEXT'
      :'SAVE GROUP + NEXT';

    return `<tr data-rr-group-row="${safe(group.key)}">
      <td><b>${safe(group.lotNo)}</b></td>
      <td>${artCell(row)}</td>
      <td><b>${safe(group.departmentCode)}</b></td>
      <td>
        <div class="rr-group-list">
          ${compactNames(group.workerNames)}
          <div class="rr-missing-count">${group.workerNames.length} worker(s)</div>
        </div>
      </td>
      <td>
        <div class="rr-group-list">
          ${compactNames(group.colourCodes,6)}
          <div class="rr-missing-count">${group.colourCodes.length} colour(s) · all bound sizes</div>
        </div>
      </td>
      <td>${safe(group.statusNames.join(', '))}</td>
      <td><b>${group.assignmentCount}</b></td>
      <td>${qty(group.assignedQty)}</td>
      <td>${groupRateHtml(group)}</td>
      <td>${safe([...group.rateFilledBy].join(', ')||'—')}</td>
      <td>
        <div class="rr-rate-editor">
          <input data-rr-rate-group="${safe(group.key)}" type="number"
            min="0.0001" step="0.0001"
            value="${inputValue}"
            placeholder="Group Actual Rate"
            inputmode="decimal">
          <button
            data-rr-save-group="${safe(group.key)}"
            data-rr-assignment-id="${safe(row.id)}"
            type="button">${safe(buttonText)}</button>
        </div>
      </td>
    </tr>`;
  }).join(''):'<tr><td colspan="11" style="padding:24px;text-align:center;color:#98a2b3">No unresolved Lot–Department rate groups.</td></tr>';

  const body=$('rrActiveRateBodyV7722');

  body.querySelectorAll('[data-rr-save-group]').forEach(button=>{
    button.onclick=()=>saveGroupRateAndNext(button);
  });

  body.querySelectorAll('[data-rr-rate-group]').forEach(input=>{
    input.addEventListener('keydown',event=>{
      if(event.key!=='Enter')return;
      event.preventDefault();
      const key=input.dataset.rrRateGroup;
      const saveButton=body.querySelector(
        `[data-rr-save-group="${CSS.escape(key)}"]`
      );
      if(saveButton&&!saveButton.disabled){
        saveGroupRateAndNext(saveButton);
      }
    });
  });

  let focusIndex=null;
  if(Number.isInteger(options.focusIndex))focusIndex=options.focusIndex;
  else if(options.focusFirst)focusIndex=0;

  if(focusIndex!==null){
    requestAnimationFrame(()=>focusGroupRateAt(focusIndex));
  }
}

function focusGroupRateAt(index){
  const inputs=[
    ...$('rrActiveRateBodyV7722').querySelectorAll('[data-rr-rate-group]')
  ];

  if(!inputs.length)return;

  const safeIndex=Math.max(
    0,
    Math.min(index,inputs.length-1)
  );
  const input=inputs[safeIndex];

  input.scrollIntoView({
    block:'center',
    inline:'nearest',
    behavior:'smooth'
  });
  input.focus();
  input.select();
}

async function saveGroupRateAndNext(button){
  const key=button.dataset.rrSaveGroup;
  const assignmentId=button.dataset.rrAssignmentId;
  const body=$('rrActiveRateBodyV7722');
  const inputs=[
    ...body.querySelectorAll('[data-rr-rate-group]')
  ];
  const input=body.querySelector(
    `[data-rr-rate-group="${CSS.escape(key)}"]`
  );
  const currentIndex=Math.max(0,inputs.indexOf(input));
  const group=state.filtered.find(item=>item.key===key);
  const rate=Number(input?.value);

  if(!group){
    say('Lot–Department group reload required.','error');
    return;
  }

  if(!Number.isFinite(rate)||rate<=0){
    say('Group Actual Rate 0 se zyada honi chahiye.','error');
    input?.focus();
    input?.select();
    return;
  }

  let reason='First Lot+Department group Actual Rate filled from Missing Rate module';

  const existingDifferent=
    group.hasConflict||
    (
      group.groupRate>0&&
      Math.abs(group.groupRate-rate)>0.0000001
    );

  if(existingDifferent){
    reason=prompt(
      `Complete group rate correction reason · ${group.lotNo} · ${group.departmentCode}`,
      'Authorized complete Lot+Department Actual Rate correction'
    )||'';

    if(!reason.trim())return;
  }else if(group.groupRate>0){
    reason='Existing Lot+Department rate applied to all remaining missing assignments';
  }

  // Issue-only list removes the complete saved group.
  // The same visual index therefore becomes the next unresolved group.
  const nextFocusIndex=$('rrMissingOnlyV7722').checked
    ?currentIndex
    :currentIndex+1;

  try{
    button.disabled=true;
    if(input)input.disabled=true;

    say(
      `Lot ${group.lotNo} · Department ${group.departmentCode} की पूरी group rate save हो रही है…`
    );

    const saved=await rpc(
      'rr_upm_set_assignment_actual_rate_v772',
      {
        p_assignment_id:assignmentId,
        p_actual_rate:rate,
        p_reason:reason.trim()
      }
    );

    await loadAssignments({focusIndex:nextFocusIndex});

    const updatedAssignments=Number(
      saved?.updated_assignments||group.assignmentCount
    );
    const autoFilled=Number(
      saved?.auto_filled_assignments||group.missingAssignments
    );

    say(
      `DONE · Lot ${saved?.lot_no||group.lotNo} · Department ${saved?.department_code||group.departmentCode} · `+
      `Group Rate ₹${money(saved?.group_rate||rate)}. `+
      `${updatedAssignments} assignment(s) updated; ${autoFilled} missing assignment(s) auto-filled across `+
      `${group.colourCodes.length} colour(s), all bound sizes and ${group.workerNames.length} worker(s). `+
      `Cursor next unresolved Lot–Department group पर पहुँच गया है.`
    );
  }catch(error){
    say(errorText(error),'error');

    if(input){
      input.disabled=false;
      input.focus();
      input.select();
    }
  }finally{
    button.disabled=false;
  }
}

function install(){
  installStyles();
  installModal();
  installButtons();
}

if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',install);
}else{
  install();
}
})();
