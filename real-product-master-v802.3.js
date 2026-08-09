(() => {
"use strict";

window.REAL_FACTORY_PRODUCT_MASTER_VERSION = "V802.2-NA-DEFAULT-EXPLICIT-DUE";
const $ = id => document.getElementById(id);
const state = {
  client:null, filter:"all", mode:"create", activeCbId:null, activeUnitId:null,
  categories:[], galleryRows:[], purchases:[], rolls:[], colours:[], allocations:[],
  arts:[], prints:[], stickerInstructions:[], metalIdInstructions:[], assignments:[], printAssignments:[], stickerAssignments:[], metalIdAssignments:[], media:[], lots:[],
  mc:{card:null,purchases:[],ledger:[]}, colourDrafts:[], materialEntries:[],
  selectedArtId:null, selectedPrintIds:[], selectedStickerIds:[], selectedMetalIdIds:[], printMode:"NA", stickerMode:"NA", metalIdMode:"NA", decisionStep:"art", mcPricingDriver:"value",
  role:null, grEntries:[], exchangeEntries:[], damageClaims:[], damageMedia:[],
  lotCostAdjustments:[], pmDecisionRows:[], pmDecisionCounts:{}, activeDetail:null, operation:null
};

const TABLES = {
  categories:"rr_material_categories", fabricPurchases:"rr_fabric_purchases", units:"rr_cb_units",
  colours:"rr_cb_colours", purchases:"rr_cb_purchase_entries", rolls:"rr_cb_purchase_rolls",
  arts:"rr_art_master", prints:"rr_print_master",
  printView:"rr_print_library_view", stickerInstructions:"rr_art_sticker_instructions", metalIdInstructions:"rr_art_metal_id_instructions_v801", assignments:"rr_cb_art_assignments",
  printAssignments:"rr_cb_print_assignments", stickerAssignments:"rr_cb_sticker_assignments", metalIdAssignments:"rr_cb_metal_id_assignments_v801", media:"rr_media", lots:"rr_cutting_lots_v3",
  allocations:"rr_cb_material_allocations", gr:"rr_product_gr_entries",
  exchanges:"rr_product_exchange_entries", damage:"rr_product_damage_claim_details_v1",
  damageMedia:"rr_product_damage_media", lotAdjustments:"rr_product_lot_cost_adjustments"
};

function esc(value){return String(value??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));}
function safe(value){try{return window.RR?.safeText?RR.safeText(value??""):esc(value)}catch{return esc(value)}}
function money(value){return new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:2}).format(Number(value||0));}
function kg(value){return `${Number(value||0).toFixed(3)} kg`;}
function today(){const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;}
function dateTime(value){if(!value)return "—";return new Intl.DateTimeFormat("en-IN",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value));}
function say(text="",type=""){const el=$("message");el.textContent=text;el.className=`message ${type}`.trim();}
function formSay(id,text="",type=""){const el=$(id);el.textContent=text;el.className=`message ${type}`.trim();}
function errorText(error){return [...new Set([error?.message,error?.details,error?.hint,error?.code].filter(Boolean))].join(" — ")||"Unknown error";}
function getClient(){
  let client=null;

  try{
    if(typeof supabaseClient!=="undefined"&&supabaseClient&&typeof supabaseClient.from==="function")client=supabaseClient;
  }catch(e){console.warn("Direct Supabase client check failed",e)}

  if(!client){
    client=[window.supabaseClient,window.supabaseDb,window.redzedSupabase,window.sb]
      .find(x=>x&&typeof x.from==="function")||null;
  }

  // Last-resort compatibility with older config.js files that expose only URL/key.
  if(!client&&window.supabase&&typeof window.supabase.createClient==="function"){
    try{
      const url=typeof SUPABASE_URL!=="undefined"?SUPABASE_URL:window.SUPABASE_URL;
      const key=typeof SUPABASE_ANON_KEY!=="undefined"?SUPABASE_ANON_KEY:window.SUPABASE_ANON_KEY;
      if(url&&key)client=window.supabase.createClient(url,key);
    }catch(e){console.warn("Supabase fallback client creation failed",e)}
  }

  if(client)window.supabaseClient=client;
  return client;
}
async function waitForRuntime(){
  const started=Date.now();
  while(Date.now()-started<15000){
    const client=getClient();
    if(client)return client;
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  return null;
}
function openSheet(id){const el=$(id);el.classList.remove("hidden");el.setAttribute("aria-hidden","false");document.body.style.overflow="hidden";}
function closeSheet(id){const el=$(id);el.classList.add("hidden");el.setAttribute("aria-hidden","true");if(!document.querySelector(".sheet:not(.hidden)"))document.body.style.overflow="";}
function setBusy(button,busy,text){if(!button)return;if(busy){button.dataset.old=button.textContent;button.disabled=true;button.textContent=text}else{button.disabled=false;button.textContent=button.dataset.old||button.textContent}}
function categoryByCode(code){return state.categories.find(x=>String(x.category_code||"").toLowerCase()===String(code).toLowerCase())||null;}
function categoryById(id){return state.categories.find(x=>String(x.id)===String(id))||null;}
function isMatchingCategory(c){const t=`${c?.category_code||""} ${c?.category_name||""}`.toLowerCase();return t.includes("matching");}
function materialCategories(){return state.categories.filter(c=>!isMatchingCategory(c));}
function canonicalD(row,index=0){const raw=String(row?.division_code||row?.cb_code||row?.child_code||"").toUpperCase().replace(/\s+/g,"");const m=raw.match(/[DS](\d+)([A-Z]*)$/);return m?`D${Number(m[1])}${m[2]||""}`:`D${Number(row?.division_index||index||1)}`;}

async function optionalTable(table,select="*",order=null){let q=state.client.from(table).select(select);if(order)q=q.order(order,{ascending:false});const r=await q;if(r.error){console.warn(`${table} unavailable`,r.error);return []}return r.data||[];}
async function requiredTable(table,select="*",order=null){let q=state.client.from(table).select(select);if(order)q=q.order(order,{ascending:false});const r=await q;if(r.error)throw new Error(`${table}: ${r.error.message}`);return r.data||[];}

async function loadGalleryRows(){
  for(const view of ["rr_product_master_gallery_v715","rr_product_master_gallery_v714","rr_product_master_gallery"]){
    const r=await state.client.from(view).select("*");
    if(!r.error && r.data?.length)return r.data;
  }
  const [purchases,units]=await Promise.all([requiredTable(TABLES.fabricPurchases),requiredTable(TABLES.units)]);
  const byId=new Map(purchases.map(p=>[String(p.id),p]));
  return units.map(u=>{const p=byId.get(String(u.purchase_id))||{};return {
    cb_id:u.purchase_id,division_id:u.id,division_index:u.division_index,
    division_code:u.cb_code||u.division_code,division_status:u.status||"planning",
    allocated_qty:Number(u.divided_weight||0),allocated_amount:Number(u.divided_amount||0),
    cb_no:p.cb_no||u.cb_base_no||"CB",created_at:u.created_at||p.created_at
  }});
}

async function loadPrints(){const v=await state.client.from(TABLES.printView).select("*");if(!v.error)return v.data||[];return requiredTable(TABLES.prints);}
async function loadMc(){const r=await state.client.rpc("rr_get_mc1_card_v1");if(r.error){state.mc={card:null,purchases:[],ledger:[],error:r.error};return}const d=r.data||{};state.mc={card:d.card||null,purchases:d.purchases||[],ledger:d.ledger||[]};}

async function loadPmDecisionRows(){
  const r=await state.client.rpc("rr_pm_decision_filter_v802",{p_filter:"ALL"});
  if(r.error)throw new Error(`Product Master Due backend unavailable: ${errorText(r.error)}`);
  return Array.isArray(r.data)?r.data:[];
}
async function loadPmDecisionCounts(){
  const r=await state.client.rpc("rr_pm_decision_tab_counts_v802");
  if(r.error)throw new Error(`Product Master Due counts unavailable: ${errorText(r.error)}`);
  return r.data||{};
}
function pmDecisionFor(unitId){
  return state.pmDecisionRows.find(x=>String(x.cb_unit_id)===String(unitId))||null;
}
function countValue(key){return Number(state.pmDecisionCounts?.[key]||0);}
function paintDueTabCounts(){
  const map={art_due:"art_due",print_due:"print_due",sticker_due:"sticker_due",metal_id_due:"metal_id_due"};
  Object.entries(map).forEach(([filter,key])=>{
    const b=document.querySelector(`#filters button[data-filter="${filter}"]`);
    if(b)b.textContent=`${b.textContent.replace(/\s+\d+$/,"")} ${countValue(key)}`;
  });
}

async function loadData(){
  const btn=$("refresh");setBusy(btn,true,"Loading…");$("gallery").setAttribute("aria-busy","true");
  try{
    const [categories,gallery,purchases,rolls,colours,allocations,arts,prints,stickerInstructions,metalIdInstructions,assignments,printAssignments,stickerAssignments,metalIdAssignments,media,lots,_mcLoaded,grEntries,exchangeEntries,damageClaims,damageMedia,lotCostAdjustments,pmDecisionRows,pmDecisionCounts]=await Promise.all([
      requiredTable(TABLES.categories),loadGalleryRows(),requiredTable(TABLES.purchases,"*","created_at"),optionalTable(TABLES.rolls),requiredTable(TABLES.colours,"*","colour_order"),optionalTable(TABLES.allocations),requiredTable(TABLES.arts,"*","updated_at"),loadPrints(),optionalTable(TABLES.stickerInstructions,"*","sequence_no"),optionalTable(TABLES.metalIdInstructions,"*","sequence_no"),requiredTable(TABLES.assignments,"*","updated_at"),requiredTable(TABLES.printAssignments,"*","sequence_no"),optionalTable(TABLES.stickerAssignments,"*","sequence_no"),optionalTable(TABLES.metalIdAssignments,"*","sequence_no"),optionalTable(TABLES.media),optionalTable(TABLES.lots,"*","created_at"),loadMc(),optionalTable(TABLES.gr,"*","created_at"),optionalTable(TABLES.exchanges,"*","created_at"),optionalTable(TABLES.damage,"*","created_at"),optionalTable(TABLES.damageMedia,"*","created_at"),optionalTable(TABLES.lotAdjustments,"*","created_at"),loadPmDecisionRows(),loadPmDecisionCounts()
    ]);
    Object.assign(state,{categories,galleryRows:gallery,purchases,rolls,colours,allocations,arts,prints,stickerInstructions,metalIdInstructions,assignments,printAssignments,stickerAssignments,metalIdAssignments,media,lots,grEntries,exchangeEntries,damageClaims,damageMedia,lotCostAdjustments,pmDecisionRows,pmDecisionCounts});
    renderAll();say("Product Master loaded.","success");
  }catch(e){console.error(e);$("gallery").innerHTML=`<article class="empty"><h3>Product Master could not load</h3><p>${safe(errorText(e))}</p></article>`;say(errorText(e),"error")}
  finally{setBusy(btn,false);$("gallery").setAttribute("aria-busy","false")}
}

function groups(){
  const map=new Map();
  state.galleryRows.forEach(row=>{
    const cbId=String(row.cb_id||row.purchase_id||"");if(!cbId)return;
    if(!map.has(cbId))map.set(cbId,{cbId,cbNo:row.cb_no||"CB",createdAt:row.created_at,status:row.division_status||"planning",divisions:[]});
    const g=map.get(cbId);const id=String(row.division_id||row.unit_id||row.id||"");
    if(!g.divisions.some(x=>String(x.division_id||x.id)===id))g.divisions.push({...row,division_id:row.division_id||row.unit_id||row.id});
  });
  return [...map.values()].map(g=>({...g,divisions:g.divisions.sort((a,b)=>Number(a.division_index||0)-Number(b.division_index||0))})).sort((a,b)=>String(b.createdAt||"").localeCompare(String(a.createdAt||"")));
}
function coloursFor(cbId){return state.colours.filter(x=>String(x.cb_id)===String(cbId)).sort((a,b)=>Number(a.colour_order||0)-Number(b.colour_order||0));}
function purchasesFor(cbId){return state.purchases.filter(x=>String(x.cb_id)===String(cbId));}
function assignmentFor(unitId){return state.assignments.find(x=>String(x.cb_id)===String(unitId))||null;}
function printsForAssignment(a){if(!a)return[];const ids=state.printAssignments.filter(x=>String(x.assignment_id)===String(a.id)).sort((x,y)=>Number(x.sequence_no)-Number(y.sequence_no)).map(x=>String(x.print_id));return ids.map(id=>state.prints.find(p=>String(p.id)===id)).filter(Boolean);}
function artFor(a){return a?state.arts.find(x=>String(x.id)===String(a.art_id))||null:null;}
function stickerIdsForAssignment(a){if(!a)return[];return state.stickerAssignments.filter(x=>String(x.assignment_id)===String(a.id)).sort((x,y)=>Number(x.sequence_no||0)-Number(y.sequence_no||0)).map(x=>String(x.sticker_instruction_id));}
function metalIdIdsForAssignment(a){if(!a)return[];return state.metalIdAssignments.filter(x=>String(x.assignment_id)===String(a.id)).sort((x,y)=>Number(x.sequence_no||0)-Number(y.sequence_no||0)).map(x=>String(x.metal_id_instruction_id));}
function stickerOptionsForArt(){return state.stickerInstructions.filter(x=>String(x.art_id)===String(state.selectedArtId)&&x.is_active!==false);}
function metalOptionsForArt(){return state.metalIdInstructions.filter(x=>String(x.art_id)===String(state.selectedArtId)&&x.is_active!==false);}
function lotsForUnit(unitId){return state.lots.filter(x=>String(x.cb_unit_id||x.division_id)===String(unitId));}
function artImage(art){if(!art)return"";return art.hero_image_url||art.image_url||art.artwork_url||state.media.find(m=>String(m.entity_id)===String(art.id))?.file_url||"";}
function printImage(p){if(!p)return"";return p.artwork_url||p.garment_preview_url||p.image_url||state.media.find(m=>String(m.entity_id)===String(p.id))?.file_url||"";}
function artNo(a){return a?.art_no||a?.art_code||a?.code||"";}function printNo(p){return p?.print_no||p?.print_code||p?.code||"";}

function renderStats(){const gs=groups();const divisions=gs.reduce((s,g)=>s+g.divisions.length,0);const decided=gs.reduce((s,g)=>s+g.divisions.filter(d=>assignmentFor(d.division_id)).length,0);const mc=state.mc.card||{};$("stats").innerHTML=[
  ["CB Cards",gs.length],["D Cards",divisions],["Art Decided",decided],["MC1 Balance",kg(mc.current_qty)],["MC1 Avg Rate",money(mc.avg_rate)]
].map(([a,b])=>`<article class="stat"><small>${safe(a)}</small><strong>${safe(b)}</strong></article>`).join("");}

function mcCardHtml(){const c=state.mc.card;if(!c){return `<article class="card mc-card"><div class="card-body"><div class="card-head"><div><span class="chip mc">MATCHING CLOTH</span><h3>MC1</h3></div></div><p class="note">MC1 backend ready नहीं है। पहले REDZED_V72035_FROM_V72033_PATCH.sql run करें।</p><div class="card-actions"><button class="primary" data-open-mc>+ MC New</button></div></div></article>`}
  return `<article class="card mc-card" data-search="mc1 matching ${safe(state.mc.purchases.map(x=>`${x.vendor_name} ${x.bill_no}`).join(" "))}"><div class="card-body"><div class="card-head"><div><span class="chip mc">CONSOLIDATED MATCHING CLOTH</span><h3>MC1</h3></div><strong>${kg(c.current_qty)}</strong></div><div class="metrics"><div class="metric"><small>Current Qty</small><strong>${kg(c.current_qty)}</strong></div><div class="metric"><small>Average Rate</small><strong>${money(c.avg_rate)}</strong></div><div class="metric"><small>Stock Value</small><strong>${money(c.current_value)}</strong></div><div class="metric"><small>Total IN</small><strong>${kg(c.total_purchase_qty)}</strong></div><div class="metric"><small>Total OUT</small><strong>${kg(c.total_consumption_qty)}</strong></div><div class="metric"><small>Last Updated</small><strong>${dateTime(c.updated_at)}</strong></div></div><p class="note">One card · No colour · No cloth name · Lot cost snapshot remains fixed.</p><div class="card-actions"><button class="primary" data-open-mc>+ MC New</button><button class="secondary" data-mc-detail>MC1 Details</button></div></div></article>`;
}

function cbCardHtml(g,d){
  const unitId=d.division_id;const a=assignmentFor(unitId);const art=artFor(a);const ps=printsForAssignment(a);const cols=coloursFor(g.cbId);const lots=lotsForUnit(unitId);const lotText=lots.map(x=>x.lot_no).filter(Boolean).join(" · ");
  const images=[art?{url:artImage(art),label:`ART ${artNo(art)}`} : null,...ps.map(p=>({url:printImage(p),label:`PRINT ${printNo(p)}`}))].filter(x=>x?.url);
  const hero=images[0]?.url||cols.find(x=>x.image_url)?.image_url||"";
  const search=[g.cbNo,canonicalD(d),artNo(art),ps.map(printNo).join(" "),lots.map(x=>x.lot_no).join(" "),purchasesFor(g.cbId).map(x=>`${x.vendor_name} ${x.vendor_bill_no} ${x.fabric_name}`).join(" "),cols.map(x=>x.colour_name).join(" ")].join(" ").toLowerCase();
  const pm=pmDecisionFor(unitId);
  const artDue=pm?pm.art_decided===false:!a;
  const printDue=pm?pm.print_status==="PRINT_DUE":false;
  const stickerDue=pm?pm.sticker_status==="STICKER_DUE":false;
  const metalIdDue=pm?pm.metal_id_status==="METAL_ID_DUE":false;
  return `<article class="card" data-kind="cb" data-ready="${a?"1":"0"}" data-art-due="${artDue?"1":"0"}" data-print-due="${printDue?"1":"0"}" data-sticker-due="${stickerDue?"1":"0"}" data-metal-id-due="${metalIdDue?"1":"0"}" data-search="${safe(search)}"><div class="card-body"><div class="card-head"><div><span class="chip ${a?"ready":""}">${a?"ART DECIDED":"ART DUE"}</span><h3>${safe(g.cbNo)}</h3><strong>${safe(canonicalD(d))}</strong></div>${hero?`<img src="${safe(hero)}" alt="" style="width:78px;height:78px;object-fit:cover;border-radius:14px">`:""}</div><div class="metrics"><div class="metric"><small>D No.</small><strong>${safe(canonicalD(d))}</strong></div><div class="metric"><small>Art</small><strong>${safe(artNo(art)||"Due")}</strong></div><div class="metric"><small>Print</small><strong>${safe(pm?.print_status==="PRINT_DUE"?"DUE":pm?.print_status==="PRINT_NA"?"N/A":ps.map(printNo).join(" · ")||"N/A")}</strong></div><div class="metric"><small>Sticker</small><strong>${safe(pm?.sticker_status==="STICKER_DUE"?"DUE":pm?.sticker_status==="STICKER_NA"?"N/A":"Decided")}</strong></div><div class="metric"><small>Metal ID</small><strong>${safe(pm?.metal_id_status==="METAL_ID_DUE"?"DUE":pm?.metal_id_status==="METAL_ID_NA"?"N/A":"Decided")}</strong></div><div class="metric"><small>Weight</small><strong>${kg(d.allocated_qty??d.divided_weight)}</strong></div><div class="metric"><small>Colours</small><strong>${cols.length}</strong></div><div class="metric"><small>Lot No.</small><strong>${safe(lotText||"Due")}</strong></div></div><div class="colour-strip">${cols.map(c=>`<span class="colour-pill">${c.image_url?`<img src="${safe(c.image_url)}">`:""}<b>${safe(c.colour_name)}</b></span>`).join("")}</div><div class="card-actions"><button class="secondary" data-cb-detail="${safe(g.cbId)}">CB Details</button><button class="primary" data-assign="${safe(unitId)}">${a?"Change Work Decision":"Decide Art / Work"}</button></div></div></article>`;
}

function filterPass(card){
  const f=state.filter;
  if(f==="all")return true;
  if(f==="mc")return card.dataset.kind==="mc";
  if(f==="cb")return card.dataset.kind==="cb";
  if(f==="art_due")return card.dataset.kind==="cb"&&card.dataset.artDue==="1";
  if(f==="print_due")return card.dataset.kind==="cb"&&card.dataset.printDue==="1";
  if(f==="sticker_due")return card.dataset.kind==="cb"&&card.dataset.stickerDue==="1";
  if(f==="metal_id_due")return card.dataset.kind==="cb"&&card.dataset.metalIdDue==="1";
  if(f==="ready")return card.dataset.kind==="cb"&&card.dataset.ready==="1";
  return true;
}
function renderGallery(){const q=$("search").value.trim().toLowerCase();let html=mcCardHtml().replace('<article class="card mc-card"','<article class="card mc-card" data-kind="mc"');groups().forEach(g=>g.divisions.forEach(d=>{html+=cbCardHtml(g,d)}));$("gallery").innerHTML=html;const cards=[...$("gallery").querySelectorAll(".card")];let visible=0;cards.forEach(c=>{const ok=filterPass(c)&&(c.dataset.search||c.textContent.toLowerCase()).includes(q);c.classList.toggle("hidden",!ok);if(ok)visible++});if(!visible)$("gallery").insertAdjacentHTML("beforeend",`<article class="empty">No matching card found.</article>`);bindGallery();}
function renderAll(){renderStats();paintDueTabCounts();renderGallery();}
function bindGallery(){$("gallery").querySelectorAll("[data-open-mc]").forEach(b=>b.onclick=openMcNew);$("gallery").querySelectorAll("[data-mc-detail]").forEach(b=>b.onclick=openMcDetails);$("gallery").querySelectorAll("[data-cb-detail]").forEach(b=>b.onclick=()=>openCbDetails(b.dataset.cbDetail));$("gallery").querySelectorAll("[data-assign]").forEach(b=>b.onclick=()=>openAssignment(b.dataset.assign));}

function newColour(index){return {name:`Colour ${index+1}`,imageUrl:"",file:null,objectUrl:""};}
function newMaterial(type="regular"){
  const regular=type==="regular";const cat=regular?(categoryByCode("regular-cloth")||materialCategories()[0]):(categoryByCode("cuff-collar")||materialCategories().find(x=>String(x.category_code).includes("cuff"))||materialCategories()[0]);
  return {id:crypto.randomUUID(),type,categoryId:cat?.id||"",vendor:"",fabric:"",billNo:"",billDate:today(),billRate:"",billValue:"",pricingDriver:"value",scope:"all",selected:[],rolls:state.colourDrafts.map(()=>[{qty:""}])};
}
function resetCbCreate(){state.mode="create";state.activeCbId=null;$("cbIdentity").classList.remove("hidden");$("colourSection").classList.remove("hidden");$("cbKicker").textContent="CB NEW";$("cbTitle").textContent="Create CB";$("cbContext").textContent="Regular Cloth + Material only";$("saveCb").textContent="Create CB";$("cbNo").value="";$("divisionCount").value="2";$("colourCount").value="6";$("cbRemarks").value="";state.colourDrafts=Array.from({length:6},(_,i)=>newColour(i));state.materialEntries=[newMaterial("regular")];renderCbForm();formSay("cbSaveMessage","");}
function resetCbAppend(cbId){const g=groups().find(x=>String(x.cbId)===String(cbId));if(!g)return;state.mode="append";state.activeCbId=cbId;$("cbIdentity").classList.add("hidden");$("colourSection").classList.add("hidden");$("cbKicker").textContent="ADD MATERIAL";$("cbTitle").textContent=g.cbNo;$("cbContext").textContent="Cuff & Collar / Other Material only";$("saveCb").textContent="Save Material";state.colourDrafts=coloursFor(cbId).map((c,i)=>({name:c.colour_name||`Colour ${i+1}`,imageUrl:c.image_url||"",persistedId:c.id,file:null,objectUrl:""}));state.materialEntries=[newMaterial("material")];renderCbForm();formSay("cbSaveMessage","");}
function openCbNew(){resetCbCreate();openSheet("cbSheet");setTimeout(()=>$("cbNo").focus(),80)}

function renderColourList(){if(state.mode!=="create")return;$("colourList").innerHTML=state.colourDrafts.map((c,i)=>`<article class="colour-row" data-colour="${i}"><div class="grid3"><label><span>Colour ${i+1} Name *</span><input class="colour-name" value="${safe(c.name)}"></label><label><span>Image URL — optional</span><input class="colour-url" value="${safe(c.imageUrl)}"></label><label><span>Camera / Gallery — optional</span><input class="colour-file" type="file" accept="image/*"></label></div>${c.objectUrl||c.imageUrl?`<img src="${safe(c.objectUrl||c.imageUrl)}" style="margin-top:8px;width:90px;height:90px;object-fit:cover;border-radius:12px">`:""}</article>`).join("");
  $("colourList").querySelectorAll("[data-colour]").forEach(n=>{const i=Number(n.dataset.colour);n.querySelector(".colour-name").oninput=e=>state.colourDrafts[i].name=e.target.value;n.querySelector(".colour-url").oninput=e=>state.colourDrafts[i].imageUrl=e.target.value;n.querySelector(".colour-file").onchange=e=>{const file=e.target.files?.[0];if(!file)return;const c=state.colourDrafts[i];if(c.objectUrl)URL.revokeObjectURL(c.objectUrl);c.file=file;c.objectUrl=URL.createObjectURL(file);renderColourList()}});
}
function divisionChoices(){const count=state.mode==="create"?Math.max(1,Number($("divisionCount").value||1)):groups().find(x=>String(x.cbId)===String(state.activeCbId))?.divisions.length||1;return Array.from({length:count},(_,i)=>i+1);}
function ensureEntryRolls(e){const count=state.colourDrafts.length;while(e.rolls.length<count)e.rolls.push([{qty:""}]);while(e.rolls.length>count)e.rolls.pop();}
function materialOptions(selected){return materialCategories().map(c=>`<option value="${safe(c.id)}" ${String(c.id)===String(selected)?"selected":""}>${safe(c.category_name)}</option>`).join("");}
function entryQty(e){return e.rolls.flat().reduce((s,r)=>s+Number(r.qty||0),0)}
function entryRate(e){const r=Number(e.billRate||0),q=entryQty(e),v=Number(e.billValue||0);return r>0?r:(q>0?v/q:0)}
function entryValue(e){const v=Number(e.billValue||0),q=entryQty(e),r=Number(e.billRate||0);return v>0?v:(q>0&&r>0?q*r:0)}
function syncEntryPricing(e,source,node){
  const q=entryQty(e),r=Number(e.billRate||0),v=Number(e.billValue||0);
  if(source==="rate"){e.pricingDriver="rate";e.billValue=q>0&&r>=0?(q*r).toFixed(2):""}
  else if(source==="value"){e.pricingDriver="value";e.billRate=q>0&&v>=0?(v/q).toFixed(4):""}
  else if(e.pricingDriver==="rate"){e.billValue=q>0&&r>=0?(q*r).toFixed(2):""}
  else{e.billRate=q>0&&v>=0?(v/q).toFixed(4):""}
  if(node){
    const rateInput=node.querySelector(".mat-rate"),valueInput=node.querySelector(".mat-value");
    if(rateInput&&document.activeElement!==rateInput)rateInput.value=e.billRate;
    if(valueInput&&document.activeElement!==valueInput)valueInput.value=e.billValue;
    const rateText=node.querySelector(".entry-rate"),qtyText=node.querySelector(".entry-qty");
    if(rateText)rateText.textContent=money(entryRate(e));
    if(qtyText)qtyText.textContent=kg(q);
  }
  updateCbSummary();
}
function renderMaterialList(){
  state.materialEntries.forEach(ensureEntryRolls);
  $("materialList").innerHTML=state.materialEntries.map((e,ei)=>`<article class="material-row" data-entry="${safe(e.id)}"><div class="material-head"><h4>${e.type==="regular"?"Regular Cloth":"Cuff / Collar / Other Material"}</h4>${e.type!=="regular"?`<button class="danger remove-entry" type="button">Remove</button>`:""}</div><div class="grid3"><label><span>Material *</span><select class="mat-category" ${e.type==="regular"?"disabled":""}>${materialOptions(e.categoryId)}</select></label><label><span>Vendor Name *</span><input class="mat-vendor" value="${safe(e.vendor)}"></label><label><span>Fabric / Material Name *</span><input class="mat-fabric" value="${safe(e.fabric)}"></label><label><span>Bill No. *</span><input class="mat-bill" value="${safe(e.billNo)}"></label><label><span>Bill Date *</span><input class="mat-date" type="date" value="${safe(e.billDate)}"></label><label><span>Bill Rate *</span><input class="mat-rate" type="number" min="0" step="0.0001" value="${safe(e.billRate)}"></label><label><span>Bill Value *</span><input class="mat-value" type="number" min="0" step="0.01" value="${safe(e.billValue)}"></label></div><div class="summary" style="margin-top:10px"><div><small>Bill Qty — rolls से</small><strong class="entry-qty">${kg(entryQty(e))}</strong></div><div><small>Bill Rate</small><strong class="entry-rate">${money(entryRate(e))}</strong></div><div><small>Allocation</small><strong>${e.scope==="all"?"All D":"Selected D"}</strong></div><div><small>Type</small><strong>${e.type==="regular"?"Regular Cloth":"Material"}</strong></div></div><div class="allocation"><label><input type="radio" name="scope-${safe(e.id)}" value="all" ${e.scope==="all"?"checked":""}>All Divisions</label><label><input type="radio" name="scope-${safe(e.id)}" value="selected" ${e.scope==="selected"?"checked":""}>Selected Divisions</label>${divisionChoices().map(i=>`<label class="division-check ${e.scope==="selected"?"":"hidden"}"><input type="checkbox" value="${i}" ${e.selected.includes(i)?"checked":""}>D${i}</label>`).join("")}</div><div class="rolls">${e.rolls.map((rolls,ci)=>`<section><strong>${safe(state.colourDrafts[ci]?.name||`Colour ${ci+1}`)}</strong><div class="roll-set" data-colour-index="${ci}">${rolls.map((r,ri)=>`<div class="roll-row" data-roll="${ri}"><b>Roll ${ri+1}</b><input class="roll-qty" type="number" min="0" step="0.001" placeholder="Qty kg" value="${safe(r.qty)}"><button class="danger remove-roll" type="button" ${ri===0?"disabled":""}>×</button></div>`).join("")}<button class="secondary add-roll" type="button" style="margin-top:7px">+ Add Roll</button></div></section>`).join("")}</div></article>`).join("");
  $("materialList").querySelectorAll("[data-entry]").forEach(n=>{
    const e=state.materialEntries.find(x=>x.id===n.dataset.entry);if(!e)return;
    const bind=(sel,key,event="input")=>{const x=n.querySelector(sel);if(x)x.addEventListener(event,ev=>{e[key]=ev.target.value;updateCbSummary()})};
    bind(".mat-category","categoryId","change");bind(".mat-vendor","vendor");bind(".mat-fabric","fabric");bind(".mat-bill","billNo");bind(".mat-date","billDate","change");
    const rateInput=n.querySelector(".mat-rate"),valueInput=n.querySelector(".mat-value");
    rateInput.oninput=ev=>{e.billRate=ev.target.value;syncEntryPricing(e,"rate",n)};
    valueInput.oninput=ev=>{e.billValue=ev.target.value;syncEntryPricing(e,"value",n)};
    n.querySelector(".remove-entry")?.addEventListener("click",()=>{state.materialEntries=state.materialEntries.filter(x=>x.id!==e.id);renderMaterialList();updateCbSummary()});
    n.querySelectorAll(`input[name="scope-${CSS.escape(e.id)}"]`).forEach(r=>r.onchange=()=>{e.scope=r.value;renderMaterialList()});
    n.querySelectorAll(".division-check input").forEach(ch=>ch.onchange=()=>{const v=Number(ch.value);e.selected=ch.checked?[...new Set([...e.selected,v])]:e.selected.filter(x=>x!==v)});
    n.querySelectorAll(".roll-set").forEach(set=>{const ci=Number(set.dataset.colourIndex);set.querySelectorAll("[data-roll]").forEach(row=>{const ri=Number(row.dataset.roll);row.querySelector(".roll-qty").oninput=ev=>{e.rolls[ci][ri].qty=ev.target.value;syncEntryPricing(e,"qty",n)};row.querySelector(".remove-roll")?.addEventListener("click",()=>{if(ri===0)return;e.rolls[ci].splice(ri,1);renderMaterialList();updateCbSummary()})});set.querySelector(".add-roll").onclick=()=>{e.rolls[ci].push({qty:""});renderMaterialList()}});
  });
}
function updateCbSummary(){const qtyTotal=state.materialEntries.reduce((s,e)=>s+entryQty(e),0);const valueTotal=state.materialEntries.reduce((s,e)=>s+entryValue(e),0);$("cbTotalQty").textContent=kg(qtyTotal);$("cbTotalValue").textContent=money(valueTotal);$("cbDivisionPreview").textContent=divisionChoices().map(i=>`D${i}`).join(" · ");}
function renderCbForm(){renderColourList();renderMaterialList();updateCbSummary();}

function validateEntry(e,index){const q=entryQty(e);if(!e.categoryId)throw new Error(`Purchase ${index+1}: Material चुनें.`);if(!e.vendor.trim())throw new Error(`Purchase ${index+1}: Vendor Name required.`);if(!e.fabric.trim())throw new Error(`Purchase ${index+1}: Fabric / Material Name required.`);if(!e.billNo.trim())throw new Error(`Purchase ${index+1}: Bill No required.`);if(!e.billDate)throw new Error(`Purchase ${index+1}: Bill Date required.`);if(q<=0)throw new Error(`Purchase ${index+1}: Roll Qty required.`);if(entryRate(e)<=0)throw new Error(`Purchase ${index+1}: Bill Rate या Bill Value required.`);if(entryValue(e)<=0)throw new Error(`Purchase ${index+1}: Bill Value required.`);if(e.scope==="selected"&&!e.selected.length)throw new Error(`Purchase ${index+1}: कम से कम एक Division चुनें.`)}
async function uploadColour(cbId,c,i){if(!c.file)return {url:c.imageUrl||null,mediaId:null};if(!window.RR?.uploadMedia)throw new Error("RR.uploadMedia unavailable for colour image.");const result=await RR.uploadMedia({file:c.file,entityType:"cb",entityId:cbId,mediaCategory:"colour",sourceType:"gallery",visibilityScope:"factory",caption:c.name});const d=result?.data||result;return {url:d?.file_url||d?.public_url||d?.url||null,mediaId:d?.id||d?.media_id||null};}
async function insertPurchase(cbId,e,divisions,colours){const q=entryQty(e);const rate=entryRate(e);const payload={cb_id:cbId,vendor_name:e.vendor.trim(),vendor_bill_no:e.billNo.trim().toUpperCase(),bill_date:e.billDate,material_category_id:e.categoryId,fabric_name:e.fabric.trim(),allocation_scope:e.scope,quantity:Number(q.toFixed(3)),rate:Number(rate.toFixed(4)),entry_notes:e.type==="regular"?"Regular Cloth":"CB Material"};const r=await state.client.from(TABLES.purchases).insert(payload).select("*").single();if(r.error)throw r.error;const rollPayload=[];e.rolls.forEach((rs,ci)=>rs.forEach((rr,ri)=>{const qty=Number(rr.qty||0);if(qty>0)rollPayload.push({purchase_entry_id:r.data.id,cb_colour_id:colours[ci].id,roll_no:ri+1,quantity:Number(qty.toFixed(3))})}));if(rollPayload.length){const x=await state.client.from(TABLES.rolls).insert(rollPayload);if(x.error)throw x.error}const indexes=e.scope==="all"?divisions.map(x=>Number(x.division_index)):e.selected;const ids=divisions.filter(x=>indexes.includes(Number(x.division_index))).map(x=>x.id||x.division_id);const a=await state.client.rpc("rr_allocate_cb_purchase_entry",{p_purchase_entry_id:r.data.id,p_division_ids:ids});if(a.error)throw a.error;return r.data;}
async function rollbackCb(cbId){for(const [table,col] of [[TABLES.purchases,"cb_id"],[TABLES.colours,"cb_id"],[TABLES.units,"purchase_id"],[TABLES.fabricPurchases,"id"]]){try{await state.client.from(table).delete().eq(col,cbId)}catch(e){console.warn("rollback",table,e)}}}

async function saveCbForm(ev){ev.preventDefault();const btn=$("saveCb");setBusy(btn,true,state.mode==="create"?"Creating…":"Saving…");formSay("cbSaveMessage","Validating…","info");let createdCbId=null;
  try{
    state.materialEntries.forEach(validateEntry);
    if(state.mode==="append"){
      const g=groups().find(x=>String(x.cbId)===String(state.activeCbId));for(const e of state.materialEntries)await insertPurchase(state.activeCbId,e,g.divisions,state.colourDrafts.map(c=>({id:c.persistedId})));closeSheet("cbSheet");await loadData();say(`${g.cbNo}: Material saved.`,"success");return;
    }
    const cbNo=$("cbNo").value.trim().toUpperCase();const divisionCount=Math.max(1,Number($("divisionCount").value||0));if(!cbNo)throw new Error("CB No. required.");if(state.colourDrafts.some(c=>!c.name.trim()))throw new Error("हर Colour का नाम required है.");const regular=state.materialEntries[0];const rq=entryQty(regular),rv=entryValue(regular);
    const rpc=await state.client.rpc("rr_create_cb_v713",{p_cb_no:cbNo,p_division_count:divisionCount,p_colour_count:state.colourDrafts.length,p_regular_qty:Number(rq.toFixed(3)),p_regular_amount:Number(rv.toFixed(2)),p_total_rolls:regular.rolls.flat().filter(x=>Number(x.qty)>0).length,p_fabric_name:regular.fabric.trim()||cbNo,p_regular_division_indexes:divisionChoices(),p_remarks:$("cbRemarks").value.trim()||null});if(rpc.error)throw rpc.error;const raw=Array.isArray(rpc.data)?rpc.data[0]:rpc.data;createdCbId=typeof raw==="string"?raw:raw?.id||raw?.cb_id||raw?.result;if(!createdCbId)throw new Error("CB created but ID not returned.");
    const du=await state.client.from(TABLES.units).select("*").eq("purchase_id",createdCbId).order("division_index");if(du.error)throw du.error;
    const colourPayload=[];for(let i=0;i<state.colourDrafts.length;i++){const c=state.colourDrafts[i];const media=await uploadColour(createdCbId,c,i);colourPayload.push({cb_id:createdCbId,colour_order:i+1,colour_name:c.name.trim(),image_url:media.url,media_id:media.mediaId,is_confirmed:true})}
    const cr=await state.client.from(TABLES.colours).insert(colourPayload).select("*").order("colour_order");if(cr.error)throw cr.error;
    for(const e of state.materialEntries)await insertPurchase(createdCbId,e,du.data||[],cr.data||[]);
    closeSheet("cbSheet");await loadData();say(`${cbNo} created with ${divisionCount} D cards.`,"success");
  }catch(e){console.error(e);if(createdCbId)await rollbackCb(createdCbId);formSay("cbSaveMessage",errorText(e),"error")}
  finally{setBusy(btn,false)}
}

function openMcNew(){if(!state.mc.card&&state.mc.error){say("MC1 SQL patch पहले run करें.","error")}$("mcForm").reset();$("mcBillDate").value=today();$("mcBillRate").value="";$("mcBillValue").value="";state.mcPricingDriver="value";formSay("mcSaveMessage","");openSheet("mcSheet");setTimeout(()=>$("mcVendor").focus(),80)}
function syncMcPricing(source){
  const q=Number($("mcBillQty").value||0),r=Number($("mcBillRate").value||0),v=Number($("mcBillValue").value||0);
  if(source==="rate"){state.mcPricingDriver="rate";if(q>0)$("mcBillValue").value=(q*r).toFixed(2)}
  else if(source==="value"){state.mcPricingDriver="value";if(q>0)$("mcBillRate").value=(v/q).toFixed(4)}
  else if(state.mcPricingDriver==="rate"){if(q>0)$("mcBillValue").value=(q*r).toFixed(2)}
  else{if(q>0)$("mcBillRate").value=(v/q).toFixed(4)}
}
async function saveMcForm(ev){ev.preventDefault();const btn=$("saveMc");setBusy(btn,true,"Saving…");formSay("mcSaveMessage","Posting MC1 purchase…","info");try{const payload={p_vendor_name:$("mcVendor").value.trim(),p_bill_no:$("mcBillNo").value.trim().toUpperCase(),p_bill_qty:Number($("mcBillQty").value||0),p_bill_value:Number($("mcBillValue").value||0),p_bill_date:$("mcBillDate").value||today(),p_remarks:$("mcRemarks").value.trim()||null};const r=await state.client.rpc("rr_post_mc_purchase_v1",payload);if(r.error)throw r.error;closeSheet("mcSheet");await loadData();say(`MC1 updated · ${kg(payload.p_bill_qty)} IN.`,"success")}catch(e){console.error(e);formSay("mcSaveMessage",errorText(e),"error")}finally{setBusy(btn,false)}}

function isOwner(){return state.role==="owner";}
function grForCbPurchase(id){return state.grEntries.filter(x=>x.source_type==="CB"&&String(x.cb_purchase_entry_id)===String(id)&&x.status!=="REVERSED");}
function grForMcPurchase(id){return state.grEntries.filter(x=>x.source_type==="MC1"&&String(x.mc_purchase_id)===String(id)&&x.status!=="REVERSED");}
function exchangesForGr(id){return state.exchangeEntries.filter(x=>String(x.gr_id)===String(id));}
function damageForPurchase(id){return state.damageClaims.filter(x=>String(x.purchase_entry_id)===String(id));}
function rollsForPurchase(id){return state.rolls.filter(x=>String(x.purchase_entry_id)===String(id)).sort((a,b)=>Number(a.roll_no||0)-Number(b.roll_no||0));}
function allocationsForPurchase(id){return state.allocations.filter(x=>String(x.purchase_entry_id)===String(id));}
function divisionById(id){return groups().flatMap(g=>g.divisions).find(x=>String(x.division_id||x.id)===String(id))||null;}
function colourById(id){return state.colours.find(x=>String(x.id)===String(id))||null;}
function grQty(rows){return rows.reduce((s,x)=>s+Number(x.gr_qty||0),0);}
function exchangeQty(grId){return exchangesForGr(grId).reduce((s,x)=>s+Number(x.received_qty||0),0);}
function operationStatus(text){return String(text||"ACTIVE").replaceAll("_"," ");}
function statusChip(text){const t=operationStatus(text);const bad=/REJECT|FULL GR|CLOSED/.test(t),good=/VERIFIED|RECEIVED|SENT/.test(t);return `<span class="status-chip ${good?"good":bad?"bad":""}">${safe(t)}</span>`;}
function normalizePhone(value){let x=String(value||"").replace(/\D/g,"");if(x.length===10)x=`91${x}`;return x;}
function adminPhoneDefault(){let phone="";try{if(typeof CFG!=="undefined")phone=CFG.DEFAULT_WHATSAPP||(Array.isArray(CFG.WHATSAPP)?CFG.WHATSAPP[0]:"")||""}catch{}return localStorage.getItem("redzed_admin_whatsapp")||phone||"";}
function openWhatsapp(phone,message){const n=normalizePhone(phone);if(!n)throw new Error("WhatsApp number required.");const url=`https://wa.me/${n}?text=${encodeURIComponent(message)}`;window.open(url,"_blank","noopener,noreferrer");}
function mediaRowsForClaim(claim){
  let rows=[];
  if(Array.isArray(claim?.media))rows=claim.media;
  else if(typeof claim?.media==="string"){try{rows=JSON.parse(claim.media)||[]}catch{}}
  if(!rows.length)rows=state.damageMedia.filter(x=>String(x.claim_id)===String(claim?.id));
  return rows;
}
function proofLinks(claim){return mediaRowsForClaim(claim).map(x=>x.file_url).filter(Boolean);}
function adminMessageWithProof(claim){const links=proofLinks(claim);return `${claim.admin_message||"Damage Verification Required"}${links.length?`\n\nProof:\n${links.join("\n")}`:""}`;}
function vendorMessageFor(claim){
  const links=proofLinks(claim);
  return `Namaste, aapke Bill No. ${claim.vendor_bill_no||"—"} ke CB ${claim.cb_no||"—"}, Division ${claim.division_code||"—"}, ${claim.particular_label||"particular"} me ${Number(claim.damage_qty||0).toFixed(3)} kg damage paya gaya hai. Claim value ${money(claim.claim_value)} hai. Kripya claim, GR ya replacement ki pushti karein.${links.length?`\n\nDamage proof:\n${links.join("\n")}`:""}`;
}
function mediaHtml(claim){const rows=mediaRowsForClaim(claim);if(!rows.length)return `<p class="muted">No proof uploaded.</p>`;return `<div class="proof-grid">${rows.map(m=>{const url=safe(m.file_url||"");const type=String(m.media_type||"").toUpperCase();return type==="IMAGE"?`<a href="${url}" target="_blank" rel="noopener"><img src="${url}" alt="Damage proof"></a>`:`<video controls preload="metadata" src="${url}"></video>`}).join("")}</div>`;}
function refreshActiveDetail(){if(!state.activeDetail)return;if(state.activeDetail.type==="mc")openMcDetails();else if(state.activeDetail.type==="cb")openCbDetails(state.activeDetail.id);}
async function reloadAndRestore(message){await loadData();refreshActiveDetail();if(message)say(message,"success");}

function bindDetailActions(){
  $("detailBody").querySelectorAll("[data-cb-gr]").forEach(b=>b.onclick=()=>openCbGr(b.dataset.cbGr,b.dataset.mode));
  $("detailBody").querySelectorAll("[data-mc-gr]").forEach(b=>b.onclick=()=>openMcGr(b.dataset.mcGr,b.dataset.mode));
  $("detailBody").querySelectorAll("[data-exchange]").forEach(b=>b.onclick=()=>openExchange(b.dataset.exchange));
  $("detailBody").querySelectorAll("[data-close-gr]").forEach(b=>b.onclick=()=>closeGrWithoutExchange(b.dataset.closeGr));
  $("detailBody").querySelectorAll("[data-damage]").forEach(b=>b.onclick=()=>openDamage(b.dataset.damage));
  $("detailBody").querySelectorAll("[data-send-admin]").forEach(b=>b.onclick=()=>sendAdminClaim(b.dataset.sendAdmin));
  $("detailBody").querySelectorAll("[data-admin-action]").forEach(b=>b.onclick=()=>adminClaimAction(b.dataset.claim,b.dataset.adminAction));
  $("detailBody").querySelectorAll("[data-vendor-message]").forEach(b=>b.onclick=()=>openVendorMessage(b.dataset.vendorMessage));
}

function mcPurchaseRow(p){
  const grs=grForMcPurchase(p.id),returned=grQty(grs),net=Math.max(0,Number(p.bill_qty||0)-returned);
  return `<tr><td>${safe(p.bill_date||"—")}</td><td><strong>${safe(p.vendor_name||"—")}</strong></td><td>${safe(p.bill_no||"—")}</td><td>${kg(p.bill_qty)}</td><td>${money(p.bill_rate)}</td><td>${money(p.bill_value)}</td><td class="negative">${kg(returned)}</td><td><strong>${kg(net)}</strong></td><td>${statusChip(p.operation_status|| (net<=0?"FULL_GR":returned>0?"PARTIAL_GR":"ACTIVE"))}</td><td><div class="row-actions">${net>0?`<button class="secondary tiny" data-mc-gr="${safe(p.id)}" data-mode="PARTIAL">Partial GR</button><button class="danger tiny" data-mc-gr="${safe(p.id)}" data-mode="FULL">Full GR</button>`:""}</div></td></tr>`;
}
function grHistoryHtml(source){
  const rows=state.grEntries.filter(g=>g.source_type===source&&g.status!=="REVERSED");
  if(!rows.length)return `<p class="muted">No GR record.</p>`;
  return `<div class="table-wrap"><table><thead><tr><th>GR No.</th><th>Date</th><th>Type</th><th>Qty</th><th>Rate</th><th>Value</th><th>Exchange IN</th><th>Status</th><th>Action</th></tr></thead><tbody>${rows.map(g=>{const received=exchangeQty(g.id),remain=Math.max(0,Number(g.gr_qty||0)-received);const canExchange=remain>0&&["AWAITING_EXCHANGE","PART_EXCHANGE_RECEIVED","GR_POSTED"].includes(g.status);return `<tr><td><strong>GR-${safe(g.gr_no)}</strong></td><td>${safe(g.gr_date||"—")}</td><td>${safe(g.gr_mode)}</td><td>${kg(g.gr_qty)}</td><td>${money(g.gr_rate)}</td><td>${money(g.gr_value)}</td><td>${kg(received)}</td><td>${statusChip(g.status)}</td><td><div class="row-actions">${canExchange?`<button class="primary tiny" data-exchange="${safe(g.id)}">Exchange IN</button>`:""}${canExchange?`<button class="secondary tiny" data-close-gr="${safe(g.id)}">Close No Exchange</button>`:""}</div></td></tr>`}).join("")}</tbody></table></div>`;
}

function openMcDetails(){
  const c=state.mc.card;if(!c){say("MC1 data unavailable.","error");return}
  state.activeDetail={type:"mc"};
  $("detailKicker").textContent="MATCHING CLOTH INVENTORY";$("detailTitle").textContent="MC1";
  const purchases=state.mc.purchases||[],ledger=state.mc.ledger||[];
  $("detailBody").innerHTML=`
    <section class="form-card"><div class="summary"><div><small>Current Qty</small><strong>${kg(c.current_qty)}</strong></div><div><small>Average Rate</small><strong>${money(c.avg_rate)}</strong></div><div><small>Current Value</small><strong>${money(c.current_value)}</strong></div><div><small>Total Consumption</small><strong>${kg(c.total_consumption_qty)}</strong></div></div></section>
    <section class="form-card spaced"><div class="section-row"><div><h3>MC1 Purchase Details</h3><p class="muted">Vendor, Bill, Qty, Rate, Value, GR और Exchange history.</p></div><button class="primary" data-open-mc>+ MC New</button></div><div class="table-wrap"><table><thead><tr><th>Bill Date</th><th>Vendor</th><th>Bill No.</th><th>Bill Qty</th><th>Rate</th><th>Value</th><th>GR Qty</th><th>Net Qty</th><th>Status</th><th>Action</th></tr></thead><tbody>${purchases.map(mcPurchaseRow).join("")||`<tr><td colspan="10">No MC1 purchase yet.</td></tr>`}</tbody></table></div></section>
    <section class="form-card spaced"><h3>MC1 GR / Exchange History</h3>${grHistoryHtml("MC1")}</section>
    <section class="form-card spaced"><h3>MC1 Ledger</h3><div class="table-wrap"><table><thead><tr><th>Date-Time</th><th>Type</th><th>Lot No.</th><th>IN Qty</th><th>OUT Qty</th><th>Rate Snapshot</th><th>Value</th><th>Balance Qty</th><th>Balance Value</th></tr></thead><tbody>${ledger.map(l=>`<tr><td>${dateTime(l.occurred_at)}</td><td>${safe(l.entry_type)}</td><td><strong>${safe(l.lot_no||"—")}</strong></td><td class="positive">${Number(l.qty_in||0)?kg(l.qty_in):"—"}</td><td class="negative">${Number(l.qty_out||0)?kg(l.qty_out):"—"}</td><td>${money(l.rate_snapshot)}</td><td>${money(Number(l.value_in||0)||Number(l.value_out||0))}</td><td>${kg(l.balance_qty)}</td><td>${money(l.balance_value)}</td></tr>`).join("")||`<tr><td colspan="9">No MC1 entry yet.</td></tr>`}</tbody></table></div></section>`;
  $("detailBody").querySelector("[data-open-mc]")?.addEventListener("click",()=>{closeSheet("detailSheet");openMcNew()});
  bindDetailActions();openSheet("detailSheet");
}

function cbPurchaseCard(p,g){
  const grs=grForCbPurchase(p.id),damages=damageForPurchase(p.id),original=Number(p.original_quantity??p.quantity??0),current=Number(p.available_quantity??p.quantity??0),returned=grQty(grs),damageQty=damages.reduce((s,x)=>s+Number(x.damage_qty||0),0),rolls=rollsForPurchase(p.id),allocs=allocationsForPurchase(p.id);
  return `<article class="history purchase-ops"><div class="card-head"><div><h4>${safe(categoryById(p.material_category_id)?.category_name||"Material")}</h4><p>${safe(p.fabric_name||"")} · <strong>${safe(p.vendor_name||"")}</strong></p><small>Bill ${safe(p.vendor_bill_no||"")} · ${safe(p.bill_date||"")}</small></div><div><strong>${kg(current)}</strong><small>${money(p.rate)}/kg · Current ${money(current*Number(p.rate||0))}</small></div></div>
    <div class="ops-metrics"><span><small>Original Qty</small><strong>${kg(original)}</strong></span><span><small>GR Qty</small><strong class="negative">${kg(returned)}</strong></span><span><small>Damage Qty</small><strong class="negative">${kg(damageQty)}</strong></span><span><small>Available Qty</small><strong>${kg(current)}</strong></span><span><small>Bill Rate</small><strong>${money(p.rate)}</strong></span><span><small>Status</small>${statusChip(p.operation_status)}</span></div>
    <div class="table-wrap compact"><table><thead><tr><th>Particular</th><th>Colour</th><th>Original</th><th>Available</th></tr></thead><tbody>${rolls.map(r=>`<tr><td>Roll ${safe(r.roll_no)}</td><td>${safe(colourById(r.cb_colour_id)?.colour_name||"—")}</td><td>${kg(r.original_quantity??r.quantity)}</td><td><strong>${kg(r.quantity)}</strong></td></tr>`).join("")||`<tr><td colspan="4">No roll row.</td></tr>`}</tbody></table></div>
    <div class="allocation-line"><small>Division allocation:</small> ${allocs.map(a=>`${safe(canonicalD(divisionById(a.division_id)))} ${kg(a.allocated_qty)}`).join(" · ")||"—"}</div>
    <p class="note">CB Damage / Partial GR / Full GR की actual entry Cutting Master से होगी। Owner approval के बाद यही bill ledger और available quantity update होगी।</p>
    ${grs.length?`<details><summary>GR / Exchange (${grs.length})</summary>${grHistoryForPurchase(grs)}</details>`:""}
    ${damages.length?`<details open><summary>Damage Claims (${damages.length})</summary>${damages.map(damageClaimHtml).join("")}</details>`:""}
  </article>`;
}
function grHistoryForPurchase(grs){return `<div class="table-wrap compact"><table><thead><tr><th>GR</th><th>Qty</th><th>Value</th><th>Reason</th><th>Exchange</th><th>Status</th><th>Action</th></tr></thead><tbody>${grs.map(g=>{const received=exchangeQty(g.id),remain=Math.max(0,Number(g.gr_qty||0)-received),can=remain>0&&["AWAITING_EXCHANGE","PART_EXCHANGE_RECEIVED","GR_POSTED"].includes(g.status);return `<tr><td>GR-${safe(g.gr_no)} · ${safe(g.gr_mode)}</td><td>${kg(g.gr_qty)}</td><td>${money(g.gr_value)}</td><td>${safe(g.reason)}</td><td>${kg(received)}</td><td>${statusChip(g.status)}</td><td><div class="row-actions">${can?`<button class="primary tiny" data-exchange="${safe(g.id)}">Exchange Roll</button><button class="secondary tiny" data-close-gr="${safe(g.id)}">No Exchange</button>`:""}</div></td></tr>`}).join("")}</tbody></table></div>`;}
function damageClaimHtml(c){const ownerVendor=isOwner()&&["ADMIN_VERIFIED","VENDOR_MESSAGE_SENT"].includes(c.claim_status);return `<article class="damage-claim"><div class="section-row"><div><strong>Damage-${safe(c.damage_no)}</strong><p>${safe(c.particular_label||"Particular")} · ${kg(c.damage_qty)} · ${money(c.claim_value)}</p><small>${safe(c.damage_stage)}${c.lot_no?` · Lot ${safe(c.lot_no)}`:""} · ${safe(c.reason)}</small></div>${statusChip(c.claim_status)}</div>${mediaHtml(c)}<div class="card-actions"><button class="secondary tiny" data-send-admin="${safe(c.id)}">WhatsApp Admin</button>${["PENDING_ADMIN","ADMIN_MESSAGE_SENT","RECHECK_REQUIRED"].includes(c.claim_status)?`<button class="primary tiny" data-admin-action="VERIFY" data-claim="${safe(c.id)}">Admin Verify</button><button class="secondary tiny" data-admin-action="RECHECK" data-claim="${safe(c.id)}">Recheck</button><button class="danger tiny" data-admin-action="REJECT" data-claim="${safe(c.id)}">Reject</button>`:""}${ownerVendor?`<button class="warning tiny" data-vendor-message="${safe(c.id)}">Owner → Vendor WhatsApp</button>`:""}</div></article>`;}

function openCbDetails(cbId){
  const g=groups().find(x=>String(x.cbId)===String(cbId));if(!g)return;
  state.activeDetail={type:"cb",id:cbId};const ps=purchasesFor(cbId),cols=coloursFor(cbId);
  $("detailKicker").textContent="CB DETAILS";$("detailTitle").textContent=g.cbNo;
  $("detailBody").innerHTML=`<section class="form-card"><div class="summary"><div><small>CB No.</small><strong>${safe(g.cbNo)}</strong></div><div><small>D Cards</small><strong>${g.divisions.map(canonicalD).join(" · ")}</strong></div><div><small>Colours</small><strong>${cols.length}</strong></div><div><small>Purchases</small><strong>${ps.length}</strong></div></div><div class="card-actions"><button id="detailAddMaterial" class="primary">+ Add Cuff / Collar / Other Material</button></div></section><section class="form-card spaced"><h3>Purchases, GR, Exchange और Damage</h3><div class="history-list">${ps.map(p=>cbPurchaseCard(p,g)).join("")||"No purchase"}</div></section>`;
  $("detailAddMaterial").onclick=()=>{closeSheet("detailSheet");resetCbAppend(cbId);openSheet("cbSheet")};bindDetailActions();openSheet("detailSheet");
}

function operationHeader(kicker,title,context){$("opsKicker").textContent=kicker;$("opsTitle").textContent=title;$("opsContext").textContent=context||"";$("opsMessage").textContent="";}
function showOperation(op){state.operation={pricingDriver:"rate",...op};renderOperation();openSheet("opsSheet");}
function purchaseById(id){return state.purchases.find(x=>String(x.id)===String(id))||null;}
function mcPurchaseById(id){return (state.mc.purchases||[]).find(x=>String(x.id)===String(id))||null;}
function grById(id){return state.grEntries.find(x=>String(x.id)===String(id))||null;}
function claimById(id){return state.damageClaims.find(x=>String(x.id)===String(id))||null;}
function divisionOptions(cbId,selected=""){const g=groups().find(x=>String(x.cbId)===String(cbId));return (g?.divisions||[]).map(d=>`<option value="${safe(d.division_id)}" ${String(d.division_id)===String(selected)?"selected":""}>${safe(canonicalD(d))} · ${kg(d.allocated_qty)}</option>`).join("");}
function rollOptions(purchaseId,selected="",allowAuto=true){const rows=rollsForPurchase(purchaseId).filter(x=>Number(x.quantity||0)>0);return `${allowAuto?`<option value="">Auto across available rolls</option>`:""}${rows.map(r=>`<option value="${safe(r.id)}" ${String(r.id)===String(selected)?"selected":""}>Roll ${safe(r.roll_no)} · ${safe(colourById(r.cb_colour_id)?.colour_name||"")} · ${kg(r.quantity)}</option>`).join("")}`;}
function colourOptions(cbId){return coloursFor(cbId).map(c=>`<option value="${safe(c.id)}">${safe(c.colour_name)}</option>`).join("");}

function openCbGr(id,mode){const p=purchaseById(id);if(!p)return;showOperation({kind:"CB_GR",purchaseId:id,mode,qty:Number(p.available_quantity??p.quantity??0)});}
function openMcGr(id,mode){const p=mcPurchaseById(id);if(!p)return;const available=Math.max(0,Number(p.bill_qty||0)-grQty(grForMcPurchase(id)));showOperation({kind:"MC_GR",purchaseId:id,mode,qty:available});}
function openExchange(grId){const g=grById(grId);if(!g)return;const remain=Math.max(0,Number(g.gr_qty||0)-exchangeQty(g.id));showOperation({kind:g.source_type==="CB"?"CB_EXCHANGE":"MC_EXCHANGE",grId,qty:remain,pricingDriver:"rate"});}
function openDamage(id){const p=purchaseById(id);if(!p)return;showOperation({kind:"DAMAGE",purchaseId:id});}
function openVendorMessage(id){const c=claimById(id);if(!c)return;showOperation({kind:"VENDOR_MESSAGE",claimId:id});}

function renderOperation(){
  const op=state.operation;if(!op)return;
  if(op.kind==="CB_GR"||op.kind==="MC_GR"){
    const p=op.kind==="CB_GR"?purchaseById(op.purchaseId):mcPurchaseById(op.purchaseId);const full=op.mode==="FULL";operationHeader("GOODS RETURN",`${full?"Full":"Partial"} GR`,`${p?.vendor_name||""} · Bill ${p?.vendor_bill_no||p?.bill_no||""}`);
    $("opsBody").innerHTML=`<section class="form-card"><div class="summary"><div><small>Available Qty</small><strong>${kg(op.qty)}</strong></div><div><small>GR Rate</small><strong>${money(p?.rate||p?.bill_rate)}</strong></div><div><small>GR Mode</small><strong>${safe(op.mode)}</strong></div><div><small>Source</small><strong>${safe(op.kind==="CB_GR"?"CB":"MC1")}</strong></div></div><div class="grid2 spaced-top"><label><span>GR Qty *</span><input id="opQty" type="number" min="0.001" max="${op.qty}" step="0.001" value="${full?op.qty:""}" ${full?"readonly":""}></label><label><span>GR Date *</span><input id="opDate" type="date" value="${today()}"></label>${op.kind==="CB_GR"&&!full?`<label><span>Roll / Particular</span><select id="opRoll">${rollOptions(op.purchaseId)}</select></label><label><span>Division</span><select id="opDivision"><option value="">Auto across allocations</option>${divisionOptions(p.cb_id)}</select></label>`:""}<label><span>Reason *</span><input id="opReason" placeholder="Vendor return reason"></label><label><span>Remarks</span><input id="opRemarks"></label></div><label class="check-line"><input id="opExchangeExpected" type="checkbox"> Replacement / Exchange expected</label></section>`;
    $("opsSave").textContent=`Post ${full?"Full":"Partial"} GR`;
  }else if(op.kind==="CB_EXCHANGE"||op.kind==="MC_EXCHANGE"){
    const g=grById(op.grId),old=op.kind==="CB_EXCHANGE"?purchaseById(g.cb_purchase_entry_id):mcPurchaseById(g.mc_purchase_id);operationHeader("EXCHANGE IN",op.kind==="CB_EXCHANGE"?"Replacement Roll Receive":"MC1 Exchange Receive",`Against GR-${g.gr_no} · ${old?.vendor_name||""}`);
    $("opsBody").innerHTML=`<section class="form-card"><div class="grid2"><label><span>Received Qty *</span><input id="opQty" type="number" min="0.001" max="${op.qty}" step="0.001" value="${op.qty}"></label><label><span>Received Date *</span><input id="opDate" type="date" value="${today()}"></label><label><span>Exchange Challan / Bill No. *</span><input id="opBillNo"></label><label><span>Rate *</span><input id="opRate" type="number" min="0.0001" step="0.0001" value="${Number(g.gr_rate||0).toFixed(4)}"></label><label><span>Value *</span><input id="opValue" type="number" min="0.01" step="0.01" value="${(Number(op.qty||0)*Number(g.gr_rate||0)).toFixed(2)}"></label>${op.kind==="CB_EXCHANGE"?`<label><span>New Roll Colour *</span><select id="opColour">${colourOptions(old.cb_id)}</select></label><label><span>New Roll No. *</span><input id="opRollNo" type="number" min="1" step="1"></label><label><span>Division *</span><select id="opDivision">${divisionOptions(old.cb_id,g.division_id)}</select></label>`:""}<label><span>Remarks</span><input id="opRemarks"></label></div><p class="note">Old returned record remains unchanged. Replacement is a new Exchange IN entry.</p></section>`;
    bindOperationPricing();$("opsSave").textContent="Receive Exchange";
  }else if(op.kind==="DAMAGE"){
    const p=purchaseById(op.purchaseId);operationHeader("DEFECT / DAMAGE","Create Vendor Damage Claim",`${p.vendor_name} · Bill ${p.vendor_bill_no}`);
    $("opsBody").innerHTML=`<section class="form-card"><div class="grid2"><label><span>Division *</span><select id="opDivision">${divisionOptions(p.cb_id)}</select></label><label><span>Roll / Particular</span><select id="opRoll">${rollOptions(p.id,"",false)}</select></label><label><span>Damage Found At *</span><select id="opStage"><option value="BEFORE_CUTTING">Before Cutting — reduce CB stock</option><option value="IN_LOT">During Cutting — deduct Lot costing</option></select></label><label id="opLotWrap" class="hidden"><span>Lot No. *</span><input id="opLotNo"></label><label><span>Damage Qty *</span><input id="opQty" type="number" min="0.001" step="0.001"></label><label><span>Damage Date *</span><input id="opDate" type="date" value="${today()}"></label><label><span>Reason *</span><input id="opReason" placeholder="Hole, stain, shade, weaving defect..."></label><label><span>Admin WhatsApp No. *</span><input id="opAdminPhone" inputmode="tel" value="${safe(adminPhoneDefault())}"></label></div><label class="spaced-top"><span>Remarks</span><textarea id="opRemarks" rows="2"></textarea></label><div class="grid2 spaced-top"><label><span>Images — max 5</span><input id="opImages" type="file" accept="image/*" multiple></label><label><span>Short Video / Screen Recording — 1</span><input id="opVideo" type="file" accept="video/*"></label></div><label class="check-line"><input id="opSendAdminNow" type="checkbox" checked> Save होने के बाद Admin WhatsApp खोलें</label><p class="note">Message केवल Admin के लिए बनेगा। Vendor WhatsApp केवल Admin verification के बाद Owner भेजेगा।</p></section>`;
    $("opStage").onchange=()=>$("opLotWrap").classList.toggle("hidden",$("opStage").value!=="IN_LOT");$("opsSave").textContent="Save Damage Claim";
  }else if(op.kind==="VENDOR_MESSAGE"){
    const c=claimById(op.claimId);operationHeader("OWNER ACTION","Vendor WhatsApp Message",`Admin verified · Damage-${c.damage_no}`);
    $("opsBody").innerHTML=`<section class="form-card"><label><span>Vendor WhatsApp No. *</span><input id="opVendorPhone" inputmode="tel" value="${safe(c.vendor_phone||"")}"></label><label class="spaced-top"><span>Message — Owner may edit</span><textarea id="opVendorMessage" rows="10">${safe(c.vendor_message||vendorMessageFor(c))}</textarea></label><p class="note">Only Owner role can send this Vendor message.</p></section>`;$("opsSave").textContent="Open Vendor WhatsApp";
  }
}
function bindOperationPricing(){const q=$("opQty"),r=$("opRate"),v=$("opValue");if(!q||!r||!v)return;const sync=source=>{const qty=Number(q.value||0),rate=Number(r.value||0),value=Number(v.value||0);if(source==="rate"){state.operation.pricingDriver="rate";v.value=qty>0?(qty*rate).toFixed(2):""}else if(source==="value"){state.operation.pricingDriver="value";r.value=qty>0?(value/qty).toFixed(4):""}else if(state.operation.pricingDriver==="value")r.value=qty>0?(value/qty).toFixed(4):"";else v.value=qty>0?(qty*rate).toFixed(2):""};q.oninput=()=>sync("qty");r.oninput=()=>sync("rate");v.oninput=()=>sync("value");}

async function uploadDamageProof(claim,images,video){
  if(!window.RR?.uploadMedia){if(images.length||video)throw new Error("real-common.js uploadMedia unavailable.");return []}
  if(images.length>5)throw new Error("Maximum 5 images allowed.");const files=[...images.map(file=>({file,type:"IMAGE"})),...(video?[{file:video,type:"VIDEO"}]:[])],uploaded=[];
  for(const item of files){const result=await RR.uploadMedia({file:item.file,entityType:"cb",entityId:String(claim.cb_id),mediaCategory:"damage",sourceType:"gallery",visibilityScope:"factory",caption:`Damage-${claim.damage_no} · ${claim.particular_label||"proof"}`});const m=result?.data||result;if(!m?.id)throw new Error(`Proof upload failed: ${item.file.name}`);const attach=await state.client.rpc("rr_attach_damage_media_v1",{p_claim_id:claim.id,p_media_id:m.id,p_media_type:item.type,p_file_url:m.file_url||m.public_url||m.url||null,p_file_name:item.file.name});if(attach.error)throw attach.error;uploaded.push({file_url:m.file_url||m.public_url||m.url||null,media_type:item.type})}
  return uploaded;
}
async function submitOperation(ev){
  ev.preventDefault();const op=state.operation,btn=$("opsSave");setBusy(btn,true,"Saving…");formSay("opsMessage","Processing…","info");
  try{
    let result,message;
    if(op.kind==="CB_GR")result=await state.client.rpc("rr_post_cb_gr_v1",{p_purchase_entry_id:op.purchaseId,p_gr_mode:op.mode,p_qty:op.mode==="FULL"?null:Number($("opQty").value||0),p_roll_id:op.mode==="FULL"?null:($("opRoll")?.value||null),p_division_id:op.mode==="FULL"?null:($("opDivision")?.value||null),p_gr_date:$("opDate").value,p_reason:$("opReason").value.trim(),p_remarks:$("opRemarks").value.trim()||null,p_exchange_expected:$("opExchangeExpected").checked});
    else if(op.kind==="MC_GR")result=await state.client.rpc("rr_post_mc_gr_v1",{p_mc_purchase_id:op.purchaseId,p_gr_mode:op.mode,p_qty:op.mode==="FULL"?null:Number($("opQty").value||0),p_gr_date:$("opDate").value,p_reason:$("opReason").value.trim(),p_remarks:$("opRemarks").value.trim()||null,p_exchange_expected:$("opExchangeExpected").checked});
    else if(op.kind==="CB_EXCHANGE")result=await state.client.rpc("rr_post_cb_exchange_v1",{p_gr_id:op.grId,p_received_qty:Number($("opQty").value||0),p_received_rate:Number($("opRate").value||0),p_challan_bill_no:$("opBillNo").value.trim(),p_received_date:$("opDate").value,p_colour_id:$("opColour").value,p_roll_no:Number($("opRollNo").value||0),p_division_id:$("opDivision").value,p_remarks:$("opRemarks").value.trim()||null});
    else if(op.kind==="MC_EXCHANGE")result=await state.client.rpc("rr_post_mc_exchange_v1",{p_gr_id:op.grId,p_received_qty:Number($("opQty").value||0),p_received_rate:Number($("opRate").value||0),p_challan_bill_no:$("opBillNo").value.trim(),p_received_date:$("opDate").value,p_remarks:$("opRemarks").value.trim()||null});
    else if(op.kind==="DAMAGE"){
      const phone=$("opAdminPhone").value.trim();localStorage.setItem("redzed_admin_whatsapp",phone);
      result=await state.client.rpc("rr_create_cb_damage_claim_v1",{p_purchase_entry_id:op.purchaseId,p_division_id:$("opDivision").value,p_roll_id:$("opRoll").value||null,p_damage_stage:$("opStage").value,p_lot_no:$("opLotNo")?.value.trim()||null,p_damage_qty:Number($("opQty").value||0),p_damage_date:$("opDate").value,p_reason:$("opReason").value.trim(),p_remarks:$("opRemarks").value.trim()||null,p_admin_phone:phone,p_particular_label:null});
      if(result.error)throw result.error;const claim=result.data?.claim||result.data;const images=[...($("opImages").files||[])],video=$("opVideo").files?.[0]||null;const uploaded=await uploadDamageProof(claim,images,video);if($("opSendAdminNow").checked){const msg=`${claim.admin_message}${uploaded.length?`\n\nProof:\n${uploaded.map(x=>x.file_url).filter(Boolean).join("\n")}`:""}`;openWhatsapp(phone,msg);const mark=await state.client.rpc("rr_mark_damage_admin_message_sent_v1",{p_claim_id:claim.id,p_admin_phone:phone});if(mark.error)console.warn(mark.error)}message=`Damage-${claim.damage_no} saved for Admin verification.`;
    }else if(op.kind==="VENDOR_MESSAGE"){
      const phone=$("opVendorPhone").value.trim(),text=$("opVendorMessage").value.trim();openWhatsapp(phone,text);result=await state.client.rpc("rr_mark_damage_vendor_message_sent_v1",{p_claim_id:op.claimId,p_vendor_phone:phone,p_vendor_message:text});message="Vendor WhatsApp opened and Owner action recorded.";
    }
    if(result?.error)throw result.error;if(!message)message=op.kind.includes("GR")?"GR posted successfully.":op.kind.includes("EXCHANGE")?"Exchange received successfully.":"Saved successfully.";closeSheet("opsSheet");await reloadAndRestore(message);
  }catch(e){console.error(e);formSay("opsMessage",errorText(e),"error")}finally{setBusy(btn,false)}
}
async function closeGrWithoutExchange(id){if(!confirm("Exchange receive नहीं होगा — GR को close करें?"))return;const r=await state.client.rpc("rr_close_gr_without_exchange_v1",{p_gr_id:id,p_note:"Closed without exchange"});if(r.error){say(errorText(r.error),"error");return}await reloadAndRestore("GR closed without exchange.");}
async function sendAdminClaim(id){const c=claimById(id);if(!c)return;const phone=c.admin_phone||adminPhoneDefault()||prompt("Admin WhatsApp number");if(!phone)return;try{localStorage.setItem("redzed_admin_whatsapp",phone);openWhatsapp(phone,adminMessageWithProof(c));const r=await state.client.rpc("rr_mark_damage_admin_message_sent_v1",{p_claim_id:id,p_admin_phone:phone});if(r.error)throw r.error;await reloadAndRestore("Admin WhatsApp opened.")}catch(e){say(errorText(e),"error")}}
async function adminClaimAction(id,action){const note=prompt(`${action} note / reason`)||"";const r=await state.client.rpc("rr_update_damage_admin_status_v1",{p_claim_id:id,p_action:action,p_note:note||null});if(r.error){say(errorText(r.error),"error");return}await reloadAndRestore(`Damage claim ${action.toLowerCase()} saved.`);}


function pickerImage(row,type){return type==="art"?artImage(row):printImage(row)}
function pickerNo(row,type){return type==="art"?artNo(row):printNo(row)}
function decisionPickButton({selected,label,sub,dataAttr,value}){
  return `<button type="button" class="pick ${selected?"selected":""}" ${dataAttr}="${safe(value)}"><strong>${safe(label)}</strong><small>${safe(sub||"")}</small></button>`;
}
function renderAssignmentPickers(){
  const q=$("assignSearch").value.trim().toLowerCase();

  $("artPicker").innerHTML=state.arts
    .filter(x=>JSON.stringify(x).toLowerCase().includes(q))
    .map(a=>`<button type="button" class="pick ${String(a.id)===String(state.selectedArtId)?"selected":""}" data-art="${safe(a.id)}">${pickerImage(a,"art")?`<img src="${safe(pickerImage(a,"art"))}">`:""}<strong>${safe(artNo(a))}</strong><small>${safe(a.product_name||a.item_name||a.category||"")}</small></button>`).join("");

  const printSpecial=[
    decisionPickButton({selected:state.printMode==="NA",label:"N.A. (DEFAULT)",sub:"No Print Work",dataAttr:"data-print-mode",value:"NA"}),
    decisionPickButton({selected:state.printMode==="DUE",label:"DUE",sub:"Decision intentionally later",dataAttr:"data-print-mode",value:"DUE"})
  ].join("");
  $("printPicker").innerHTML=printSpecial+state.prints
    .filter(x=>JSON.stringify(x).toLowerCase().includes(q))
    .map(p=>`<button type="button" class="pick ${state.printMode==="SELECTED"&&state.selectedPrintIds.includes(String(p.id))?"selected":""}" data-print="${safe(p.id)}">${pickerImage(p,"print")?`<img src="${safe(pickerImage(p,"print"))}">`:""}<strong>${safe(printNo(p))}</strong><small>${safe(p.print_name||p.short_note||"")}</small></button>`).join("");

  const stickers=stickerOptionsForArt().filter(x=>JSON.stringify(x).toLowerCase().includes(q));
  $("stickerPicker").innerHTML=[
    decisionPickButton({selected:state.stickerMode==="NA",label:"N.A. (DEFAULT)",sub:"No Sticker Work",dataAttr:"data-sticker-mode",value:"NA"}),
    decisionPickButton({selected:state.stickerMode==="DUE",label:"DUE",sub:"Decision intentionally later",dataAttr:"data-sticker-mode",value:"DUE"}),
    ...stickers.map(s=>`<button type="button" class="pick ${state.stickerMode==="SELECTED"&&state.selectedStickerIds.includes(String(s.id))?"selected":""}" data-sticker="${safe(s.id)}"><strong>${safe(String(s.work_type||"STICKER").toUpperCase())}</strong><small>${safe(s.work_name||s.notes||"")}</small></button>`)
  ].join("");

  const metals=metalOptionsForArt().filter(x=>JSON.stringify(x).toLowerCase().includes(q));
  $("metalIdPicker").innerHTML=[
    decisionPickButton({selected:state.metalIdMode==="NA",label:"N.A. (DEFAULT)",sub:"No Metal ID Work",dataAttr:"data-metal-mode",value:"NA"}),
    decisionPickButton({selected:state.metalIdMode==="DUE",label:"DUE",sub:"Decision intentionally later",dataAttr:"data-metal-mode",value:"DUE"}),
    ...metals.map(m=>`<button type="button" class="pick ${state.metalIdMode==="SELECTED"&&state.selectedMetalIdIds.includes(String(m.id))?"selected":""}" data-metal="${safe(m.id)}"><strong>METAL ID</strong><small>${safe(m.work_name||m.notes||"")}</small></button>`)
  ].join("");

  $("artPicker").querySelectorAll("[data-art]").forEach(b=>b.onclick=()=>{
    state.selectedArtId=b.dataset.art;
    state.selectedStickerIds=[];
    state.selectedMetalIdIds=[];
    state.stickerMode="NA";
    state.metalIdMode="NA";
    renderAssignmentPickers();
  });

  $("printPicker").querySelectorAll("[data-print-mode]").forEach(b=>b.onclick=()=>{
    state.printMode=b.dataset.printMode;
    if(state.printMode!=="SELECTED")state.selectedPrintIds=[];
    renderAssignmentPickers();
  });
  $("printPicker").querySelectorAll("[data-print]").forEach(b=>b.onclick=()=>{
    const id=b.dataset.print;
    state.printMode="SELECTED";
    state.selectedPrintIds=state.selectedPrintIds.includes(id)?state.selectedPrintIds.filter(x=>x!==id):[...state.selectedPrintIds,id];
    if(!state.selectedPrintIds.length)state.printMode="NA";
    renderAssignmentPickers();
  });

  $("stickerPicker").querySelectorAll("[data-sticker-mode]").forEach(b=>b.onclick=()=>{
    state.stickerMode=b.dataset.stickerMode;
    if(state.stickerMode!=="SELECTED")state.selectedStickerIds=[];
    renderAssignmentPickers();
  });
  $("stickerPicker").querySelectorAll("[data-sticker]").forEach(b=>b.onclick=()=>{
    const id=b.dataset.sticker;
    state.stickerMode="SELECTED";
    state.selectedStickerIds=state.selectedStickerIds.includes(id)?state.selectedStickerIds.filter(x=>x!==id):[...state.selectedStickerIds,id];
    if(!state.selectedStickerIds.length)state.stickerMode="NA";
    renderAssignmentPickers();
  });

  $("metalIdPicker").querySelectorAll("[data-metal-mode]").forEach(b=>b.onclick=()=>{
    state.metalIdMode=b.dataset.metalMode;
    if(state.metalIdMode!=="SELECTED")state.selectedMetalIdIds=[];
    renderAssignmentPickers();
  });
  $("metalIdPicker").querySelectorAll("[data-metal]").forEach(b=>b.onclick=()=>{
    const id=b.dataset.metal;
    state.metalIdMode="SELECTED";
    state.selectedMetalIdIds=state.selectedMetalIdIds.includes(id)?state.selectedMetalIdIds.filter(x=>x!==id):[...state.selectedMetalIdIds,id];
    if(!state.selectedMetalIdIds.length)state.metalIdMode="NA";
    renderAssignmentPickers();
  });
}

function openAssignment(unitId){
  const card=groups().flatMap(g=>g.divisions.map(d=>({g,d}))).find(x=>String(x.d.division_id)===String(unitId));
  if(!card)return;
  state.activeUnitId=unitId;
  const a=assignmentFor(unitId);

  state.selectedArtId=a?.art_id||null;
  const existingPrints=printsForAssignment(a).map(x=>String(x.id));
  state.selectedPrintIds=existingPrints;
  state.printMode=a?.print_due?"DUE":a?.print_not_applicable?"NA":existingPrints.length?"SELECTED":"NA";

  const existingStickers=stickerIdsForAssignment(a);
  state.selectedStickerIds=existingStickers;
  state.stickerMode=a?.sticker_due?"DUE":a?.sticker_not_applicable?"NA":existingStickers.length?"SELECTED":"NA";

  const existingMetal=metalIdIdsForAssignment(a);
  state.selectedMetalIdIds=existingMetal;
  state.metalIdMode=a?.metal_id_due?"DUE":a?.metal_id_not_applicable?"NA":existingMetal.length?"SELECTED":"NA";

  $("assignTitle").textContent=canonicalD(card.d);
  $("assignContext").textContent=card.g.cbNo;
  $("assignSearch").value="";
  formSay("assignMessage","");
  showAssignTab("art");
  renderAssignmentPickers();
  openSheet("assignSheet");
}

function showAssignTab(tab){
  state.decisionStep=tab;
  ["art","print","sticker","metalId"].forEach(key=>{
    const picker=$(key==="metalId"?"metalIdPicker":`${key}Picker`);
    const tabEl=$(key==="metalId"?"metalIdTab":`${key}Tab`);
    const active=key===tab;
    picker?.classList.toggle("hidden",!active);
    tabEl?.classList.toggle("active",active);
  });
  const cfg={
    art:["SUBMIT & CONTINUE","Art select kijiye. Submit & Continue se PRINT section khulega."],
    print:["SUBMIT & CONTINUE","Print select karein, ya N.A. leave karein, ya DUE select karein. Submit & Continue se STICKER section khulega."],
    sticker:["SUBMIT & CONTINUE","Sticker select karein, ya N.A. leave karein, ya DUE select karein. Submit & Continue se METAL ID section khulega."],
    metalId:["SAVE & EXIT","Metal ID select karein, ya N.A. leave karein, ya DUE select karein. Save & Exit final decision save karega."]
  }[tab];
  $("decisionNext").textContent=cfg[0];
  $("decisionNote").textContent=cfg[1];
  $("assignSearch").value="";
  renderAssignmentPickers();
}

function validateDecisionStep(){
  if(state.decisionStep==="art"&&!state.selectedArtId)return "Art select karna zaroori hai.";
  if(state.decisionStep==="print"&&state.printMode==="SELECTED"&&!state.selectedPrintIds.length)return "Actual Print select karein, ya N.A./DUE choose karein.";
  if(state.decisionStep==="sticker"&&state.stickerMode==="SELECTED"&&!state.selectedStickerIds.length)return "Sticker instruction select karein, ya N.A./DUE choose karein.";
  if(state.decisionStep==="metalId"&&state.metalIdMode==="SELECTED"&&!state.selectedMetalIdIds.length)return "Metal ID instruction select karein, ya N.A./DUE choose karein.";
  return "";
}

async function saveDecisionBundle(){
  const btn=$("decisionNext");
  setBusy(btn,true,"Saving…");
  try{
    const r=await state.client.rpc("rr_pm_save_decision_bundle_v802_2",{
      p_cb_unit_id:state.activeUnitId,
      p_art_id:state.selectedArtId,
      p_print_mode:state.printMode,
      p_print_ids:state.selectedPrintIds,
      p_sticker_mode:state.stickerMode,
      p_sticker_instruction_ids:state.selectedStickerIds,
      p_metal_id_mode:state.metalIdMode,
      p_metal_id_instruction_ids:state.selectedMetalIdIds
    });
    if(r.error)throw r.error;
    closeSheet("assignSheet");
    await loadData();
    say("Art / Print / Sticker / Metal ID decision saved.","success");
  }catch(e){
    console.error(e);
    formSay("assignMessage",errorText(e),"error");
  }finally{
    setBusy(btn,false);
  }
}

async function advanceDecision(){
  const err=validateDecisionStep();
  if(err){formSay("assignMessage",err,"error");return;}
  formSay("assignMessage","");
  if(state.decisionStep==="art")return showAssignTab("print");
  if(state.decisionStep==="print")return showAssignTab("sticker");
  if(state.decisionStep==="sticker")return showAssignTab("metalId");
  return saveDecisionBundle();
}



async function loadRole(){
  const r=await state.client.rpc("rr_current_role");
  if(!r.error&&r.data){state.role=String(r.data).toLowerCase();return state.role}
  if(window.RR?.requireOwner){await RR.requireOwner();state.role="owner";return state.role}
  throw new Error(`User role could not be verified: ${errorText(r.error)}`);
}
function bindStatic(){
  document.querySelectorAll("[data-close]").forEach(x=>x.addEventListener("click",()=>closeSheet(x.dataset.close)));
  $("openCbNew").onclick=openCbNew;$("openMcNew").onclick=openMcNew;$("refresh").onclick=loadData;$("search").oninput=renderGallery;
  $("filters").querySelectorAll("button").forEach(b=>b.onclick=()=>{state.filter=b.dataset.filter;$("filters").querySelectorAll("button").forEach(x=>x.classList.toggle("active",x===b));renderGallery()});
  $("divisionCount").oninput=()=>{state.materialEntries.forEach(e=>{if(e.scope==="all")e.selected=[]});renderMaterialList();updateCbSummary()};
  $("colourCount").oninput=()=>{const n=Math.max(1,Math.min(20,Number($("colourCount").value||1)));while(state.colourDrafts.length<n)state.colourDrafts.push(newColour(state.colourDrafts.length));while(state.colourDrafts.length>n){const c=state.colourDrafts.pop();if(c.objectUrl)URL.revokeObjectURL(c.objectUrl)}state.materialEntries.forEach(ensureEntryRolls);renderCbForm()};
  $("addMaterial").onclick=()=>{state.materialEntries.push(newMaterial("material"));renderMaterialList();updateCbSummary()};
  $("cbForm").onsubmit=saveCbForm;$("mcForm").onsubmit=saveMcForm;$("mcBillQty").oninput=()=>syncMcPricing("qty");$("mcBillRate").oninput=()=>syncMcPricing("rate");$("mcBillValue").oninput=()=>syncMcPricing("value");
  $("artTab").onclick=()=>showAssignTab("art");$("printTab").onclick=()=>showAssignTab("print");$("stickerTab").onclick=()=>showAssignTab("sticker");$("metalIdTab").onclick=()=>showAssignTab("metalId");$("assignSearch").oninput=renderAssignmentPickers;$("decisionNext").onclick=advanceDecision;
  $("opsForm").onsubmit=submitOperation;
  document.addEventListener("keydown",e=>{if(e.key==="Escape"){const open=document.querySelector(".sheet:not(.hidden)");if(open)closeSheet(open.id)}});
}

async function boot(){try{state.client=await waitForRuntime();if(!state.client)throw new Error("Supabase client unavailable. Check config.js, then refresh.");await loadRole();if(!["owner","admin"].includes(state.role))throw new Error("Product Master requires Owner or Admin role.");bindStatic();$("mcBillDate").value=today();await loadData()}catch(e){console.error(e);$("gallery").innerHTML=`<article class="empty"><h3>Product Master start failed</h3><p>${safe(errorText(e))}</p></article>`;say(errorText(e),"error")}}
boot();
})();
