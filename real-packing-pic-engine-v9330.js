(()=>{
  "use strict";
  if(window.__RR_PACKING_PIC_ENGINE_V9330__)return;
  window.__RR_PACKING_PIC_ENGINE_V9330__=true;
  const BUCKET="redzed-media",MODE="TEST",AI_FN="rr-ai-garment-images-v9330";
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  let lastLot="",gateBypass=false,selectedFiles=[];
  function db(){return window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb}
  function msg(t,cls){const m=$("message");if(m){m.textContent=t||"";m.className="fg-msg "+(cls||"")}else console.log(t)}
  function lot(){return String($("selectedPackLot")?.textContent||"").replace(/^Lot\s+/i,"").trim()}
  function mediaBlock(){
    if($("rrPackPicBlock")){bindPicButtons();return $("rrPackPicBlock");}
    const host=$("packSummary")||$("packWorkspace");
    if(!host)return null;
    const div=document.createElement("div");
    div.id="rrPackPicBlock";
    div.className="fg-panel rr-pack-pics";
    div.innerHTML=`<div class="fg-title-row"><div><h3>Final Pics + AI Generated Pics</h3><p class="fg-muted">Submit se pehle 3 final camera/gallery pics aur 3 AI generated pics mandatory.</p></div><button class="fg-btn" id="rrPicRefresh" type="button">Refresh Pics</button></div>
      <div class="fg-grid">
        <div class="fg-field"><label>Camera Pic</label><input id="rrCameraPics" type="file" accept="image/*" capture="environment" multiple></div>
        <div class="fg-field"><label>Gallery Pic</label><input id="rrGalleryPics" type="file" accept="image/*" multiple></div>
        <div class="fg-field"><label>AI Prompt</label><textarea id="rrAiPrompt">Create a clean branded e-commerce garment catalog image from this factory camera photo. Keep garment design, colour, print/artwork, fabric feel and proportions accurate. Remove messy background, improve lighting, make it suitable for webstore sale card, no fake logos, no text unless already on garment.</textarea></div>
      </div>
      <div class="fg-actions"><button class="fg-btn ok" id="rrUploadPics" type="button">UPLOAD SELECTED FINAL PICS</button><button class="fg-btn primary" id="rrGenerateAiPics" type="button">GENERATE 3 AI PICS</button></div><div id="rrPicLocalMsg" class="fg-msg"></div>
      <div id="rrPicStatus" class="fg-summary"></div><div id="rrPicPreview" class="rr-pic-preview"></div>`;
    host.insertAdjacentElement("afterend",div);
    bindPicButtons();
    return div;
  }
  function bindPicButtons(){
    const cam=$("rrCameraPics"),gal=$("rrGalleryPics"),up=$("rrUploadPics"),ai=$("rrGenerateAiPics"),ref=$("rrPicRefresh");
    if(cam&&!cam.dataset.rrBound){cam.dataset.rrBound="1";cam.addEventListener("change",collectFiles)}
    if(gal&&!gal.dataset.rrBound){gal.dataset.rrBound="1";gal.addEventListener("change",collectFiles)}
    if(up&&!up.dataset.rrBound){up.dataset.rrBound="1";up.addEventListener("click",e=>{e.preventDefault();e.stopPropagation();uploadSelected()})}
    if(ai&&!ai.dataset.rrBound){ai.dataset.rrBound="1";ai.addEventListener("click",e=>{e.preventDefault();e.stopPropagation();localMsg("AI button clicked. Camera pics check ho rahe hain…");generateAi()})}
    if(ref&&!ref.dataset.rrBound){ref.dataset.rrBound="1";ref.addEventListener("click",e=>{e.preventDefault();loadSummary(true)})}
  }
  function localMsg(t,cls){const x=$("rrPicLocalMsg");if(x){x.textContent=t||"";x.className="fg-msg "+(cls||"")}msg(t,cls)}
  function collectFiles(){
    selectedFiles=[...($("rrCameraPics")?.files||[]),...($("rrGalleryPics")?.files||[])].filter(f=>/^image\//i.test(f.type||""));
    const p=$("rrPicPreview"); if(!p)return;
    p.innerHTML=selectedFiles.map((f,i)=>`<div class="rr-thumb"><span>${i+1}</span><img src="${URL.createObjectURL(f)}" alt=""></div>`).join("");
  }
  async function rpc(name,args){
    const c=db(); if(!c?.rpc)throw Error("Supabase client unavailable");
    const {data,error}=await c.rpc(name,args); if(error)throw error; return data;
  }
  async function loadSummary(silent=false){
    const l=lot(); if(!l)return null;
    mediaBlock();
    const s=await rpc("rr_pack_media_summary_v9330",{p_lot_no:l,p_data_mode:MODE});
    renderSummary(s);
    if(!silent)localMsg(`Pics loaded: Camera ${s.camera_count||0}/3, AI ${s.ai_count||0}/3`,"ok");
    return s;
  }
  function renderSummary(s){
    const st=$("rrPicStatus"),pv=$("rrPicPreview"); if(!st||!pv)return;
    st.innerHTML=`<span class="fg-chip">Camera <b>${Number(s.camera_count||0)}/3</b></span><span class="fg-chip">AI <b>${Number(s.ai_count||0)}/3</b></span><span class="fg-chip">Total <b>${Number(s.total_count||0)}</b></span>`;
    const media=Array.isArray(s.media)?s.media:[];
    pv.innerHTML=media.map((m,i)=>`<div class="rr-thumb"><span>${esc(m.media_role||"PIC")} ${i+1}</span><img src="${esc(m.image_url||m.storage_path||"")}" alt=""></div>`).join("")||"<p class='fg-muted'>Abhi pics nahi hain.</p>";
  }
  async function uploadFile(file,path){
    const c=db(); if(!c?.storage)throw Error("Storage unavailable");
    const up=await c.storage.from(BUCKET).upload(path,file,{contentType:file.type||"image/jpeg",upsert:false});
    if(up.error)throw up.error;
    const pub=c.storage.from(BUCKET).getPublicUrl(path);
    return {path,image_url:pub.data.publicUrl};
  }
  async function uploadSelected(){
    try{
      const l=lot(); if(!l)throw Error("Lot select karein");
      if(!selectedFiles.length)throw Error("Camera/Gallery se pics select karein");
      localMsg("Upload clicked. Final pics upload ho rahi hain…");
      const cur=await rpc("rr_pack_media_summary_v9330",{p_lot_no:l,p_data_mode:MODE});
      const start=Number(cur.camera_count||0)+1;
      const items=[];
      for(let i=0;i<selectedFiles.length;i++){
        localMsg(`Uploading ${i+1}/${selectedFiles.length}…`);
        const f=selectedFiles[i],ext=(f.name.split(".").pop()||"jpg").replace(/[^a-z0-9]/gi,"").toLowerCase()||"jpg";
        const path=`packing-final/${MODE}/${encodeURIComponent(l)}/${Date.now()}-${crypto.randomUUID()}.${ext}`;
        const u=await uploadFile(f,path);
        items.push({media_role:"CAMERA",variant_no:start+i,image_url:u.image_url,storage_path:u.path,caption:"[CAMERA] Final packing image",customer_caption:"Final packing image"});
      }
      const s=await rpc("rr_pack_save_media_v9330",{p_lot_no:l,p_items:items,p_data_mode:MODE});
      selectedFiles=[];$("rrCameraPics").value="";$("rrGalleryPics").value="";
      renderSummary(s); localMsg("Final pics saved. Ab AI Generate chalayein.","ok");
    }catch(e){localMsg(e.message||String(e),"error")}
  }
  function b64File(b64,name){
    const bin=atob(b64),arr=new Uint8Array(bin.length);
    for(let i=0;i<bin.length;i++)arr[i]=bin.charCodeAt(i);
    return new File([arr],name,{type:"image/png"});
  }
  async function generateAi(){
    try{
      const l=lot(); if(!l)throw Error("Lot select karein");
      const s=await rpc("rr_pack_media_summary_v9330",{p_lot_no:l,p_data_mode:MODE});
      const cams=(Array.isArray(s.media)?s.media:[]).filter(x=>x.media_role==="CAMERA"&&x.image_url).slice(0,3);
      if(cams.length<3)throw Error(`AI se pehle UPLOAD SELECTED FINAL PICS dabana hoga. Uploaded camera pics: ${cams.length}/3`);
      localMsg("AI pics generate ho rahi hain…");
      const c=db(); if(!c?.functions)throw Error("Supabase Functions unavailable");
      const {data,error}=await c.functions.invoke(AI_FN,{body:{lot_no:l,image_urls:cams.map(x=>x.image_url),prompt:$("rrAiPrompt").value}});
      if(error)throw error;
      if(!data?.ok)throw Error(data?.error||"AI generation failed");
      const start=100+Number(s.ai_count||0),items=[];
      for(let i=0;i<(data.images_b64||[]).length;i++){
        const file=b64File(data.images_b64[i],`ai-${i+1}.png`);
        const path=`packing-ai/${MODE}/${encodeURIComponent(l)}/${Date.now()}-${crypto.randomUUID()}.png`;
        const u=await uploadFile(file,path);
        items.push({media_role:"AI",variant_no:start+i,image_url:u.image_url,storage_path:u.path,caption:"[AI] Generated garment image",customer_caption:"AI generated garment image"});
      }
      const next=await rpc("rr_pack_save_media_v9330",{p_lot_no:l,p_items:items,p_data_mode:MODE});
      renderSummary(next); localMsg("AI pics generated and saved.","ok");
    }catch(e){localMsg(e.message||String(e),"error")}
  }
  async function ensureGate(){
    const s=await loadSummary(true);
    const camera=Number(s?.camera_count||0),ai=Number(s?.ai_count||0);
    if(camera<3)throw Error(`Submit blocked: 3 final camera/gallery pics mandatory. Current ${camera}/3`);
    if(ai<3)throw Error(`Submit blocked: 3 AI generated pics mandatory. Current ${ai}/3`);
  }
  document.addEventListener("click",async e=>{
    const ai=e.target?.closest?.("#rrGenerateAiPics");
    if(ai){e.preventDefault();e.stopImmediatePropagation();localMsg("AI button clicked. Camera pics check ho rahe hain…");generateAi();return;}
    const up=e.target?.closest?.("#rrUploadPics");
    if(up){e.preventDefault();e.stopImmediatePropagation();localMsg("Upload button clicked…");uploadSelected();return;}
    const btn=e.target?.closest?.("#submitPack");
    if(!btn||gateBypass)return;
    e.preventDefault();e.stopImmediatePropagation();
    try{await ensureGate();gateBypass=true;btn.click();setTimeout(()=>gateBypass=false,0)}
    catch(err){gateBypass=false;localMsg(err.message||String(err),"error");mediaBlock()?.scrollIntoView({behavior:"smooth",block:"center"})}
  },true);
  function tick(){
    const l=lot(); bindPicButtons();
    if(l&&l!==lastLot&&!$("packWorkspace")?.hidden){lastLot=l;mediaBlock();loadSummary(true).catch(e=>localMsg(e.message,"error"))}
  }
  const style=document.createElement("style");
  style.textContent=`.rr-pack-pics{margin-top:12px}.rr-pic-preview{display:grid;grid-template-columns:repeat(auto-fill,minmax(105px,1fr));gap:8px;margin-top:10px}.rr-thumb{position:relative;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:#0f1115;min-height:105px}.rr-thumb img{width:100%;height:125px;object-fit:cover;display:block}.rr-thumb span{position:absolute;left:5px;top:5px;background:#000b;color:#fff;border-radius:999px;padding:3px 6px;font-size:10px;font-weight:900;z-index:1}`;
  document.head.appendChild(style);
  new MutationObserver(tick).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:["hidden"]});
  document.addEventListener("click",()=>setTimeout(tick,80),true);
  setInterval(bindPicButtons,1000);
  setTimeout(tick,500);
})();
