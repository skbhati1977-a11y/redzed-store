(() => {
  "use strict";
  const $ = (id) => document.getElementById(id), q = new URLSearchParams(location.search);
  const role = String(q.get("role") || "CUSTOMER").toUpperCase(), orderId = q.get("order") || "", batchId = q.get("batch") || "", chatId = q.get("chat") || "", shareToken = q.get("t") || q.get("c") || "";
  const money = (n) => "₹" + Number(n || 0).toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[c]);
  const refLabel = (kind, ref) => { const clean=String(ref||"").trim(),type=String(kind||"").toUpperCase(); return !clean ? type : new RegExp(`(^|\\s)${type}(\\s|$)`,`i`).test(clean) ? clean : `${type} ${clean}`; };
  const DEVICE_KEY = "rr_customer_device_v9592", SESSION_KEY = "rr_customer_secure_session_v9592";
  let order = null, doc = null, lines = [], chargesReady = false, customerProfile = {}, piChatSent = false, staffRpcClient = null, addLotTimer = null, addLotSeq = 0;

  function message(text, kind = "error") { const box = $("msg"),boot=$("jpegBootStatus"); if(box){box.textContent = text || "";box.className = `msg ${kind}`;} if(boot&&text)boot.textContent=text; }
  function friendlyError(error) { const raw = String(error?.message || error || "Action failed."); if(/Failed to fetch|NetworkError|Load failed|fetch/i.test(raw))return "Internet connection नहीं है। Connection आने के बाद दोबारा tap करें।"; if(/permission denied|jwt|valid distributor login|salesman\/admin/i.test(raw))return "Login session expire या access unavailable है। दोबारा login करके यही page खोलें।"; if(/column .* does not exist|relation .* does not exist|schema cache|undefined function/i.test(raw))return "Data mapping update incomplete है। Page reload करके फिर try करें।"; return raw; }
  function requireOnline() { if (navigator.onLine === false) throw Error("Internet connection नहीं है। Connection आने के बाद दोबारा tap करें।"); }
  async function runButton(id, task, options = {}) { const button = $(id); if (!button || button.dataset.busy === "1" || button.dataset.locked === "1") return; const old = button.textContent; button.dataset.busy = "1"; button.disabled = true; button.classList.add("busy"); button.textContent = options.busyText || "PLEASE WAIT…"; message(""); try { if (options.online) requireOnline(); await task(); } catch (error) { if (error?.name !== "AbortError") { console.error("TEST67 invoice action failed", error); message(friendlyError(error)); } } finally { button.dataset.busy = "0"; button.classList.remove("busy"); button.disabled = button.dataset.locked === "1"; button.textContent = button.dataset.locked === "1" ? (button.dataset.lockedLabel || "SENT ✓") : old; } }

  function renderPiChatState() { const button=$("sendChat"); if(!button)return; button.dataset.locked=piChatSent?"1":"0"; button.disabled=piChatSent; button.textContent=piChatSent?"LIVE PI LINKED TO CHAT ✓":"LINK LIVE PI TO REAL CHAT"; }

  function device() { let d = localStorage.getItem(DEVICE_KEY); if (!d) { const a = new Uint8Array(24); crypto.getRandomValues(a); d = [...a].map((b) => b.toString(16).padStart(2, "0")).join(""); localStorage.setItem(DEVICE_KEY, d); } return d; }
  function auth() { let s = null; try { s = JSON.parse(localStorage.getItem(SESSION_KEY) || "null"); } catch (_) {} if (!s?.session_token) throw Error("Valid distributor login required."); return { p_session_token: s.session_token, p_device_id: device() }; }
  async function rpc(name, args = {}) {
    if (role === "REDZED" && staffRpcClient) {
      const { data, error } = await staffRpcClient.rpc(name, args);
      if (error) throw error;
      return data;
    }
    return RF853.rpc(name, args);
  }
  function values(x) { const qty = Number(x.distributor_pi_qty ?? x.proposed_qty ?? x.requested_qty ?? x.quantity ?? x.qty ?? 0), purchase = Number(x.base_rate ?? x.purchase_rate ?? x.rate ?? 0), margin = Number(x.rate_enhancement ?? x.margin_amount ?? 0), grossRate = Number(x.sale_rate ?? (purchase + margin)), discount = Number(x.customer_discount ?? x.discount ?? x.discount_amount ?? 0), finalRate = Number(x.final_rate ?? x.final_customer_rate ?? (grossRate - discount)); return { qty, purchase, margin, grossRate, discount, finalRate, effectiveMargin: finalRate - purchase, amount: qty * finalRate }; }
  function staffPiEditable() { return role === "REDZED" && doc?.kind !== "CI" && (!doc?.ref || doc?.revision_open === true); }
  function canEditQty() { return (role === "DISTRIBUTOR" && doc?.kind !== "CI") || staffPiEditable(); }
  function chargeValues() { const c = doc?.charges || {}; return { valuePct:Number(c.value_pct || 0), freight:Number(c.freight || 0), other:Number(c.other || 0) }; }
  function readCharges() { return { valuePct:Number($("valuePct").value || 0), freight:Math.max(0,Number($("freightInput").value || 0)), other:Math.max(0,Number($("otherInput").value || 0)) }; }
  function statusLabel(status) { const value=String(status||"DRAFT").toUpperCase(); if(value==="WAITING_CONFIRMATION")return "PI SENT · CONFIRMATION OPTIONAL"; if(value==="CI_FINAL")return role==="REDZED"?"CI FINAL · SENT TO DISTRIBUTOR":"UPSTREAM CI RECEIVED · CUSTOMER PI READY"; return ({SUBMITTED:"REQUIREMENT RECEIVED",PI_PROPOSED:"PI READY",CONFIRMED:"PI CONFIRMED",PARTIAL_CONFIRMED:"PI PARTIALLY CONFIRMED",FINAL:"CUSTOMER CI FINAL",CLOSED:"CUSTOMER CI SENT",CANCELLED:"CANCELLED · PI RESTORED",DRAFT:"DRAFT"})[value]||value.replaceAll("_"," "); }

  function render() {
    let displayGross = 0, discount = 0, gross = 0, totalQty = 0; const staff = role === "REDZED";
    $("godownHead").classList.toggle("internal-only", !staff); $("sourceHead").classList.toggle("internal-only", !staff); $("actionHead").classList.toggle("internal-only", !staff); [$("discountHead"),$("discountLabel"),$("discount")].forEach((x)=>x.classList.toggle("internal-only",role!=="DISTRIBUTOR"));
    $("workingTitle").textContent = staff ? (doc?.kind === "CI" ? "REDZED CI / ALLOCATION SUMMARY" : "REDZED ALLOCATION / PI WORKING TABLE") : role === "DISTRIBUTOR" ? (doc?.kind === "CI" ? "CUSTOMER CI SUMMARY" : "DISTRIBUTOR CUSTOMER PI WORKING TABLE") : (doc?.kind === "CI" ? "CI DETAILS" : "PI DETAILS");
    $("workingHelp").textContent = staff ? (doc?.kind === "CI" ? `${refLabel("CI",doc?.ref)} distributor को भेजी जा चुकी है · CI final और read-only है ✓` : doc?.revision_open ? `${refLabel("PI",doc.ref)} · REVISION ${doc.revision_no || 2} खुली है। Qty, charges और direct lot बदलकर एक बार UPDATE & RESEND करें।` : doc?.ref ? `${refLabel("PI",doc.ref)} distributor को भेजी जा चुकी है और अब locked है ✓` : "Requested Qty original और locked है। Working PI Qty को available/frozen stock के अनुसार बदलें, charges/direct lot जोड़ें, फिर SAVE DRAFT या MAKE & SEND PI करें।") : role === "DISTRIBUTOR" ? (doc?.kind === "CI" ? `${refLabel("CI",doc?.ref)} customer के लिए final और read-only है ✓` : "Requested Qty और editable Customer PI Qty एक ही mapped line पर हैं।") : `${refLabel(doc?.kind||"PI",doc?.ref)} read-only document है।`;
    $("workingQtyHead").textContent = doc?.kind === "CI" ? "Final CI Qty" : staff ? "REDZED Working PI Qty" : "PI Qty";
    $("rows").innerHTML = lines.map((x, i) => { const v = values(x), source=x.is_extra?"DIRECT REDZED ADD-ON":(x.requirement_display_no || x.order_ref || "Requirement"); displayGross += v.qty * v.grossRate; discount += v.qty * v.discount; gross += v.amount; totalQty += v.qty; return `<tr><td data-label="S.No.">${i + 1}</td><td data-label="Pic">${x.image_url ? `<img class="pic" src="${esc(x.image_url)}" alt="">` : "👕"}</td><td data-label="Article / Lot"><b>${esc(x.lot_no || x.article_name || "-")}</b>${x.is_extra?'<small class="muted source-meta">Direct pieces</small>':''}</td><td data-label="Category">${esc(x.category || x.article_name || "-")}</td><td data-label="Size">${esc(x.size_text || x.size || "-")}</td>${staff ? `<td data-label="Source Requirement"><span><b>${esc(source)}</b>${x.is_extra?'':`<small class="muted source-meta">Private ref: ${esc(x.customer_ref || "hidden")}</small>`}</span></td>` : ""}<td data-label="Requested Qty"><b>${x.is_extra?"—":Number(x.requested_qty ?? x.quantity ?? x.qty ?? 0)}</b></td><td data-label="${doc?.kind === "CI" ? "Final CI Qty" : staff ? "Working PI Qty" : "PI Qty"}">${canEditQty() ? `<input class="num" data-qty="${esc(x.id)}" type="number" min="${x.is_extra?1:0}" value="${v.qty}" aria-label="Working PI quantity for ${esc(x.lot_no || "line")}">` : v.qty}</td><td data-label="Rate">${money(role === "DISTRIBUTOR" ? v.grossRate : v.finalRate)}${role === "DISTRIBUTOR" ? `<small class="pricing-detail pricing-private">Purchase ${money(v.purchase)} + Margin ${money(v.margin)} · Effective margin ${money(v.effectiveMargin)}</small>` : ""}</td>${role === "DISTRIBUTOR" ? `<td data-label="Discount" class="pricing-private">${money(v.discount)}</td>` : ""}<td data-label="Net Rate">${money(v.finalRate)}</td><td data-label="Amount">${money(v.amount)}</td>${staff ? `<td data-label="Godown / Allocation" class="rr-godown-view-only">${esc(x.godown || x.stock_type || "—")}</td><td data-label="Action">${x.is_extra&&staffPiEditable()?`<button type="button" class="remove-extra" data-remove-extra="${esc(x.id)}">REMOVE</button>`:"—"}</td>` : ""}</tr>`; }).join("");
    $("rows").querySelectorAll("[data-remove-extra]").forEach((button)=>{button.onclick=()=>removeExtraLot(button.dataset.removeExtra);});
    const saved=chargeValues(), editable=(role==="DISTRIBUTOR"&&doc?.kind!=="CI")||staffPiEditable(); if(!chargesReady){[["valuePct",saved.valuePct],["freightInput",saved.freight],["otherInput",saved.other]].forEach(([id,v])=>{$(id).value=v;});chargesReady=true;} ["valuePct","freightInput","otherInput"].forEach((id)=>{$(id).readOnly=!editable;});
    $("addLotCard").classList.toggle("on",staffPiEditable());
    const c=readCharges(), valueAmount=gross*c.valuePct/100, raw=gross+valueAmount+c.freight+c.other, rounded=Math.round(raw/10)*10, round=rounded-raw;
    $("gross").textContent=money(gross); $("discount").textContent=money(discount); $("valueAmount").textContent=money(valueAmount); $("freight").textContent=money(c.freight); $("other").textContent=money(c.other); $("round").textContent=(round>=0?"+":"")+money(round); $("total").textContent=money(rounded); $("items").textContent=lines.length; $("qty").textContent=totalQty;
    $("party").value = order?.customer_name || doc?.customer_name || "Customer"; $("collection").value = order?.collection_display_no || doc?.collection_display_no || order?.batch_ref || "—"; $("collectionLabel").textContent=staff?(order?.batch_kind==="CONSOLIDATED"?"Mapped Requirements":"Mapped Source Requirement"):"Linked Collection";
    $("reqNo").textContent = order?.requirement_display_no || doc?.requirement_display_no || order?.batch_ref || "Requirement —"; $("docNo").textContent = (doc?.kind === "CI" ? "CI" : "PI") + " No. " + (doc?.ref || "DRAFT") + (doc?.kind!=="CI"&&Number(doc?.revision_no||1)>1?` · REV ${doc.revision_no}`:""); $("docTitle").textContent = doc?.kind === "CI" ? (order?.batch_kind === "CONSOLIDATED" ? "CONSOLIDATED CI" : "CI · COMMERCIAL INVOICE") : (order?.batch_kind === "CONSOLIDATED" ? "CONSOLIDATED PI" : "PI · PROFORMA INVOICE");
    $("status").value = doc?.revision_open?`PI REVISION ${doc.revision_no||2} · EDITABLE`:statusLabel(doc?.status); $("docDate").textContent = new Date(doc?.pushed_at || doc?.created_at || Date.now()).toLocaleString("en-IN");
    const operator = ["DISTRIBUTOR", "REDZED"].includes(role), redzedPiSent = role === "REDZED" && doc?.kind !== "CI" && !!doc?.ref && !doc?.revision_open;
    $("saveDraft").hidden = role!=="REDZED" || !staffPiEditable(); $("savePi").hidden = !operator || doc?.kind === "CI"; $("savePi").dataset.locked=redzedPiSent?"1":"0"; $("savePi").dataset.lockedLabel=redzedPiSent?`${refLabel("PI",doc.ref)} · SENT ✓`:""; $("savePi").disabled=redzedPiSent; $("savePi").textContent=redzedPiSent?$("savePi").dataset.lockedLabel:role==="REDZED"?(doc?.ref?`UPDATE & RESEND REVISION ${doc.revision_no || 2}`:"MAKE & SEND PI TO DISTRIBUTOR"):(doc?.ref?"UPDATE LIVE PI":"SAVE & LINK PI"); $("sendChat").hidden = role!=="DISTRIBUTOR" || !doc?.ref; renderPiChatState(); $("convertCi").hidden = !operator || !doc?.ref || doc?.kind === "CI" || (role==="REDZED"&&doc?.revision_open); $("convertCi").textContent=role==="REDZED"?(order?.batch_kind==="CONSOLIDATED"?"CONVERT TO CONSOLIDATED CI":"CONVERT PI TO CI"):"CONVERT TO CUSTOMER CI · CONFIRMATION OPTIONAL"; $("cancelCi").hidden = !operator || doc?.kind !== "CI"; $("confirmationRule").hidden = !operator || doc?.kind === "CI"; $("download").hidden = !operator || !doc?.ref; $("share").hidden = !operator || !doc?.ref;
    if (role === "CUSTOMER" && doc?.ref && doc?.kind !== "CI") renderResponse();
    if (q.get("mode") === "jpeg") setTimeout(() => showJpegMode().catch((error) => message(friendlyError(error))), 0);
  }
  function renderResponse() { $("response").classList.add("on"); $("responseLines").innerHTML = lines.map((x) => { const v = values(x), d = x.decision || "WAITING", qty = x.customer_qty ?? v.qty; return `<div class="decision"><span><b>${esc(x.lot_no)}</b><small class="muted">${esc(x.category || "-")} · ${esc(x.size_text || "-")} · ${money(v.finalRate)}</small></span><select data-action="${esc(x.id)}"><option value="CONFIRM" ${d === "CONFIRM" ? "selected" : ""}>CONFIRM</option><option value="CHANGE" ${d === "CHANGE" ? "selected" : ""}>CHANGE</option><option value="CANCEL" ${d === "CANCEL" ? "selected" : ""}>CANCEL</option></select><input class="num" data-response-qty="${esc(x.id)}" type="number" min="0" value="${Number(qty || 0)}"></div>`; }).join(""); }

  function hideAddSuggestions() { $("addLotSuggestions").classList.remove("on"); $("addLotSuggestions").innerHTML=""; }
  async function searchAddLots() {
    const query=String($("addLot").value||"").trim(),seq=++addLotSeq;if(!query){hideAddSuggestions();return;}
    try{
      const result=await rpc("rr_ws_stock_search_v9411",{p_search:query,p_multi_lots:"",p_sort:"LOT_ASC",p_data_mode:"TEST"});if(seq!==addLotSeq)return;
      const rows=(Array.isArray(result)?result:[]).filter((x)=>Number(x.available_qty||0)>0).slice(0,20);
      $("addLotSuggestions").innerHTML=rows.length?rows.map((x)=>`<button type="button" class="lot-suggestion" data-lot-pick="${esc(x.lot_no)}"><b>${esc(x.lot_no)}</b><small>${esc(x.category||"-")} · ${esc(x.sizes||"-")} · AVL ${Number(x.available_qty||0)}</small></button>`).join(""):'<div class="muted" style="padding:10px">Sellable lot नहीं मिला।</div>';
      $("addLotSuggestions").classList.add("on");
    }catch(error){$("addMsg").textContent=friendlyError(error);hideAddSuggestions();}
  }
  function bindAddLotSearch(){
    $("addLot").addEventListener("input",()=>{clearTimeout(addLotTimer);addLotTimer=setTimeout(searchAddLots,180);});
    $("addLot").addEventListener("focus",()=>{if($("addLot").value.trim())searchAddLots();});
    $("addLotSuggestions").addEventListener("click",(event)=>{const pick=event.target.closest("[data-lot-pick]");if(!pick)return;$("addLot").value=pick.dataset.lotPick||"";hideAddSuggestions();$("addQty").focus();});
    document.addEventListener("click",(event)=>{if(event.target!==$("addLot")&&!$("addLotSuggestions").contains(event.target))hideAddSuggestions();});
  }
  async function addExtraLot(){
    if(!staffPiEditable())throw Error("PI revision is locked.");
    const lot=String($("addLot").value||"").trim(),qty=Math.floor(Number($("addQty").value||0));if(!lot||qty<=0)throw Error("Lot No. और positive Qty भरें।");
    await saveDraft();
    await rpc("rr_market_staff_pi_extra_lot_add_v67",{p_batch_id:order.id,p_lot_no:lot,p_qty:qty});
    $("addLot").value="";$("addQty").value="";hideAddSuggestions();chargesReady=false;await loadRedzed();render();message(`${lot.toUpperCase()} × ${qty} direct PI row added ✓`,"ok");
  }
  async function removeExtraLot(lineId){
    if(!staffPiEditable())return;
    try{
      await saveDraft();
      await rpc("rr_market_staff_pi_extra_lot_remove_v67",{p_batch_id:order.id,p_line_id:lineId});
      chargesReady=false;await loadRedzed();render();message("Direct PI row removed ✓","ok");
    }catch(error){message(friendlyError(error));}
  }

  async function loadDistributor() {
    const a = auth(), [w, p, charges, delivery] = await Promise.all([rpc("rr_market_partner_workspace_v67", a), rpc("rr_market_partner_customer_pi_state_v67", a),rpc("rr_market_partner_customer_pi_charges_get_v67",{...a,p_order_id:orderId}),rpc("rr_market_partner_pi_chat_status_v67",{...a,p_order_id:orderId})]);
    order = (w.orders || []).find((x) => String(x.id) === String(orderId)); if (!order) throw Error("Requirement unavailable.");
    const ps = (Array.isArray(p) ? p : []).find((x) => String(x.order_id) === String(orderId)); if (ps) { const m = new Map((ps.lines || []).map((x) => [String(x.id), x])); order.lines = (order.lines || []).map((x) => ({ ...x, ...(m.get(String(x.id)) || {}) })); }
    const piRef=ps?.distributor_pi_ref||order.distributor_pi_ref, piStatus=ps?.distributor_pi_status||order.distributor_pi_status, piPushed=ps?.distributor_pi_pushed_at||order.distributor_pi_pushed_at, ciRef=ps?.customer_ci_ref||"", ciVisible=ps?.customer_ci_visible??order.customer_ci_visible;
    lines = order.lines || []; piChatSent=delivery?.sent===true; doc = piRef ? { ref: piRef, status: piStatus || "WAITING", pushed_at: piPushed, kind: ciVisible && ciRef ? "CI" : "PI",charges } : { kind: "PI",charges }; if (doc.kind === "CI") doc.ref = ciRef;
  }
  async function loadRedzed() {
    if (!batchId) throw Error("Batch reference missing."); const detail = await rpc("rr_market_staff_batch_detail_v67", { p_batch_id: batchId });
    const sourceOrders=detail.orders||[], sourceCount=sourceOrders.length, sourceMapping=detail.batch_kind==="CONSOLIDATED"?`${sourceCount} source requirements · consolidated`:sourceOrders[0]?.requirement_display_no||`${sourceCount} source requirement`;
    order = { id: detail.id, batch_ref: detail.batch_ref, batch_kind: detail.batch_kind, customer_name: detail.direct_customer_name, requirement_display_no: detail.requirement_display_no || detail.batch_ref, collection_display_no: sourceMapping };
    lines = (detail.orders || []).flatMap((o) => (o.lines || []).map((x) => ({ ...x, order_ref: o.order_ref, requirement_display_no: o.requirement_display_no, customer_ref: o.customer_ref }))).concat((detail.extra_lines||[]).map((x)=>({...x,is_extra:true,requirement_display_no:"DIRECT REDZED ADD-ON"})));
    const revision={revision_no:Number(detail.pi_revision_no||1),revision_open:detail.pi_revision_open===true,charges:detail.charges||{}};
    doc = detail.ci_ref ? { kind: "CI", ref: detail.ci_ref, status: detail.status,...revision } : detail.pi_ref ? { kind: "PI", ref: detail.pi_ref, status: detail.status,...revision } : { kind: "PI", status: detail.status,...revision };
    const lots = [...new Set(lines.map((x) => x.lot_no).filter(Boolean))]; const locations = await Promise.all(lots.map(async (lot) => [lot, await rpc("rr_pi_staff_godown_v67", { p_lot_no: lot })]));
    const byLot = new Map(locations); lines.forEach((x) => { x.godown = byLot.get(x.lot_no) || "—"; });
  }
  async function loadCustomer() { doc = await rpc("rr_market_partner_customer_invoice_view_v67", { p_token: shareToken }); if (!doc) throw Error("PI अभी उपलब्ध नहीं है।"); doc.charges=doc.charges||{}; lines = doc.lines || []; order = { customer_name: "Customer", requirement_display_no: doc.requirement_display_no, collection_display_no: doc.collection_display_no }; }
  async function loadUpstream() { if(!batchId)throw Error("Mapped REDZED batch missing.");const detail=await rpc("rr_market_partner_batch_invoice_view_v67",{...auth(),p_batch_id:batchId});doc={kind:detail.kind,ref:detail.ref,status:detail.status,created_at:detail.created_at,charges:detail.charges||{}};lines=detail.lines||[];order={customer_name:detail.party_name||"Distributor",requirement_display_no:detail.requirement_display_no,collection_display_no:detail.collection_display_no,batch_kind:"SINGLE"}; }
  function proposals() { return lines.map((x) => ({ line_id: x.id, proposed_qty: Math.max(0, Math.floor(Number(document.querySelector(`[data-qty="${CSS.escape(x.id)}"]`)?.value ?? values(x).qty))) })); }
  async function staffNotice(noticeBatchId) { if (!chatId) return; await rpc("rr_market_staff_batch_chat_upsert_v67", { p_chat_id: chatId, p_batch_id: noticeBatchId }); }

  async function imageData(url) { if (!url) return null; try { const blob=await (await fetch(url)).blob(); return await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=reject;r.readAsDataURL(blob);}); } catch (_) { return null; } }
  async function packingRows(){return Promise.all(lines.map(async(x)=>{let c={};try{c=await rpc("rr_pi_lot_context_v9517",{p_lot_no:x.lot_no,p_customer_name:order?.customer_name||"",p_data_mode:"TEST"});customerProfile={...customerProfile,...c};}catch(_){}return {...x,image_url:c.image||x.image_url,size_text:c.size_text||c.size||x.size_text,pack_pcs_per_box:Number(c.pack_pcs_per_box||0)};}));}
  function boxResult(qty,pack){if(!pack)return "—";const b=Math.floor(qty/pack),l=qty%pack;return `${b?`${b} BOX`:""}${b&&l?" + ":""}${l?`${l} LOOSE`:""}`||"—";}
  function boxSummary(rows){const m=new Map();let loose=0,total=0;rows.forEach(x=>{const q=values(x).qty,p=x.pack_pcs_per_box||0;total+=q;if(p){const b=Math.floor(q/p);if(b)m.set(p,(m.get(p)||0)+b);loose+=q%p;}else loose+=q;});return {lines:[...m].sort((a,b)=>b[0]-a[0]).map(([boxQty,count])=>({boxQty,count,pcs:boxQty*count})),loose,total};}
  async function showPreviewMode(){
    message("Latest PI grid तैयार हो रही है…","ok");
    const rows=await packingRows(),bs=boxSummary(rows),c=chargeValues();
    const gross=rows.reduce((sum,x)=>sum+values(x).amount,0),value=gross*c.valuePct/100,raw=gross+value+c.freight+c.other,total=Math.round(raw/10)*10,round=total-raw;
    const itemRows=rows.map((x,i)=>{const v=values(x);return `<tr><td>${i+1}</td><td>${x.image_url?`<img src="${esc(x.image_url)}" alt="">`:"—"}</td><td>${esc(x.category||x.item_name||x.article_name||"-")}</td><td>${esc(x.size_text||"-")}</td><td>${esc(x.lot_no||"-")}</td><td>${v.qty}</td><td>${money(v.finalRate)}</td><td>${money(v.amount)}</td><td>${boxResult(v.qty,x.pack_pcs_per_box)}</td></tr>`}).join("");
    const boxRows=bs.lines.map(x=>`<tr><td>${x.count}</td><td>${x.boxQty}</td><td>${x.count} Box</td><td>${x.pcs}</td></tr>`).join("")+`<tr><td>Loose</td><td>—</td><td>—</td><td>${bs.loose}</td></tr><tr><th>Total</th><td>—</td><td>—</td><th>${bs.total}</th></tr>`;
    document.body.innerHTML=`<main class="livePi"><h2>${esc(doc?.kind||"PI")} No: ${esc(doc?.ref||"DRAFT")}</h2><div class="party"><b>Party Name:</b> ${esc(order?.customer_name||"Customer")}<br><b>Created Date:</b> ${esc($("docDate")?.textContent||"—")}</div><table><thead><tr><th>Sr.</th><th>Image</th><th>Item Name</th><th>Size</th><th>Lot No.</th><th>QTY</th><th>Rate</th><th>Amount</th><th>Box Count</th></tr></thead><tbody>${itemRows}<tr><th colspan="5">Total</th><th>${bs.total}</th><td></td><th>${money(gross)}</th><td>—</td></tr></tbody></table><div class="summaries"><table><thead><tr><th colspan="4">QTY DETAILS</th></tr><tr><th>Box Count</th><th>Box Qty</th><th>Box Count (PCS)</th><th>TTL Qty</th></tr></thead><tbody>${boxRows}</tbody></table><table><thead><tr><th colspan="2">AMOUNT SUMMARY</th></tr></thead><tbody><tr><td>Grand Total Amount</td><th>${money(gross)}</th></tr><tr><td>Value Added (${c.valuePct}%)</td><td>${money(value)}</td></tr><tr><td>Freight</td><td>${money(c.freight)}</td></tr><tr><td>Other Charges</td><td>${money(c.other)}</td></tr><tr><td>Round Off</td><td>${money(round)}</td></tr><tr><th>Net Payable Amount</th><th>${money(total)}</th></tr></tbody></table></div><div class="grandLine"><b>Grand Total Items</b> ${rows.length} &nbsp; <b>Grand Total Qty (PCS)</b> ${bs.total}</div></main><style>*{box-sizing:border-box}body{margin:0;background:#fff;color:#111;font:10px Arial}.livePi{width:100%;padding:18px;background:#fff}.livePi h2{font-size:16px;margin:0 0 8px;border-bottom:1px solid #555;padding-bottom:7px}.party{line-height:1.5;margin-bottom:10px}table{width:100%;border-collapse:collapse;table-layout:fixed}th,td{border:1px solid #667;padding:4px;text-align:center;overflow-wrap:anywhere}thead th{background:#dcecf5}td img{display:block;width:100%;height:42px;object-fit:contain}.summaries{display:grid;grid-template-columns:1.5fr 1fr;gap:9px;margin-top:10px}.grandLine{border:1px solid #667;margin-top:9px;padding:6px}@media(max-width:420px){body{font-size:8px}.livePi{padding:10px}th,td{padding:3px}.summaries{gap:5px}}</style>`;
  }
  async function makePdf() {
    if (!window.jspdf?.jsPDF) throw Error("A4 PDF engine unavailable.");
    const pdf=new window.jspdf.jsPDF({orientation:"portrait",unit:"mm",format:"a4",compress:true}), rows=await packingRows(), pics=await Promise.all(rows.map(x=>imageData(x.image_url))), c=readCharges(), fmt=n=>Number(n||0).toLocaleString("en-IN",{maximumFractionDigits:2});
    pdf.setTextColor(0);pdf.setDrawColor(65);pdf.setFont("helvetica","bold");pdf.setFontSize(14);pdf.text(`${doc?.kind||"PI"} No: ${doc?.ref||"DRAFT"}`,14,15);pdf.line(14,19,196,19);pdf.setFontSize(8.8);let py=25;[["Party Name",$("party").value],["Mobile Number",customerProfile.mobile||customerProfile.customer_mobile||order?.customer_mobile||order?.mobile||"—"],["Created Date",$("docDate").textContent||"—"]].forEach(([k,v])=>{pdf.setFont("helvetica","bold");pdf.text(`${k}:`,14,py);pdf.setFont("helvetica","normal");pdf.text(String(v),41,py);py+=5;});
    const body=rows.map((x,i)=>{const v=values(x),itemName=x.category||x.item_name||x.cloth_name||x.article_name||"-";return [i+1,"",itemName,x.size_text||"-",x.lot_no||"-",fmt(v.qty),fmt(v.finalRate),fmt(v.amount),boxResult(v.qty,x.pack_pcs_per_box)];}),qty=rows.reduce((s,x)=>s+values(x).qty,0),gross=rows.reduce((s,x)=>s+values(x).amount,0),compact=rows.length>8;
    pdf.autoTable({startY:py+3,head:[["Sr. No.","Image","Item Name","Size","Lot No.","QTY","Rate","Amount","Box Count"]],body,foot:[[{content:"Total",colSpan:5,styles:{fontStyle:"bold",fillColor:[218,234,245]}},{content:fmt(qty),styles:{halign:"right",fontStyle:"bold",fillColor:[218,234,245]}},{content:"",styles:{fillColor:[218,234,245]}},{content:fmt(gross),styles:{halign:"right",fontStyle:"bold",fillColor:[218,234,245]}},{content:"—",styles:{halign:"center",fillColor:[218,234,245]}}]],theme:"grid",margin:{left:14,right:14},rowPageBreak:"avoid",styles:{fontSize:compact?6.2:7.1,fontStyle:"bold",cellPadding:compact?1:1.6,textColor:0,lineColor:65,lineWidth:.18,valign:"middle"},headStyles:{fillColor:[218,234,245],textColor:0,halign:"center"},columnStyles:{0:{cellWidth:10},1:{cellWidth:16},2:{cellWidth:36},3:{cellWidth:21},4:{cellWidth:21},5:{cellWidth:13,halign:"right"},6:{cellWidth:15,halign:"right"},7:{cellWidth:19,halign:"right"},8:{cellWidth:31,halign:"center"}},didParseCell:d=>{if(d.section==="body"&&d.column.index===1)d.cell.styles.minCellHeight=compact?11:16;},didDrawCell:d=>{if(d.section==="body"&&d.column.index===1&&pics[d.row.index])try{pdf.addImage(pics[d.row.index],"JPEG",d.cell.x+1,d.cell.y+1,d.cell.width-2,d.cell.height-2,undefined,"FAST");}catch(_){}}});
    let sy=(pdf.lastAutoTable?.finalY||py)+7;if(sy>225){pdf.addPage();sy=18;}const bs=boxSummary(rows),value=gross*c.valuePct/100,raw=gross+value+c.freight+c.other,total=Math.round(raw/10)*10,round=total-raw;
    const qr=[[{content:"QTY DETAILS",colSpan:5,styles:{fontStyle:"bold",halign:"center",fillColor:[218,234,245]}}],["Box Count","Box Qty (PCS)","Box Count (PCS)","TTL Qty (PCS)","Remarks"]];bs.lines.forEach(x=>qr.push([String(x.count),String(x.boxQty),`${x.count} Box`,fmt(x.pcs),""]));qr.push(["Loose","—","—",fmt(bs.loose),""]);qr.push(["Total","—","—",fmt(bs.total),""]);pdf.autoTable({startY:sy,body:qr,theme:"grid",margin:{left:14,right:78},tableWidth:118,styles:{fontSize:7.6,cellPadding:1.6,textColor:0,lineColor:65,lineWidth:.18}});const qe=pdf.lastAutoTable.finalY;
    const ar=[[{content:"AMOUNT SUMMARY",colSpan:2,styles:{fontStyle:"bold",halign:"center",fillColor:[218,234,245]}}],["Grand Total Amount",fmt(gross)],[`Value Added${c.valuePct?` (${fmt(c.valuePct)}%)`:""}`,fmt(value)],["Freight",fmt(c.freight)],["Other Charges",fmt(c.other)],["Round Off",fmt(round)],["Net Payable Amount",fmt(total)]];pdf.autoTable({startY:sy,body:ar,theme:"grid",margin:{left:138,right:14},tableWidth:58,styles:{fontSize:7.6,cellPadding:1.6,textColor:0,lineColor:65,lineWidth:.18},columnStyles:{0:{cellWidth:38},1:{cellWidth:20,halign:"right"}}});let by=Math.max(qe,pdf.lastAutoTable.finalY)+5;if(by>278){pdf.addPage();by=18;}pdf.autoTable({startY:by,body:[[{content:"Grand Total Items",styles:{fontStyle:"bold",fillColor:[218,234,245]}},String(rows.length),{content:"Grand Total Qty (PCS)",styles:{fontStyle:"bold",fillColor:[218,234,245]}},fmt(qty),"Remarks:"]],theme:"grid",margin:{left:14,right:14},tableWidth:182,styles:{fontSize:7.8,cellPadding:2,textColor:0,lineColor:65,lineWidth:.18},columnStyles:{0:{cellWidth:34},1:{cellWidth:18},2:{cellWidth:42},3:{cellWidth:18},4:{cellWidth:70}}});
    return pdf;
  }
  function pdfName(){return `${doc?.kind||"PI"}-${doc?.ref||"DRAFT"}.pdf`.replace(/[^a-z0-9_.-]+/gi,"-");}
  async function pdfAttachment(){const pdf=await makePdf(),blob=pdf.output("blob"),data_url=await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=reject;r.readAsDataURL(blob);});return {pdf,blob,data_url,name:pdfName(),type:"application/pdf"};}
  async function jpegAttachment(){
    if(!window.pdfjsLib)throw Error("PI JPEG preview engine unavailable.");
    const pdf=await makePdf(),data=pdf.output("arraybuffer");
    pdfjsLib.GlobalWorkerOptions.workerSrc="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js";
    const source=await pdfjsLib.getDocument({data:new Uint8Array(data)}).promise,pages=[];let width=0,height=0;
    for(let pageNo=1;pageNo<=source.numPages;pageNo++){
      const page=await source.getPage(pageNo),base=page.getViewport({scale:1}),scale=Math.max(1,900/base.width),viewport=page.getViewport({scale});
      pages.push({page,viewport});width=Math.max(width,Math.floor(viewport.width));height+=Math.floor(viewport.height);
    }
    const canvas=document.createElement("canvas");canvas.width=width;canvas.height=height;const context=canvas.getContext("2d",{alpha:false});context.fillStyle="#fff";context.fillRect(0,0,width,height);let top=0;
    for(const item of pages){await item.page.render({canvasContext:context,viewport:item.viewport,transform:[1,0,0,1,0,top]}).promise;top+=Math.floor(item.viewport.height);}
    const blob=await new Promise((resolve,reject)=>canvas.toBlob((value)=>value?resolve(value):reject(Error("PI JPEG preview create failed.")),"image/jpeg",.9));
    const data_url=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=reject;reader.readAsDataURL(blob);});
    return {blob,data_url,name:pdfName().replace(/\.pdf$/i,"-preview.jpg"),type:"image/jpeg"};
  }
  async function showJpegMode(){
    message("पूरी JPG तैयार हो रही है…","ok");
    const attachment=await jpegAttachment();
    const embedded=q.get("embed")==="1";
    document.body.innerHTML=`<main style="margin:0;min-height:100dvh;background:#fff;color:#fff">${embedded?"":`<div style="position:sticky;top:0;z-index:2;display:flex;align-items:center;gap:10px;padding:10px;background:#101722;border-bottom:1px solid #334155"><button id="jpegBack" style="padding:9px 13px;border:1px solid #53677f;border-radius:9px;background:#182535;color:#fff;font-weight:900">BACK</button><b style="flex:1">${esc(doc?.ref||"PI")} · COMPLETE JPG</b></div>`}<img src="${attachment.data_url}" alt="${esc(doc?.ref||"PI")}" style="display:block;width:100%;height:auto;background:#fff"></main>`;
    if(!embedded)document.getElementById("jpegBack").onclick=()=>history.back();
  }
  async function downloadPdf(){(await makePdf()).save(pdfName());message("A4 PDF download शुरू हुई ✓","ok");}
  async function sendRealChat(){requireOnline();if(piChatSent){renderPiChatState();return;}const a=auth(),attachment=await jpegAttachment(),result=await rpc("rr_market_partner_pi_chat_send_v67",{...a,p_order_id:order.id,p_attachment:{name:attachment.name,type:attachment.type,data_url:attachment.data_url}});piChatSent=!!result?.sent_at;renderPiChatState();message(result?.already_sent?`${doc.kind||"PI"} ${doc.ref} पहले ही Real Chat में भेजी जा चुकी है ✓`:`${doc.kind||"PI"} ${doc.ref} JPEG preview के साथ Real Chat में भेजी ✓`,"ok");}

  async function saveDraft() {
    if (role !== "REDZED") return;
    const payload=proposals(),c=readCharges(),r=await rpc("rr_market_staff_save_pi_working_v67",{p_batch_id:order.id,p_line_proposals:payload,p_value_pct:c.valuePct,p_freight:c.freight,p_other:c.other,p_send:false});
    lines.forEach((x)=>{x.proposed_qty=payload.find((y)=>y.line_id===x.id)?.proposed_qty;});
    doc.status=r.status;doc.charges={value_pct:c.valuePct,freight:c.freight,other:c.other,tax_pct:0};doc.revision_open=r.pi_revision_open===true;doc.revision_no=Number(r.pi_revision_no||doc.revision_no||1);message(`${r.requirement_display_no || "Requirement"} PI revision draft saved ✓`,"ok");render();
  }

  async function savePi() {
    try {
      if (role === "REDZED" && doc?.ref && !doc?.revision_open) {
        message(`${refLabel("PI", doc.ref)} पहले ही distributor को भेजी जा चुकी है ✓`, "ok");
        render();
        return;
      }
      if (role === "REDZED") { const payload = proposals(),c=readCharges(), r = await rpc("rr_market_staff_save_pi_working_v67", { p_batch_id: order.id, p_line_proposals: payload, p_value_pct:c.valuePct,p_freight:c.freight,p_other:c.other,p_send:true }); doc = { kind: "PI", ref: r.pi_ref, status: r.status, pushed_at: new Date().toISOString(),revision_no:Number(r.pi_revision_no||1),revision_open:r.pi_revision_open===true,charges:{value_pct:c.valuePct,freight:c.freight,other:c.other,tax_pct:0} }; lines.forEach((x) => { x.proposed_qty = payload.find((y) => y.line_id === x.id)?.proposed_qty; }); if (r.already_sent) { message(`${refLabel("PI", r.pi_ref)} पहले ही distributor को भेजी जा चुकी है ✓`, "ok"); render(); return; } await staffNotice(r.id); }
      else { const a = auth(), c=readCharges(), payload = lines.map((x) => ({ line_id: x.id, qty: Math.max(0, Math.floor(Number(document.querySelector(`[data-qty="${CSS.escape(x.id)}"]`)?.value ?? values(x).qty))) })); await rpc("rr_market_partner_customer_pi_charges_v67",{...a,p_order_id:order.id,p_value_pct:c.valuePct,p_freight:c.freight,p_other:c.other,p_tax_pct:0}); const r = await rpc("rr_market_partner_make_customer_pi_v67", { ...a, p_order_id: order.id, p_lines: payload, p_note: null }); doc = { kind: "PI", ref: r.distributor_pi_ref, status: r.distributor_pi_status || "WAITING", pushed_at: new Date().toISOString(),charges:{value_pct:c.valuePct,freight:c.freight,other:c.other,tax_pct:0} }; lines.forEach((x) => { x.distributor_pi_qty = payload.find((y) => y.line_id === x.id)?.qty; }); try { await sendRealChat(); } catch (e) { throw Error(`PI ${doc.ref} saved, but Real Chat delivery failed: ${e.message}`); } }
      message(`${refLabel("PI", doc.ref)} भेजी ✓`,"ok"); render();
    } catch (e) { throw e; }
  }
  async function convertCi() {
    try {
      if (role === "REDZED") { const r = await rpc("rr_market_staff_finalize_ci_v67", { p_batch_id: order.id, p_ci_ref: "" }); doc = { kind: "CI", ref: r.ci_ref, status: r.status, created_at: new Date().toISOString() }; await staffNotice(r.id); }
      else { const r = await rpc("rr_market_partner_convert_customer_ci_v67", { ...auth(), p_order_id: order.id }); doc = { kind: "CI", ref: r.customer_ci_ref, status: r.status || "FINAL", created_at: new Date().toISOString() }; }
      message(`${refLabel("CI", doc.ref)} generated ✓`,"ok"); render();
    } catch (e) { throw e; }
  }
  function askCancellationReason() {
    const dialog=$("cancelDialog"),form=$("cancelForm"),reason=$("cancelReason");
    return new Promise((resolve)=>{
      let selected=null,settled=false;
      const finish=()=>{if(settled)return;settled=true;resolve(selected);};
      form.onsubmit=(event)=>{event.preventDefault();const value=String(reason.value||"").trim();if(!value){reason.setCustomValidity("Cancellation reason required है।");reason.reportValidity();return;}reason.setCustomValidity("");selected=value;dialog.close("rollback");};
      $("keepCi").onclick=()=>dialog.close("keep");
      dialog.oncancel=(event)=>{event.preventDefault();dialog.close("keep");};
      dialog.addEventListener("close",finish,{once:true});
      $("cancelTitle").textContent=`Cancel ${refLabel("CI",doc?.ref)} · Rollback to PI`;
      reason.value="";
      dialog.showModal();
      setTimeout(()=>reason.focus(),50);
    });
  }
  async function cancelCi() {
    const reason=await askCancellationReason(); if(!reason)return;
    if(role==="REDZED"){
      const r=await rpc("rr_market_staff_cancel_ci_v67",{p_batch_id:order.id,p_reason:reason});
      doc={kind:"PI",ref:r.pi_ref,status:r.status,revision_no:Number(r.pi_revision_no||2),revision_open:r.pi_revision_open===true,charges:r.charges||{}};chargesReady=false; await loadRedzed();await staffNotice(r.id);
    }else{
      const r=await rpc("rr_market_partner_cancel_customer_ci_v67",{...auth(),p_order_id:order.id,p_reason:reason});
      doc={kind:"PI",ref:r.distributor_pi_ref,status:r.status}; piChatSent=false;
    }
    message("CI cancelled · latest PI restored ✓","ok"); render();
  }
  async function respond() { const decisions = lines.map((x) => ({ line_id: x.id, action: document.querySelector(`[data-action="${CSS.escape(x.id)}"]`).value, qty: Number(document.querySelector(`[data-response-qty="${CSS.escape(x.id)}"]`).value || 0) })), r = await rpc("rr_market_partner_customer_distributor_pi_response_v67", { p_token: shareToken, p_decisions: decisions, p_note: $("note").value || null }); message(`PI response ${r.distributor_pi_status} · distributor को भेजी ✓`,"ok"); }
  async function share() { const a=await pdfAttachment(),file=new File([a.blob],a.name,{type:a.type}); if(navigator.canShare?.({files:[file]})) await navigator.share({title:`${doc.kind||"PI"} ${doc.ref}`,files:[file]}); else {a.pdf.save(a.name);message("A4 PDF downloaded; Downloads से share करें।","ok");} }
  async function boot() { try { if (role === "DISTRIBUTOR") await loadDistributor(); else if (role === "REDZED") await loadRedzed(); else if(role === "UPSTREAM") await loadUpstream(); else await loadCustomer(); render(); bindAddLotSearch(); ["valuePct","freightInput","otherInput"].forEach((id)=>$(id).addEventListener("input",render)); $("rows").addEventListener("change",(event)=>{const input=event.target.closest?.("[data-qty]");if(!input)return;const line=lines.find((item)=>String(item.id)===String(input.dataset.qty));if(!line)return;const value=Math.max(line.is_extra?1:0,Math.floor(Number(input.value||0)));if(role==="REDZED")line.proposed_qty=value;else line.distributor_pi_qty=value;render();}); $("addRow").onclick=()=>runButton("addRow",addExtraLot,{online:true,busyText:"ADDING LOT…"}); $("saveDraft").onclick=()=>runButton("saveDraft",saveDraft,{online:true,busyText:"SAVING DRAFT…"}); $("savePi").onclick = ()=>runButton("savePi",savePi,{online:true,busyText:"SENDING PI…"}); $("sendChat").onclick=()=>runButton("sendChat",sendRealChat,{online:true,busyText:"SENDING…"}); $("convertCi").onclick = ()=>runButton("convertCi",convertCi,{online:true,busyText:"CREATING CI…"}); $("cancelCi").onclick = ()=>runButton("cancelCi",cancelCi,{online:true,busyText:"ROLLING BACK…"}); $("sendResponse").onclick = ()=>runButton("sendResponse",respond,{online:true,busyText:"SENDING…"}); $("download").onclick=()=>runButton("download",downloadPdf,{busyText:"MAKING PDF…"}); $("share").onclick = ()=>runButton("share",share,{busyText:"PREPARING…"}); window.addEventListener("offline",()=>message("Internet connection नहीं है। Real Chat और CI actions connection आने तक उपलब्ध नहीं हैं।")); window.addEventListener("online",()=>message("Internet connection वापस आ गया है। अब action दोबारा tap करें।","ok")); } catch (e) { console.error("TEST67 invoice boot failed",e); message(friendlyError(e)); } }
  async function authenticatedBoot() {
    if (role === "REDZED") {
      const client = await RF853.client();
      let session = (await client.auth.getSession()).data?.session || null;
      if (!session && typeof window.RRRefreshSupabaseSession === "function") session = await window.RRRefreshSupabaseSession(false);
      if (!session) {
        session = await new Promise((resolve) => {
          let finished = false;
          let subscription = null;
          let timer = null;
          const finish = (value) => {
            if (finished) return;
            finished = true;
            clearTimeout(timer);
            subscription?.unsubscribe?.();
            resolve(value || null);
          };
          const result = client.auth.onAuthStateChange((_event, value) => { if (value) finish(value); });
          subscription = result?.data?.subscription || null;
          timer = setTimeout(() => finish(null), 1200);
        });
      }
      if (!session?.access_token) {
        const next = `${location.pathname.split("/").pop()}${location.search}`;
        location.replace(`real-login.html?next=${encodeURIComponent(next)}`);
        return;
      }
      staffRpcClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
        global: { headers: { Authorization: `Bearer ${session.access_token}` } },
      });
    }
    await boot();
  }
  authenticatedBoot().catch((error) => message(friendlyError(error)));
})();
