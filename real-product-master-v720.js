 (() => {
"use strict";

window.REDZED_PRODUCT_MASTER_VERSION = "720.1-CB-MC1-RUNTIME-FIX";
const $ = id => document.getElementById(id);
const state = {
  client:null, filter:"all", mode:"create", activeCbId:null, activeUnitId:null,
  categories:[], galleryRows:[], purchases:[], rolls:[], colours:[], allocations:[],
  arts:[], prints:[], assignments:[], printAssignments:[], media:[], lots:[],
  mc:{card:null,purchases:[],ledger:[]}, colourDrafts:[], materialEntries:[],
  selectedArtId:null, selectedPrintIds:[]
};

const TABLES = {
  categories:"rr_material_categories", fabricPurchases:"rr_fabric_purchases", units:"rr_cb_units",
  colours:"rr_cb_colours", purchases:"rr_cb_purchase_entries", rolls:"rr_cb_purchase_rolls",
  allocations:"rr_cb_purchase_allocations", arts:"rr_art_master", prints:"rr_print_master",
  printView:"rr_print_library_view", assignments:"rr_cb_art_assignments",
  printAssignments:"rr_cb_print_assignments", media:"rr_media", lots:"rr_cutting_lots_v3"
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

async function loadData(){
  const btn=$("refresh");setBusy(btn,true,"Loading…");$("gallery").setAttribute("aria-busy","true");
  try{
    const [categories,gallery,purchases,rolls,colours,allocations,arts,prints,assignments,printAssignments,media,lots]=await Promise.all([
      requiredTable(TABLES.categories),loadGalleryRows(),requiredTable(TABLES.purchases,"*","created_at"),optionalTable(TABLES.rolls),requiredTable(TABLES.colours,"*","colour_order"),optionalTable(TABLES.allocations),requiredTable(TABLES.arts,"*","updated_at"),loadPrints(),requiredTable(TABLES.assignments,"*","updated_at"),requiredTable(TABLES.printAssignments,"*","sequence_no"),optionalTable(TABLES.media),optionalTable(TABLES.lots,"*","created_at"),loadMc()
    ]);
    Object.assign(state,{categories,galleryRows:gallery,purchases,rolls,colours,allocations,arts,prints,assignments,printAssignments,media,lots});
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
function lotsForUnit(unitId){return state.lots.filter(x=>String(x.cb_unit_id||x.division_id)===String(unitId));}
function artImage(art){if(!art)return"";return art.hero_image_url||art.image_url||art.artwork_url||state.media.find(m=>String(m.entity_id)===String(art.id))?.file_url||"";}
function printImage(p){if(!p)return"";return p.artwork_url||p.garment_preview_url||p.image_url||state.media.find(m=>String(m.entity_id)===String(p.id))?.file_url||"";}
function artNo(a){return a?.art_no||a?.art_code||a?.code||"";}function printNo(p){return p?.print_no||p?.print_code||p?.code||"";}

function renderStats(){const gs=groups();const divisions=gs.reduce((s,g)=>s+g.divisions.length,0);const decided=gs.reduce((s,g)=>s+g.divisions.filter(d=>assignmentFor(d.division_id)).length,0);const mc=state.mc.card||{};$("stats").innerHTML=[
  ["CB Cards",gs.length],["D Cards",divisions],["Art Decided",decided],["MC1 Balance",kg(mc.current_qty)],["MC1 Avg Rate",money(mc.avg_rate)]
].map(([a,b])=>`<article class="stat"><small>${safe(a)}</small><strong>${safe(b)}</strong></article>`).join("");}

function mcCardHtml(){const c=state.mc.card;if(!c){return `<article class="card mc-card"><div class="card-body"><div class="card-head"><div><span class="chip mc">MATCHING CLOTH</span><h3>MC1</h3></div></div><p class="note">MC1 backend ready नहीं है। पहले redzed-mc1-v720.sql run करें।</p><div class="card-actions"><button class="primary" data-open-mc>+ MC New</button></div></div></article>`}
  return `<article class="card mc-card" data-search="mc1 matching ${safe(state.mc.purchases.map(x=>`${x.vendor_name} ${x.bill_no}`).join(" "))}"><div class="card-body"><div class="card-head"><div><span class="chip mc">CONSOLIDATED MATCHING CLOTH</span><h3>MC1</h3></div><strong>${kg(c.current_qty)}</strong></div><div class="metrics"><div class="metric"><small>Current Qty</small><strong>${kg(c.current_qty)}</strong></div><div class="metric"><small>Average Rate</small><strong>${money(c.avg_rate)}</strong></div><div class="metric"><small>Stock Value</small><strong>${money(c.current_value)}</strong></div><div class="metric"><small>Total IN</small><strong>${kg(c.total_purchase_qty)}</strong></div><div class="metric"><small>Total OUT</small><strong>${kg(c.total_consumption_qty)}</strong></div><div class="metric"><small>Last Updated</small><strong>${dateTime(c.updated_at)}</strong></div></div><p class="note">One card · No colour · No cloth name · Lot cost snapshot remains fixed.</p><div class="card-actions"><button class="primary" data-open-mc>+ MC New</button><button class="secondary" data-mc-detail>MC1 Details</button></div></div></article>`;
}

function cbCardHtml(g,d){
  const unitId=d.division_id;const a=assignmentFor(unitId);const art=artFor(a);const ps=printsForAssignment(a);const cols=coloursFor(g.cbId);const lots=lotsForUnit(unitId);const lotText=lots.map(x=>x.lot_no).filter(Boolean).join(" · ");
  const images=[art?{url:artImage(art),label:`ART ${artNo(art)}`} : null,...ps.map(p=>({url:printImage(p),label:`PRINT ${printNo(p)}`}))].filter(x=>x?.url);
  const hero=images[0]?.url||cols.find(x=>x.image_url)?.image_url||"";
  const search=[g.cbNo,canonicalD(d),artNo(art),ps.map(printNo).join(" "),lots.map(x=>x.lot_no).join(" "),purchasesFor(g.cbId).map(x=>`${x.vendor_name} ${x.vendor_bill_no} ${x.fabric_name}`).join(" "),cols.map(x=>x.colour_name).join(" ")].join(" ").toLowerCase();
  return `<article class="card" data-kind="cb" data-ready="${a?"1":"0"}" data-search="${safe(search)}"><div class="card-body"><div class="card-head"><div><span class="chip ${a?"ready":""}">${a?"ART DECIDED":"ART DUE"}</span><h3>${safe(g.cbNo)}</h3><strong>${safe(canonicalD(d))}</strong></div>${hero?`<img src="${safe(hero)}" alt="" style="width:78px;height:78px;object-fit:cover;border-radius:14px">`:""}</div><div class="metrics"><div class="metric"><small>D No.</small><strong>${safe(canonicalD(d))}</strong></div><div class="metric"><small>Art</small><strong>${safe(artNo(art)||"Due")}</strong></div><div class="metric"><small>Print</small><strong>${safe(a?.print_not_applicable?"N/A":ps.map(printNo).join(" · ")||"Due")}</strong></div><div class="metric"><small>Weight</small><strong>${kg(d.allocated_qty??d.divided_weight)}</strong></div><div class="metric"><small>Colours</small><strong>${cols.length}</strong></div><div class="metric"><small>Lot No.</small><strong>${safe(lotText||"Due")}</strong></div></div><div class="colour-strip">${cols.map(c=>`<span class="colour-pill">${c.image_url?`<img src="${safe(c.image_url)}">`:""}<b>${safe(c.colour_name)}</b></span>`).join("")}</div><div class="card-actions"><button class="secondary" data-cb-detail="${safe(g.cbId)}">CB Details</button><button class="primary" data-assign="${safe(unitId)}">${a?"Change Art / Print":"Assign Art / Print"}</button></div></div></article>`;
}

function filterPass(card){const f=state.filter;if(f==="all")return true;if(f==="mc")return card.dataset.kind==="mc";if(f==="cb")return card.dataset.kind==="cb";if(f==="planning")return card.dataset.kind==="cb"&&card.dataset.ready==="0";if(f==="ready")return card.dataset.kind==="cb"&&card.dataset.ready==="1";return true;}
function renderGallery(){const q=$("search").value.trim().toLowerCase();let html=mcCardHtml().replace('<article class="card mc-card"','<article class="card mc-card" data-kind="mc"');groups().forEach(g=>g.divisions.forEach(d=>{html+=cbCardHtml(g,d)}));$("gallery").innerHTML=html;const cards=[...$("gallery").querySelectorAll(".card")];let visible=0;cards.forEach(c=>{const ok=filterPass(c)&&(c.dataset.search||c.textContent.toLowerCase()).includes(q);c.classList.toggle("hidden",!ok);if(ok)visible++});if(!visible)$("gallery").insertAdjacentHTML("beforeend",`<article class="empty">No matching card found.</article>`);bindGallery();}
function renderAll(){renderStats();renderGallery();}
function bindGallery(){$("gallery").querySelectorAll("[data-open-mc]").forEach(b=>b.onclick=openMcNew);$("gallery").querySelectorAll("[data-mc-detail]").forEach(b=>b.onclick=openMcDetails);$("gallery").querySelectorAll("[data-cb-detail]").forEach(b=>b.onclick=()=>openCbDetails(b.dataset.cbDetail));$("gallery").querySelectorAll("[data-assign]").forEach(b=>b.onclick=()=>openAssignment(b.dataset.assign));}

function newColour(index){return {name:`Colour ${index+1}`,imageUrl:"",file:null,objectUrl:""};}
function newMaterial(type="regular"){
  const regular=type==="regular";const cat=regular?(categoryByCode("regular-cloth")||materialCategories()[0]):(categoryByCode("cuff-collar")||materialCategories().find(x=>String(x.category_code).includes("cuff"))||materialCategories()[0]);
  return {id:crypto.randomUUID(),type,categoryId:cat?.id||"",vendor:"",fabric:"",billNo:"",billDate:today(),billValue:"",scope:"all",selected:[],rolls:state.colourDrafts.map(()=>[{qty:""}])};
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
function entryRate(e){const q=entryQty(e),v=Number(e.billValue||0);return q>0?v/q:0}
function entryValue(e){return Number(e.billValue||0)}
function renderMaterialList(){
  state.materialEntries.forEach(ensureEntryRolls);
  $("materialList").innerHTML=state.materialEntries.map((e,ei)=>`<article class="material-row" data-entry="${safe(e.id)}"><div class="material-head"><h4>${e.type==="regular"?"Regular Cloth":"Cuff / Collar / Other Material"}</h4>${e.type!=="regular"?`<button class="danger remove-entry" type="button">Remove</button>`:""}</div><div class="grid3"><label><span>Material *</span><select class="mat-category" ${e.type==="regular"?"disabled":""}>${materialOptions(e.categoryId)}</select></label><label><span>Vendor Name *</span><input class="mat-vendor" value="${safe(e.vendor)}"></label><label><span>Fabric / Material Name *</span><input class="mat-fabric" value="${safe(e.fabric)}"></label><label><span>Bill No. *</span><input class="mat-bill" value="${safe(e.billNo)}"></label><label><span>Bill Date *</span><input class="mat-date" type="date" value="${safe(e.billDate)}"></label><label><span>Bill Value *</span><input class="mat-value" type="number" min="0" step="0.01" value="${safe(e.billValue)}"></label></div><div class="summary" style="margin-top:10px"><div><small>Bill Qty — rolls से</small><strong class="entry-qty">${kg(entryQty(e))}</strong></div><div><small>Rate — Auto</small><strong class="entry-rate">${money(entryRate(e))}</strong></div><div><small>Allocation</small><strong>${e.scope==="all"?"All D":"Selected D"}</strong></div><div><small>Type</small><strong>${e.type==="regular"?"Regular Cloth":"Material"}</strong></div></div><div class="allocation"><label><input type="radio" name="scope-${safe(e.id)}" value="all" ${e.scope==="all"?"checked":""}>All Divisions</label><label><input type="radio" name="scope-${safe(e.id)}" value="selected" ${e.scope==="selected"?"checked":""}>Selected Divisions</label>${divisionChoices().map(i=>`<label class="division-check ${e.scope==="selected"?"":"hidden"}"><input type="checkbox" value="${i}" ${e.selected.includes(i)?"checked":""}>D${i}</label>`).join("")}</div><div class="rolls">${e.rolls.map((rolls,ci)=>`<section><strong>${safe(state.colourDrafts[ci]?.name||`Colour ${ci+1}`)}</strong><div class="roll-set" data-colour-index="${ci}">${rolls.map((r,ri)=>`<div class="roll-row" data-roll="${ri}"><b>Roll ${ri+1}</b><input class="roll-qty" type="number" min="0" step="0.001" placeholder="Qty kg" value="${safe(r.qty)}"><button class="danger remove-roll" type="button" ${ri===0?"disabled":""}>×</button></div>`).join("")}<button class="secondary add-roll" type="button" style="margin-top:7px">+ Add Roll</button></div></section>`).join("")}</div></article>`).join("");
  $("materialList").querySelectorAll("[data-entry]").forEach(n=>{const e=state.materialEntries.find(x=>x.id===n.dataset.entry);if(!e)return;const bind=(sel,key,event="input")=>{const x=n.querySelector(sel);if(x)x.addEventListener(event,ev=>{e[key]=ev.target.value;updateCbSummary();if(key==="billValue")renderMaterialList()})};bind(".mat-category","categoryId","change");bind(".mat-vendor","vendor");bind(".mat-fabric","fabric");bind(".mat-bill","billNo");bind(".mat-date","billDate","change");bind(".mat-value","billValue");n.querySelector(".remove-entry")?.addEventListener("click",()=>{state.materialEntries=state.materialEntries.filter(x=>x.id!==e.id);renderMaterialList();updateCbSummary()});n.querySelectorAll(`input[name="scope-${CSS.escape(e.id)}"]`).forEach(r=>r.onchange=()=>{e.scope=r.value;renderMaterialList()});n.querySelectorAll(".division-check input").forEach(ch=>ch.onchange=()=>{const v=Number(ch.value);e.selected=ch.checked?[...new Set([...e.selected,v])]:e.selected.filter(x=>x!==v)});n.querySelectorAll(".roll-set").forEach(set=>{const ci=Number(set.dataset.colourIndex);set.querySelectorAll("[data-roll]").forEach(row=>{const ri=Number(row.dataset.roll);row.querySelector(".roll-qty").oninput=ev=>{e.rolls[ci][ri].qty=ev.target.value;updateCbSummary();row.closest("[data-entry]").querySelector(".entry-qty").textContent=kg(entryQty(e));row.closest("[data-entry]").querySelector(".entry-rate").textContent=money(entryRate(e))};row.querySelector(".remove-roll")?.addEventListener("click",()=>{if(ri===0)return;e.rolls[ci].splice(ri,1);renderMaterialList();updateCbSummary()})});set.querySelector(".add-roll").onclick=()=>{e.rolls[ci].push({qty:""});renderMaterialList()}})});
}
function updateCbSummary(){const qtyTotal=state.materialEntries.reduce((s,e)=>s+entryQty(e),0);const valueTotal=state.materialEntries.reduce((s,e)=>s+entryValue(e),0);$("cbTotalQty").textContent=kg(qtyTotal);$("cbTotalValue").textContent=money(valueTotal);$("cbDivisionPreview").textContent=divisionChoices().map(i=>`D${i}`).join(" · ");}
function renderCbForm(){renderColourList();renderMaterialList();updateCbSummary();}

function validateEntry(e,index){const q=entryQty(e);if(!e.categoryId)throw new Error(`Purchase ${index+1}: Material चुनें.`);if(!e.vendor.trim())throw new Error(`Purchase ${index+1}: Vendor Name required.`);if(!e.fabric.trim())throw new Error(`Purchase ${index+1}: Fabric / Material Name required.`);if(!e.billNo.trim())throw new Error(`Purchase ${index+1}: Bill No required.`);if(!e.billDate)throw new Error(`Purchase ${index+1}: Bill Date required.`);if(q<=0)throw new Error(`Purchase ${index+1}: Roll Qty required.`);if(Number(e.billValue||0)<=0)throw new Error(`Purchase ${index+1}: Bill Value required.`);if(e.scope==="selected"&&!e.selected.length)throw new Error(`Purchase ${index+1}: कम से कम एक Division चुनें.`)}
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

function openMcNew(){if(!state.mc.card&&state.mc.error){say("MC1 SQL patch पहले run करें.","error")}$("mcForm").reset();$("mcBillDate").value=today();$("mcBillRate").value="0";formSay("mcSaveMessage","");openSheet("mcSheet");setTimeout(()=>$("mcVendor").focus(),80)}
function updateMcRate(){const q=Number($("mcBillQty").value||0),v=Number($("mcBillValue").value||0);$("mcBillRate").value=q>0?(v/q).toFixed(4):"0";}
async function saveMcForm(ev){ev.preventDefault();const btn=$("saveMc");setBusy(btn,true,"Saving…");formSay("mcSaveMessage","Posting MC1 purchase…","info");try{const payload={p_vendor_name:$("mcVendor").value.trim(),p_bill_no:$("mcBillNo").value.trim().toUpperCase(),p_bill_qty:Number($("mcBillQty").value||0),p_bill_value:Number($("mcBillValue").value||0),p_bill_date:$("mcBillDate").value||today(),p_remarks:$("mcRemarks").value.trim()||null};const r=await state.client.rpc("rr_post_mc_purchase_v1",payload);if(r.error)throw r.error;closeSheet("mcSheet");await loadData();say(`MC1 updated · ${kg(payload.p_bill_qty)} IN.`,"success")}catch(e){console.error(e);formSay("mcSaveMessage",errorText(e),"error")}finally{setBusy(btn,false)}}

function openMcDetails(){const c=state.mc.card;if(!c){say("MC1 data unavailable.","error");return}$("detailKicker").textContent="MATCHING CLOTH INVENTORY";$("detailTitle").textContent="MC1";const ledger=state.mc.ledger||[];$("detailBody").innerHTML=`<section class="form-card"><div class="summary"><div><small>Current Qty</small><strong>${kg(c.current_qty)}</strong></div><div><small>Average Rate</small><strong>${money(c.avg_rate)}</strong></div><div><small>Current Value</small><strong>${money(c.current_value)}</strong></div><div><small>Total Consumption</small><strong>${kg(c.total_consumption_qty)}</strong></div></div></section><section class="form-card" style="margin-top:12px"><h3>MC1 Ledger</h3><div class="table-wrap"><table><thead><tr><th>Date-Time</th><th>Type</th><th>Lot No.</th><th>IN Qty</th><th>OUT Qty</th><th>Rate Snapshot</th><th>Value</th><th>Balance Qty</th><th>Balance Value</th></tr></thead><tbody>${ledger.map(l=>`<tr><td>${dateTime(l.occurred_at)}</td><td>${safe(l.entry_type)}</td><td><strong>${safe(l.lot_no||"—")}</strong></td><td class="positive">${Number(l.qty_in||0)?kg(l.qty_in):"—"}</td><td class="negative">${Number(l.qty_out||0)?kg(l.qty_out):"—"}</td><td>${money(l.rate_snapshot)}</td><td>${money(Number(l.value_in||0)||Number(l.value_out||0))}</td><td>${kg(l.balance_qty)}</td><td>${money(l.balance_value)}</td></tr>`).join("")||`<tr><td colspan="9">No MC1 entry yet.</td></tr>`}</tbody></table></div></section>`;openSheet("detailSheet")}

function openCbDetails(cbId){const g=groups().find(x=>String(x.cbId)===String(cbId));if(!g)return;const ps=purchasesFor(cbId),cols=coloursFor(cbId);$("detailKicker").textContent="CB DETAILS";$("detailTitle").textContent=g.cbNo;$("detailBody").innerHTML=`<section class="form-card"><div class="summary"><div><small>CB No.</small><strong>${safe(g.cbNo)}</strong></div><div><small>D Cards</small><strong>${g.divisions.map(canonicalD).join(" · ")}</strong></div><div><small>Colours</small><strong>${cols.length}</strong></div><div><small>Purchases</small><strong>${ps.length}</strong></div></div><div class="card-actions"><button id="detailAddMaterial" class="primary">+ Add Cuff / Collar / Other Material</button></div></section><section class="form-card" style="margin-top:12px"><h3>Purchases</h3><div class="history-list">${ps.map(p=>`<article class="history"><div class="card-head"><div><h4>${safe(categoryById(p.material_category_id)?.category_name||"Material")}</h4><p>${safe(p.fabric_name||"")} · ${safe(p.vendor_name||"")}</p><small>Bill ${safe(p.vendor_bill_no||"")} · ${safe(p.bill_date||"")}</small></div><div><strong>${kg(p.quantity)}</strong><small>${money(p.rate)}/kg · ${money(Number(p.quantity||0)*Number(p.rate||0))}</small></div></div></article>`).join("")||"No purchase"}</div></section>`;$("detailAddMaterial").onclick=()=>{closeSheet("detailSheet");resetCbAppend(cbId);openSheet("cbSheet")};openSheet("detailSheet")}

function pickerImage(row,type){return type==="art"?artImage(row):printImage(row)}
function pickerNo(row,type){return type==="art"?artNo(row):printNo(row)}
function renderAssignmentPickers(){const q=$("assignSearch").value.trim().toLowerCase();$("artPicker").innerHTML=state.arts.filter(x=>JSON.stringify(x).toLowerCase().includes(q)).map(a=>`<button class="pick ${String(a.id)===String(state.selectedArtId)?"selected":""}" data-art="${safe(a.id)}">${pickerImage(a,"art")?`<img src="${safe(pickerImage(a,"art"))}">`:""}<strong>${safe(artNo(a))}</strong><small>${safe(a.product_name||a.item_name||a.category||"")}</small></button>`).join("");$("printPicker").innerHTML=`<button class="pick ${state.selectedPrintIds.includes("__NA__")?"selected":""}" data-print="__NA__"><strong>N/A</strong><small>No Print Required</small></button>`+state.prints.filter(x=>JSON.stringify(x).toLowerCase().includes(q)).map(p=>`<button class="pick ${state.selectedPrintIds.includes(String(p.id))?"selected":""}" data-print="${safe(p.id)}">${pickerImage(p,"print")?`<img src="${safe(pickerImage(p,"print"))}">`:""}<strong>${safe(printNo(p))}</strong><small>${safe(p.print_name||p.short_note||"")}</small></button>`).join("");$("artPicker").querySelectorAll("[data-art]").forEach(b=>b.onclick=()=>{state.selectedArtId=b.dataset.art;renderAssignmentPickers()});$("printPicker").querySelectorAll("[data-print]").forEach(b=>b.onclick=()=>{const id=b.dataset.print;if(id==="__NA__")state.selectedPrintIds=["__NA__"];else{state.selectedPrintIds=state.selectedPrintIds.filter(x=>x!=="__NA__");state.selectedPrintIds=state.selectedPrintIds.includes(id)?state.selectedPrintIds.filter(x=>x!==id):[...state.selectedPrintIds,id]}renderAssignmentPickers()})}
function openAssignment(unitId){const card=groups().flatMap(g=>g.divisions.map(d=>({g,d}))).find(x=>String(x.d.division_id)===String(unitId));if(!card)return;state.activeUnitId=unitId;const a=assignmentFor(unitId);state.selectedArtId=a?.art_id||null;state.selectedPrintIds=a?.print_not_applicable?["__NA__"]:printsForAssignment(a).map(x=>String(x.id));$("assignTitle").textContent=canonicalD(card.d);$("assignContext").textContent=card.g.cbNo;$("assignSearch").value="";formSay("assignMessage","");showAssignTab("art");renderAssignmentPickers();openSheet("assignSheet")}
function showAssignTab(tab){const art=tab==="art";$("artPicker").classList.toggle("hidden",!art);$("printPicker").classList.toggle("hidden",art);$("artTab").classList.toggle("active",art);$("printTab").classList.toggle("active",!art)}
async function saveAssignment(){if(!state.selectedArtId){formSay("assignMessage","Art select करें.","error");return}const btn=$("saveAssignment");setBusy(btn,true,"Saving…");try{const na=state.selectedPrintIds.includes("__NA__");const clean=state.selectedPrintIds.filter(x=>x!=="__NA__");if(!na){const rpc=await state.client.rpc("rr_save_cb_art_print_assignment",{p_cb_unit_id:state.activeUnitId,p_art_id:state.selectedArtId,p_print_ids:clean});if(!rpc.error){closeSheet("assignSheet");await loadData();say("Art / Print decision saved.","success");return}if(!/function|schema cache|PGRST202/i.test(`${rpc.error.code} ${rpc.error.message}`))throw rpc.error}
    const existing=assignmentFor(state.activeUnitId);const payload={art_id:state.selectedArtId,print_not_applicable:na,status:"material_check",bypass_reason:null,bypassed_by:null,bypassed_at:null};const r=existing?await state.client.from(TABLES.assignments).update(payload).eq("id",existing.id).select().single():await state.client.from(TABLES.assignments).insert({cb_id:state.activeUnitId,...payload}).select().single();if(r.error)throw r.error;const del=await state.client.from(TABLES.printAssignments).delete().eq("assignment_id",r.data.id);if(del.error)throw del.error;if(clean.length){const ins=await state.client.from(TABLES.printAssignments).insert(clean.map((id,i)=>({assignment_id:r.data.id,print_id:id,sequence_no:i+1})));if(ins.error)throw ins.error}await state.client.from(TABLES.units).update({status:"art_assigned"}).eq("id",state.activeUnitId);closeSheet("assignSheet");await loadData();say("Art / Print decision saved.","success")
  }catch(e){console.error(e);formSay("assignMessage",errorText(e),"error")}finally{setBusy(btn,false)}}

function bindStatic(){
  document.querySelectorAll("[data-close]").forEach(x=>x.addEventListener("click",()=>closeSheet(x.dataset.close)));
  $("openCbNew").onclick=openCbNew;$("openMcNew").onclick=openMcNew;$("refresh").onclick=loadData;$("search").oninput=renderGallery;
  $("filters").querySelectorAll("button").forEach(b=>b.onclick=()=>{state.filter=b.dataset.filter;$("filters").querySelectorAll("button").forEach(x=>x.classList.toggle("active",x===b));renderGallery()});
  $("divisionCount").oninput=()=>{state.materialEntries.forEach(e=>{if(e.scope==="all")e.selected=[]});renderMaterialList();updateCbSummary()};
  $("colourCount").oninput=()=>{const n=Math.max(1,Math.min(20,Number($("colourCount").value||1)));while(state.colourDrafts.length<n)state.colourDrafts.push(newColour(state.colourDrafts.length));while(state.colourDrafts.length>n){const c=state.colourDrafts.pop();if(c.objectUrl)URL.revokeObjectURL(c.objectUrl)}state.materialEntries.forEach(ensureEntryRolls);renderCbForm()};
  $("addMaterial").onclick=()=>{state.materialEntries.push(newMaterial("material"));renderMaterialList();updateCbSummary()};
  $("cbForm").onsubmit=saveCbForm;$("mcForm").onsubmit=saveMcForm;$("mcBillQty").oninput=updateMcRate;$("mcBillValue").oninput=updateMcRate;
  $("artTab").onclick=()=>showAssignTab("art");$("printTab").onclick=()=>showAssignTab("print");$("assignSearch").oninput=renderAssignmentPickers;$("saveAssignment").onclick=saveAssignment;
  document.addEventListener("keydown",e=>{if(e.key==="Escape"){const open=document.querySelector(".sheet:not(.hidden)");if(open)closeSheet(open.id)}});
}

async function boot(){try{state.client=await waitForRuntime();if(!state.client)throw new Error("Supabase client unavailable. Replace config.js and HTML from the V720.1 ZIP, then refresh.");if(window.RR?.requireOwner)await RR.requireOwner();bindStatic();$("mcBillDate").value=today();await loadData()}catch(e){console.error(e);$("gallery").innerHTML=`<article class="empty"><h3>Product Master start failed</h3><p>${safe(errorText(e))}</p></article>`;say(errorText(e),"error")}}
boot();
})();
