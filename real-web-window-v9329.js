(()=> {
  "use strict";
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  const money=v=>"₹"+Number(v||0).toLocaleString("en-IN");
  const state={rows:[],bucket:new Map(),gallery:[],gidx:0};
  function statusLabel(s){return s==="IN_STOCK"?"✅ In Stock":s==="LOW_STOCK"?"⚠️ Low Stock":s==="COMING_SOON"?"⏳ Coming Soon":"❌ Sold Out"}
  function statusClass(s){return s==="IN_STOCK"?"ok":s==="LOW_STOCK"||s==="COMING_SOON"?"warn":"bad"}
  function msg(t){$("msg").textContent=t||""}
  async function load(){
    try{
      msg("Loading…");
      const q=($("searchText").value||$("quickSearch").value||"").trim();
      const data=await RF853.rpc("rr_web_window_cards_v9329",{p_search:q,p_category:$("category").value,p_stock_status:$("stockStatus").value,p_data_mode:RF853.mode(),p_limit:90,p_offset:0});
      state.rows=Array.isArray(data)?data:[];
      renderCards();
      msg(`${state.rows.length} lots loaded.`);
    }catch(e){msg(e.message)}
  }
  function cardMedia(r){
    const arr=Array.isArray(r.media)?r.media:[];
    return arr.map(x=>({url:x.image_url||x.storage_path||"",cap:x.customer_caption||x.caption||r.caption||r.lot_no})).filter(x=>x.url);
  }
  function renderCards(){
    $("cards").className=`ww-grid cols-${$("viewCols").value}`;
    $("cards").innerHTML=state.rows.map(r=>{
      const media=cardMedia(r), img=r.primary_image_url||media[0]?.url||"", hidden=Math.max((Number(r.image_count)||media.length)-1,0);
      const qty=Math.max(1,Math.min(Number(r.available_qty||0),Number(r.available_qty||0)||1));
      return `<article class="ww-card" data-lot="${esc(r.lot_no)}">
        <div class="ww-img" data-gallery="${esc(r.lot_no)}">${img?`<img src="${esc(img)}" alt="${esc(r.lot_no)}">`:`<div class="fallback">👕</div>`}${hidden?`<span class="ww-badge">+${hidden}</span>`:""}</div>
        <div class="ww-body">
          <div class="ww-line"><b>${esc(r.lot_no)}</b><b>${money(r.sale_rate)}/pcs</b></div>
          <div class="ww-tags"><span class="tag2 ${statusClass(r.stock_status)}">${statusLabel(r.stock_status)}</span>${r.category?`<span class="tag2">${esc(r.category)}</span>`:""}${r.art_no?`<span class="tag2">Art ${esc(r.art_no)}</span>`:""}</div>
          <div class="ww-line"><span>Available</span><b>${Number(r.available_qty||0)}</b></div>
          <div class="ww-line"><span>CB / Print / Metal</span><span>${esc([r.cb_no,r.print_no,r.metal_id_no].filter(Boolean).join(" · ")||"-")}</span></div>
          <div class="ww-cap">${esc(r.caption||"")}</div>
          <div class="ww-actions"><input data-qty="${esc(r.lot_no)}" type="number" min="0" value="${qty}" inputmode="numeric"><button data-addbox="${esc(r.lot_no)}">+Box</button><button class="primary" data-add="${esc(r.lot_no)}">Add/Set</button></div>
        </div>
      </article>`;
    }).join("")||'<div class="card">No lots found.</div>';
  }
  function getBoxQty(){return Math.max(1,Number($("bucketBoxQty")?.value||18)||18)}
  function addLot(lot,mode="manual"){
    const r=state.rows.find(x=>String(x.lot_no)===String(lot)); if(!r)return;
    const input=document.querySelector(`[data-qty="${CSS.escape(lot)}"]`);
    const max=Math.max(0,Number(r.available_qty||0));
    const prev=state.bucket.get(lot)?.qty||0;
    const raw=mode==="box"?prev+getBoxQty():Number(input?.value||0);
    const qty=Math.max(0,Math.min(max,raw));
    if(raw>max) msg(`Qty ${raw} available ${max} se zyada hai. ${max} tak hi set kiya.`);
    state.bucket.set(lot,{...r,qty});
    renderBucket();
  }
  function renderBucket(){
    const rows=[...state.bucket.values()].filter(x=>x.qty>0);
    $("bucketRows").innerHTML=rows.length?rows.map(x=>`<div class="ww-line"><b>${esc(x.lot_no)}</b><span>${x.qty} pcs × ${money(x.sale_rate)} <button data-bdel="${esc(x.lot_no)}">×</button></span></div>`).join(""):"No lot selected.";
  }
  function copyBucket(){
    const lines=[...state.bucket.values()].filter(x=>x.qty>0).map(x=>({lot_no:x.lot_no,stock_type:"REGULAR",qty:x.qty,rate:Number(x.sale_rate||0),short_item_name:x.short_item_name||x.item_name||x.lot_no}));
    navigator.clipboard?.writeText(JSON.stringify(lines,null,2));
    msg(`${lines.length} PI draft lines copied. PI screen me paste/reference kar sakte hain.`);
  }
  function openGallery(lot){
    const r=state.rows.find(x=>String(x.lot_no)===String(lot)); if(!r)return;
    const media=cardMedia(r);
    if(!media.length&&r.primary_image_url)media.push({url:r.primary_image_url,cap:r.caption||r.lot_no});
    if(!media.length)return;
    state.gallery=media; state.gidx=0; showGallery();
  }
  function showGallery(){
    const x=state.gallery[state.gidx]; if(!x)return;
    $("galleryImg").src=x.url;$("galleryCap").textContent=`${state.gidx+1}/${state.gallery.length} · ${x.cap||""}`;$("gallery").classList.add("open");
  }
  function closeGallery(){$("gallery").classList.remove("open")}
  function moveGallery(d){if(!state.gallery.length)return;state.gidx=(state.gidx+d+state.gallery.length)%state.gallery.length;showGallery()}
  function openDrawer(v){$("drawer").classList.toggle("open",v);$("drawerBack").classList.toggle("open",v)}
  document.addEventListener("click",e=>{
    const g=e.target.closest("[data-gallery]"); if(g)return openGallery(g.dataset.gallery);
    const add=e.target.closest("[data-add]"); if(add)return addLot(add.dataset.add);
    const addb=e.target.closest("[data-addbox]"); if(addb)return addLot(addb.dataset.addbox,"box");
    const del=e.target.closest("[data-bdel]"); if(del){state.bucket.delete(del.dataset.bdel);renderBucket();}
  });
  let sx=0,sy=0;$("gallery").addEventListener("touchstart",e=>{sx=e.touches[0].clientX;sy=e.touches[0].clientY},{passive:true});$("gallery").addEventListener("touchend",e=>{const dx=e.changedTouches[0].clientX-sx,dy=e.changedTouches[0].clientY-sy;if(Math.abs(dy)>80&&dy>0)closeGallery();else if(Math.abs(dx)>50)moveGallery(dx<0?1:-1)},{passive:true});
  $("galleryImg").onclick=()=>moveGallery(1);$("galleryClose").onclick=closeGallery;
  $("filterBtn").onclick=()=>openDrawer(true);$("drawerClose").onclick=()=>openDrawer(false);$("drawerBack").onclick=()=>openDrawer(false);$("applyFilter").onclick=()=>{openDrawer(false);load()};$("refreshBtn").onclick=load;$("viewCols").onchange=renderCards;$("quickSearch").onkeydown=e=>{if(e.key==="Enter"){ $("searchText").value=$("quickSearch").value; load();}};$("dataMode").onchange=load;$("clearBucket").onclick=()=>{state.bucket.clear();renderBucket()};$("copyBucket").onclick=copyBucket;
  window.addEventListener("keydown",e=>{if(e.key==="Escape"){closeGallery();openDrawer(false)}else if($("gallery").classList.contains("open")&&e.key==="ArrowRight")moveGallery(1);else if($("gallery").classList.contains("open")&&e.key==="ArrowLeft")moveGallery(-1)});
  load();
})();