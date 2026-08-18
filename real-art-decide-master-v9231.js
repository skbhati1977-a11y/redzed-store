(()=>{
"use strict";
if(window.__RR_ART_DECIDE_MASTER_9233__)return;
window.__RR_ART_DECIDE_MASTER_9233__=true;

const $=id=>document.getElementById(id);
const state={
  client:null,role:null,filter:"all",decisions:[],counts:{},units:[],purchases:[],
  arts:[],prints:[],stickers:[],metals:[],media:[],assignments:[],printAssignments:[],
  stickerAssignments:[],metalAssignments:[],stickerInstructions:[],metalInstructions:[],
  active:null,step:"art",artId:null,printMode:"NA",printIds:[],stickerMode:"NA",
  stickerIds:[],metalMode:"NA",metalIds:[],createContext:null,createTimers:[],
  viewerItems:[],viewerIndex:0
};

const MASTER_META={
  art:{label:"Art",url:"art-v9148/?v=9233&from=art-decide",focus:"artNo"},
  print:{label:"Print",url:"real-print-master.html?v=9233&from=art-decide",focus:"printNo"},
  sticker:{label:"Sticker",url:"real-sticker-master-v804.html?v=9233&from=art-decide",focus:"itemNo",open:"newItem"},
  metal:{label:"Metal ID",url:"real-metal-id-master-v804.html?v=9233&from=art-decide",focus:"itemNo",open:"newItem"}
};

const FILTERS=[
  ["all","All CB","all"],
  ["art_due","Art Due","art_due"],
  ["art_decided","Art Decided","art_decided"],
  ["print_due","Print Due","print_due"],
  ["print_decided","Print Decided","print_decided"],
  ["sticker_due","Sticker Due","sticker_due"],
  ["sticker_decided","Sticker Decided","sticker_decided"],
  ["metal_id_due","Metal ID Due","metal_id_due"],
  ["metal_id_decided","Metal ID Decided","metal_id_decided"],
  ["fully_decided","Fully Decided","all_decisions_complete"]
];

const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
const textError=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(" — ")||"Unknown error";
const kg=v=>`${Number(v||0).toFixed(3)} kg`;
function say(text="",type=""){const el=$("message");el.textContent=text;el.className=`message ${type}`.trim()}
function decisionSay(text="",type=""){const el=$("decisionMessage");el.textContent=text;el.className=`message ${type}`.trim()}
function setBusy(button,busy,label){if(!button)return;if(busy){if(!button.dataset.old)button.dataset.old=button.textContent;button.disabled=true;button.textContent=label}else{button.disabled=false;button.textContent=button.dataset.old||button.textContent;delete button.dataset.old}}

function getClient(){
  try{if(window.supabaseClient?.from)return window.supabaseClient}catch(_e){}
  try{if(typeof supabaseClient!=="undefined"&&supabaseClient?.from)return supabaseClient}catch(_e){}
  return [window.supabaseDb,window.redzedSupabase,window.sb].find(x=>x?.from)||null
}
async function waitForClient(){const started=Date.now();while(Date.now()-started<12000){const c=getClient();if(c)return c;await new Promise(r=>setTimeout(r,100))}return null}
async function loadRole(){const r=await state.client.rpc("rr_current_role");if(!r.error&&r.data){state.role=String(r.data).toLowerCase();return}if(window.RR?.requireOwner){await RR.requireOwner();state.role="owner";return}throw new Error(`User role could not be verified: ${textError(r.error)}`)}
async function currentDataMode(){try{const r=await state.client.rpc("rr_app_data_mode_state_v786");if(!r.error&&r.data?.default_mode)return String(r.data.default_mode).toUpperCase()}catch(_e){}return "TEST"}
async function rows(table){const r=await state.client.from(table).select("*");if(r.error)throw new Error(`${table}: ${textError(r.error)}`);return r.data||[]}
async function optionalRows(table){try{return await rows(table)}catch(e){console.warn(e);return[]}}
async function printRows(){let r=await state.client.from("rr_print_library_view").select("*");if(!r.error)return r.data||[];r=await state.client.from("rr_print_master").select("*");if(r.error)throw new Error(`Print Master: ${textError(r.error)}`);return r.data||[]}
async function mediaRows(){
  try{
    const r=await state.client.from("rr_media").select("entity_type,entity_id,file_url,is_cover,sort_order,created_at").in("entity_type",["art","printing","sticker_master_v803","metal_id_master_v803"]);
    if(r.error){console.warn(r.error);return[]}
    return r.data||[]
  }catch(e){console.warn(e);return[]}
}

function unitFor(id){return state.units.find(x=>String(x.id)===String(id))||null}
function purchaseFor(unit){return state.purchases.find(x=>String(x.id)===String(unit?.purchase_id))||null}
function dNo(unit){return `D${Number(unit?.division_index||1)}`}
function cbNo(unit){return purchaseFor(unit)?.cb_no||unit?.cb_base_no||String(unit?.cb_code||"CB").replace(/[-\s]S\d+.*$/i,"")||"CB"}
function decisionFor(id){return state.decisions.find(x=>String(x.cb_unit_id)===String(id))||null}
function assignmentFor(id){return state.assignments.find(x=>String(x.cb_id)===String(id))||null}
function printIdsForAssignment(a){if(!a)return[];return state.printAssignments.filter(x=>String(x.assignment_id)===String(a.id)).sort((x,y)=>Number(x.sequence_no||0)-Number(y.sequence_no||0)).map(x=>String(x.print_id)).filter(Boolean)}
function stickerIdsForAssignment(a){if(!a)return[];return state.stickerAssignments.filter(x=>String(x.assignment_id)===String(a.id)).sort((x,y)=>Number(x.sequence_no||0)-Number(y.sequence_no||0)).map(x=>state.stickerInstructions.find(i=>String(i.id)===String(x.sticker_instruction_id))?.sticker_master_id).filter(Boolean).map(String)}
function metalIdsForAssignment(a){if(!a)return[];return state.metalAssignments.filter(x=>String(x.assignment_id)===String(a.id)).sort((x,y)=>Number(x.sequence_no||0)-Number(y.sequence_no||0)).map(x=>state.metalInstructions.find(i=>String(i.id)===String(x.metal_id_instruction_id))?.metal_id_master_id).filter(Boolean).map(String)}
function byId(list,id){return (list||[]).find(x=>String(x.id)===String(id))||null}
function activeOnly(list){return (list||[]).filter(x=>x.is_active!==false)}

function derivedCounts(){
  const d=state.decisions;
  return {
    all:d.length,
    art_due:d.filter(x=>!x.art_decided||x.art_status==="ART_DUE").length,
    art_decided:d.filter(x=>x.art_decided).length,
    print_due:d.filter(x=>x.print_status==="PRINT_DUE").length,
    print_decided:d.filter(x=>x.print_decided).length,
    sticker_due:d.filter(x=>x.sticker_status==="STICKER_DUE").length,
    sticker_decided:d.filter(x=>x.sticker_decided).length,
    metal_id_due:d.filter(x=>x.metal_id_status==="METAL_ID_DUE").length,
    metal_id_decided:d.filter(x=>x.metal_id_decided).length,
    all_decisions_complete:d.filter(x=>x.all_decisions_complete).length
  }
}

async function loadData(){
  const refresh=$("refresh");setBusy(refresh,true,"Loading…");$("gallery").setAttribute("aria-busy","true");
  try{
    const [allR,countR,arts,prints,stickers,metals,media,assignments,printAssignments,stickerAssignments,metalAssignments,stickerInstructions,metalInstructions]=await Promise.all([
      state.client.rpc("rr_pm_decision_filter_v802",{p_filter:"ALL"}),
      state.client.rpc("rr_pm_decision_tab_counts_v802"),
      rows("rr_art_master"),printRows(),rows("rr_sticker_master_library_v803"),rows("rr_metal_id_master_library_v803"),mediaRows(),
      optionalRows("rr_cb_art_assignments"),optionalRows("rr_cb_print_assignments"),optionalRows("rr_cb_sticker_assignments"),optionalRows("rr_cb_metal_id_assignments_v801"),
      optionalRows("rr_art_sticker_instructions"),optionalRows("rr_art_metal_id_instructions_v801")
    ]);
    if(allR.error)throw new Error(`CB decision list: ${textError(allR.error)}`);
    state.decisions=Array.isArray(allR.data)?allR.data:[];
    const ids=state.decisions.map(x=>x.cb_unit_id).filter(Boolean);
    let units=[];
    if(ids.length){const u=await state.client.from("rr_cb_units").select("*").in("id",ids);if(u.error)throw new Error(`CB children: ${textError(u.error)}`);units=u.data||[]}
    const purchaseIds=[...new Set(units.map(x=>x.purchase_id).filter(Boolean))];
    let purchases=[];
    if(purchaseIds.length){const p=await state.client.from("rr_fabric_purchases").select("*").in("id",purchaseIds);if(p.error)throw new Error(`CB purchases: ${textError(p.error)}`);purchases=p.data||[]}
    Object.assign(state,{units,purchases,arts:activeOnly(arts),prints:activeOnly(prints),stickers:activeOnly(stickers),metals:activeOnly(metals),media,assignments,printAssignments,stickerAssignments,metalAssignments,stickerInstructions,metalInstructions});
    state.counts=!countR.error&&countR.data?countR.data:derivedCounts();
    renderStatusTabs();renderGallery();
    say(`${state.decisions.length} CB child decision records loaded.`,"success")
  }catch(e){
    console.error(e);
    $("gallery").innerHTML=`<article class="empty"><h3>Art Decide Master could not load</h3><p>${esc(textError(e))}</p></article>`;
    say(textError(e),"error")
  }finally{$("gallery").setAttribute("aria-busy","false");setBusy(refresh,false)}
}

function countFor(key){const fallback=derivedCounts();return Number(state.counts?.[key]??fallback[key]??0)}
function renderStatusTabs(){
  $("statusTabs").innerHTML=FILTERS.map(([key,label,countKey])=>`<button class="status-tab ${state.filter===key?"active":""}" type="button" data-filter="${key}"><span>${label}</span><b>${countFor(countKey)}</b></button>`).join("");
  $("statusTabs").querySelectorAll("[data-filter]").forEach(b=>b.onclick=()=>{state.filter=b.dataset.filter;renderStatusTabs();renderGallery()})
}
function filterPass(d){
  switch(state.filter){
    case"art_due":return !d.art_decided||d.art_status==="ART_DUE";
    case"art_decided":return !!d.art_decided;
    case"print_due":return d.print_status==="PRINT_DUE";
    case"print_decided":return !!d.print_decided;
    case"sticker_due":return d.sticker_status==="STICKER_DUE";
    case"sticker_decided":return !!d.sticker_decided;
    case"metal_id_due":return d.metal_id_status==="METAL_ID_DUE";
    case"metal_id_decided":return !!d.metal_id_decided;
    case"fully_decided":return !!d.all_decisions_complete;
    default:return true
  }
}
function filterLabel(){return FILTERS.find(x=>x[0]===state.filter)?.[1]||"All CB"}
function prettyStatus(value,fallback="PENDING"){return String(value||fallback).replaceAll("_"," ")}
function statusTone(value){value=String(value||"").toUpperCase();if(value.includes("DUE")||value.includes("PENDING"))return"due";if(value.includes("DECIDED")||value.includes("NA")||value.includes("N/A"))return"done";return""}

function mediaImage(entityType,id){
  const list=state.media.filter(m=>String(m.entity_type)===String(entityType)&&String(m.entity_id)===String(id)&&m.file_url);
  list.sort((a,b)=>(Number(b.is_cover||0)-Number(a.is_cover||0))||(Number(a.sort_order||999)-Number(b.sort_order||999))||String(a.created_at||"").localeCompare(String(b.created_at||"")));
  return list[0]?.file_url||""
}
function itemImage(kind,row){
  if(!row)return"";
  if(kind==="art")return mediaImage("art",row.id);
  if(kind==="print")return row.artwork_url||row.garment_preview_url||row.image_url||mediaImage("printing",row.id);
  if(kind==="sticker")return row.image_url||mediaImage("sticker_master_v803",row.id);
  return row.image_url||mediaImage("metal_id_master_v803",row.id)
}
function previewMeta(kind,row){
  if(kind==="art")return{no:row?.art_no||row?.art_code||"ART",name:row?.product_name||row?.item_name||row?.description||"Art"};
  if(kind==="print")return{no:row?.print_no||row?.print_code||"PRINT",name:row?.print_name||row?.short_note||"Print"};
  if(kind==="sticker")return{no:row?.sticker_no||"STICKER",name:[row?.sticker_name,row?.sticker_quality].filter(Boolean).join(" · ")||"Sticker"};
  return{no:row?.metal_id_no||"METAL ID",name:[row?.metal_id_name,row?.id_size].filter(Boolean).join(" · ")||"Metal ID"}
}
function decisionPreview(unitId){
  const a=assignmentFor(unitId);
  if(!a)return[];
  const out=[];
  const art=byId(state.arts,a.art_id);
  if(art){const m=previewMeta("art",art);out.push({kind:"ART",no:m.no,name:m.name,image:itemImage("art",art)})}
  else out.push({kind:"ART",no:"N.A.",name:"No Art selected",image:"",na:true});

  const pids=printIdsForAssignment(a);
  if(a.print_not_applicable)out.push({kind:"PRINT",no:"N.A.",name:"No Print Work",image:"",na:true});
  else pids.forEach(id=>{const row=byId(state.prints,id);if(row){const m=previewMeta("print",row);out.push({kind:"PRINT",no:m.no,name:m.name,image:itemImage("print",row)})}});

  const sids=stickerIdsForAssignment(a);
  if(a.sticker_not_applicable)out.push({kind:"STICKER",no:"N.A.",name:"No Sticker Work",image:"",na:true});
  else sids.forEach(id=>{const row=byId(state.stickers,id);if(row){const m=previewMeta("sticker",row);out.push({kind:"STICKER",no:m.no,name:m.name,image:itemImage("sticker",row)})}});

  const mids=metalIdsForAssignment(a);
  if(a.metal_id_not_applicable)out.push({kind:"METAL ID",no:"N.A.",name:"No Metal ID Work",image:"",na:true});
  else mids.forEach(id=>{const row=byId(state.metals,id);if(row){const m=previewMeta("metal",row);out.push({kind:"METAL ID",no:m.no,name:m.name,image:itemImage("metal",row)})}});
  return out
}
function previewHtml(unitId){
  const items=decisionPreview(unitId);
  if(!items.length)return"";
  const imageItems=items.filter(x=>x.image);
  const imageIndex=item=>imageItems.indexOf(item);
  const groups=["ART","PRINT","STICKER","METAL ID"].map(kind=>{
    const rows=items.filter(x=>x.kind===kind);
    if(!rows.length)return`<div class="craft-group"><small>${kind}</small><div class="craft-tiles"><div class="craft-tile na"><span>N.A.</span><b>N.A.</b></div></div></div>`;
    return `<div class="craft-group"><small>${kind}</small><div class="craft-tiles">${rows.map(item=>{
      const idx=imageIndex(item);
      return `<button class="craft-tile ${item.na?"na":""}" type="button" ${item.image?`data-view-unit="${esc(unitId)}" data-view-index="${idx}"`:"disabled"}>${item.image?`<img src="${esc(item.image)}" alt="${esc(`${item.kind} ${item.no}`)}" loading="lazy">`:`<span>${item.na?"N.A.":"NO IMAGE"}</span>`}<b>${esc(item.no)}</b></button>`
    }).join("")}</div></div>`
  }).join("");
  return `<section class="craft-preview"><div class="craft-preview-head"><strong>Decided Craft Preview</strong><small>Thumbnail touch = big view</small></div><div class="craft-grid">${groups}</div></section>`
}

function renderGallery(){
  const q=$("search").value.trim().toLowerCase();
  const filtered=state.decisions.filter(filterPass).map(d=>({d,u:unitFor(d.cb_unit_id)})).filter(x=>x.u).filter(({u})=>{const s=`${cbNo(u)} ${dNo(u)} ${u.cb_code||""}`.toLowerCase();return !q||s.includes(q)}).sort((a,b)=>`${cbNo(a.u)}-${dNo(a.u)}`.localeCompare(`${cbNo(b.u)}-${dNo(b.u)}`,undefined,{numeric:true}));
  $("galleryKicker").textContent=filterLabel().toUpperCase();
  $("galleryTitle").textContent="CB Child Cards";
  $("visibleCount").textContent=`${filtered.length} shown`;
  const cards=filtered.map(({d,u})=>{
    const cb=cbNo(u),dn=dNo(u),complete=!!d.all_decisions_complete;
    const preview=complete?previewHtml(u.id):"";
    return `<article class="card" data-unit="${esc(u.id)}"><div class="card-body"><div class="card-head"><div><span class="chip ${complete?"ready":""}">${complete?"FULLY DECIDED":"CRAFTING DECISION"}</span><h3>${esc(cb)}</h3></div><span class="dno">${esc(dn)}</span></div><div class="metrics status-metrics"><div class="metric"><small>Art</small><strong class="status-text ${statusTone(d.art_status)}">${esc(prettyStatus(d.art_status,d.art_decided?"ART DECIDED":"ART DUE"))}</strong></div><div class="metric"><small>Print</small><strong class="status-text ${statusTone(d.print_status)}">${esc(prettyStatus(d.print_status))}</strong></div><div class="metric"><small>Sticker</small><strong class="status-text ${statusTone(d.sticker_status)}">${esc(prettyStatus(d.sticker_status))}</strong></div><div class="metric"><small>Metal ID</small><strong class="status-text ${statusTone(d.metal_id_status)}">${esc(prettyStatus(d.metal_id_status))}</strong></div><div class="metric"><small>Weight</small><strong>${esc(kg(u.divided_weight??u.allocated_qty))}</strong></div><div class="metric"><small>Child</small><strong>${esc(dn)}</strong></div></div>${preview}<button class="btn primary" type="button" data-decide="${esc(u.id)}" style="width:100%">${complete?"Edit Crafting Decision":"Decide / Edit Crafting"}</button></div></article>`
  }).join("");
  $("gallery").innerHTML=cards||`<article class="empty"><h3>No ${esc(filterLabel())} CB child</h3><p>${q?"Search badal kar dekhein.":"Is status mein abhi koi CB child nahi hai."}</p></article>`;
  $("gallery").querySelectorAll("[data-decide]").forEach(b=>b.onclick=()=>openDecision(b.dataset.decide));
  $("gallery").querySelectorAll("[data-view-unit]").forEach(b=>b.onclick=()=>openViewer(b.dataset.viewUnit,Number(b.dataset.viewIndex||0)))
}

function openViewer(unitId,index=0){
  const items=decisionPreview(unitId).filter(x=>x.image);
  if(!items.length)return;
  state.viewerItems=items;state.viewerIndex=Math.max(0,Math.min(index,items.length-1));
  paintViewer();
  const sheet=$("imageViewer");sheet.classList.remove("hidden");sheet.setAttribute("aria-hidden","false");document.body.style.overflow="hidden"
}
function paintViewer(){
  const item=state.viewerItems[state.viewerIndex];if(!item)return;
  $("viewerTitle").textContent=`${item.kind} · ${item.no}`;
  $("viewerName").textContent=item.name||"";
  $("viewerImage").src=item.image;
  $("viewerImage").alt=`${item.kind} ${item.no}`;
  $("viewerCounter").textContent=`${state.viewerIndex+1} / ${state.viewerItems.length}`;
  $("viewerPrev").disabled=state.viewerItems.length<2;
  $("viewerNext").disabled=state.viewerItems.length<2
}
function closeViewer(){const sheet=$("imageViewer");sheet.classList.add("hidden");sheet.setAttribute("aria-hidden","true");$("viewerImage").removeAttribute("src");state.viewerItems=[];state.viewerIndex=0;if($("decisionSheet").classList.contains("hidden")&&$("masterSheet").classList.contains("hidden"))document.body.style.overflow=""}
function moveViewer(delta){const n=state.viewerItems.length;if(!n)return;state.viewerIndex=(state.viewerIndex+delta+n)%n;paintViewer()}

function openDecision(unitId){
  const u=unitFor(unitId);if(!u)return;
  const a=assignmentFor(unitId),d=decisionFor(unitId);
  state.active=u;state.step="art";state.artId=a?.art_id?String(a.art_id):null;
  state.printIds=printIdsForAssignment(a);state.printMode=a?.print_due?"DUE":a?.print_not_applicable?"NA":state.printIds.length?"SELECTED":d?.print_status==="PRINT_DUE"?"DUE":"NA";
  state.stickerIds=stickerIdsForAssignment(a);state.stickerMode=a?.sticker_due?"DUE":a?.sticker_not_applicable?"NA":state.stickerIds.length?"SELECTED":d?.sticker_status==="STICKER_DUE"?"DUE":"NA";
  state.metalIds=metalIdsForAssignment(a);state.metalMode=a?.metal_id_due?"DUE":a?.metal_id_not_applicable?"NA":state.metalIds.length?"SELECTED":d?.metal_id_status==="METAL_ID_DUE"?"DUE":"NA";
  $("decisionTitle").textContent=`${cbNo(u)} · ${dNo(u)}`;$("decisionContext").textContent="Cutting se pehle complete crafting decision";$("pickerSearch").value="";decisionSay("");showStep("art");
  const sheet=$("decisionSheet");sheet.classList.remove("hidden");sheet.setAttribute("aria-hidden","false");document.body.style.overflow="hidden"
}
function closeDecision(){if(!$("masterSheet").classList.contains("hidden"))return;const sheet=$("decisionSheet");sheet.classList.add("hidden");sheet.setAttribute("aria-hidden","true");document.body.style.overflow=""}

function currentMode(){return state.step==="print"?state.printMode:state.step==="sticker"?state.stickerMode:state.step==="metal"?state.metalMode:null}
function setMode(mode){if(state.step==="print"){state.printMode=mode;if(mode!=="SELECTED")state.printIds=[]}else if(state.step==="sticker"){state.stickerMode=mode;if(mode!=="SELECTED")state.stickerIds=[]}else if(state.step==="metal"){state.metalMode=mode;if(mode!=="SELECTED")state.metalIds=[]}renderPicker()}
function itemMeta(step,row){
  if(step==="art")return{id:row.id,no:row.art_no||row.art_code||"ART",name:row.product_name||row.item_name||row.description||"Art"};
  if(step==="print")return{id:row.id,no:row.print_no||row.print_code||"PRINT",name:row.print_name||row.short_note||"Print"};
  if(step==="sticker")return{id:row.id,no:row.sticker_no||"STICKER",name:[row.sticker_name,row.sticker_quality].filter(Boolean).join(" · ")||"Sticker"};
  return{id:row.id,no:row.metal_id_no||"METAL ID",name:[row.metal_id_name,row.id_size].filter(Boolean).join(" · ")||"Metal ID"}
}
function sourceForStep(step=state.step){return step==="art"?state.arts:step==="print"?state.prints:step==="sticker"?state.stickers:state.metals}
function selectedIds(){return state.step==="print"?state.printIds:state.step==="sticker"?state.stickerIds:state.metalIds}
function renderPicker(){
  const step=state.step,q=$("pickerSearch").value.trim().toLowerCase(),mode=$("modeRow"),meta=MASTER_META[step];
  $("quickAdd").innerHTML=`<button class="btn add-new" id="addNewMaster" type="button">+ Add New ${esc(meta.label)}</button><small>Creates directly in ${esc(meta.label)} Master and returns here for selection.</small>`;
  $("addNewMaster").onclick=()=>openMasterCreate(step);
  if(step==="art"){mode.classList.add("hidden");mode.innerHTML=""}else{mode.classList.remove("hidden");const m=currentMode();mode.innerHTML=[["NA","N.A."],["DUE","DUE"],["SELECTED","SELECT MASTER"]].map(([v,l])=>`<button class="mode ${m===v?"selected":""}" type="button" data-mode="${v}"><strong>${l}</strong></button>`).join("");mode.querySelectorAll("[data-mode]").forEach(b=>b.onclick=()=>setMode(b.dataset.mode))}
  let list=sourceForStep();if(step!=="art"&&currentMode()!=="SELECTED")list=[];
  list=list.filter(row=>{const m=itemMeta(step,row);return !q||`${m.no} ${m.name}`.toLowerCase().includes(q)});
  const selected=selectedIds();
  $("picker").innerHTML=list.map(row=>{const m=itemMeta(step,row),on=step==="art"?String(state.artId)===String(m.id):selected.includes(String(m.id));return `<button class="pick ${on?"selected":""}" type="button" data-pick="${esc(m.id)}"><strong>${esc(m.no)}</strong><small>${esc(m.name)}</small></button>`}).join("")||`<article class="empty" style="padding:22px"><p>${step!=="art"&&currentMode()!=="SELECTED"?"N.A. / DUE selected. Continue karein.":"No matching master found. + Add New use kar sakte hain."}</p></article>`;
  $("picker").querySelectorAll("[data-pick]").forEach(b=>b.onclick=()=>togglePick(b.dataset.pick))
}
function togglePick(id){id=String(id);if(state.step==="art")state.artId=id;else if(state.step==="print"){state.printMode="SELECTED";state.printIds=state.printIds.includes(id)?state.printIds.filter(x=>x!==id):[...state.printIds,id]}else if(state.step==="sticker"){state.stickerMode="SELECTED";state.stickerIds=state.stickerIds.includes(id)?state.stickerIds.filter(x=>x!==id):[...state.stickerIds,id]}else{state.metalMode="SELECTED";state.metalIds=state.metalIds.includes(id)?state.metalIds.filter(x=>x!==id):[...state.metalIds,id]}renderPicker()}

function clearCreateTimers(){state.createTimers.forEach(clearTimeout);state.createTimers=[]}
function createSnapshot(step){return new Set(sourceForStep(step).map(x=>String(x.id)))}
async function refreshMasterSource(step){
  let list=[];
  if(step==="art")list=await rows("rr_art_master");
  else if(step==="print")list=await printRows();
  else if(step==="sticker")list=await rows("rr_sticker_master_library_v803");
  else list=await rows("rr_metal_id_master_library_v803");
  list=activeOnly(list);
  if(step==="art")state.arts=list;else if(step==="print")state.prints=list;else if(step==="sticker")state.stickers=list;else state.metals=list;
  return list
}
function newestCreated(list,before){return list.filter(x=>!before.has(String(x.id))).sort((a,b)=>String(b.created_at||b.updated_at||"").localeCompare(String(a.created_at||a.updated_at||"")))[0]||null}
function selectCreated(step,row){if(!row)return;const id=String(row.id);if(step==="art")state.artId=id;else if(step==="print"){state.printMode="SELECTED";if(!state.printIds.includes(id))state.printIds=[...state.printIds,id]}else if(step==="sticker"){state.stickerMode="SELECTED";if(!state.stickerIds.includes(id))state.stickerIds=[...state.stickerIds,id]}else{state.metalMode="SELECTED";if(!state.metalIds.includes(id))state.metalIds=[...state.metalIds,id]}}

async function detectCreated(autoClose=false){
  const ctx=state.createContext;if(!ctx)return null;
  try{
    const list=await refreshMasterSource(ctx.step),created=newestCreated(list,ctx.before);
    if(!created){if(!autoClose)renderPicker();return null}
    selectCreated(ctx.step,created);
    const label=MASTER_META[ctx.step].label;
    if(autoClose)closeMasterSheet(false);
    renderPicker();decisionSay(`${label} Master mein naya ${label} create hua aur yahan auto-selected hai.`,"success");
    return created
  }catch(e){console.warn("Master refresh failed",e);return null}
}
function scheduleCreateDetection(){clearCreateTimers();[900,2200,4500].forEach(ms=>state.createTimers.push(setTimeout(()=>detectCreated(true),ms)))}
function prepareEmbeddedMaster(){
  const ctx=state.createContext,frame=$("masterFrame");if(!ctx||!frame)return;
  try{
    const doc=frame.contentDocument;if(!doc)return;
    doc.querySelectorAll("#rrSliceRail,#rrSlicePanel,#rrSliceBack,#rr-global-data-mode-badge-v786-1-1").forEach(x=>x.remove());
    doc.body?.classList.remove("rrSliceReserved");if(doc.documentElement)doc.documentElement.style.setProperty("--rr-slice-rail","0px");
    const meta=MASTER_META[ctx.step];
    if(meta.open){setTimeout(()=>doc.getElementById(meta.open)?.click(),120)}
    setTimeout(()=>{const target=doc.getElementById(meta.focus);target?.scrollIntoView({block:"center"});target?.focus({preventScroll:true})},260);
    doc.addEventListener("submit",scheduleCreateDetection,true)
  }catch(e){console.warn("Embedded master setup unavailable",e)}
}
function openMasterCreate(step){
  const meta=MASTER_META[step];if(!meta)return;
  clearCreateTimers();state.createContext={step,before:createSnapshot(step)};
  $("masterTitle").textContent=`Add New ${meta.label}`;$("masterHint").textContent=`Actual ${meta.label} Master form · save ke baad naya item yahin auto-select hoga.`;
  const sheet=$("masterSheet");sheet.classList.remove("hidden");sheet.setAttribute("aria-hidden","false");
  const frame=$("masterFrame");frame.onload=prepareEmbeddedMaster;frame.src=meta.url
}
async function closeMasterSheet(sync=true){
  const ctx=state.createContext;clearCreateTimers();
  if(sync&&ctx){await detectCreated(false)}
  state.createContext=null;
  const sheet=$("masterSheet");sheet.classList.add("hidden");sheet.setAttribute("aria-hidden","true");
  const frame=$("masterFrame");frame.onload=null;frame.src="about:blank";
  renderPicker()
}

function showStep(step){state.step=step;$("decisionTabs").querySelectorAll("[data-step]").forEach(b=>b.classList.toggle("active",b.dataset.step===step));const cfg={art:["Art select kijiye ya + Add New Art se Art Master mein naya Art banaiye.","SUBMIT & CONTINUE"],print:["Print select karein; N.A./DUE choose karein; ya + Add New Print se Print Master mein create karein.","SUBMIT & CONTINUE"],sticker:["Sticker select karein; N.A./DUE choose karein; ya + Add New Sticker se Sticker Master mein create karein.","SUBMIT & CONTINUE"],metal:["Metal ID select karein; N.A./DUE choose karein; ya + Add New Metal ID. Phir SAVE & EXIT.","SAVE & EXIT"]}[step];$("decisionNote").textContent=cfg[0];$("decisionNext").textContent=cfg[1];$("pickerSearch").value="";decisionSay("");renderPicker()}
function stepError(step){if(step==="art"&&!state.artId)return"Art select karna zaroori hai.";if(step==="print"&&state.printMode==="SELECTED"&&!state.printIds.length)return"Print select karein, ya N.A./DUE choose karein.";if(step==="sticker"&&state.stickerMode==="SELECTED"&&!state.stickerIds.length)return"Sticker select karein, ya N.A./DUE choose karein.";if(step==="metal"&&state.metalMode==="SELECTED"&&!state.metalIds.length)return"Metal ID select karein, ya N.A./DUE choose karein.";return""}
function allError(){return stepError("art")||stepError("print")||stepError("sticker")||stepError("metal")}
async function advance(){const err=stepError(state.step);if(err){decisionSay(err,"error");return}if(state.step==="art")return showStep("print");if(state.step==="print")return showStep("sticker");if(state.step==="sticker")return showStep("metal");return saveDecision()}
async function saveDecision(){
  const err=allError();if(err){decisionSay(err,"error");return}
  const btn=$("decisionNext");setBusy(btn,true,"Saving…");
  try{
    const mode=await currentDataMode();
    const r=await state.client.rpc("rr_pm_save_decision_bundle_v804",{p_cb_unit_id:state.active.id,p_art_id:state.artId,p_print_mode:state.printMode,p_print_ids:state.printIds,p_sticker_mode:state.stickerMode,p_sticker_master_ids:state.stickerIds,p_metal_id_mode:state.metalMode,p_metal_id_master_ids:state.metalIds,p_data_mode:mode});
    if(r.error)throw r.error;
    const savedLabel=`${cbNo(state.active)} · ${dNo(state.active)}`;
    closeDecision();await loadData();say(`${savedLabel} Art / Crafting decision saved.`,"success")
  }catch(e){console.error(e);decisionSay(textError(e),"error")}
  finally{setBusy(btn,false)}
}

function bind(){
  $("refresh").onclick=loadData;$("search").oninput=renderGallery;$("pickerSearch").oninput=renderPicker;$("decisionNext").onclick=advance;
  $("decisionTabs").querySelectorAll("[data-step]").forEach(b=>b.onclick=()=>showStep(b.dataset.step));
  document.querySelectorAll("[data-close]").forEach(b=>b.onclick=closeDecision);
  document.querySelectorAll("[data-master-close]").forEach(b=>b.onclick=()=>closeMasterSheet(true));
  $("masterDone").onclick=()=>closeMasterSheet(true);
  $("viewerClose").onclick=closeViewer;$("viewerBackdrop").onclick=closeViewer;$("viewerPrev").onclick=()=>moveViewer(-1);$("viewerNext").onclick=()=>moveViewer(1);
  document.addEventListener("keydown",e=>{
    if(e.key==="ArrowLeft"&&!$("imageViewer").classList.contains("hidden"))return moveViewer(-1);
    if(e.key==="ArrowRight"&&!$("imageViewer").classList.contains("hidden"))return moveViewer(1);
    if(e.key!=="Escape")return;
    if(!$("imageViewer").classList.contains("hidden"))closeViewer();
    else if(!$("masterSheet").classList.contains("hidden"))closeMasterSheet(true);
    else if(!$("decisionSheet").classList.contains("hidden"))closeDecision()
  })
}
async function boot(){try{state.client=await waitForClient();if(!state.client)throw new Error("Supabase client unavailable.");await loadRole();if(!["owner","admin"].includes(state.role))throw new Error("Art Decide Master requires Owner/Admin role.");bind();await loadData()}catch(e){console.error(e);$("gallery").innerHTML=`<article class="empty"><h3>Art Decide Master start failed</h3><p>${esc(textError(e))}</p></article>`;say(textError(e),"error")}}
boot();
})();
