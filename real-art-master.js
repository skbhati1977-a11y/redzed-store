(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const form = $("artForm"), message = $("artMessage"), cards = $("artCards");
  const reloadButton = $("reloadArts"), saveButton = $("saveArtBtn"), cancelEdit = $("cancelEdit");
  const preview = $("imagePreview"), selectedFiles = $("selectedFiles");
  const fileInputs = [$("cameraFiles"), $("galleryFiles")];
  const costInputs = {
    cut:$("cutCost"), print:$("printCost"), sticker:$("stickerCost"), kr:$("krCost"),
    ov:$("ovCost"), fld:$("fldCost"), threadCut:$("threadCutCost"),
    press:$("pressCost"), pack:$("packCost"), other:$("otherCost")
  };
  let artRows=[], summaryRows=[], mediaMap={}, queuedFiles=[];
  let captionBuilder;

  const setMessage=(text,type="")=>{message.textContent=text||"";message.className=`rr-message ${type}`.trim()};
  const firstValue=(row,keys,fallback=0)=>{for(const k of keys){if(row?.[k]!==undefined&&row[k]!==null)return row[k]}return fallback};
  const totalCost=()=>Object.values(costInputs).reduce((s,i)=>s+RR.number(i.value),0);
  const updateTotal=()=>{$("makingTotal").textContent=RR.money(totalCost())};
  Object.values(costInputs).forEach(i=>i.addEventListener("input",updateTotal));

  function categoryDefaultName(category){
    return ({
      "R.NK / Crew Neck":"Crew Neck T-Shirt","Drop Shoulder":"Drop Shoulder T-Shirt",
      "Self Collar":"Self Collar Polo","Flat Polo Collar":"Flat Polo","Hoodies":"Hoodie",
      "Pre Winter":"Sweatshirt","Nikkar / Shorts / Bermuda":"Shorts / Bermuda",
      "Lower / Pajama":"Lower / Pajama"
    })[category]||"";
  }

  $("designCategory").addEventListener("change",()=>{
    if(!$("itemName").value.trim()) $("itemName").value=categoryDefaultName($("designCategory").value);
  });

  function updateQueued(){
    queuedFiles=fileInputs.flatMap(i=>Array.from(i.files||[]));
    selectedFiles.textContent=queuedFiles.length?`${queuedFiles.length} artwork image(s) ready`:"No new images selected";
    preview.innerHTML=queuedFiles.map((f,i)=>`<figure class="rz-media-item"><img src="${URL.createObjectURL(f)}"><figcaption>${i===0?"Icon / Cover":`Artwork ${i+1}`}</figcaption></figure>`).join("");
  }
  fileInputs.forEach(i=>i.addEventListener("change",updateQueued));

  async function loadData(){
    reloadButton.disabled=true;reloadButton.textContent="Loading...";
    const [a,s,m]=await Promise.all([
      supabaseClient.from("rr_art_master").select("*").order("created_at",{ascending:false}).limit(300),
      supabaseClient.from("rr_art_cost_summary").select("*"),
      RR.getMediaMap("art","reference")
    ]);
    reloadButton.disabled=false;reloadButton.textContent="Refresh";
    if(a.error)throw a.error;if(s.error)throw s.error;
    artRows=a.data||[];summaryRows=s.data||[];mediaMap=m||{};renderCards();
  }

  const summary=(id)=>summaryRows.find(r=>String(r.art_id)===String(id))||{};

  function renderCards(){
    if(!artRows.length){cards.innerHTML="<p>No Art saved yet.</p>";return}
    cards.innerHTML=artRows.map(art=>{
      const imgs=mediaMap[String(art.id)]||[];
      const image=imgs[0]?.file_url||"";
      const cost=firstValue(summary(art.id),["total_making_cost","making_cost","total_process_cost","process_cost"],0);
      return `<article class="rz-master-card" data-art-id="${RR.safeText(art.id)}">
        <button class="rz-card-image" type="button" data-view-art="${RR.safeText(art.id)}">
          ${image?`<img src="${RR.safeText(image)}">`:`<div class="rz-placeholder">ART</div>`}
          <span>${imgs.length} image${imgs.length===1?"":"s"}</span>
        </button>
        <div class="rz-card-body">
          <small>${RR.safeText(art.category||"Art")}</small>
          <h3>${RR.safeText(art.art_no)} · ${RR.safeText(art.item_name||art.product_name||"")}</h3>
          <p>${RR.safeText(art.caption_text||art.description||"")}</p>
          <div class="rz-metric-row"><b>Process ${RR.money(cost)}</b><b>Other Margin ${RR.money(art.default_margin||0)}</b></div>
          <button class="rr-btn rr-btn-secondary" type="button" data-edit-art="${RR.safeText(art.id)}">Edit</button>
        </div>
      </article>`;
    }).join("");
    cards.querySelectorAll("[data-edit-art]").forEach(b=>b.addEventListener("click",()=>editArt(b.dataset.editArt)));
    cards.querySelectorAll("[data-view-art]").forEach(b=>b.addEventListener("click",()=>openArtViewer(b.dataset.viewArt)));
  }

  async function editArt(id){
    const art=artRows.find(r=>String(r.id)===String(id));if(!art)return;
    $("artId").value=art.id;$("artNo").value=art.art_no||"";
    $("designCategory").value=art.category||"";
    $("itemName").value=art.item_name||art.product_name||"";
    $("designNotes").value=art.other_material_note||"";
    $("defaultMargin").value=art.default_margin??22;
    const aliases={
      cut:["cutting_rate","cut_cost"],print:["printing_rate","print_cost"],sticker:["sticker_rate","sticker_cost","sticker"],
      kr:["kr_rate","kr_cost","kr"],ov:["ov_rate","ov_cost","ov"],fld:["fld_rate","fld_cost","fld"],
      threadCut:["thread_cut_rate","thread_cut_cost","th_cut_cost","th_cut"],press:["press_rate","press_cost","press"],
      pack:["packing_rate","pack_cost","packing_cost","pack"],other:["other_rate","other_cost","others_cost","others"]
    };
    for(const [k,names] of Object.entries(aliases))costInputs[k].value=firstValue(summary(id),names,0);
    const imgs=mediaMap[String(id)]||[];
    preview.innerHTML=imgs.map((x,i)=>`<figure class="rz-media-item"><img src="${RR.safeText(x.file_url)}"><figcaption>${i===0?"Icon / Cover":`Artwork ${i+1}`}</figcaption></figure>`).join("");
    await captionBuilder.load(Array.isArray(art.caption_items)?art.caption_items:[]);
    $("formTitle").textContent=`Edit ${art.art_no}`;saveButton.textContent="Update Art";cancelEdit.classList.remove("rr-hidden");
    updateTotal();scrollTo({top:0,behavior:"smooth"});
  }

  function resetForm(){
    form.reset();$("artId").value="";
    Object.assign(costInputs.cut,{value:"2.5"});costInputs.print.value="0";costInputs.sticker.value="0";
    costInputs.kr.value="0";costInputs.ov.value="0";costInputs.fld.value="0";costInputs.threadCut.value="2.5";
    costInputs.press.value="2.25";costInputs.pack.value="0.80";costInputs.other.value="6";
    $("defaultMargin").value="22";queuedFiles=[];selectedFiles.textContent="No new images selected";preview.innerHTML="";
    $("formTitle").textContent="Add Art";saveButton.textContent="Save Art";cancelEdit.classList.add("rr-hidden");
    captionBuilder.load([]);updateTotal();
  }

  async function saveCosts(artId){
    const cols=await RR.getTableColumns("rr_art_costs");
    const aliases={art_id:["art_id"],cut:["cutting_rate","cut_cost"],print:["printing_rate","print_cost"],
      sticker:["sticker_rate","sticker_cost","sticker"],kr:["kr_rate","kr_cost","kr"],ov:["ov_rate","ov_cost","ov"],
      fld:["fld_rate","fld_cost","fld"],threadCut:["thread_cut_rate","thread_cut_cost","th_cut_cost","th_cut"],
      press:["press_rate","press_cost","press"],pack:["packing_rate","pack_cost","packing_cost","pack"],
      other:["other_rate","other_cost","others_cost","others"]};
    const payload={}, artCol=RR.pickColumn(cols,aliases.art_id);
    if(!artCol)throw new Error("rr_art_costs art_id column missing.");payload[artCol]=artId;
    for(const[k,names]of Object.entries(aliases)){if(k==="art_id")continue;const c=RR.pickColumn(cols,names);if(c)payload[c]=RR.number(costInputs[k].value)}
    const read=await supabaseClient.from("rr_art_costs").select("*").eq(artCol,artId).maybeSingle();
    if(read.error)throw read.error;
    const write=read.data?await supabaseClient.from("rr_art_costs").update(payload).eq(artCol,artId):await supabaseClient.from("rr_art_costs").insert(payload);
    if(write.error)throw write.error;
  }

  form.addEventListener("submit",async(e)=>{
    e.preventDefault();setMessage("");saveButton.disabled=true;saveButton.textContent="Saving...";
    try{
      const cols=await RR.getTableColumns("rr_art_master"), existing=$("artId").value;
      const payload=RR.filterPayload({
        art_no:$("artNo").value.trim().toUpperCase(), category:$("designCategory").value,
        item_name:$("itemName").value.trim(),product_name:$("itemName").value.trim(),
        description:$("description").value.trim(),other_material_note:$("designNotes").value.trim(),
        default_margin:RR.number($("defaultMargin").value),is_active:true
      },cols);
      const result=existing
        ?await supabaseClient.from("rr_art_master").update(payload).eq("id",existing).select().single()
        :await supabaseClient.from("rr_art_master").insert(payload).select().single();
      if(result.error)throw result.error;const art=result.data;
      await saveCosts(art.id);
      await supabaseClient.rpc("rr_save_art_captions",{p_art_id:art.id,p_items:captionBuilder.getItems()});
      for(const input of fileInputs){
        const sourceType=input.id==="cameraFiles"?"camera":"gallery";
        for(const file of Array.from(input.files||[]))await RR.uploadMedia({
          file,entityType:"art",entityId:art.id,mediaCategory:"reference",
          sourceType,visibilityScope:"factory",caption:`${art.art_no} artwork`
        });
      }
      setMessage("Art saved successfully.","success");resetForm();await loadData();
    }catch(err){console.error(err);setMessage(err.message||"Art could not be saved.","error")}
    finally{saveButton.disabled=false;saveButton.textContent=$("artId").value?"Update Art":"Save Art"}
  });

  // Zoom viewer
  let viewerImages=[],viewerIndex=0,zoom=1;
  function renderViewer(){const x=viewerImages[viewerIndex];$("viewerImage").src=x?.file_url||"";$("viewerImage").style.transform=`scale(${zoom})`}
  function openArtViewer(id){
    const art=artRows.find(r=>String(r.id)===String(id));viewerImages=mediaMap[String(id)]||[];if(!viewerImages.length)return;
    viewerIndex=0;zoom=1;$("viewerTitle").textContent=`${art.art_no} · ${art.item_name||art.product_name||""}`;
    $("viewerText").textContent=art.caption_text||art.description||"";$("mediaViewer").classList.remove("rr-hidden");renderViewer();
  }
  $("viewerClose").onclick=()=>$("mediaViewer").classList.add("rr-hidden");
  $("viewerZoomIn").onclick=()=>{zoom=Math.min(4,zoom+.25);renderViewer()};
  $("viewerZoomOut").onclick=()=>{zoom=Math.max(.5,zoom-.25);renderViewer()};
  $("viewerReset").onclick=()=>{zoom=1;renderViewer()};
  $("viewerPrev").onclick=()=>{viewerIndex=(viewerIndex-1+viewerImages.length)%viewerImages.length;zoom=1;renderViewer()};
  $("viewerNext").onclick=()=>{viewerIndex=(viewerIndex+1)%viewerImages.length;zoom=1;renderViewer()};
  $("viewerStage").addEventListener("wheel",e=>{e.preventDefault();zoom=Math.max(.5,Math.min(4,zoom+(e.deltaY<0?.15:-.15)));renderViewer()},{passive:false});

  cancelEdit.addEventListener("click",resetForm);
  reloadButton.addEventListener("click",()=>loadData().catch(e=>setMessage(e.message,"error")));

  (async()=>{
    try{
      await RR.requireOwner();
      captionBuilder=new RRCaptionBuilder({
        masterType:"art",categoryInput:$("designCategory"),
        container:$("artCaptionBuilder"),outputInput:$("description")
      });
      await captionBuilder.load();resetForm();await loadData();
    }catch(err){console.error(err);setMessage(err.message||"Art Master could not open.","error")}
  })();
})();
       
