(() => {
  "use strict";
  const $ = (id) => document.getElementById(id), q = new URLSearchParams(location.search);
  const role = String(q.get("role") || "CUSTOMER").toUpperCase(), orderId = q.get("order") || "", batchId = q.get("batch") || "", chatId = q.get("chat") || "", shareToken = q.get("t") || q.get("c") || "";
  const money = (n) => "₹" + Number(n || 0).toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[c]);
  const DEVICE_KEY = "rr_customer_device_v9592", SESSION_KEY = "rr_customer_secure_session_v9592";
  let order = null, doc = null, lines = [], chargesReady = false;

  function device() { let d = localStorage.getItem(DEVICE_KEY); if (!d) { const a = new Uint8Array(24); crypto.getRandomValues(a); d = [...a].map((b) => b.toString(16).padStart(2, "0")).join(""); localStorage.setItem(DEVICE_KEY, d); } return d; }
  function auth() { let s = null; try { s = JSON.parse(localStorage.getItem(SESSION_KEY) || "null"); } catch (_) {} if (!s?.session_token) throw Error("Valid distributor login required."); return { p_session_token: s.session_token, p_device_id: device() }; }
  async function rpc(name, args = {}) { return RF853.rpc(name, args); }
  function values(x) { const qty = Number(x.distributor_pi_qty ?? x.proposed_qty ?? x.requested_qty ?? x.quantity ?? x.qty ?? 0), purchase = Number(x.base_rate ?? x.purchase_rate ?? x.rate ?? 0), margin = Number(x.rate_enhancement ?? x.margin_amount ?? 0), grossRate = Number(x.sale_rate ?? (purchase + margin)), discount = Number(x.customer_discount ?? x.discount ?? x.discount_amount ?? 0), finalRate = Number(x.final_rate ?? x.final_customer_rate ?? (grossRate - discount)); return { qty, purchase, margin, grossRate, discount, finalRate, effectiveMargin: finalRate - purchase, amount: qty * finalRate }; }
  function canEditQty() { return (role === "DISTRIBUTOR" || role === "REDZED") && !doc?.ref; }
  function chargeValues() { const c = doc?.charges || {}; return { valuePct:Number(c.value_pct || 0), freight:Number(c.freight || 0), other:Number(c.other || 0) }; }
  function readCharges() { return { valuePct:Number($("valuePct").value || 0), freight:Math.max(0,Number($("freightInput").value || 0)), other:Math.max(0,Number($("otherInput").value || 0)) }; }

  function render() {
    let displayGross = 0, discount = 0, gross = 0, totalQty = 0; const staff = role === "REDZED";
    $("godownHead").classList.toggle("internal-only", !staff); [$("discountHead"),$("discountLabel"),$("discount")].forEach((x)=>x.classList.toggle("internal-only",role!=="DISTRIBUTOR"));
    $("rows").innerHTML = lines.map((x, i) => { const v = values(x); displayGross += v.qty * v.grossRate; discount += v.qty * v.discount; gross += v.amount; totalQty += v.qty; return `<tr><td>${i + 1}</td><td>${x.image_url ? `<img class="pic" src="${esc(x.image_url)}" alt="">` : "👕"}</td><td><b>${esc(x.lot_no || x.article_name || "-")}</b></td><td>${esc(x.category || x.article_name || "-")}</td><td>${esc(x.size_text || x.size || "-")}</td><td>${canEditQty() ? `<input class="num" data-qty="${esc(x.id)}" type="number" min="0" value="${v.qty}">` : v.qty}</td><td>${money(role === "DISTRIBUTOR" ? v.grossRate : v.finalRate)}${role === "DISTRIBUTOR" ? `<small class="pricing-detail pricing-private">Purchase ${money(v.purchase)} + Margin ${money(v.margin)} · Effective margin ${money(v.effectiveMargin)}</small>` : ""}</td>${role === "DISTRIBUTOR" ? `<td class="pricing-private">${money(v.discount)}</td>` : ""}<td>${money(v.finalRate)}</td><td>${money(v.amount)}</td>${staff ? `<td class="rr-godown-view-only">${esc(x.godown || "—")}</td>` : ""}</tr>`; }).join("");
    const saved=chargeValues(), editable=role==="DISTRIBUTOR"&&!doc?.ref; if(!chargesReady){[["valuePct",saved.valuePct],["freightInput",saved.freight],["otherInput",saved.other]].forEach(([id,v])=>{$(id).value=v;});chargesReady=true;} ["valuePct","freightInput","otherInput"].forEach((id)=>{$(id).readOnly=!editable;});
    const c=readCharges(), valueAmount=gross*c.valuePct/100, raw=gross+valueAmount+c.freight+c.other, rounded=Math.round(raw/10)*10, round=rounded-raw;
    $("gross").textContent=money(gross); $("discount").textContent=money(discount); $("valueAmount").textContent=money(valueAmount); $("freight").textContent=money(c.freight); $("other").textContent=money(c.other); $("round").textContent=(round>=0?"+":"")+money(round); $("total").textContent=money(rounded); $("items").textContent=lines.length; $("qty").textContent=totalQty;
    $("party").value = order?.customer_name || doc?.customer_name || "Customer"; $("collection").value = order?.collection_display_no || doc?.collection_display_no || order?.batch_ref || "—";
    $("reqNo").textContent = "Requirement No. " + (order?.requirement_display_no || doc?.requirement_display_no || order?.batch_ref || "—"); $("docNo").textContent = (doc?.kind === "CI" ? "CI" : "PI") + " No. " + (doc?.ref || "DRAFT"); $("docTitle").textContent = doc?.kind === "CI" ? "CI · COMMERCIAL INVOICE" : "PI · PROFORMA INVOICE";
    $("status").value = doc?.status || "DRAFT"; $("docDate").textContent = new Date(doc?.pushed_at || doc?.created_at || Date.now()).toLocaleString("en-IN");
    const operator = ["DISTRIBUTOR", "REDZED"].includes(role);
    $("savePi").hidden = !operator || !!doc?.ref; $("convertCi").hidden = !operator || !doc?.ref || doc?.kind === "CI"; $("download").hidden = !operator || !doc?.ref; $("share").hidden = !operator || !doc?.ref;
    if (role === "CUSTOMER" && doc?.ref && doc?.kind !== "CI") renderResponse();
  }
  function renderResponse() { $("response").classList.add("on"); $("responseLines").innerHTML = lines.map((x) => { const v = values(x), d = x.decision || "WAITING", qty = x.customer_qty ?? v.qty; return `<div class="decision"><span><b>${esc(x.lot_no)}</b><small class="muted">${esc(x.category || "-")} · ${esc(x.size_text || "-")} · ${money(v.finalRate)}</small></span><select data-action="${esc(x.id)}"><option value="CONFIRM" ${d === "CONFIRM" ? "selected" : ""}>CONFIRM</option><option value="CHANGE" ${d === "CHANGE" ? "selected" : ""}>CHANGE</option><option value="CANCEL" ${d === "CANCEL" ? "selected" : ""}>CANCEL</option></select><input class="num" data-response-qty="${esc(x.id)}" type="number" min="0" value="${Number(qty || 0)}"></div>`; }).join(""); }

  async function loadDistributor() {
    const a = auth(), [w, p, charges] = await Promise.all([rpc("rr_market_partner_workspace_v67", a), rpc("rr_market_partner_customer_pi_state_v67", a),rpc("rr_market_partner_customer_pi_charges_get_v67",{...a,p_order_id:orderId})]);
    order = (w.orders || []).find((x) => String(x.id) === String(orderId)); if (!order) throw Error("Requirement unavailable.");
    const ps = (Array.isArray(p) ? p : []).find((x) => String(x.order_id) === String(orderId)); if (ps) { const m = new Map((ps.lines || []).map((x) => [String(x.id), x])); order.lines = (order.lines || []).map((x) => ({ ...x, ...(m.get(String(x.id)) || {}) })); }
    const piRef=ps?.distributor_pi_ref||order.distributor_pi_ref, piStatus=ps?.distributor_pi_status||order.distributor_pi_status, piPushed=ps?.distributor_pi_pushed_at||order.distributor_pi_pushed_at, ciRef=ps?.customer_ci_ref||order.ci_ref, ciVisible=ps?.customer_ci_visible??order.customer_ci_visible;
    lines = order.lines || []; doc = piRef ? { ref: piRef, status: piStatus || "WAITING", pushed_at: piPushed, kind: ciVisible && ciRef ? "CI" : "PI",charges } : { kind: "PI",charges }; if (doc.kind === "CI") doc.ref = ciRef;
  }
  async function loadRedzed() {
    if (!batchId) throw Error("Batch reference missing."); const detail = await rpc("rr_market_staff_batch_detail_v67", { p_batch_id: batchId });
    order = { id: detail.id, batch_ref: detail.batch_ref, customer_name: detail.direct_customer_name, requirement_display_no: detail.batch_ref, collection_display_no: detail.batch_ref };
    lines = (detail.orders || []).flatMap((o) => (o.lines || []).map((x) => ({ ...x, order_ref: o.order_ref })));
    doc = detail.ci_ref ? { kind: "CI", ref: detail.ci_ref, status: detail.status } : detail.pi_ref ? { kind: "PI", ref: detail.pi_ref, status: detail.status } : { kind: "PI", status: detail.status };
    const lots = [...new Set(lines.map((x) => x.lot_no).filter(Boolean))]; const locations = await Promise.all(lots.map(async (lot) => [lot, await rpc("rr_pi_staff_godown_v67", { p_lot_no: lot })]));
    const byLot = new Map(locations); lines.forEach((x) => { x.godown = byLot.get(x.lot_no) || "—"; });
  }
  async function loadCustomer() { doc = await rpc("rr_market_partner_customer_invoice_view_v67", { p_token: shareToken }); if (!doc) throw Error("PI अभी उपलब्ध नहीं है।"); doc.charges=doc.charges||{}; lines = doc.lines || []; order = { customer_name: "Customer", requirement_display_no: doc.requirement_display_no, collection_display_no: doc.collection_display_no }; }
  function proposals() { return lines.map((x) => ({ line_id: x.id, proposed_qty: Math.max(0, Math.floor(Number(document.querySelector(`[data-qty="${CSS.escape(x.id)}"]`)?.value ?? values(x).qty))) })); }
  async function staffNotice(message) { if (!chatId) return; await rpc("rr_chat_send_staff_v9433", { p_chat_id: chatId, p_channel: "GROUP", p_message_type: "TEXT", p_body: message, p_payload: { relation_scope: "DISTRIBUTOR_REDZED", ui: "TEST67_SHARED_INVOICE" }, p_reply_to: null, p_order_session_id: null }); }

  async function imageData(url) { if (!url) return null; try { const blob=await (await fetch(url)).blob(); return await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=reject;r.readAsDataURL(blob);}); } catch (_) { return null; } }
  async function makePdf() {
    if (!window.jspdf?.jsPDF) throw Error("A4 PDF engine unavailable.");
    const pdf=new window.jspdf.jsPDF({orientation:"portrait",unit:"mm",format:"a4",compress:true}), pics=await Promise.all(lines.map((x)=>imageData(x.image_url))), c=readCharges();
    pdf.setTextColor(20); pdf.setFontSize(18); pdf.text(doc?.kind==="CI"?"COMMERCIAL INVOICE":"PROFORMA INVOICE",105,15,{align:"center"});
    pdf.setFontSize(9); pdf.text(`Invoice: ${doc?.ref||"DRAFT"}`,14,23); pdf.text(`Party: ${$("party").value}`,14,29); pdf.text($("reqNo").textContent,14,35); pdf.text(`Collection: ${$("collection").value}`,14,41);
    const body=lines.map((x,i)=>{const v=values(x);return [i+1,"",x.lot_no||x.article_name||"-",x.category||x.article_name||"-",x.size_text||x.size||"-",v.qty,money(v.finalRate),money(v.amount)];});
    pdf.autoTable({startY:47,head:[["S.No.","Pic","Article / Lot","Category","Size","Qty","Net Rate","Amount"]],body,styles:{fontSize:7,cellPadding:2,valign:"middle"},columnStyles:{1:{cellWidth:18,minCellHeight:20},0:{cellWidth:10},5:{cellWidth:10}},didDrawCell:(d)=>{if(d.section==="body"&&d.column.index===1&&pics[d.row.index])try{pdf.addImage(pics[d.row.index],"JPEG",d.cell.x+1,d.cell.y+1,16,18);}catch(_){}}});
    let y=(pdf.lastAutoTable?.finalY||50)+8; if(y>250){pdf.addPage();y=18;} const gross=lines.reduce((s,x)=>s+values(x).amount,0), value=gross*c.valuePct/100, raw=gross+value+c.freight+c.other, total=Math.round(raw/10)*10, round=total-raw, qty=lines.reduce((s,x)=>s+values(x).qty,0);
    [["Gross Amount",gross],[`Value Added (${c.valuePct}%)`,value],["Freight",c.freight],["Other Charges",c.other],["Round Off",round],["TTL Amount",total]].forEach(([label,val],i)=>{pdf.text(String(label),135,y+i*6);pdf.text(money(val).replace("₹","Rs. "),196,y+i*6,{align:"right"});}); pdf.text(`TTL Items ${lines.length}  |  TTL Qty ${qty}`,196,y+40,{align:"right"});
    return pdf;
  }
  function pdfName(){return `${doc?.kind||"PI"}-${doc?.ref||"DRAFT"}.pdf`.replace(/[^a-z0-9_.-]+/gi,"-");}
  async function pdfAttachment(){const pdf=await makePdf(),blob=pdf.output("blob"),data_url=await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=reject;r.readAsDataURL(blob);});return {pdf,blob,data_url,name:pdfName(),type:"application/pdf"};}
  async function downloadPdf(){try{(await makePdf()).save(pdfName());}catch(e){$("msg").textContent=e.message;}}

  async function savePi() {
    try {
      if (role === "REDZED") { const payload = proposals(), r = await rpc("rr_market_staff_propose_batch_v67", { p_batch_id: order.id, p_line_proposals: payload, p_pi_ref: "" }); doc = { kind: "PI", ref: r.pi_ref, status: r.status, pushed_at: new Date().toISOString() }; lines.forEach((x) => { x.proposed_qty = payload.find((y) => y.line_id === x.id)?.proposed_qty; }); await staffNotice(`[PBATCH:${r.id}] ${r.batch_ref} · PI ${r.pi_ref} SENT TO DISTRIBUTOR`); }
      else { const a = auth(), c=readCharges(), payload = lines.map((x) => ({ line_id: x.id, qty: Math.max(0, Math.floor(Number(document.querySelector(`[data-qty="${CSS.escape(x.id)}"]`)?.value ?? values(x).qty))) })); await rpc("rr_market_partner_customer_pi_charges_v67",{...a,p_order_id:order.id,p_value_pct:c.valuePct,p_freight:c.freight,p_other:c.other,p_tax_pct:0}); const r = await rpc("rr_market_partner_make_customer_pi_v67", { ...a, p_order_id: order.id, p_lines: payload, p_note: null }); doc = { kind: "PI", ref: r.distributor_pi_ref, status: r.distributor_pi_status || "WAITING", pushed_at: new Date().toISOString(),charges:{value_pct:c.valuePct,freight:c.freight,other:c.other,tax_pct:0} }; lines.forEach((x) => { x.distributor_pi_qty = payload.find((y) => y.line_id === x.id)?.qty; }); const attachment=await pdfAttachment(); try { await rpc("rr_market_partner_chat_send_v67", { ...a, p_lane: "CUSTOMER_GROUP", p_partner_customer_id: order.customer_id || order.partner_customer_id, p_message: `[DPI:${order.id}] ${doc.ref} · ${order.requirement_display_no || order.order_ref || "REQUIREMENT"} · PI SENT TO CUSTOMER`, p_attachment: {name:attachment.name,type:attachment.type,data_url:attachment.data_url} }); } catch (e) { throw Error(`PI ${doc.ref} saved, but Real Chat delivery failed: ${e.message}`); } }
      $("msg").textContent = `PI ${doc.ref} भेजी ✓`; render();
    } catch (e) { $("msg").textContent = e.message; }
  }
  async function convertCi() {
    try {
      if (role === "REDZED") { const r = await rpc("rr_market_staff_finalize_ci_v67", { p_batch_id: order.id, p_ci_ref: "" }); doc = { kind: "CI", ref: r.ci_ref, status: r.status, created_at: new Date().toISOString() }; await staffNotice(`[PBATCH:${r.id}] ${r.batch_ref} · CI ${r.ci_ref} SENT TO DISTRIBUTOR`); }
      else { const r = await rpc("rr_market_partner_convert_customer_ci_v67", { ...auth(), p_order_id: order.id }); doc = { kind: "CI", ref: r.customer_ci_ref, status: r.status || "FINAL", created_at: new Date().toISOString() }; }
      $("msg").textContent = `CI ${doc.ref} generated ✓`; render();
    } catch (e) { $("msg").textContent = e.message; }
  }
  async function respond() { try { const decisions = lines.map((x) => ({ line_id: x.id, action: document.querySelector(`[data-action="${CSS.escape(x.id)}"]`).value, qty: Number(document.querySelector(`[data-response-qty="${CSS.escape(x.id)}"]`).value || 0) })), r = await rpc("rr_market_partner_customer_distributor_pi_response_v67", { p_token: shareToken, p_decisions: decisions, p_note: $("note").value || null }); $("msg").textContent = `PI response ${r.distributor_pi_status} · distributor को भेजी ✓`; } catch (e) { $("msg").textContent = e.message; } }
  async function share() { try { const a=await pdfAttachment(),file=new File([a.blob],a.name,{type:a.type}); if(navigator.canShare?.({files:[file]})) await navigator.share({title:`${doc.kind||"PI"} ${doc.ref}`,files:[file]}); else {a.pdf.save(a.name);$("msg").textContent="A4 PDF downloaded; share it from Downloads.";} } catch(e){if(e.name!=="AbortError")$("msg").textContent=e.message;} }
  async function boot() { try { if (role === "DISTRIBUTOR") await loadDistributor(); else if (role === "REDZED") await loadRedzed(); else await loadCustomer(); render(); ["valuePct","freightInput","otherInput"].forEach((id)=>$(id).addEventListener("input",render)); $("savePi").onclick = savePi; $("convertCi").onclick = convertCi; $("sendResponse").onclick = respond; $("download").onclick=downloadPdf; $("share").onclick = share; } catch (e) { $("msg").textContent = e.message; } }
  boot();
})();
