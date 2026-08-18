(() => {
"use strict";

window.REAL_FACTORY_CUTTING_CB_ACTIONS_VERSION = "720.36.2-SAVE-LOCK-FINAL";

const state = {
  client: null,
  role: "",
  actions: [],
  sources: [],
  current: null,
  proofDraft: { images: [], video: null, urls: [] },
  reportSubmitting: false,
  reportCommitted: false,
  renderQueued: false
};

const $ = id => document.getElementById(id);
const safe = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
const kg = value => `${Number(value || 0).toFixed(3)} kg`;
const money = value => new Intl.NumberFormat("en-IN", {style:"currency",currency:"INR",maximumFractionDigits:2}).format(Number(value || 0));
const errorText = error => [error?.message,error?.details,error?.hint,error?.code].filter(Boolean).join(" — ") || "Unknown error";
const statusText = value => String(value || "").replaceAll("_", " ");

function getClient(){
  let client = null;
  try{
    if(typeof supabaseClient !== "undefined" && supabaseClient?.from) client = supabaseClient;
  }catch{}
  return client || [window.supabaseClient,window.supabaseDb,window.redzedSupabase,window.sb].find(x => x?.from) || null;
}

function coreState(){
  try{return window.RRCuttingMasterPM?.state?.() || {}}catch{return {}}
}

function say(text,type="info"){
  const box = $("cmMessage");
  if(!box) return;
  box.textContent = text;
  box.className = `rr-message ${type}`;
}

function roleCanAdmin(){return ["owner","admin"].includes(state.role)}
function roleIsOwner(){return state.role === "owner"}

function normalizePhone(value){
  let x = String(value || "").replace(/\D/g, "");
  if(x.length === 10) x = `91${x}`;
  return x;
}

function adminPhoneDefault(){
  let phone = "";
  try{
    phone = CFG.DEFAULT_WHATSAPP || (Array.isArray(CFG.WHATSAPP) ? CFG.WHATSAPP[0] : "") || "";
  }catch{}
  return localStorage.getItem("redzed_admin_whatsapp") || phone || "";
}

function whatsappUrl(phone,message){
  const number = normalizePhone(phone);
  if(!number) throw new Error("WhatsApp number required.");
  return `https://wa.me/${number}?text=${encodeURIComponent(message)}`;
}

function openWhatsapp(phone,message,{sameTabFallback=false}={}){
  const url = whatsappUrl(phone,message);
  const win = window.open(url, "_blank", "noopener,noreferrer");
  if(win) return true;
  if(sameTabFallback){
    window.location.assign(url);
    return false;
  }
  throw new Error("Browser ने WhatsApp popup block किया। WhatsApp Admin button से दोबारा खोलें।");
}

function proofLinks(action){
  return Array.isArray(action.media) ? action.media.map(x => x.file_url).filter(Boolean) : [];
}

function messageWithProof(action,base){
  const links = proofLinks(action);
  return `${base || action.admin_message || "Cutting action verification required."}${links.length ? `\n\nProof:\n${links.join("\n")}` : ""}`;
}

function lotNoFromForm(){
  const values = [
    $("cmManualLotNo")?.value,
    ...[...document.querySelectorAll(".cm-dev-lot-no")].map(x => x.value),
    $("lotNo")?.value
  ].map(x => String(x || "").trim().toUpperCase()).filter(Boolean);
  return [...new Set(values)].join(" / ");
}

function activeCard(){return coreState().activeCard || null}
function activeDivisionId(){return String(activeCard()?.division?.division_id || "")}
function activeCbId(){return String(activeCard()?.group?.cb_id || "")}

function actionsForDivision(divisionId){
  return state.actions.filter(x => String(x.division_id) === String(divisionId));
}

function hasBlockingPending(divisionId){
  return actionsForDivision(divisionId).some(x => ["PENDING_ADMIN","ADMIN_MESSAGE_SENT","ADMIN_VERIFIED","RECHECK_REQUIRED"].includes(x.status));
}

function cbIdForDivision(divisionId){
  const active = activeCard();
  if(String(active?.division?.division_id || "") === String(divisionId)) return String(active?.group?.cb_id || "");
  const row = (coreState().galleryRows || []).find(x => String(x.division_id || x.unit_id || x.id) === String(divisionId));
  return String(row?.cb_id || row?.purchase_id || "");
}
function hasApprovedFullGr(divisionId){
  const cbId = cbIdForDivision(divisionId);
  return state.actions.some(x =>
    x.action_type === "FULL_GR" && x.effect_posted === true &&
    ["OWNER_APPROVED","VENDOR_MESSAGE_SENT"].includes(x.status) &&
    (String(x.division_id) === String(divisionId) || (x.full_gr_scope === "CB" && String(x.cb_id) === cbId))
  );
}

async function loadRole(){
  const r = await state.client.rpc("rr_current_role");
  if(!r.error && r.data) state.role = String(r.data).toLowerCase();
}

function textKey(value){
  return String(value ?? "").trim();
}

function canonicalDivisionCode(value){
  const raw = textKey(value).toUpperCase().replace(/\s+/g, "");
  const match = raw.match(/[DS](\d+)([A-Z]*)$/);
  return match ? `D${Number(match[1])}${match[2] || ""}` : raw;
}

function normalizeSourceRow(row = {}){
  return {
    ...row,
    cb_id:
      row.cb_id ||
      row.parent_cb_id ||
      row.fabric_purchase_id ||
      "",
    division_id:
      row.division_id ||
      row.cb_unit_id ||
      row.unit_id ||
      row.cb_division_id ||
      row.allocation_division_id ||
      "",
    division_code:
      row.division_code ||
      row.cb_code ||
      row.unit_code ||
      row.child_code ||
      "",
    purchase_entry_id:
      row.purchase_entry_id ||
      row.cb_purchase_entry_id ||
      row.source_purchase_entry_id ||
      "",
    roll_id:
      row.roll_id ||
      row.purchase_roll_id ||
      row.source_roll_id ||
      "",
    bill_no:
      row.bill_no ||
      row.vendor_bill_no ||
      "",
    vendor_name:
      row.vendor_name ||
      row.supplier_name ||
      "",
    fabric_name:
      row.fabric_name ||
      row.material_name ||
      "",
    colour_name:
      row.colour_name ||
      row.color_name ||
      "",
    roll_no:
      row.roll_no ??
      row.roll_number ??
      "",
    division_available_qty: Number(
      row.division_available_qty ??
      row.available_qty ??
      row.division_balance_qty ??
      row.current_qty ??
      row.balance_qty ??
      0
    ),
    roll_available_qty: Number(
      row.roll_available_qty ??
      row.roll_balance_qty ??
      row.current_roll_qty ??
      row.available_roll_qty ??
      0
    )
  };
}

function sourceRowKey(row = {}){
  return [
    textKey(row.cb_id),
    textKey(row.division_id),
    canonicalDivisionCode(row.division_code),
    textKey(row.purchase_entry_id),
    textKey(row.roll_id)
  ].join("|");
}

function mergeSourceRows(...groups){
  const map = new Map();
  groups.flat().filter(Boolean).map(normalizeSourceRow).forEach(row => {
    const key = sourceRowKey(row);
    if(!map.has(key)) map.set(key,row);
    else map.set(key,{...map.get(key),...row});
  });
  return [...map.values()];
}

function isRegularPurchase(row = {},regularCategoryIds = new Set()){
  const categoryId = textKey(row.material_category_id);
  const note = `${row.entry_notes || ""} ${row.entry_kind || ""}`.trim().toLowerCase();
  if(regularCategoryIds.size) return regularCategoryIds.has(categoryId);
  if(/matching|cuff|collar|other material|cb material/.test(note)) return false;
  return /regular cloth|purchase/.test(note) || !note;
}

async function loadBaseTableSourcesForActive(){
  const cbId = textKey(state.current?.cbId || activeCbId());
  const divisionId = textKey(state.current?.divisionId || activeDivisionId());
  const card = activeCard();
  const divisionCode = canonicalDivisionCode(
    card?.division?.division_code ||
    card?.division?.cb_code ||
    card?.division?.child_code ||
    ""
  );

  if(!cbId || !divisionId) return [];

  const [purchaseResult,allocationResult,colourResult,categoryResult] = await Promise.all([
    state.client.from("rr_cb_purchase_entries").select("*").eq("cb_id",cbId),
    state.client.from("rr_cb_material_allocations").select("*").eq("division_id",divisionId),
    state.client.from("rr_cb_colours").select("*").eq("cb_id",cbId),
    state.client.from("rr_material_categories").select("id,category_code,category_name")
  ]);

  const errors = [purchaseResult,allocationResult,colourResult]
    .map(result => result.error)
    .filter(Boolean);
  if(errors.length){
    console.warn("Base-table Source Bill fallback unavailable",errors);
    return [];
  }

  const regularCategoryIds = new Set(
    (categoryResult.error ? [] : categoryResult.data || [])
      .filter(row => {
        const label = `${row.category_code || ""} ${row.category_name || ""}`.toLowerCase();
        return label.includes("regular-cloth") || label.includes("regular cloth");
      })
      .map(row => textKey(row.id))
  );

  const purchases = (purchaseResult.data || []).filter(row =>
    Number(row.quantity ?? row.available_quantity ?? 0) > 0.0005 &&
    isRegularPurchase(row,regularCategoryIds)
  );
  const purchaseMap = new Map(purchases.map(row => [textKey(row.id),row]));

  const allocations = (allocationResult.data || []).filter(row =>
    purchaseMap.has(textKey(row.purchase_entry_id)) &&
    Number(row.allocated_qty ?? row.available_qty ?? 0) > 0.0005
  );
  const purchaseIds = [...new Set(allocations.map(row => textKey(row.purchase_entry_id)).filter(Boolean))];
  if(!purchaseIds.length) return [];

  const rollResult = await state.client
    .from("rr_cb_purchase_rolls")
    .select("*")
    .in("purchase_entry_id",purchaseIds);
  if(rollResult.error){
    console.warn("Source Bill roll fallback unavailable",rollResult.error);
    return [];
  }

  const colourMap = new Map((colourResult.data || []).map(row => [textKey(row.id),row]));
  const rollsByPurchase = new Map();
  (rollResult.data || []).forEach(row => {
    const pid = textKey(row.purchase_entry_id);
    if(!rollsByPurchase.has(pid)) rollsByPurchase.set(pid,[]);
    rollsByPurchase.get(pid).push(row);
  });

  const out = [];
  allocations.forEach(allocation => {
    const pid = textKey(allocation.purchase_entry_id);
    const purchase = purchaseMap.get(pid);
    const allocationQty = Number(allocation.allocated_qty ?? allocation.available_qty ?? 0);
    (rollsByPurchase.get(pid) || []).forEach(roll => {
      const rollQty = Number(roll.quantity ?? roll.available_quantity ?? 0);
      if(rollQty <= 0.0005) return;
      const colour = colourMap.get(textKey(roll.cb_colour_id)) || {};
      out.push(normalizeSourceRow({
        cb_id:cbId,
        division_id:divisionId,
        division_code:divisionCode,
        purchase_entry_id:pid,
        roll_id:roll.id,
        bill_no:purchase.vendor_bill_no || purchase.bill_no || "",
        vendor_name:purchase.vendor_name || "",
        fabric_name:purchase.fabric_name || "",
        colour_name:colour.colour_name || colour.color_name || "",
        roll_no:roll.roll_no,
        division_available_qty:allocationQty,
        roll_available_qty:rollQty,
        rate:purchase.rate,
        source_origin:"base_tables"
      }));
    });
  });

  return out;
}

async function loadSourceData(options = {}){
  const result = await state.client
    .from("rr_cutting_regular_purchase_sources_v1")
    .select("*");

  let viewRows = [];
  if(result.error){
    console.warn("Regular purchase source view unavailable",result.error);
  }else{
    viewRows = (result.data || []).map(normalizeSourceRow);
  }

  state.sources = mergeSourceRows(viewRows);

  if(options.ensureActive && !sourceRowsForActive().length){
    const fallbackRows = await loadBaseTableSourcesForActive();
    state.sources = mergeSourceRows(state.sources,fallbackRows);
  }

  return !result.error || state.sources.length > 0;
}

async function loadAddonData(){
  if(!state.client) return;
  const [a] = await Promise.all([
    state.client.from("rr_cutting_cb_action_details_v1").select("*").order("created_at",{ascending:false}),
    loadSourceData()
  ]);
  if(a.error) console.warn("Cutting CB actions view unavailable",a.error);
  else state.actions = a.data || [];
  scheduleDecorate();
}

function injectStyles(){
  if($("rrCuttingCbActionStyles")) return;
  const style = document.createElement("style");
  style.id = "rrCuttingCbActionStyles";
  style.textContent = `
    .rr-cba-panel{border:1px solid #5b4045!important;background:linear-gradient(145deg,#21171a,#15151a)!important}
    .rr-cba-head{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap}
    .rr-cba-head h3,.rr-cba-head p{margin:0}.rr-cba-head p{color:#aaa;margin-top:5px}
    .rr-cba-buttons{display:flex;gap:7px;flex-wrap:wrap;margin-top:12px}.rr-cba-buttons button{min-height:42px;border-radius:11px;padding:0 12px;font-weight:900}
    .rr-cba-danger{background:#4b1d24;color:#ffc1c8;border:1px solid #8c3d49}.rr-cba-warn{background:#4a3815;color:#ffe2a0;border:1px solid #8b6a27}
    .rr-cba-list{display:grid;gap:8px;margin-top:12px}.rr-cba-item{padding:11px;border:1px solid #34343d;border-radius:12px;background:#101015}
    .rr-cba-item-head{display:flex;justify-content:space-between;gap:8px}.rr-cba-item small{color:#aaa}.rr-cba-status{display:inline-flex;padding:4px 7px;border-radius:999px;background:#282831;border:1px solid #4b4b56;font-size:10px;font-weight:900}
    .rr-cba-proof{display:flex;gap:7px;overflow:auto;margin-top:8px}.rr-cba-proof img,.rr-cba-proof video{width:86px;height:86px;object-fit:cover;border-radius:9px;background:#08080a}
    .rr-cba-actions{display:flex;gap:6px;flex-wrap:wrap;margin-top:9px}.rr-cba-actions button{min-height:34px;padding:0 9px;border-radius:9px;font-size:11px;font-weight:900}
    .rr-cba-blocked{margin-top:10px;padding:10px;border:1px solid #a23e4a;border-radius:11px;background:#401b21;color:#ffd0d5;font-weight:900}
    .rr-cba-sheet{position:fixed;inset:0;z-index:30000;isolation:isolate}.rr-cba-backdrop{position:absolute;inset:0;background:rgba(0,0,0,.76)}
    .rr-cba-dialog{position:absolute;right:0;top:0;bottom:0;width:min(680px,100%);overflow:auto;background:#0d0d11;border-left:1px solid #444;padding:16px}
    .rr-cba-dialog header{display:flex;justify-content:space-between;gap:10px;align-items:flex-start;position:sticky;top:-16px;background:#0d0d11;padding:16px 0 12px;z-index:2;border-bottom:1px solid #292932}
    .rr-cba-dialog h2{margin:0}.rr-cba-close{width:42px;height:42px;border-radius:11px;border:1px solid #65404a;background:#351a20;color:#ffd0d5;font-size:24px}
    .rr-cba-form{display:grid;gap:11px;margin-top:12px}.rr-cba-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:9px}.rr-cba-form label span{display:block;font-size:12px;color:#bbb;margin-bottom:5px;font-weight:800}
    .rr-cba-form input,.rr-cba-form select,.rr-cba-form textarea{width:100%;padding:11px;border-radius:11px;border:1px solid #3a3a44;background:#101014;color:#fff}
    .rr-cba-summary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:7px}.rr-cba-summary div{padding:9px;border:1px solid #33333d;border-radius:10px;background:#111116}.rr-cba-summary small,.rr-cba-summary strong{display:block}
    .rr-cba-submit{display:flex;justify-content:flex-end;gap:8px;position:sticky;bottom:-16px;background:#0d0d11;padding:12px 0 0}
    .rr-cba-proof-picker{padding:11px;border:1px solid #34343d;border-radius:12px;background:#101015}
    .rr-cba-proof-picker>span{display:block;font-size:12px;color:#bbb;margin-bottom:7px;font-weight:800}
    .rr-cba-proof-picker input[type=file]{padding:9px;background:#17171d}
    .rr-cba-draft-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;margin-top:9px}
    .rr-cba-draft-item{position:relative;min-width:0;padding:7px;border:1px solid #3a3a44;border-radius:11px;background:#0b0b0f}
    .rr-cba-draft-item img,.rr-cba-draft-item video{display:block;width:100%;aspect-ratio:1/1;object-fit:cover;border-radius:8px;background:#050507}
    .rr-cba-draft-item video{aspect-ratio:16/10}
    .rr-cba-draft-item small{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;margin-top:5px;color:#bbb}
    .rr-cba-remove-proof{position:absolute;right:3px;top:3px;width:32px;height:32px;border:1px solid #a84a59;border-radius:999px;background:#481b23;color:#fff;font-size:20px;font-weight:900;line-height:1;z-index:2}
    .rr-cba-proof-count{margin-top:7px;color:#aaa;font-size:11px}
    @media(max-width:620px){.rr-cba-grid,.rr-cba-summary{grid-template-columns:1fr}.rr-cba-draft-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
  `;
  document.head.appendChild(style);
}

function sourceRowsForActive(){
  const card = activeCard();
  const cbId = textKey(state.current?.cbId || activeCbId());
  const divisionId = textKey(state.current?.divisionId || activeDivisionId());
  const divisionCode = canonicalDivisionCode(
    card?.division?.division_code ||
    card?.division?.cb_code ||
    card?.division?.child_code ||
    ""
  );

  const cbRows = state.sources.filter(row => textKey(row.cb_id) === cbId);
  const exactRows = cbRows.filter(row => textKey(row.division_id) === divisionId);
  if(exactRows.length) return exactRows;

  const codeRows = cbRows.filter(row =>
    divisionCode && canonicalDivisionCode(row.division_code) === divisionCode
  );
  if(codeRows.length) return codeRows;

  const unscopedRows = cbRows.filter(row =>
    !textKey(row.division_id) && !textKey(row.division_code)
  );
  if(unscopedRows.length) return unscopedRows;

  console.warn("No source bill rows matched active Cutting card",{
    cbId,
    divisionId,
    divisionCode,
    cbSourceRows:cbRows.length
  });
  return [];
}

function uniquePurchases(rows){
  const map = new Map();
  rows.forEach(x => {if(!map.has(String(x.purchase_entry_id))) map.set(String(x.purchase_entry_id),x)});
  return [...map.values()];
}


function proofFileKey(file){
  return [file?.name || "", file?.size || 0, file?.lastModified || 0].join(":");
}

function proofMimeType(file){
  try{
    const inferred = window.RR?.inferMimeType?.(file);
    if(inferred) return String(inferred).toLowerCase();
  }catch{}
  const declared = String(file?.type || "").toLowerCase();
  if(declared) return declared;
  const ext = String(file?.name || "").split(".").pop().toLowerCase();
  return ({jpg:"image/jpeg",jpeg:"image/jpeg",png:"image/png",webp:"image/webp",heic:"image/heic",heif:"image/heif",mp4:"video/mp4",mov:"video/quicktime",webm:"video/webm","3gp":"video/3gpp"})[ext] || "";
}

function releaseProofDraftUrls(){
  (state.proofDraft.urls || []).forEach(url => {
    try{URL.revokeObjectURL(url)}catch{}
  });
  state.proofDraft.urls = [];
}

function resetProofDraft(){
  releaseProofDraftUrls();
  state.proofDraft.images = [];
  state.proofDraft.video = null;
}

function closeReportSheet({force=false}={}){
  if(state.reportSubmitting && !state.reportCommitted && !force){
    const message = $("rrCbaMessage");
    if(message){
      message.textContent = "Report save हो रही है। कृपया पूरा होने तक प्रतीक्षा करें।";
      message.className = "rr-message info";
    }
    return;
  }
  const sheet = $("rrCbActionSheet");
  if(sheet) sheet.classList.add("cm-hidden");
  resetProofDraft();
  state.reportSubmitting = false;
  state.reportCommitted = false;
}

function addDraftImages(files){
  const incoming = [...(files || [])].filter(file => proofMimeType(file).startsWith("image/"));
  const map = new Map(state.proofDraft.images.map(file => [proofFileKey(file), file]));
  incoming.forEach(file => map.set(proofFileKey(file), file));
  const next = [...map.values()];
  if(next.length > 5){
    throw new Error("Maximum 5 images allowed.");
  }
  state.proofDraft.images = next;
}

function setDraftVideo(file){
  if(file && !proofMimeType(file).startsWith("video/")){
    throw new Error("Video file select करें।");
  }
  state.proofDraft.video = file || null;
}

function renderProofDraft(){
  releaseProofDraftUrls();
  const imageHolder = $("rrCbaImagePreview");
  const videoHolder = $("rrCbaVideoPreview");
  const imageCount = $("rrCbaImageCount");
  if(imageCount) imageCount.textContent = `${state.proofDraft.images.length}/5 images selected`;

  if(imageHolder){
    imageHolder.innerHTML = state.proofDraft.images.map((file,index) => {
      const url = URL.createObjectURL(file);
      state.proofDraft.urls.push(url);
      return `<article class="rr-cba-draft-item"><button class="rr-cba-remove-proof" type="button" data-remove-image="${index}" aria-label="Remove image">×</button><img src="${safe(url)}" alt="Selected proof image"><small>${safe(file.name)}</small></article>`;
    }).join("");
    imageHolder.querySelectorAll("[data-remove-image]").forEach(button => {
      button.onclick = () => {
        state.proofDraft.images.splice(Number(button.dataset.removeImage),1);
        renderProofDraft();
      };
    });
  }

  if(videoHolder){
    const file = state.proofDraft.video;
    if(!file){
      videoHolder.innerHTML = "";
    }else{
      const url = URL.createObjectURL(file);
      state.proofDraft.urls.push(url);
      videoHolder.innerHTML = `<article class="rr-cba-draft-item"><button class="rr-cba-remove-proof" type="button" data-remove-video aria-label="Remove video">×</button><video controls preload="metadata" src="${safe(url)}"></video><small>${safe(file.name)}</small></article>`;
      videoHolder.querySelector("[data-remove-video]").onclick = () => {
        state.proofDraft.video = null;
        const input = $("rrCbaVideo");
        if(input) input.value = "";
        renderProofDraft();
      };
    }
  }
}

function bindProofDraftInputs(){
  const images = $("rrCbaImages");
  const video = $("rrCbaVideo");
  if(images){
    images.onchange = () => {
      try{
        addDraftImages(images.files);
        images.value = "";
        $("rrCbaMessage").textContent = "";
        renderProofDraft();
      }catch(error){
        images.value = "";
        $("rrCbaMessage").textContent = errorText(error);
        $("rrCbaMessage").className = "rr-message error";
      }
    };
  }
  if(video){
    video.onchange = () => {
      try{
        setDraftVideo(video.files?.[0] || null);
        $("rrCbaMessage").textContent = "";
        renderProofDraft();
      }catch(error){
        video.value = "";
        $("rrCbaMessage").textContent = errorText(error);
        $("rrCbaMessage").className = "rr-message error";
      }
    };
  }
  renderProofDraft();
}

function currentActionLabel(type){
  if(type === "DAMAGE") return "Damage Report";
  if(type === "PARTIAL_GR") return "Partial GR Report";
  return "Full GR Report";
}

async function openReport(type){
  const card = activeCard();
  if(!card){say("पहले Cutting D-card खोलें।","error");return}
  const lotNo = lotNoFromForm();
  if(!lotNo){say("पहले Manual Lot No भरें, फिर Damage / GR report करें।","error");return}
  state.current = {type,cbId:activeCbId(),divisionId:activeDivisionId(),lotNo};

  renderReportSheet();
  loadSourceData({ensureActive:true}).then(() => {
    if($("rrCbActionSheet")?.classList.contains("cm-hidden")) return;
    if(state.current?.type !== type) return;
    renderReportSheet();
  }).catch(error => console.warn("Damage / GR source refresh warning",error));
}

function ensureReportSheet(){
  let sheet = $("rrCbActionSheet");
  if(sheet) return sheet;
  sheet = document.createElement("section");
  sheet.id = "rrCbActionSheet";
  sheet.className = "rr-cba-sheet cm-hidden";
  sheet.innerHTML = `
    <div class="rr-cba-backdrop" data-cba-close></div>
    <div class="rr-cba-dialog" role="dialog" aria-modal="true">
      <header><div><small style="color:#ff7b86;font-weight:900">CUTTING MASTER REPORT</small><h2 id="rrCbaTitle">Damage / GR</h2><p id="rrCbaContext" style="color:#aaa;margin:5px 0 0"></p></div><button class="rr-cba-close" type="button" data-cba-close>×</button></header>
      <form id="rrCbaForm" class="rr-cba-form">
        <div id="rrCbaBody"></div>
        <p id="rrCbaMessage" class="rr-message"></p>
        <div class="rr-cba-submit"><button class="cm-secondary" type="button" data-cba-close>Cancel</button><button id="rrCbaSave" class="cm-primary" type="submit">Save Report</button></div>
      </form>
    </div>`;
  document.body.appendChild(sheet);
  sheet.querySelectorAll("[data-cba-close]").forEach(x => x.onclick = closeReportSheet);
  $("rrCbaForm").addEventListener("submit",submitReport);
  return sheet;
}

function renderReportSheet(){
  const sheet = ensureReportSheet();
  state.reportSubmitting = false;
  state.reportCommitted = false;
  resetProofDraft();
  const card = activeCard();
  const rows = sourceRowsForActive();
  const purchases = uniquePurchases(rows);
  const type = state.current.type;
  $("rrCbaTitle").textContent = currentActionLabel(type);
  $("rrCbaContext").textContent = `${card.group.cb_no} · ${card.division.division_code || card.division.cb_code || "D"} · Lot ${state.current.lotNo}`;
  const purchaseOptions = purchases
    .filter(p => textKey(p.purchase_entry_id))
    .map(p => `<option value="${safe(p.purchase_entry_id)}">${safe(p.bill_no)} · ${safe(p.vendor_name)} · ${safe(p.fabric_name)} · ${kg(p.division_available_qty)}</option>`)
    .join("");
  const sourceBillNotice = type !== "FULL_GR" && !purchaseOptions
    ? `<p class="rr-message error" style="margin:10px 0 0">इस D card के लिए Source Bill allocation नहीं मिला। Product Master में इसी CB के Bill और D allocation को check करें।</p>`
    : "";
  $("rrCbaBody").innerHTML = `
    <section class="cm-form-card">
      <div class="rr-cba-summary">
        <div><small>CB</small><strong>${safe(card.group.cb_no)}</strong></div>
        <div><small>Division</small><strong>${safe(card.division.division_code || card.division.cb_code || "D")}</strong></div>
        <div><small>Lot No.</small><strong>${safe(state.current.lotNo)}</strong></div>
      </div>
      <div class="rr-cba-grid" style="margin-top:11px">
        ${type === "FULL_GR" ? `<label><span>Full GR Scope *</span><select id="rrCbaScope"><option value="DIVISION">Current D Card / Set</option><option value="CB">Entire CB Number</option></select></label>` : `<label><span>Source Bill *</span><select id="rrCbaPurchase"><option value="">Select Bill</option>${purchaseOptions}</select></label><label><span>Roll / Colour *</span><select id="rrCbaRoll"><option value="">Select source bill first</option></select></label>`}
        <label><span>Qty *</span><input id="rrCbaQty" type="number" min="0.001" step="0.001" ${type === "FULL_GR" ? "readonly" : ""}></label>
        <label><span>Reason *</span><input id="rrCbaReason" placeholder="Damage / return reason"></label>
        <label><span>Admin WhatsApp No.</span><input id="rrCbaAdminPhone" inputmode="tel" value="${safe(adminPhoneDefault())}"></label>
        <div class="rr-cba-proof-picker"><span>Images — max 5</span><input id="rrCbaImages" type="file" accept="image/*" multiple><div id="rrCbaImageCount" class="rr-cba-proof-count">0/5 images selected</div><div id="rrCbaImagePreview" class="rr-cba-draft-grid"></div></div>
        <div class="rr-cba-proof-picker"><span>Short Video / Screen Recording — 1</span><input id="rrCbaVideo" type="file" accept="video/mp4,video/webm,video/quicktime,video/*"><div id="rrCbaVideoPreview" class="rr-cba-draft-grid"></div></div>
      </div>
      ${type !== "DAMAGE" ? `<label style="display:flex;gap:8px;align-items:center;margin-top:10px"><input id="rrCbaExchange" type="checkbox" style="width:auto"><span style="margin:0">Exchange / replacement expected</span></label>` : ""}
      <label style="margin-top:10px"><span>Remarks</span><textarea id="rrCbaRemarks" rows="2"></textarea></label>
      <label style="display:flex;gap:8px;align-items:center;margin-top:10px"><input id="rrCbaSendAdmin" type="checkbox" checked style="width:auto"><span style="margin:0">Save के बाद Admin WhatsApp खोलें</span></label>
      ${sourceBillNotice}
      <p style="color:#aaa;line-height:1.45">यह report stock या costing को तुरंत नहीं बदलेगी। Admin verification और Owner approval के बाद ही Product Master ledger, CB quantity और cost पर effect आएगा।</p>
    </section>`;

  if(type === "FULL_GR"){
    const updateFull = () => {
      const scope = $("rrCbaScope").value;
      const unique = new Map();
      const allRows = scope === "CB" ? state.sources.filter(x => String(x.cb_id) === state.current.cbId) : rows;
      allRows.forEach(x => unique.set(`${x.purchase_entry_id}:${x.division_id || x.division_code}`,x));
      $("rrCbaQty").value = [...unique.values()].reduce((s,x) => s + Number(x.division_available_qty || 0),0).toFixed(3);
    };
    $("rrCbaScope").onchange = updateFull;
    updateFull();
  }else{
    $("rrCbaPurchase").onchange = () => {
      const pid = $("rrCbaPurchase").value;
      const pr = purchases.find(x => String(x.purchase_entry_id) === String(pid));
      const rollRows = rows.filter(x => String(x.purchase_entry_id) === String(pid) && x.roll_id);
      $("rrCbaRoll").innerHTML = `<option value="">Select Roll / Colour</option>` + rollRows.map(r => `<option value="${safe(r.roll_id)}" data-max="${Number(r.roll_available_qty || 0)}">${safe(r.colour_name || "Colour")} · Roll ${safe(r.roll_no)} · ${kg(r.roll_available_qty)}</option>`).join("");
      $("rrCbaQty").max = Number(pr?.division_available_qty || 0);
    };
    $("rrCbaRoll").onchange = () => {
      const opt = $("rrCbaRoll").selectedOptions[0];
      if(opt?.dataset.max) $("rrCbaQty").max = opt.dataset.max;
    };
  }
  bindProofDraftInputs();
  $("rrCbaMessage").textContent = "";
  sheet.classList.remove("cm-hidden");
}

function actionSourcePurchaseId(action={}){
  return String(action.purchase_entry_id || action.cb_purchase_entry_id || action.source_purchase_entry_id || "");
}

function actionSourceRollId(action={}){
  return String(action.roll_id || action.purchase_roll_id || action.source_roll_id || "");
}

function pendingDuplicateFor(payload){
  const liveStatuses = new Set(["PENDING_ADMIN","ADMIN_MESSAGE_SENT","ADMIN_VERIFIED","RECHECK_REQUIRED"]);
  const reason = String(payload.p_reason || "").trim().toLowerCase();
  const lotNo = String(payload.p_lot_no || "").trim().toUpperCase();
  const qty = Number(payload.p_qty || 0);
  return state.actions.find(action =>
    liveStatuses.has(String(action.status || "").toUpperCase()) &&
    String(action.division_id || "") === String(payload.p_division_id || "") &&
    String(action.action_type || "").toUpperCase() === String(payload.p_action_type || "").toUpperCase() &&
    String(action.source_lot_no || "").trim().toUpperCase() === lotNo &&
    actionSourcePurchaseId(action) === String(payload.p_purchase_entry_id || "") &&
    actionSourceRollId(action) === String(payload.p_roll_id || "") &&
    String(action.full_gr_scope || "") === String(payload.p_full_gr_scope || "") &&
    Math.abs(Number(action.qty || 0) - qty) < 0.0005 &&
    String(action.reason || "").trim().toLowerCase() === reason
  ) || null;
}

async function uploadProof(action,images,video){
  if((images.length || video) && !window.RR?.uploadMedia) throw new Error("real-common.js uploadMedia unavailable.");
  if(images.length > 5) throw new Error("Maximum 5 images allowed.");
  const files = [...images.map(file => ({file,type:"IMAGE"})), ...(video ? [{file:video,type:"VIDEO"}] : [])];
  for(const item of files){
    const result = await RR.uploadMedia({
      file:item.file,entityType:"cutting-action",entityId:String(action.id),
      mediaCategory:"damage",sourceType:"gallery",visibilityScope:"factory",
      caption:`Cutting Action ${action.action_no} · ${action.source_lot_no}`
    });
    const media = result?.data || result;
    if(!media?.id) throw new Error(`Proof upload failed: ${item.file.name}`);
    const attach = await state.client.rpc("rr_cutting_attach_cb_action_media_v1",{
      p_action_id:action.id,p_media_id:media.id,p_media_type:item.type,
      p_file_url:media.file_url || media.public_url || media.url || null,
      p_file_name:item.file.name
    });
    if(attach.error) throw attach.error;
  }
}

async function submitReport(event){
  event.preventDefault();
  if(state.reportSubmitting || state.reportCommitted) return;

  const button = $("rrCbaSave");
  const old = button.textContent;
  let committed = false;
  let action = null;

  try{
    const type = state.current.type;
    if(type !== "FULL_GR" && !$("rrCbaPurchase").value) throw new Error("Source Bill select करें।");
    if(type !== "FULL_GR" && !$("rrCbaRoll").value) throw new Error("Roll / Colour particular select करें।");

    const qty = Number($("rrCbaQty").value || 0);
    const reason = $("rrCbaReason").value.trim();
    if(qty <= 0) throw new Error("Qty required है।");
    if(!reason) throw new Error("Reason required है।");

    const payload = {
      p_cb_id:state.current.cbId,
      p_division_id:state.current.divisionId,
      p_action_type:type,
      p_purchase_entry_id:type === "FULL_GR" ? null : $("rrCbaPurchase").value || null,
      p_roll_id:type === "FULL_GR" ? null : $("rrCbaRoll").value || null,
      p_qty:qty,
      p_full_gr_scope:type === "FULL_GR" ? $("rrCbaScope").value : null,
      p_lot_no:state.current.lotNo,
      p_reason:reason,
      p_remarks:$("rrCbaRemarks").value.trim() || null,
      p_admin_phone:$("rrCbaAdminPhone").value.trim() || null,
      p_exchange_expected:Boolean($("rrCbaExchange")?.checked)
    };

    const duplicate = pendingDuplicateFor(payload);
    if(duplicate){
      throw new Error(`Same report Action-${duplicate.action_no} पहले से pending है। Duplicate Save नहीं किया गया।`);
    }

    const images = [...state.proofDraft.images];
    const video = state.proofDraft.video || null;
    const sendAdmin = Boolean($("rrCbaSendAdmin")?.checked && payload.p_admin_phone);

    state.reportSubmitting = true;
    button.disabled = true;
    button.textContent = "Saving…";

    const r = await state.client.rpc("rr_cutting_report_cb_action_v1",payload);
    if(r.error) throw r.error;

    action = r.data?.action || r.data;
    if(!action?.id) throw new Error("Report save हुआ लेकिन Action ID नहीं मिला।");

    committed = true;
    state.reportCommitted = true;
    button.textContent = "Saved";

    let proofWarning = "";
    try{
      await uploadProof(action,images,video);
    }catch(proofError){
      proofWarning = ` Proof upload warning: ${errorText(proofError)}.`;
    }

    await loadAddonData();
    let saved = state.actions.find(x => String(x.id) === String(action.id)) || action;
    let whatsappMessage = "";
    let whatsappWarning = "";

    if(sendAdmin){
      localStorage.setItem("redzed_admin_whatsapp",payload.p_admin_phone);
      whatsappMessage = messageWithProof(saved,r.data?.admin_message);
      const mark = await state.client.rpc("rr_cutting_mark_admin_message_sent_v1",{
        p_action_id:action.id,
        p_admin_phone:payload.p_admin_phone
      });
      if(mark.error){
        whatsappWarning = ` WhatsApp status update warning: ${errorText(mark.error)}.`;
      }else{
        await loadAddonData();
        saved = state.actions.find(x => String(x.id) === String(action.id)) || saved;
        whatsappMessage = messageWithProof(saved,r.data?.admin_message);
      }
    }

    closeReportSheet({force:true});
    renderLotActionPanel();

    const warnings = `${proofWarning}${whatsappWarning}`.trim();
    say(
      warnings
        ? `${currentActionLabel(type)} saved as Action-${action.action_no || ""}. दोबारा Save न करें.${warnings}`
        : `${currentActionLabel(type)} saved as Action-${action.action_no || ""}. Admin/Owner decision pending.`,
      warnings ? "error" : "success"
    );

    if(sendAdmin && whatsappMessage){
      // Async save के बाद mobile browser new-tab popup block कर सकता है.
      // First try a new tab; if blocked, use the same tab so the saved report is never submitted again.
      openWhatsapp(payload.p_admin_phone,whatsappMessage,{sameTabFallback:true});
    }
  }catch(error){
    console.error(error);
    if(committed){
      closeReportSheet({force:true});
      await loadAddonData();
      renderLotActionPanel();
      say(`Report save हो चुकी है। दोबारा Save न करें। ${errorText(error)}`,"error");
    }else{
      const message = $("rrCbaMessage");
      if(message){
        message.textContent = errorText(error);
        message.className = "rr-message error";
      }else{
        say(errorText(error),"error");
      }
    }
  }finally{
    state.reportSubmitting = false;
    if(!committed){
      state.reportCommitted = false;
      button.disabled = false;
      button.textContent = old;
    }
  }
}

function mediaHtml(action){
  const rows = Array.isArray(action.media) ? action.media : [];
  if(!rows.length) return "";
  return `<div class="rr-cba-proof">${rows.map(m => String(m.media_type).toUpperCase() === "IMAGE" ? `<a href="${safe(m.file_url)}" target="_blank"><img src="${safe(m.file_url)}" alt="Proof"></a>` : `<video controls preload="metadata" src="${safe(m.file_url)}"></video>`).join("")}</div>`;
}

function actionButtons(action){
  const out = [];
  if(!["REJECTED","CLOSED"].includes(action.status)) out.push(`<button class="cm-secondary" type="button" data-cba-admin-msg="${safe(action.id)}">WhatsApp Admin</button>`);
  if(roleCanAdmin() && ["PENDING_ADMIN","ADMIN_MESSAGE_SENT","RECHECK_REQUIRED"].includes(action.status)){
    out.push(`<button class="cm-primary" type="button" data-cba-admin="VERIFY" data-id="${safe(action.id)}">Admin Verify</button>`);
    out.push(`<button class="cm-secondary" type="button" data-cba-admin="RECHECK" data-id="${safe(action.id)}">Recheck</button>`);
    out.push(`<button class="rr-cba-danger" type="button" data-cba-admin="REJECT" data-id="${safe(action.id)}">Reject</button>`);
  }
  if(roleIsOwner() && action.status === "ADMIN_VERIFIED" && !action.effect_posted){
    out.push(`<button class="cm-primary" type="button" data-cba-owner="APPROVE" data-id="${safe(action.id)}">Owner Approve & Apply</button>`);
    out.push(`<button class="rr-cba-danger" type="button" data-cba-owner="REJECT" data-id="${safe(action.id)}">Owner Reject</button>`);
  }
  if(roleIsOwner() && action.effect_posted && ["OWNER_APPROVED","VENDOR_MESSAGE_SENT"].includes(action.status)){
    out.push(`<button class="rr-cba-warn" type="button" data-cba-vendor="${safe(action.id)}">Owner → Vendor WhatsApp</button>`);
  }
  return out.join("");
}

function renderLotActionPanel(){
  const form = $("lotForm");
  const card = activeCard();
  if(!form || !card || $("lotSheet")?.classList.contains("cm-hidden")) return;
  let panel = $("rrCuttingCbActionPanel");
  if(!panel){
    panel = document.createElement("section");
    panel.id = "rrCuttingCbActionPanel";
    panel.className = "cm-form-card rr-cba-panel";
    const anchor = form.querySelector(".cm-notes") || form.querySelector(".cm-sticky");
    form.insertBefore(panel,anchor);
  }
  const rows = actionsForDivision(activeDivisionId());
  const blocked = hasApprovedFullGr(activeDivisionId());
  const signature = JSON.stringify({
    divisionId: activeDivisionId(),
    lotNo: lotNoFromForm(),
    role: state.role,
    blocked,
    rows: rows.map(x => [x.id,x.status,x.effect_posted,x.qty,x.value_snapshot,(x.media||[]).length])
  });
  if(panel.dataset.signature === signature){bindPanelActions(panel);return}
  panel.dataset.signature = signature;
  panel.innerHTML = `
    <div class="rr-cba-head"><div><h3>Damage / GR Decision</h3><p>Entry Cutting Master से होगी। Product Master CB card में permanent ledger reflect होगा।</p></div><span class="rr-cba-status">${safe(state.role || "user")}</span></div>
    ${blocked ? `<div class="rr-cba-blocked">Full GR approved — यह D card आगे Lot release के लिए blocked है।</div>` : `<div class="rr-cba-buttons"><button class="rr-cba-warn" type="button" data-cba-report="DAMAGE">Report Damage</button><button class="cm-secondary" type="button" data-cba-report="PARTIAL_GR">Report Partial GR</button><button class="rr-cba-danger" type="button" data-cba-report="FULL_GR">Report Full GR</button></div>`}
    <div class="rr-cba-list">${rows.length ? rows.map(a => `<article class="rr-cba-item"><div class="rr-cba-item-head"><div><strong>Action-${safe(a.action_no)} · ${safe(statusText(a.action_type))}</strong><div><small>${safe(a.source_lot_no || "—")} · ${kg(a.qty)} · ${money(a.value_snapshot)}</small></div></div><span class="rr-cba-status">${safe(statusText(a.status))}</span></div><div style="margin-top:6px"><small>${safe(a.bill_no || "Full CB/D scope")} · ${safe(a.colour_name || "")} ${a.roll_no ? `Roll ${safe(a.roll_no)}` : ""} · ${safe(a.reason)}</small></div>${mediaHtml(a)}<div class="rr-cba-actions">${actionButtons(a)}</div></article>`).join("") : `<small style="color:#aaa">No Damage / GR report for this D card.</small>`}</div>`;
  bindPanelActions(panel);
}

function bindPanelActions(panel){
  panel.querySelectorAll("[data-cba-report]").forEach(b => b.onclick = () => openReport(b.dataset.cbaReport));
  panel.querySelectorAll("[data-cba-admin-msg]").forEach(b => b.onclick = () => sendAdmin(b.dataset.cbaAdminMsg));
  panel.querySelectorAll("[data-cba-admin]").forEach(b => b.onclick = () => adminDecision(b.dataset.id,b.dataset.cbaAdmin));
  panel.querySelectorAll("[data-cba-owner]").forEach(b => b.onclick = () => ownerDecision(b.dataset.id,b.dataset.cbaOwner));
  panel.querySelectorAll("[data-cba-vendor]").forEach(b => b.onclick = () => sendVendor(b.dataset.cbaVendor));
}

async function sendAdmin(id){
  const action = state.actions.find(x => String(x.id) === String(id));
  if(!action) return;
  const phone = action.admin_phone || adminPhoneDefault() || prompt("Admin WhatsApp number") || "";
  if(!phone) return;
  try{
    localStorage.setItem("redzed_admin_whatsapp",phone);
    openWhatsapp(phone,messageWithProof(action));
    const r = await state.client.rpc("rr_cutting_mark_admin_message_sent_v1",{p_action_id:id,p_admin_phone:phone});
    if(r.error) throw r.error;
    await loadAddonData();renderLotActionPanel();
  }catch(e){say(errorText(e),"error")}
}

async function adminDecision(id,decision){
  const note = prompt(`${decision} note / reason`) || "";
  const r = await state.client.rpc("rr_cutting_admin_decide_cb_action_v1",{p_action_id:id,p_action:decision,p_note:note || null});
  if(r.error){say(errorText(r.error),"error");return}
  await loadAddonData();renderLotActionPanel();say(`Admin ${decision.toLowerCase()} saved.`,"success");
}

async function ownerDecision(id,decision){
  const label = decision === "APPROVE" ? "Owner approval stock और costing पर apply करेगा। Continue?" : "इस report को reject करें?";
  if(!confirm(label)) return;
  const note = prompt("Owner note") || "";
  const r = await state.client.rpc("rr_cutting_owner_decide_cb_action_v1",{p_action_id:id,p_decision:decision,p_note:note || null});
  if(r.error){say(errorText(r.error),"error");return}
  document.querySelector("#lotSheet [data-close-lot]")?.click();
  await loadAddonData();
  await window.RRCuttingMasterPM?.refresh?.();
  say(decision === "APPROVE" ? "Owner approved. CB quantity और cost ledger update हो गया।" : "Owner rejected the report.","success");
}

async function sendVendor(id){
  const action = state.actions.find(x => String(x.id) === String(id));
  if(!action) return;
  const phone = action.vendor_phone || prompt("Vendor WhatsApp number") || "";
  if(!phone) return;
  const message = prompt("Vendor message",messageWithProof(action,action.vendor_message || "")) || "";
  if(!message) return;
  try{
    openWhatsapp(phone,message);
    const r = await state.client.rpc("rr_cutting_mark_cb_action_vendor_sent_v1",{p_action_id:id,p_vendor_phone:phone,p_vendor_message:message});
    if(r.error) throw r.error;
    await loadAddonData();renderLotActionPanel();
  }catch(e){say(errorText(e),"error")}
}

function decorateGallery(){
  document.querySelectorAll(".cm-card[data-division-id]").forEach(card => {
    const divisionId = card.dataset.divisionId;
    const rows = actionsForDivision(divisionId);
    const pending = rows.filter(x => ["PENDING_ADMIN","ADMIN_MESSAGE_SENT","ADMIN_VERIFIED","RECHECK_REQUIRED"].includes(x.status)).length;
    const full = hasApprovedFullGr(divisionId) || String(coreState().galleryRows?.find(x => String(x.division_id) === String(divisionId))?.operation_status || "") === "FULL_GR_CLOSED";
    const desiredText = full ? "FULL GR APPROVED · CUTTING BLOCKED" : (pending ? `${pending} Damage / GR decision pending` : "");
    let box = card.querySelector(".rr-cba-card-status");
    if(desiredText){
      if(!box){
        box = document.createElement("div");
        card.querySelector(".cm-actions")?.before(box);
      }
      const desiredClass = `rr-cba-card-status ${full ? "rr-cba-blocked" : ""}`.trim();
      if(box.className !== desiredClass) box.className = desiredClass;
      if(box.textContent !== desiredText) box.textContent = desiredText;
    }else if(box){
      box.remove();
    }
    if(full) card.querySelectorAll("[data-single],[data-multi],[data-release-lot]").forEach(b => {if(!b.disabled)b.disabled=true;b.title="Full GR approved"});
  });
}

function scheduleDecorate(){
  if(state.renderQueued) return;
  state.renderQueued = true;
  requestAnimationFrame(() => {
    state.renderQueued = false;
    decorateGallery();
    renderLotActionPanel();
  });
}

function bindReleaseGuard(){
  $("lotForm")?.addEventListener("submit",event => {
    const divisionId = activeDivisionId();
    if(!divisionId) return;
    if(hasBlockingPending(divisionId)){
      event.preventDefault();event.stopImmediatePropagation();
      say("Damage / GR report का Admin और Owner decision pending है। Final Lot release अभी blocked है।","error");
      return;
    }
    if(hasApprovedFullGr(divisionId)){
      event.preventDefault();event.stopImmediatePropagation();
      say("Full GR approved है। यह D card Lot release नहीं हो सकता।","error");
    }
  },true);
}

async function boot(){
  injectStyles();
  ensureReportSheet();
  state.client = getClient();
  if(!state.client){console.warn("V720.35 Cutting CB actions: Supabase client unavailable");return}
  await loadRole();
  await loadAddonData();
  bindReleaseGuard();
  const observer = new MutationObserver(scheduleDecorate);
  observer.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:["class","aria-hidden"]});
  scheduleDecorate();
  window.REAL_FACTORY_CUTTING_CB_ACTIONS = {refresh:loadAddonData,state:() => ({...state})};
}

if(document.readyState === "loading") document.addEventListener("DOMContentLoaded",boot);
else boot();
})();
