(() => {
"use strict"; const $=id=>document.getElementById(id);
const form=$("printForm"),cards=$("printCards"),message=$("printMessage"),inputs=[$("printCamera"),$("printGallery")];
let rows=[],mediaMap={},builder,queued=[];
const safe=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
const money=v=>new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:2}).format(Number(v||0));
const msg=(t,k="")=>{message.textContent=t||"";message.className=`rr-message ${k}`.trim()};
function alpha(n){let s="";while(n>0){n--;s=String.fromCharCode(65+n%26)+s;n=Math.floor(n/26)}return s}
function frames(){const b=$("frameBase").value.trim().toUpperCase()||"FRAME",n=Math.max(1,+$("colours").value||1);return Array.from({length:n},(_,i)=>b+alpha(i+1))}
function auto(){const n=Math.max(1,+$("colours").value||1),r=Math.max(0,+$("ratePerColour").value||0);$("printCost").value=money(n*r);$("frameSummary").textContent=frames().join(" · ")}
["frameBase","colours","ratePerColour"].forEach(id=>$(id).addEventListener("input",auto));
function queuedPreview(){queued=inputs.flatMap(x=>Array.from(x.files||[]));$("printImagePreview").innerHTML=queued.map((f,i)=>`<figure class="rz-media-item"><img src="${URL.createObjectURL(f)}"><figcaption>${i===0?"Icon / Cover":`Print Image ${i+1}`}</figcaption></figure>`).join("")}
inputs.forEach(x=>x.addEventListener("change",queuedPreview));
async function load(){
 const [r,m]=await Promise.all([supabaseClient.from("rr_print_master").select("*").order("updated_at",{ascending:false}),RR.getMediaMap("printing","print")]);
 if(r.error)throw r.error;rows=r.data||[];mediaMap=m||{};render();
}
function render(){
 const q=$("searchInput").value.trim().toLowerCase(),list=rows.filter(x=>`${x.print_no} ${x.print_name} ${x.placement} ${x.print_type}`.toLowerCase().includes(q));
 cards.innerHTML=list.length?list.map(x=>{const imgs=mediaMap[String(x.id)]||[],url=imgs[0]?.file_url||x.artwork_url||"";
 return `<article class="prm-card"><button class="prm-card-image" data-view="${safe(x.id)}">${url?`<img src="${safe(url)}">`:`<div class="prm-placeholder">PRINT</div>`}<span class="prm-card-badge">${x.colours} colour${+x.colours===1?"":"s"}</span></button><div class="prm-card-body"><span class="prm-card-code">${safe(x.print_no)}</span><h3>${safe(x.print_name)}</h3><div class="prm-frame-list">${(x.frame_labels||[]).map(f=>`<i>${safe(f)}</i>`).join("")}</div><div class="prm-meta"><span>${safe(x.placement)}</span><b>${money(x.print_cost)}</b></div><p>${safe(x.caption_text||x.notes||"")}</p><button class="rr-btn rr-btn-secondary" data-edit="${safe(x.id)}">Edit</button></div></article>`}).join(""):"<p>No Print saved yet.</p>";
 cards.querySelectorAll("[data-edit]").forEach(b=>b.onclick=()=>edit(b.dataset.edit));
 cards.querySelectorAll("[data-view]").forEach(b=>b.onclick=()=>openViewer(b.dataset.view));
}
async function edit(id){const x=rows.find(r=>String(r.id)===String(id));if(!x)return;reset();$("printId").value=x.id;$("printNo").value=x.print_no;$("printName").value=x.print_name;$("frameBase").value=x.frame_base;$("colours").value=x.colours;$("placement").value=x.placement;$("printType").value=x.print_type;$("ratePerColour").value=x.rate_per_colour;$("notes").value=x.notes||"";$("editorTitle").textContent=`Edit ${x.print_no}`;$("savePrintBtn").textContent="Update Print";await builder.load(Array.isArray(x.caption_items)?x.caption_items:[]);const imgs=mediaMap[String(x.id)]||[];$("printImagePreview").innerHTML=imgs.map((m,i)=>`<figure class="rz-media-item"><img src="${safe(m.file_url)}"><figcaption>${i===0?"Icon / Cover":`Print Image ${i+1}`}</figcaption></figure>`).join("");auto();$("printEditor").classList.remove("prm-hidden");scrollTo({top:0,behavior:"smooth"})}
function reset(){form.reset();$("printId").value="";$("colours").value=1;$("ratePerColour").value=5;$("editorTitle").textContent="Add Print";$("savePrintBtn").textContent="Save Print";queued=[];$("printImagePreview").innerHTML="";if(builder)builder.load([]);auto();msg("")}
async function upload(file,id,sourceType){await RR.uploadMedia({file,entityType:"printing",entityId:id,mediaCategory:"print",sourceType,visibilityScope:"factory",caption:`${$("printNo").value.trim().toUpperCase()} print image`})}
form.addEventListener("submit",async e=>{e.preventDefault();const btn=$("savePrintBtn");btn.disabled=true;btn.textContent="Saving...";try{const id=$("printId").value,no=$("printNo").value.trim().toUpperCase();let q=supabaseClient.from("rr_print_master").select("id").eq("print_no",no).limit(1);if(id)q=q.neq("id",id);const chk=await q;if(chk.error)throw chk.error;if((chk.data||[]).length)throw new Error(`Print No "${no}" already exists.`);
const payload={print_no:no,print_name:$("printName").value.trim(),frame_base:$("frameBase").value.trim().toUpperCase(),colours:Math.max(1,+$("colours").value||1),placement:$("placement").value,print_type:$("printType").value,rate_per_colour:Math.max(0,+$("ratePerColour").value||0),notes:$("notes").value.trim(),is_active:true};
const r=id?await supabaseClient.from("rr_print_master").update(payload).eq("id",id).select().single():await supabaseClient.from("rr_print_master").insert(payload).select().single();if(r.error)throw r.error;
await supabaseClient.rpc("rr_save_print_captions",{p_print_id:r.data.id,p_items:builder.getItems()});
for(const input of inputs){const source=input.id==="printCamera"?"camera":"gallery";for(const f of Array.from(input.files||[]))await upload(f,r.data.id,source)}
msg("Print saved successfully.","success");reset();$("printEditor").classList.add("prm-hidden");await load()}catch(e){console.error(e);msg(e.message||"Print could not be saved.","error")}finally{btn.disabled=false;btn.textContent=$("printId").value?"Update Print":"Save Print"}});
$("newPrintBtn").onclick=()=>{reset();$("printEditor").classList.remove("prm-hidden")};$("closeEditorBtn").onclick=()=>$("printEditor").classList.add("prm-hidden");$("refreshBtn").onclick=()=>load().catch(e=>msg(e.message,"error"));$("searchInput").oninput=render;
// Viewer
let v=[],vi=0,z=1;function vr(){const x=v[vi];$("viewerImage").src=x?.file_url||x||"";$("viewerImage").style.transform=`scale(${z})`}
function openViewer(id){const x=rows.find(r=>String(r.id)===String(id));v=mediaMap[String(id)]||[];if(!v.length&&x.artwork_url)v=[x.artwork_url];if(!v.length)return;vi=0;z=1;$("viewerTitle").textContent=`${x.print_no} · ${x.print_name}`;$("viewerText").textContent=x.caption_text||x.notes||"";$("mediaViewer").classList.remove("rr-hidden");vr()}
$("viewerClose").onclick=()=>$("mediaViewer").classList.add("rr-hidden");$("viewerZoomIn").onclick=()=>{z=Math.min(4,z+.25);vr()};$("viewerZoomOut").onclick=()=>{z=Math.max(.5,z-.25);vr()};$("viewerReset").onclick=()=>{z=1;vr()};$("viewerPrev").onclick=()=>{vi=(vi-1+v.length)%v.length;z=1;vr()};$("viewerNext").onclick=()=>{vi=(vi+1)%v.length;z=1;vr()};
(async()=>{try{await RR.requireOwner();builder=new RRCaptionBuilder({masterType:"print",printTypeInput:$("printType"),container:$("printCaptionBuilder"),outputInput:$("notes")});await builder.load();reset();await load()}catch(e){console.error(e);msg(e.message||"Print Master could not open.","error")}})();
})();

