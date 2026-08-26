(()=>{
  "use strict";
  if(window.__RR_PACKING_PIC_ENGINE_V9340__)return;
  window.__RR_PACKING_PIC_ENGINE_V9340__=true;
  const BUCKET="redzed-media",MODE="TEST";
  const $=id=>document.getElementById(id),db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  let lastLot="",gateBypass=false,selectedFiles=[],uploadRunning=false;
  let rateSnapshot=null,ratePollBusy=false;
  function lot(){return String($("selectedPackLot")?.textContent||"").replace(/^Lot\s+/i,"").trim()}
  function msg(t,cls){const m=$("message");if(m){m.textContent=t||"";m.className="fg-msg "+(cls||"")}console.log(t||"")}
  function localMsg(t,cls){const x=$("rrPicLocalMsg");if(x){x.textContent=t||"";x.className="fg-msg "+(cls||"")}msg(t,cls)}
  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error("Supabase client unavailable");const {data,error}=await c.rpc(name,args);if(error)throw error;return data}
  function cleanErr(e){return String(e?.message||e?.context?.msg||e?.details||e||"Unknown error")}
  function algoReady(){return !!document.querySelector("#packRows tr")}
  function block(){
    if($("rrCatalogEngine"))return $("rrCatalogEngine");
    const table=$("packRows")?.closest(".fg-table-wrap")||$("packSummary");if(!table)return null;
    const root=document.createElement("section");root.id="rrCatalogEngine";root.className="rr-catalog-engine";
    root.innerHTML=`
      <section class="fg-panel rr-rate-gate"><div class="fg-title-row"><div><h3>Final Rate Approval · RRQ</h3><p class="fg-muted">Packing algorithm ke baad final approval mandatory. Packing operator ko sale rate visible nahi hoga.</p></div><button class="fg-btn" id="rrRateRefresh" type="button">Refresh</button></div><div id="rrRateStatus" class="fg-summary"></div><div class="fg-actions"><button class="fg-btn primary" id="rrRequestRate" type="button">REQUEST FINAL RATE APPROVAL</button></div></section>
      <section class="fg-panel" id="rrSourcePics" hidden><div class="fg-title-row"><div><h3>3 Final Garment Photos</h3><p class="fg-muted">Final rate approve hone ke baad Camera/Gallery se exactly product-truth photos. Specific photo delete karke replace ki ja sakti hai.</p></div><button class="fg-btn" id="rrPicRefresh" type="button">Refresh Pics</button></div><div class="fg-grid two"><div class="fg-field"><label>Camera</label><input id="rrCameraPics" type="file" accept="image/*" capture="environment" multiple></div><div class="fg-field"><label>Gallery</label><input id="rrGalleryPics" type="file" accept="image/*" multiple></div></div><div class="fg-actions"><button class="fg-btn ok" id="rrUploadPics" type="button">UPLOAD SELECTED FINAL PICS</button></div><div id="rrCameraPreview" class="rr-pic-preview"></div></section>
      <div id="rrPicLocalMsg" class="fg-msg"></div>`;
    table.insertAdjacentElement("afterend",root);bind();return root;
  }
  function bind(){
    const once=(id,ev,fn)=>{const n=$(id);if(n&&!n.dataset.rrBound){n.dataset.rrBound="1";n.addEventListener(ev,fn)}};
    once("rrRateRefresh","click",()=>loadAll());once("rrRequestRate","click",requestRate);once("rrPicRefresh","click",()=>loadAll());
    once("rrCameraPics","change",collectFiles);once("rrGalleryPics","change",collectFiles);once("rrUploadPics","click",uploadSelected);
  }
  function collectFiles(){selectedFiles=[...($("rrCameraPics")?.files||[]),...($("rrGalleryPics")?.files||[])].filter(f=>/^image\//i.test(f.type||""));localMsg(`${selectedFiles.length} image selected.`)}
  async function uploadFile(file,path){const c=db();const up=await c.storage.from(BUCKET).upload(path,file,{contentType:file.type||"image/jpeg",upsert:false});if(up.error)throw up.error;return{path,image_url:c.storage.from(BUCKET).getPublicUrl(path).data.publicUrl}}
  async function removePaths(paths){const clean=(paths||[]).filter(Boolean);if(!clean.length)return;const r=await db().storage.from(BUCKET).remove(clean);if(r.error)console.warn(r.error)}
  async function requestRate(){try{if(!algoReady())throw Error("Pehle Packing Algorithm/Table complete karein.");const l=lot();if(!l)throw Error("Lot select karein");const b=$("rrRequestRate");b.disabled=true;localMsg("Final rate approval request bheji ja rahi hai…");await rpc("rr_pack_request_rate_v9340",{p_lot_no:l,p_data_mode:MODE});localMsg("Request Admin/Super Admin ko bhej di gayi.","ok");await loadAll()}catch(e){localMsg(cleanErr(e),"error")}finally{if($("rrRequestRate"))$("rrRequestRate").disabled=false}}
  async function loadRate(statusOnly=false){const l=lot();if(!l)return{approved:false,status:"NOT_REQUESTED"};const s=await rpc("rr_pack_rate_status_v9340",{p_lot_no:l,p_data_mode:MODE});if(l!==lot()||$("packWorkspace")?.hidden)return s;rateSnapshot={lot:l,...s};const st=$("rrRateStatus"),req=$("rrRequestRate");if(st){const text=s.approved?`APPROVED · ${esc(s.art_code||"")}`:s.status==="NOT_REQUESTED"?"Approval not requested":`${esc(s.status)} · Admin action pending`;const html=`<span class="fg-chip"><b>${text}</b></span>`;if(st.innerHTML!==html)st.innerHTML=html}
    if(req){req.hidden=!!s.approved;req.disabled=!algoReady()}
    if(!statusOnly)$("rrSourcePics").hidden=!s.approved;return s}
  async function refreshApproval(force=false){
    const l=lot();
    if(ratePollBusy||!l||document.hidden||$("packWorkspace")?.hidden||!$("rrRateStatus"))return;
    if(!force&&rateSnapshot?.lot===l&&rateSnapshot.approved)return;
    ratePollBusy=true;
    try{
      const wasApproved=rateSnapshot?.lot===l&&rateSnapshot.approved;
      const status=await loadRate(true);
      if(l!==lot()||$("packWorkspace")?.hidden)return;
      // Refresh photos once when final rate approval arrives.
      if(status.approved&&!wasApproved)await loadAll();
    }catch(e){console.warn('Packing approval status refresh failed',e?.message||e)}
    finally{ratePollBusy=false}
  }
  async function mediaSummary(){const l=lot();if(!l)return null;const s=await rpc("rr_pack_media_summary_v9330",{p_lot_no:l,p_data_mode:MODE});const cams=(s?.media||[]).filter(x=>x.media_role==="CAMERA");const p=$("rrCameraPreview");if(p)p.innerHTML=cams.map((m,i)=>`<div class="rr-thumb"><span>FINAL ${i+1}</span><img src="${esc(m.image_url||m.storage_path||"")}" alt=""><button class="rr-del" data-cam-del="${esc(m.media_id)}" data-path="${esc(m.storage_path||"")}" type="button">×</button></div>`).join("")||"<p class='fg-muted'>Abhi final garment pics nahi hain.</p>";return s}
  async function uploadSelected(e){e?.preventDefault();if(uploadRunning)return;uploadRunning=true;const b=$("rrUploadPics");try{const rate=await loadRate();if(!rate.approved)throw Error("Final rate approval required");const l=lot(),cur=await mediaSummary(),have=Number(cur?.camera_count||0);if(!selectedFiles.length)throw Error("Camera/Gallery images select karein");if(have+selectedFiles.length>3)throw Error(`Total final garment photos 3 hi rahengi. Current ${have}/3.`);b.disabled=true;b.textContent="UPLOADING…";const items=[];for(let i=0;i<selectedFiles.length;i++){const f=selectedFiles[i],ext=(f.name.split(".").pop()||"jpg").replace(/[^a-z0-9]/gi,"").toLowerCase()||"jpg",path=`packing-final/${MODE}/${encodeURIComponent(l)}/${Date.now()}-${crypto.randomUUID()}.${ext}`,u=await uploadFile(f,path);items.push({media_role:"CAMERA",variant_no:have+i+1,image_url:u.image_url,storage_path:u.path,caption:"[CAMERA] Final packing image",customer_caption:"Final packing image"})}await rpc("rr_pack_save_media_v9332",{p_lot_no:l,p_items:items,p_data_mode:MODE});selectedFiles=[];if($("rrCameraPics"))$("rrCameraPics").value="";if($("rrGalleryPics"))$("rrGalleryPics").value="";localMsg("Final garment photos saved.","ok");await loadAll()}catch(err){localMsg(cleanErr(err),"error")}finally{uploadRunning=false;if(b){b.disabled=false;b.textContent="UPLOAD SELECTED FINAL PICS"}}}
  async function deleteCamera(id,path){try{if(!confirm("Final garment photo delete karein?"))return;const r=await rpc("rr_pack_camera_delete_v9340",{p_media_id:id,p_lot_no:lot(),p_data_mode:MODE});await removePaths([r?.storage_path||path]);await loadAll();localMsg("Photo deleted. Replacement upload karein.","ok")}catch(e){localMsg(cleanErr(e),"error")}}
  async function loadAll(){block();bind();try{await loadRate();await mediaSummary()}catch(e){localMsg(cleanErr(e),"error")}}
  async function ensureGate(){const rate=await loadRate();if(!rate.approved)throw Error("Submit blocked: Final Rate Approval pending");const s=await mediaSummary();if(Number(s?.camera_count||0)!==3)throw Error(`Submit blocked: 3 final garment photos mandatory. Current ${Number(s?.camera_count||0)}/3`)}
  document.addEventListener("click",async e=>{const cam=e.target?.closest?.("[data-cam-del]");if(cam){e.preventDefault();deleteCamera(cam.dataset.camDel,cam.dataset.path);return}const btn=e.target?.closest?.("#submitPack");if(!btn||gateBypass)return;e.preventDefault();e.stopImmediatePropagation();try{await ensureGate();gateBypass=true;btn.click();setTimeout(()=>gateBypass=false,0)}catch(err){gateBypass=false;localMsg(err.message||String(err),"error");block()?.scrollIntoView({behavior:"smooth",block:"center"})}},true);
  function tick(){const l=lot();bind();if(l&&l!==lastLot&&!$("packWorkspace")?.hidden){lastLot=l;block();loadAll()}else if(l&&!$("packWorkspace")?.hidden&&$("rrRequestRate"))$("rrRequestRate").disabled=!algoReady()}
  const style=document.createElement("style");style.textContent=`.rr-catalog-engine{margin-top:10px}.rr-pic-preview{display:grid;grid-template-columns:repeat(3,minmax(90px,1fr));gap:8px;margin-top:10px}.rr-thumb{position:relative;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:#0f1115;min-height:120px}.rr-thumb img{width:100%;height:150px;object-fit:cover;display:block}.rr-thumb span{position:absolute;left:5px;top:5px;background:#000b;color:#fff;border-radius:999px;padding:3px 6px;font-size:10px;font-weight:900;z-index:1}.rr-del{position:absolute;right:4px;top:4px;border-radius:999px;padding:3px 7px;background:#5a2029}@media(max-width:600px){.rr-pic-preview{grid-template-columns:1fr 1fr}}`;
  document.head.appendChild(style);new MutationObserver(tick).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:["hidden"]});document.addEventListener("click",()=>setTimeout(tick,120),true);setInterval(tick,1200);setTimeout(tick,500);
  setInterval(()=>refreshApproval(),5000);
  window.addEventListener('focus',()=>refreshApproval(true));
  window.addEventListener('pageshow',()=>refreshApproval(true));
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)refreshApproval(true)});
})();
