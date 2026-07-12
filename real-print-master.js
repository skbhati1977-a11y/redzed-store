(() => {
"use strict";
const $=id=>document.getElementById(id);
let prints=[],mediaMap={},queued=[],selectedIcon=null,activeImage=null;
const form=$("printForm"),message=$("printMessage"),cards=$("printCards");

const say=(text,type="")=>{message.textContent=text||"";message.className=`rr-message ${type}`.trim()};
const compactNumber=value=>{const n=Number(value||0);return Number.isFinite(n)?String(n):"0"};

const statusMeta=status=>{
 const key=String(status||"active").toLowerCase();
 return {
  active:{label:"Active",className:"status-active"},
  remaking:{label:"Remaking",className:"status-remaking"},
  available:{label:"Available",className:"status-available"},
  retired:{label:"Retired",className:"status-retired"}
 }[key]||{label:key,className:"status-available"};
};

const enableFastNumberInput=(root=document)=>{
 root.querySelectorAll('input[type="number"]').forEach(input=>{
  if(input.dataset.fastNumberReady==="1")return;
  input.dataset.fastNumberReady="1";
  input.addEventListener("focus",()=>{
   const v=String(input.value??"").trim();
   if(["0","0.0","0.00"].includes(v))input.value="";
   else setTimeout(()=>input.select?.(),0);
  });
  input.addEventListener("blur",()=>{
   input.value=String(input.value??"").trim()===""?"0":compactNumber(input.value);
  });
 });
};

const printId=()=>$("printId").value;
const savedImages=()=>printId()?(mediaMap[String(printId())]||[]):[];
const allImages=()=>[
 ...savedImages().map(x=>({type:"saved",id:x.id,url:x.file_url,label:x.caption||x.file_name||"Saved image",media:x,isCover:!!x.is_cover})),
 ...queued.map(x=>({type:"new",id:x.tempId,url:x.url,label:x.file.name,file:x.file,sourceType:x.sourceType,isCover:selectedIcon?.type==="new"&&selectedIcon.id===x.tempId}))
];
const currentIcon=()=>{const list=allImages();return list.find(x=>selectedIcon&&x.type===selectedIcon.type&&x.id===selectedIcon.id)||list.find(x=>x.isCover)||list[0]||null};

function bindLongPress(el,item){
 if(!el)return;let timer,long=false;
 const stop=()=>clearTimeout(timer);
 el.onpointerdown=()=>{long=false;timer=setTimeout(()=>{long=true;activeImage=item;$("actionImageLabel").textContent=item.label;$("imageActionSheet").classList.remove("rr-hidden");navigator.vibrate?.(30)},650)};
 el.onpointerup=stop;el.onpointerleave=stop;el.onpointercancel=stop;
 el.onclick=e=>{if(long){e.preventDefault();long=false}else openViewer(item)};
}

function renderImages(){
 const list=allImages(),icon=currentIcon();
 $("selectedFiles").textContent=queued.length?`${queued.length} new image(s) ready`:"No new images selected";
 $("iconStatus").innerHTML=icon?`<img src="${RR.safeText(icon.url)}"><div><small>PRINT ICON</small><strong>${RR.safeText(icon.label)}</strong></div>`:`<span class="print-icon-star">★</span><div><small>PRINT ICON</small><strong>No icon selected</strong></div>`;
 $("imagePreview").innerHTML=list.map(item=>{
  const isIcon=icon&&item.type===icon.type&&item.id===icon.id;
  return `<figure class="print-media-item ${isIcon?"is-icon":""}" data-type="${item.type}" data-id="${RR.safeText(item.id)}"><div class="print-media-thumb"><img src="${RR.safeText(item.url)}">${isIcon?'<span class="print-icon-badge">★ PRINT ICON</span>':""}<span class="print-hold-hint">Hold</span></div><figcaption>${RR.safeText(item.label)}</figcaption></figure>`;
 }).join("");
 list.forEach(item=>bindLongPress($("imagePreview").querySelector(`[data-type="${item.type}"][data-id="${CSS.escape(String(item.id))}"]`),item));
}

function updateFiles(){
 queued.forEach(x=>URL.revokeObjectURL(x.url));queued=[];
 for(const input of [$("cameraFiles"),$("galleryFiles")]){
  const sourceType=input.id==="cameraFiles"?"camera":"gallery";
  Array.from(input.files||[]).forEach(file=>queued.push({tempId:crypto.randomUUID(),file,sourceType,url:URL.createObjectURL(file)}));
 }
 if(!selectedIcon&&queued[0])selectedIcon={type:"new",id:queued[0].tempId};
 renderImages();
}
$("cameraFiles").onchange=updateFiles;$("galleryFiles").onchange=updateFiles;

const closeActions=()=>{$("imageActionSheet").classList.add("rr-hidden");activeImage=null};
$("actionCancel").onclick=closeActions;
$("actionView").onclick=()=>{const x=activeImage;closeActions();if(x)openViewer(x)};
$("actionSetIcon").onclick=async()=>{const x=activeImage;closeActions();if(!x)return;selectedIcon={type:x.type,id:x.id};renderImages();if(x.type==="saved")await setSavedIcon(x.id);say("Print Icon updated.","success")};
$("actionRemove").onclick=async()=>{
 const x=activeImage;closeActions();if(!x)return;
 const icon=currentIcon(),isCurrent=icon&&icon.type===x.type&&icon.id===x.id;
 if(isCurrent&&allImages().length>1){alert("Set another image as Print Icon first.");return}
 if(!confirm(`Remove "${x.label}"?`))return;
 if(x.type==="new"){const q=queued.find(y=>y.tempId===x.id);if(q)URL.revokeObjectURL(q.url);queued=queued.filter(y=>y.tempId!==x.id)}
 else{if(x.media.storage_path)await supabaseClient.storage.from("redzed-media").remove([x.media.storage_path]);await supabaseClient.from("rr_media").delete().eq("id",x.id);mediaMap[String(printId())]=savedImages().filter(y=>y.id!==x.id)}
 if(isCurrent)selectedIcon=null;renderImages();
};

async function setSavedIcon(id){
 const pid=printId();if(!pid)return;
 await supabaseClient.from("rr_media").update({is_cover:false}).eq("entity_type","printing").eq("entity_id",pid);
 await supabaseClient.from("rr_media").update({is_cover:true}).eq("id",id);
}

function frameRow(data={}){
 const row=document.createElement("div");
 row.className="print-frame-row";
 row.innerHTML=`<input class="frame-no" placeholder="Frame No" value="${RR.safeText(data.frame_no||"")}"><select class="frame-status"><option value="active">Active</option><option value="remaking">Remaking</option><option value="retired">Retired</option><option value="available">Available</option></select><input class="frame-note" placeholder="Optional note" value="${RR.safeText(data.note||"")}"><button class="frame-remove" type="button">×</button>`;
 const statusSelect=row.querySelector(".frame-status");
 statusSelect.value=data.frame_status||"active";

 const paintStatus=()=>{
  row.classList.remove("status-active-row","status-remaking-row","status-available-row","status-retired-row");
  row.classList.add(`status-${statusSelect.value}-row`);
 };
 statusSelect.addEventListener("change",paintStatus);
 paintStatus();

 row.querySelector(".frame-remove").onclick=()=>row.remove();
 return row;
}
const addFrame=data=>$("frameRows").appendChild(frameRow(data));
$("addFrameBtn").onclick=()=>addFrame();

function getFrameRows(){
 return [...$("frameRows").querySelectorAll(".print-frame-row")].map((row,index)=>({
  frame_no:row.querySelector(".frame-no").value.trim().toUpperCase(),
  frame_status:row.querySelector(".frame-status").value,
  colour_order:index+1,
  note:row.querySelector(".frame-note").value.trim()
 })).filter(x=>x.frame_no);
}

async function loadData(){
 const btn=$("reloadPrints");
 btn.disabled=true;
 btn.textContent="Loading...";
 try{
  const [p,m]=await Promise.all([
   supabaseClient.from("rr_print_library_view").select("*").order("updated_at",{ascending:false}),
   RR.getMediaMap("printing","print")
  ]);
  if(p.error)throw p.error;
  prints=p.data||[];
  mediaMap=m||{};
  renderCards();
 }finally{
  btn.disabled=false;
  btn.textContent="Refresh";
 }
}

function renderCards(){
 const q=$("printSearch").value.trim().toLowerCase();
 const list=prints.filter(p=>`${p.print_no} ${p.print_name} ${p.short_note||""} ${(p.frames||[]).map(f=>`${f.frame_no} ${f.frame_status}`).join(" ")}`.toLowerCase().includes(q));
 cards.innerHTML=list.length?list.map(p=>{
  const imgs=mediaMap[String(p.id)]||[],icon=imgs.find(x=>x.is_cover)||imgs[0];
  return `<article class="print-master-card"><button class="print-card-image" data-view="${p.id}">${icon?`<img src="${RR.safeText(icon.file_url)}"><span class="print-card-icon-badge">★ ICON</span>`:'<div class="print-placeholder">PRINT</div>'}</button><div class="print-card-body"><small>${compactNumber(p.design_colours)} Colour${Number(p.design_colours)===1?"":"s"}</small><h3>${RR.safeText(p.print_no)} · ${RR.safeText(p.print_name||"")}</h3><div class="print-card-summary">
        <span class="print-count-badge">🎨 ${compactNumber(p.design_colours)} Colour${Number(p.design_colours)===1?"":"s"}</span>
        <span class="print-count-badge">🖼 ${(p.frames||[]).length} Frame${(p.frames||[]).length===1?"":"s"}</span>
       </div>
       <div class="print-frame-badges">${(p.frames||[]).map(f=>{
        const meta=statusMeta(f.frame_status);
        return `<span class="${meta.className}">${RR.safeText(f.frame_no)} · ${meta.label}</span>`;
       }).join("")}</div>
       <p>${RR.safeText(p.short_note||"")}</p><button class="rr-btn rr-btn-secondary" data-edit="${p.id}">Edit</button></div></article>`;
 }).join(""):"<p>No Print found.</p>";
 cards.querySelectorAll("[data-edit]").forEach(b=>b.onclick=()=>editPrint(b.dataset.edit));
 cards.querySelectorAll("[data-view]").forEach(b=>b.onclick=()=>openSavedViewer(b.dataset.view));
}
$("printSearch").oninput=renderCards;$("reloadPrints").onclick=()=>loadData().catch(e=>say(e.message,"error"));

async function editPrint(id){
 const p=prints.find(x=>String(x.id)===String(id));if(!p)return;
 $("printId").value=p.id;$("printNo").value=p.print_no||"";$("printName").value=p.print_name||"";$("designColours").value=compactNumber(p.design_colours||1);$("shortNote").value=p.short_note||"";
 $("frameRows").innerHTML="";(p.frames||[]).forEach(addFrame);
 queued.forEach(x=>URL.revokeObjectURL(x.url));queued=[];$("cameraFiles").value="";$("galleryFiles").value="";
 const icon=(mediaMap[String(id)]||[]).find(x=>x.is_cover)||(mediaMap[String(id)]||[])[0];
 selectedIcon=icon?{type:"saved",id:icon.id}:null;renderImages();
 $("formTitle").textContent=`Edit ${p.print_no}`;$("savePrintBtn").textContent="Update Print";$("cancelEdit").classList.remove("rr-hidden");scrollTo({top:0,behavior:"smooth"});
}

function resetForm(){
 form.reset();$("printId").value="";$("designColours").value="1";$("frameRows").innerHTML="";addFrame();
 queued.forEach(x=>URL.revokeObjectURL(x.url));queued=[];selectedIcon=null;$("cameraFiles").value="";$("galleryFiles").value="";renderImages();
 $("formTitle").textContent="Add New Print";$("savePrintBtn").textContent="Save Print";$("cancelEdit").classList.add("rr-hidden");say("");
}
$("cancelEdit").onclick=resetForm;


async function getFrameTransferConflicts(frames,currentPrintId){
 const frameNos=frames.map(x=>x.frame_no).filter(Boolean);
 if(!frameNos.length)return [];

 const {data:frameRows,error:frameError}=await supabaseClient
  .from("rr_print_frames")
  .select("frame_no,print_id,frame_status")
  .in("frame_no",frameNos);

 if(frameError)throw frameError;

 const conflicts=(frameRows||[]).filter(row=>
  row.print_id &&
  String(row.print_id)!==String(currentPrintId||"")
 );

 if(!conflicts.length)return [];

 const printIds=[...new Set(conflicts.map(x=>x.print_id))];

 const {data:printRows,error:printError}=await supabaseClient
  .from("rr_print_master")
  .select("id,print_no,print_name")
  .in("id",printIds);

 if(printError)throw printError;

 const printMap=Object.fromEntries(
  (printRows||[]).map(p=>[String(p.id),p])
 );

 return conflicts.map(row=>({
  ...row,
  oldPrint:printMap[String(row.print_id)]||{}
 }));
}

async function confirmFrameReassignments(frames,currentPrintId,newPrintNo){
 const conflicts=await getFrameTransferConflicts(frames,currentPrintId);
 if(!conflicts.length)return false;

 const details=conflicts.map(row=>{
  const oldNo=row.oldPrint.print_no||"another Print";
  const oldName=row.oldPrint.print_name?` · ${row.oldPrint.print_name}`:"";
  return `Frame ${row.frame_no} is already assigned to ${oldNo}${oldName}`;
 }).join("
");

 const ok=confirm(
  `DUPLICATE FRAME WARNING

${details}

` +
  `Transfer this Frame to ${newPrintNo}?

` +
  `Yes = remove from old Print and assign here
` +
  `Cancel = do not save`
 );

 if(!ok)throw new Error("Frame transfer cancelled. Nothing was changed.");

 return true;
}

form.onsubmit=async e=>{
 e.preventDefault();const btn=$("savePrintBtn");btn.disabled=true;btn.textContent="Saving...";say("");
 try{
  const no=$("printNo").value.trim().toUpperCase(),name=$("printName").value.trim(),colours=Math.max(1,Number($("designColours").value||1)),id=printId();
  if(!no)throw new Error("Enter Print No");if(!name)throw new Error("Enter Print Name");if(!id&&allImages().length===0)throw new Error("Select at least one Print image");
  if(prints.some(p=>String(p.print_no||"").trim().toUpperCase()===no&&String(p.id)!==String(id||"")))throw new Error(`Print No ${no} already exists`);
  const frames=getFrameRows();if(frames.length!==colours)throw new Error(`Design has ${colours} colour(s), so enter exactly ${colours} Frame No(s)`);
  const dup=frames.map(x=>x.frame_no).find((x,i,a)=>a.indexOf(x)!==i);if(dup)throw new Error(`Duplicate Frame No: ${dup}`);
  const allowFrameTransfer=await confirmFrameReassignments(frames,id,no);

  const payload={print_no:no,print_name:name,design_colours:colours,short_note:$("shortNote").value.trim(),is_active:true};
  const r=id?await supabaseClient.from("rr_print_master").update(payload).eq("id",id).select().single():await supabaseClient.from("rr_print_master").insert(payload).select().single();if(r.error)throw r.error;
  const fr=await supabaseClient.rpc("rr_save_print_frames",{
   p_print_id:r.data.id,
   p_rows:frames,
   p_allow_reassign:allowFrameTransfer
  });
  if(fr.error){
   const msg=String(fr.error.message||"");
   if(msg.includes("FRAME_TRANSFER_REQUIRED")){
    const parts=msg.split("|");
    throw new Error(
     `Frame ${parts[1]||""} is already assigned to ${parts[2]||"another Print"}. ` +
     `Transfer confirmation is required.`
    );
   }
   throw fr.error;
  }
  const uploaded=[];for(const item of queued){const media=await RR.uploadMedia({file:item.file,entityType:"printing",entityId:r.data.id,mediaCategory:"print",sourceType:item.sourceType,visibilityScope:"factory",caption:`${r.data.print_no} print image`});uploaded.push({tempId:item.tempId,media})}
  const iconId=selectedIcon?.type==="saved"?selectedIcon.id:uploaded.find(x=>x.tempId===selectedIcon?.id)?.media?.id;
  if(iconId){await supabaseClient.from("rr_media").update({is_cover:false}).eq("entity_type","printing").eq("entity_id",r.data.id);await supabaseClient.from("rr_media").update({is_cover:true}).eq("id",iconId)}
  say("Print saved successfully.","success");resetForm();await loadData();
 }catch(err){console.error(err);say(err.message||"Print could not be saved.","error")}finally{btn.disabled=false;btn.textContent=printId()?"Update Print":"Save Print"}
};

let viewer=[],viewerIndex=0,zoom=1;
const draw=()=>{const x=viewer[viewerIndex];$("viewerImage").src=x?.file_url||x?.url||"";$("viewerImage").style.transform=`scale(${zoom})`};
function openViewer(item){viewer=allImages();viewerIndex=Math.max(0,viewer.findIndex(x=>x.id===item.id));zoom=1;$("viewerTitle").textContent=`${$("printNo").value||"New Print"} · ${$("printName").value||""}`;$("viewerText").textContent=$("shortNote").value||"";$("mediaViewer").classList.remove("rr-hidden");draw()}
function openSavedViewer(id){const p=prints.find(x=>String(x.id)===String(id));viewer=mediaMap[String(id)]||[];if(!viewer.length)return;viewerIndex=0;zoom=1;$("viewerTitle").textContent=`${p.print_no} · ${p.print_name||""}`;$("viewerText").textContent=p.short_note||"";$("mediaViewer").classList.remove("rr-hidden");draw()}
$("viewerClose").onclick=()=>$("mediaViewer").classList.add("rr-hidden");$("viewerZoomIn").onclick=()=>{zoom=Math.min(4,zoom+.25);draw()};$("viewerZoomOut").onclick=()=>{zoom=Math.max(.5,zoom-.25);draw()};$("viewerReset").onclick=()=>{zoom=1;draw()};$("viewerPrev").onclick=()=>{viewerIndex=(viewerIndex-1+viewer.length)%viewer.length;zoom=1;draw()};$("viewerNext").onclick=()=>{viewerIndex=(viewerIndex+1)%viewer.length;zoom=1;draw()};

(async()=>{try{await RR.requireOwner();enableFastNumberInput(document);resetForm();await loadData()}catch(e){console.error(e);say(e.message||"Print Master could not open.","error")}})();
})();
