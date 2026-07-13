(() => {
"use strict";
const $=id=>document.getElementById(id);
const PROCESSES=[
 {code:"cut",name:"Cut",order:10},
 {code:"print",name:"Print",order:20},
 {code:"sticker",name:"Sticker",order:30},
 {code:"kr",name:"KR",order:40},
 {code:"ov",name:"OV",order:50},
 {code:"fld",name:"FLD",order:60},
 {code:"thread-cut",name:"Thread Cut",order:70},
 {code:"press",name:"Press",order:80},
 {code:"pack",name:"Pack",order:90},
 {code:"others",name:"Others",order:100}
];

let categories=[],arts=[],summaries=[],mediaMap={},queued=[],selectedIcon=null,builder,activeImage=null;
let categoryHasCosts=false;
let basicRatesUnlocked=false;

function refreshBasicLockIcon(){
 const lock=$("basicLockToggle");
 if(!lock)return;

 if(!categoryHasCosts){
  lock.textContent="🔓";
  lock.disabled=true;
  lock.title="Enter first Basic rates";
  return;
 }

 lock.disabled=false;
 lock.textContent=basicRatesUnlocked?"🔓":"🔒";
 lock.title=basicRatesUnlocked
  ?"Lock Category Basic Rates"
  :"Unlock Category Basic Rates";
}

$("basicLockToggle")?.addEventListener("click",()=>{
 if(!categoryHasCosts)return;

 if(!basicRatesUnlocked){
  const ok=confirm(
   "Update Category Basic Rates for future Arts?\n\nOld Products will remain unchanged."
  );
  if(!ok)return;
 }

 basicRatesUnlocked=!basicRatesUnlocked;

 document.querySelectorAll('[data-kind="basic"]').forEach(input=>{
  input.readOnly=!basicRatesUnlocked;
 });

 refreshBasicLockIcon();

 if(basicRatesUnlocked){
  document.querySelector('[data-kind="basic"]')?.focus();
 }
});

const form=$("artForm"),message=$("artMessage"),cards=$("artCards");

const say=(t,k="")=>{message.textContent=t||"";message.className=`rr-message ${k}`.trim()};
const money=v=>RR.money(Number(v||0));

const enableFastNumberInput=(root=document)=>{
 root.querySelectorAll('input[type="number"]').forEach(input=>{
  if(input.dataset.fastNumberReady==="1")return;
  input.dataset.fastNumberReady="1";

  input.addEventListener("focus",()=>{
   const value=String(input.value??"").trim();
   if(value==="0"||value==="0.0"||value==="0.00"){
    input.value="";
    input.dispatchEvent(new Event("input",{bubbles:true}));
   }else{
    setTimeout(()=>input.select?.(),0);
   }
  });

  input.addEventListener("blur",()=>{
   if(String(input.value??"").trim()===""){
    input.value="0";
    input.dispatchEvent(new Event("input",{bubbles:true}));
   }
  });
 });
};

const compactNumber=value=>{
 const n=Number(value||0);
 return Number.isFinite(n)?String(n):"0";
};

const normalizeNumberInputs=(root=document)=>{
 root.querySelectorAll('input[type="number"]').forEach(input=>{
  if(String(input.value??"").trim()!==""){
   input.value=compactNumber(input.value);
  }else{
   input.value="0";
  }
 });
};
const rowInput=(code,type)=>document.querySelector(`[data-process="${code}"][data-kind="${type}"]`);

function renderCostRows(basics={}){
 $("costRows").innerHTML=PROCESSES.map(p=>`
  <tr>
   <td>${p.name}</td>
   <td><input data-process="${p.code}" data-kind="basic" type="number" inputmode="decimal" step="0.01" min="0"
      value="${compactNumber(basics[p.code])}" ${categoryHasCosts&&!basicRatesUnlocked?"readonly":""}></td>
   <td><input data-process="${p.code}" data-kind="extra" type="number" inputmode="decimal" step="0.01" value="0"></td>
   <td><strong data-process="${p.code}" data-kind="total">${money(basics[p.code]||0)}</strong></td>
  </tr>`).join("");
 document.querySelectorAll('#costRows input').forEach(i=>i.addEventListener("input",updateCostTotals));
 normalizeNumberInputs($("costRows"));
 enableFastNumberInput($("costRows"));
 refreshBasicLockIcon();
 updateCostTotals();
}


function costRows(){
 return PROCESSES.map(p=>({
  process_code:p.code,process_name:p.name,sort_order:p.order,
  basic_rate:Number(rowInput(p.code,"basic")?.value||0),
  extra_rate:Number(rowInput(p.code,"extra")?.value||0)
 }));
}
function updateCostTotals(){
 let grand=0;
 for(const p of PROCESSES){
  const b=Number(rowInput(p.code,"basic")?.value||0),e=Number(rowInput(p.code,"extra")?.value||0),t=b+e;
  const out=document.querySelector(`[data-process="${p.code}"][data-kind="total"]`);
  if(out)out.textContent=money(t);grand+=t;
 }
 const margin=Number($("defaultMargin")?.value||0);
 $("makingTotal").textContent=money(grand);
 if($("finalProcessCost"))$("finalProcessCost").textContent=money(grand);
 if($("finalMargin"))$("finalMargin").textContent=money(margin);
 if($("finalArtCost"))$("finalArtCost").textContent=money(grand+margin);
}

async function loadCategories(selected=""){
 const r=await supabaseClient.from("rr_art_categories").select("*").eq("is_active",true).order("category_name");
 if(r.error)throw r.error;categories=r.data||[];
 $("artCategory").innerHTML='<option value="">Select category</option>'+categories.map(c=>`<option value="${c.id}">${RR.safeText(c.category_name)}</option>`).join("");
 if(selected)$("artCategory").value=selected;
}
async function loadCategoryCosts(id){
 if(!id){categoryHasCosts=false;basicRatesUnlocked=false;$("firstCategoryNotice").classList.add("rr-hidden");renderCostRows({});return}
 const r=await supabaseClient.rpc("rr_get_art_category_costs",{p_category_id:id});
 if(r.error)throw r.error;
 categoryHasCosts=(r.data||[]).length>0;
 basicRatesUnlocked=!categoryHasCosts;
 const basics={};(r.data||[]).forEach(x=>basics[x.process_code]=x.basic_rate);
 $("firstCategoryNotice").classList.toggle("rr-hidden",categoryHasCosts);
 renderCostRows(basics);
 const c=categories.find(x=>x.id===id);
 if(c?.default_design_name&&!$("itemName").value.trim())$("itemName").value=c.default_design_name;
}
$("artCategory").onchange=()=>loadCategoryCosts($("artCategory").value).catch(e=>say(e.message,"error"));
$("defaultMargin").addEventListener("input",updateCostTotals);

$("addCategoryBtn").onclick=()=>$("categoryDialog").classList.remove("rr-hidden");
$("cancelCategory").onclick=()=>$("categoryDialog").classList.add("rr-hidden");
$("categoryForm").onsubmit=async e=>{
 e.preventDefault();
 const r=await supabaseClient.rpc("rr_add_art_category",{p_category_name:$("newCategoryName").value,p_default_design_name:$("newDefaultDesignName").value||null});
 if(r.error){alert(r.error.message);return}
 $("categoryDialog").classList.add("rr-hidden");$("categoryForm").reset();await loadCategories(r.data.id);await loadCategoryCosts(r.data.id);
};

const artId=()=>$("artId").value;
const saved=()=>artId()?(mediaMap[String(artId())]||[]):[];
const allImages=()=>[
 ...saved().map(x=>({type:"saved",id:x.id,url:x.file_url,label:x.caption||x.file_name||"Saved artwork",media:x,isCover:!!x.is_cover})),
 ...queued.map(x=>({type:"new",id:x.tempId,url:x.url,label:x.file.name,file:x.file,sourceType:x.sourceType,isCover:selectedIcon?.type==="new"&&selectedIcon.id===x.tempId}))
];
const chosenIcon=()=>{const a=allImages();return a.find(x=>selectedIcon&&x.type===selectedIcon.type&&x.id===selectedIcon.id)||a.find(x=>x.isCover)||a[0]||null};

function renderImages(){
 const list=allImages(),ico=chosenIcon();
 $("selectedFiles").textContent=queued.length?`${queued.length} new artwork image(s) ready`:"No new images selected";
 $("iconStatus").innerHTML=ico?`<img src="${RR.safeText(ico.url)}"><div><small>ART ICON</small><strong>${RR.safeText(ico.label)}</strong></div>`:`<span class="art-icon-star">★</span><div><small>ART ICON</small><strong>No icon selected</strong></div>`;
 $("imagePreview").innerHTML=list.map(x=>{
  const is=ico&&x.type===ico.type&&x.id===ico.id;
  return `<figure class="art-media-item ${is?"is-icon":""}" data-type="${x.type}" data-id="${x.id}">
   <div class="art-media-thumb"><img src="${RR.safeText(x.url)}">${is?'<span class="art-icon-badge">★ ART ICON</span>':""}<span class="art-longpress-hint">Hold</span></div>
   <figcaption>${RR.safeText(x.label)}</figcaption></figure>`;
 }).join("");
 list.forEach(x=>bindHold(document.querySelector(`[data-type="${x.type}"][data-id="${CSS.escape(String(x.id))}"]`),x));
}
function bindHold(el,image){
 if(!el)return;let timer,long=false;
 const stop=()=>clearTimeout(timer);
 el.onpointerdown=()=>{long=false;timer=setTimeout(()=>{long=true;activeImage=image;$("actionImageLabel").textContent=image.label;$("imageActionSheet").classList.remove("rr-hidden");navigator.vibrate?.(30)},650)};
 el.onpointerup=stop;el.onpointerleave=stop;el.onpointercancel=stop;
 el.onclick=e=>{if(long){e.preventDefault();long=false}else openViewer(image)};
}
function updateFiles(){
 queued.forEach(x=>URL.revokeObjectURL(x.url));queued=[];
 for(const input of [$("cameraFiles"),$("galleryFiles")]){
  const sourceType=input.id==="cameraFiles"?"camera":"gallery";
  Array.from(input.files||[]).forEach(file=>queued.push({tempId:crypto.randomUUID(),file,sourceType,url:URL.createObjectURL(file)}));
 }
 if(!selectedIcon&&queued[0])selectedIcon={type:"new",id:queued[0].tempId};renderImages();
}
$("cameraFiles").onchange=updateFiles;$("galleryFiles").onchange=updateFiles;
const closeActions=()=>{$("imageActionSheet").classList.add("rr-hidden");activeImage=null};
$("actionCancel").onclick=closeActions;
$("actionView").onclick=()=>{const x=activeImage;closeActions();if(x)openViewer(x)};
$("actionSetIcon").onclick=async()=>{
 const x=activeImage;closeActions();if(!x)return;
 try{
  selectedIcon={type:x.type,id:x.id};
  renderImages();
  if(x.type==="saved")await setSavedIcon(x.id);
  say("Art Icon updated.","success");
 }catch(e){say(e.message||"Icon could not be updated.","error")}
};
$("actionRemove").onclick=async()=>{
 const x=activeImage;closeActions();if(!x)return;
 const current=chosenIcon()&&chosenIcon().type===x.type&&chosenIcon().id===x.id;
 if(current&&allImages().length>1){alert("Set another image as Art Icon first.");return}
 if(!confirm(`Remove "${x.label}"?`))return;
 if(x.type==="new"){const q=queued.find(y=>y.tempId===x.id);if(q)URL.revokeObjectURL(q.url);queued=queued.filter(y=>y.tempId!==x.id)}
 else{if(x.media.storage_path){const s=await supabaseClient.storage.from("redzed-media").remove([x.media.storage_path]);if(s.error)throw s.error}const d=await supabaseClient.from("rr_media").delete().eq("id",x.id);if(d.error)throw d.error;mediaMap[String(artId())]=saved().filter(y=>y.id!==x.id)}
 if(current)selectedIcon=null;renderImages();
};
async function setSavedIcon(id){
 const a=artId();if(!a)return;
 let r=await supabaseClient.from("rr_media").update({is_cover:false}).eq("entity_type","art").eq("entity_id",a);if(r.error)throw r.error;
 r=await supabaseClient.from("rr_media").update({is_cover:true}).eq("id",id);if(r.error)throw r.error;
}

async function loadData(){
 const reloadBtn=$("reloadArts");
 if(reloadBtn){reloadBtn.disabled=true;reloadBtn.textContent="Loading...";}
 const [a,s,m]=await Promise.all([
  supabaseClient.from("rr_art_master").select("*").order("created_at",{ascending:false}),
  supabaseClient.from("rr_art_process_cost_summary").select("*"),
  RR.getMediaMap("art","reference")
 ]);
 if(a.error)throw a.error;
 if(s.error)throw s.error;
 arts=a.data||[];
 summaries=s.data||[];
 mediaMap=m||{};
 renderCards();
 if(reloadBtn){reloadBtn.disabled=false;reloadBtn.textContent="Refresh";}
}
const sum=id=>summaries.find(x=>String(x.art_id)===String(id))||{};
function renderCards(){
 cards.innerHTML=arts.length?arts.map(a=>{const imgs=mediaMap[String(a.id)]||[],ico=imgs.find(x=>x.is_cover)||imgs[0],s=sum(a.id),items=Array.isArray(a.caption_items)?a.caption_items:[];
 return `<article class="art-master-card"><button class="art-card-image" data-view="${a.id}">${ico?`<img src="${RR.safeText(ico.file_url)}"><span class="art-card-icon-badge">★ ICON</span>`:'<div class="art-placeholder">ART</div>'}</button><div class="art-card-body"><small>${RR.safeText(s.category_name||a.category||"")}</small><h3>${RR.safeText(a.art_no)} · ${RR.safeText(a.item_name||a.product_name||"")}</h3><div class="art-feature-badges">${items.slice(0,3).map(i=>`<span>${RR.safeText(i.text)}</span>`).join("")}</div><div class="art-card-metrics"><span><small>Process Cost</small><b>${money(s.total_process_cost)}</b></span><span><small>Other Margin</small><b>${money(a.default_margin)}</b></span></div><button class="rr-btn rr-btn-secondary" data-edit="${a.id}">Edit</button></div></article>`}).join(""):"<p>No Art saved yet.</p>";
 cards.querySelectorAll("[data-edit]").forEach(b=>b.onclick=()=>editArt(b.dataset.edit));cards.querySelectorAll("[data-view]").forEach(b=>b.onclick=()=>openSavedViewer(b.dataset.view));
}
async function editArt(id){
 const a=arts.find(x=>String(x.id)===String(id));if(!a)return;
 $("artId").value=a.id;$("artNo").value=a.art_no||"";$("itemName").value=a.item_name||a.product_name||"";$("defaultMargin").value=a.default_margin??22;$("designNotes").value=a.other_material_note||"";
 await loadCategories(a.art_category_id||"");
 const r=await supabaseClient.from("rr_art_process_costs").select("*").eq("art_id",id).order("sort_order");
 if(r.error)throw r.error;categoryHasCosts=true;basicRatesUnlocked=false;$("firstCategoryNotice").classList.add("rr-hidden");
 const basics={};(r.data||[]).forEach(x=>basics[x.process_code]=x.basic_rate);renderCostRows(basics);(r.data||[]).forEach(x=>{const i=rowInput(x.process_code,"extra");if(i)i.value=x.extra_rate});updateCostTotals();
 queued=[];const cover=saved().find(x=>x.is_cover)||saved()[0];selectedIcon=cover?{type:"saved",id:cover.id}:null;renderImages();
 await builder.load(Array.isArray(a.caption_items)?a.caption_items:[]);
 $("formTitle").textContent=`Edit ${a.art_no}`;$("saveArtBtn").textContent="Update Art";$("cancelEdit").classList.remove("rr-hidden");scrollTo({top:0,behavior:"smooth"});
}
function reset(){
 form.reset();$("artId").value="";$("defaultMargin").value=22;queued=[];selectedIcon=null;$("imagePreview").innerHTML="";$("iconStatus").innerHTML='<span class="art-icon-star">★</span><div><small>ART ICON</small><strong>No icon selected</strong></div>';$("formTitle").textContent="Add New Art";$("saveArtBtn").textContent="Save Art";$("cancelEdit").classList.add("rr-hidden");builder?.load();categoryHasCosts=false;basicRatesUnlocked=false;renderCostRows({});updateCostTotals();
}
$("cancelEdit").onclick=reset;
$("reloadArts").onclick=()=>loadData().catch(e=>{say(e.message||"Could not refresh Arts","error");$("reloadArts").disabled=false;$("reloadArts").textContent="Refresh";});


async function updateCategoryBasicDefaults(categoryId){
 const rows=costRows();

 const { error: deleteError } = await supabaseClient
  .from("rr_art_category_costs")
  .delete()
  .eq("category_id",categoryId);

 if(deleteError)throw deleteError;

 const payload=rows.map(row=>({
  category_id:categoryId,
  process_code:row.process_code,
  process_name:row.process_name,
  basic_rate:row.basic_rate,
  sort_order:row.sort_order
 }));

 const { error } = await supabaseClient
  .from("rr_art_category_costs")
  .insert(payload);

 if(error)throw error;
}

form.onsubmit=async e=>{
 e.preventDefault();const btn=$("saveArtBtn");btn.disabled=true;btn.textContent="Saving...";say("");
 try{
  const categoryId=$("artCategory").value;
  if(!categoryId)throw new Error("Select Art Category");

  const enteredArtNo=$("artNo").value.trim().toUpperCase();
  if(!enteredArtNo)throw new Error("Enter Art No");

  if(!artId() && allImages().length===0){
   throw new Error("Select at least one Artwork image");
  }

  const duplicate=arts.find(a=>
   String(a.art_no||"").trim().toUpperCase()===enteredArtNo &&
   String(a.id)!==String(artId()||"")
  );
  if(duplicate)throw new Error(`Art No ${enteredArtNo} already exists`);
  const cols=await RR.getTableColumns("rr_art_master"),existing=artId();
  const category=categories.find(x=>x.id===categoryId);
  const payload=RR.filterPayload({art_no:enteredArtNo,art_category_id:categoryId,category:category?.category_name,item_name:$("itemName").value.trim(),product_name:$("itemName").value.trim(),description:$("description").value.trim(),other_material_note:$("designNotes").value.trim(),default_margin:RR.number($("defaultMargin").value),is_active:true},cols);
  const r=existing?await supabaseClient.from("rr_art_master").update(payload).eq("id",existing).select().single():await supabaseClient.from("rr_art_master").insert(payload).select().single();if(r.error)throw r.error;
  if(basicRatesUnlocked&&categoryHasCosts){
   await updateCategoryBasicDefaults(categoryId);
  }
  let x=await supabaseClient.rpc("rr_save_art_process_costs",{p_art_id:r.data.id,p_category_id:categoryId,p_rows:costRows()});if(x.error)throw x.error;
  x=await supabaseClient.rpc("rr_save_art_captions",{p_art_id:r.data.id,p_items:builder.getItems()});if(x.error)throw x.error;
  const uploaded=[];for(const q of queued){const media=await RR.uploadMedia({file:q.file,entityType:"art",entityId:r.data.id,mediaCategory:"reference",sourceType:q.sourceType,visibilityScope:"factory",caption:`${r.data.art_no} artwork`});uploaded.push({tempId:q.tempId,media})}
  let iconId=selectedIcon?.type==="saved"?selectedIcon.id:uploaded.find(u=>u.tempId===selectedIcon?.id)?.media?.id;if(iconId){await supabaseClient.from("rr_media").update({is_cover:false}).eq("entity_type","art").eq("entity_id",r.data.id);await supabaseClient.from("rr_media").update({is_cover:true}).eq("id",iconId)}
  say("Art saved successfully.","success");basicRatesUnlocked=false;refreshBasicLockIcon();reset();await loadData();
 }catch(err){console.error(err);say(err.message||"Art could not be saved.","error")}finally{btn.disabled=false;btn.textContent=artId()?"Update Art":"Save Art"}
};

// Viewer
let viewer=[],index=0,zoom=1;
function draw(){const x=viewer[index];$("viewerImage").src=x?.file_url||x?.url||"";$("viewerImage").style.transform=`scale(${zoom})`}
function openViewer(image){viewer=allImages();index=Math.max(0,viewer.findIndex(x=>x.id===image.id));zoom=1;$("viewerTitle").textContent=$("artNo").value||"Artwork";$("viewerText").textContent=$("description").value||$("designNotes").value||"";$("mediaViewer").classList.remove("rr-hidden");draw()}
function openSavedViewer(id){const a=arts.find(x=>String(x.id)===String(id));viewer=mediaMap[String(id)]||[];if(!viewer.length)return;index=0;zoom=1;$("viewerTitle").textContent=`${a.art_no} · ${a.item_name||a.product_name||""}`;$("viewerText").textContent=a.caption_text||a.description||"";$("mediaViewer").classList.remove("rr-hidden");draw()}
$("viewerClose").onclick=()=>$("mediaViewer").classList.add("rr-hidden");$("viewerZoomIn").onclick=()=>{zoom=Math.min(4,zoom+.25);draw()};$("viewerZoomOut").onclick=()=>{zoom=Math.max(.5,zoom-.25);draw()};$("viewerReset").onclick=()=>{zoom=1;draw()};$("viewerPrev").onclick=()=>{index=(index-1+viewer.length)%viewer.length;zoom=1;draw()};$("viewerNext").onclick=()=>{index=(index+1)%viewer.length;zoom=1;draw()};

(async()=>{try{await RR.requireOwner();builder=new RRCaptionBuilder({masterType:"art",categoryInput:$("artCategory"),container:$("artCaptionBuilder"),outputInput:$("description")});await loadCategories();renderCostRows({});normalizeNumberInputs(document);enableFastNumberInput(document);await builder.load();await loadData()}catch(e){console.error(e);say(e.message||"Art Master could not open.","error")}})();
})();
                    
