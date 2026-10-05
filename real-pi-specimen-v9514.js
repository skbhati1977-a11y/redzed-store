(() => {
  "use strict";
  const $ = (x) => document.getElementById(x),
    money = (n) =>
      "₹" +
      Number(n || 0).toLocaleString("en-IN", { maximumFractionDigits: 2 });
  let ctx = {},
    piId = null,
    piNo = "",
    customerId = null,
    isSuper = false,
    discountDirty = false,
    draftNeedsSave = false,
    saving = false,
    finalized = false,
    partyDiscount = null,
    editingItem = null,
    lotSearchVersion = 0,
    lotSearchTimer = null,
    lotOptions = [],
    activeLotOption = -1;
  try {
    ctx = JSON.parse(sessionStorage.getItem("rr_pi_requirement_v9514") || "{}");
  } catch (_) {}
  let lines = Array.isArray(ctx.lines) ? ctx.lines.map((x) => ({ ...x })) : [];
  async function rpc(n, a = {}) {
    return RF853.rpc(n, a);
  }
  async function loadTest() {
    const t = new URLSearchParams(location.search).get("testpi");
    if (!t) return;
    ctx = await rpc("rr_pi_test_context_v9522", { p_token: t });
    lines = (ctx.lines || []).map((x) => ({ ...x }));
    piId = null;
    piNo = "";
  }
  async function loadRequirementUrl() {
    const query = new URLSearchParams(location.search);
    const savedPiId = query.get("pi_id");
    if (savedPiId) {
      ctx = await rpc("rr_sales_pi_detail_v500", { p_pi_id: savedPiId });
      lines = (ctx.lines || []).map((x) => ({
        ...x,
        size: x.size || x.size_text || "",
      }));
      piId = ctx.pi_id;
      piNo = ctx.pi_no || "";
      ctx.requirement_id = ctx.requirement_id || query.get("requirement_id") || null;
      finalized = !!ctx.status && ctx.status !== "DRAFT";
      return;
    }
    const id = query.get("requirement_id") || ctx.requirement_id;
    if (!id) return;
    ctx = await rpc("rr_pi_requirement_bootstrap_v9541", {
      p_requirement_id: id,
    });
    piId = ctx.pi_id || null;
    piNo = ctx.pi_no || "";
    finalized = !!ctx.status && ctx.status !== "DRAFT";
    lines = (ctx.lines || []).map((x) => ({
      ...x,
      size: x.size || x.size_text || "",
    }));
    try {
      sessionStorage.setItem(
        "rr_pi_requirement_v9514",
        JSON.stringify({ ...ctx, lines: lines.map((x) => ({ ...x })) }),
      );
    } catch (_) {}
  }
  async function contexts(preserve = true, items = lines) {
    await Promise.all(
      items.map(async (x) => {
        try {
          const c = await rpc("rr_pi_lot_context_v9517", {
            p_lot_no: x.lot_no,
            p_customer_name: ctx.customer_name,
            p_data_mode: "TEST",
          });
          x.approved = +c.approved_rate || 0;
          x.customerRate =
            c.customer_lot_rate == null ? null : +c.customer_lot_rate;
          const mapped = +c.effective_rate || x.approved;
          if (!preserve || x.rate == null) x.rate = mapped;
          if (x.stock_type === "TRADED" && !finalized) {
            const trade = await rpc("rr_trade_effective_rate_v849", {
              p_lot_no: x.lot_no,
              p_party_name: ctx.customer_name,
              p_data_mode: "TEST",
            });
            x.approved = x.rate = +trade.target_sale_rate;
          }
          x.allowed = +c.allowed_discount || 0;
          if (!discountDirty && !finalized) x.discount = x.allowed;
          x.category = c.category || x.category || "";
          x.available = +c.available_qty || 0;
          x.box = +c.pack_pcs_per_box || 0;
          x.rate_path = c.rate_path || "NONE";
          x.rrqAvailable = +c.rrq_available || 0;
          x.image = c.image || x.image || "";
          x.size = c.size_text || c.size || x.size || "";
          customerId = c.customer_id || customerId;
          delete x.context_error;
          try {
            x.godown = await rpc("rr_pi_staff_godown_v67", {
              p_lot_no: x.lot_no,
            });
          } catch (_) {
            x.godown = "—";
          }
        } catch (e) {
          x.context_error = e.message;
        }
      }),
    );
  }
  function hideLotSuggestions() {
    clearTimeout(lotSearchTimer);
    lotSearchVersion++;
    $("itemLotSuggestions").hidden = true;
    $("itemLot").setAttribute("aria-expanded", "false");
    $("itemLot").removeAttribute("aria-activedescendant");
    lotOptions = [];
    activeLotOption = -1;
  }
  function pickLot(index) {
    const lot = lotOptions[index];
    if (!lot || saving || finalized) return;
    $("itemLot").value = lot.lot_no;
    hideLotSuggestions();
    $("itemQty").focus();
  }
  function highlightLot(index) {
    activeLotOption = index;
    $("itemLotSuggestions").querySelectorAll("[role=option]").forEach((el,i) => {
      el.setAttribute("aria-selected", String(i === index));
      if (i === index) {
        $("itemLot").setAttribute("aria-activedescendant", el.id);
        el.scrollIntoView?.({block:"nearest"});
      }
    });
  }
  function bindLotSuggestions() {
    const input = $("itemLot"), list = $("itemLotSuggestions");
    input.addEventListener("input", () => {
      hideLotSuggestions();
      const term = input.value.trim().toUpperCase();
      if (!term || finalized || saving) return;
      const version = lotSearchVersion;
      lotSearchTimer = setTimeout(async () => {
        const status = (message) => {
          list.replaceChildren();
          const el = document.createElement("div");
          el.className = "lot-picker-status";
          el.setAttribute("role", "status");
          el.textContent = message;
          list.appendChild(el);
          list.hidden = false;
          input.setAttribute("aria-expanded", "true");
        };
        status("Searching lots…");
        try {
          const result = await rpc("rr_ws_stock_search_v9411", {p_search:term,p_multi_lots:"",p_sort:"LOT_ASC",p_data_mode:"TEST"});
          if (version !== lotSearchVersion || finalized || saving) return;
          lotOptions = (Array.isArray(result) ? result : []).filter(x => String(x.lot_no || "").toUpperCase().includes(term) && Number(x.available_qty) > 0)
            .sort((a,b) => Number(!String(a.lot_no).toUpperCase().startsWith(term)) - Number(!String(b.lot_no).toUpperCase().startsWith(term)))
            .slice(0,20);
          if (!lotOptions.length) { status("No available lots found."); return; }
          list.replaceChildren();
          lotOptions.forEach((lot,i) => {
            const option = document.createElement("button");
            option.type = "button"; option.className = "lot-option"; option.id = "pi-lot-option-" + i; option.tabIndex = -1;
            option.setAttribute("role", "option"); option.setAttribute("aria-selected", "false");
            const placeholder = document.createElement("span"); placeholder.className = "lot-micro"; placeholder.textContent = "👕";
            try {
              const url = new URL(lot.thumbnail, location.href);
              if (!lot.thumbnail || !["https:","http:"].includes(url.protocol)) throw Error("No image");
              const img = document.createElement("img"); img.className = "lot-micro"; img.src = url.href; img.alt = ""; img.loading = "lazy";
              img.onerror = () => img.replaceWith(placeholder);
              option.appendChild(img);
            } catch (_) { option.appendChild(placeholder); }
            const text = document.createElement("span"), name = document.createElement("b"), detail = document.createElement("small");
            name.textContent = lot.lot_no;
            detail.textContent = [lot.category, lot.sizes, `${lot.available_qty} PCS`].filter(Boolean).join(" · ");
            text.append(name,detail); option.appendChild(text);
            option.addEventListener("pointerdown", e => e.preventDefault());
            option.onclick = () => pickLot(i);
            list.appendChild(option);
          });
          list.hidden = false;
          input.setAttribute("aria-expanded", "true");
        } catch(e) {
          if (version === lotSearchVersion) status("Lot search unavailable. Edit the lot number to retry.");
        }
      }, 200);
    });
    input.addEventListener("keydown", e => {
      if (e.key === "Escape") { hideLotSuggestions(); return; }
      if (list.hidden || !lotOptions.length) return;
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        e.preventDefault(); highlightLot((activeLotOption + (e.key === "ArrowDown" ? 1 : -1) + lotOptions.length) % lotOptions.length);
      } else if (e.key === "Enter" && activeLotOption >= 0) { e.preventDefault(); pickLot(activeLotOption); }
      else if (e.key === "Tab") hideLotSuggestions();
    });
    input.addEventListener("blur", hideLotSuggestions);
    document.addEventListener("pointerdown", e => { if (!e.target.closest(".lot-picker")) hideLotSuggestions(); });
  }
  function setPartyDiscount(value) {
    if (!isSuper || finalized || saving) return;
    if (!Number.isFinite(value) || value < 0 || value > 10) {
      $("msg").textContent = "Party discount must be between ₹0 and ₹10 per piece.";
      return;
    }
    partyDiscount = value;
    discountDirty = true;
    draftNeedsSave = true;
    lines.forEach((line) => (line.discount = value));
  }
  function resetItemEditor() {
    hideLotSuggestions();
    editingItem = null;
    $("itemLot").value = $("itemQty").value = "";
    $("itemStockType").value = "REGULAR";
    $("addItem").textContent = "ADD ITEM";
    $("cancelItemEdit").hidden = true;
    $("itemEditorMessage").textContent = "";
  }
  async function addOrReplaceItem() {
    if (saving || finalized) return;
    hideLotSuggestions();
    const lot = $("itemLot").value.trim().toUpperCase();
    const qty = Number($("itemQty").value);
    const stockType = $("itemStockType").value;
    const index = editingItem;
    if (!/^[A-Z0-9][A-Z0-9._/-]*$/.test(lot) || !Number.isSafeInteger(qty) || qty < 1) {
      $("itemEditorMessage").textContent = "Enter a valid lot number and whole PCS qty greater than zero.";
      return;
    }
    if (lines.some((x,i) => i !== index && x.lot_no.trim().toUpperCase() === lot && (x.stock_type || "REGULAR") === stockType)) {
      $("itemEditorMessage").textContent = "This lot already exists. Use EDIT / REPLACE to change its PCS qty.";
      return;
    }
    saving = true;
    $("addItem").disabled = true;
    $("itemEditorMessage").textContent = "Checking lot, stock and approved rate…";
    try {
      const old = index === null ? null : lines[index];
      const sameLot = old && old.lot_no.trim().toUpperCase() === lot && (old.stock_type || "REGULAR") === stockType;
      const candidate = { ...(sameLot ? old : {}), lot_no: lot, qty, stock_type: stockType, discount: partyDiscount ?? 0 };
      await contexts(!!sameLot, [candidate]);
      if (candidate.context_error) throw Error(candidate.context_error);
      if (candidate.available < qty) throw Error(`${lot}: only ${candidate.available} PCS available.`);
      candidate.discount = discountDirty ? partyDiscount : candidate.allowed;
      if (!discountDirty) {
        partyDiscount = candidate.allowed;
        lines.forEach((line) => (line.discount = partyDiscount));
      }
      if (sameLot && old.qty !== qty) delete candidate.reason;
      if (index === null) lines.push(candidate); else lines[index] = candidate;
      draftNeedsSave = true;
      resetItemEditor();
      render();
      saving = false;
      const saved = await save(false, true);
      $("itemEditorMessage").textContent = saved ? "Item auto-saved to PI draft." : "Item is not saved yet. Use RETRY AUTO-SAVE.";
    } catch(e) {
      $("itemEditorMessage").textContent = e.message;
    } finally {
      saving = false;
      $("addItem").disabled = false;
    }
  }
  function exceptions() {
    return lines.filter((x) => x.box > 0 && x.qty % x.box !== 0);
  }
  function boxResult(x) {
    if (!x.box) return "—";
    const f = Math.floor(x.qty / x.box),
      l = x.qty % x.box;
    return (
      `${f ? f + " BOX" : ""}${f && l ? " + " : ""}${l ? l + " LOOSE" : ""}` ||
      "0"
    );
  }
  function render() {
    let gross = 0,
      q = 0;
    partyDiscount = lines[0]?.discount ?? partyDiscount ?? 0;
    $("partyDiscount").value = partyDiscount;
    $("partyDiscount").readOnly = !isSuper || finalized;
    $("discountHelp").textContent = finalized ? "Saved bill discount" : isSuper
      ? "Applies equally to every item. Saving this bill updates the party default for future bills."
      : "Approved party discount · automatically applied to every item";
    $("rows").innerHTML = lines
      .map((x, i) => {
        x.qty = +x.qty || 0;
        x.rate = +x.rate || 0;
        x.discount = +x.discount || 0;
        x.net = Math.max(0, x.rate - x.discount);
        x.amount = x.qty * x.net;
        gross += x.amount;
        q += x.qty;
        const rateAlt = x.approved > 0 && x.rate !== x.approved,
          qtyWarn = x.qty > x.available,
          boxWarn = x.box > 0 && x.qty % x.box !== 0,
          delta = (x.rate - x.approved) * x.qty;
        return `<tr><td>${i + 1}</td><td><button class="btn" data-edit="${i}" type="button">EDIT / REPLACE</button><button class="btn del" data-del="${i}" type="button">DELETE</button></td><td>${x.image ? `<img class="pic" src="${x.image}">` : "👕"}</td><td><b>${x.lot_no}</b></td><td>${x.category || ""}</td><td>${x.size || ""}</td><td><input class="num qty ${boxWarn || qtyWarn ? "alter" : ""}" data-i="${i}" value="${x.qty}" type="number" min="1">${qtyWarn ? `<div class="warn">Stock ${x.available}</div>` : ""}</td><td>${x.box || "—"}</td><td>${boxResult(x)}</td><td><input class="num rate ${rateAlt ? "alter" : ""}" data-i="${i}" value="${x.rate}" type="number" min="0"><div class="muted">Approved ${money(x.approved)}${x.customerRate != null ? ` · Customer-Lot ${money(x.customerRate)}` : ""}</div></td><td><input class="num disc" data-i="${i}" value="${x.discount}" type="number" min="0" ${isSuper ? "" : "readonly"}><div class="muted">Party ${money(x.allowed)}</div></td><td>${money(x.net)}</td><td>${money(x.amount)}</td><td class="rrq"><div>Available ${money(x.rrqAvailable)}</div><div>This PI ${(delta >= 0 ? "+" : "") + money(delta)}</div><b>Balance ${money(x.rrqAvailable + delta)}</b></td><td class="rr-godown-view-only">${x.godown || "—"}</td></tr>`;
      })
      .join("");
    document.querySelectorAll(".qty,.rate,.disc").forEach(
      (el) =>
        (el.onchange = (e) => {
          if (finalized || saving) return;
          const x = lines[+e.target.dataset.i],
            v = +e.target.value || 0;
          if (e.target.classList.contains("qty")) x.qty = v;
          if (e.target.classList.contains("rate")) x.rate = v;
          if (e.target.classList.contains("disc")) setPartyDiscount(v);
          draftNeedsSave = true;
          render();
          save(false, true);
        }),
    );
    const vp = +$("value").value || 0,
      fr = +$("freight").value || 0,
      ot = +$("other").value || 0,
      va = (gross * vp) / 100,
      raw = gross + va + fr + ot,
      total = Math.round(raw / 10) * 10,
      ro = total - raw;
    $("gross").textContent = money(gross);
    $("valueAmt").textContent = money(va);
    $("round").textContent = (ro >= 0 ? "+" : "") + money(ro);
    $("items").textContent = lines.length;
    $("qty").textContent = q;
    $("total").textContent = money(total);
    remarks();
    if (finalized) $("rows").querySelectorAll("input,button").forEach((el) => (el.disabled = true));
  }
  function bindDelete() {
    const body = $("rows");
    body.onclick = (e) => {
      if (saving || finalized) return;
      const edit = e.target.closest("[data-edit]");
      if (edit && body.contains(edit)) {
        hideLotSuggestions();
        editingItem = Number(edit.dataset.edit);
        const line = lines[editingItem];
        $("itemLot").value = line.lot_no;
        $("itemQty").value = line.qty;
        $("itemStockType").value = line.stock_type || "REGULAR";
        $("addItem").textContent = "UPDATE / REPLACE ITEM";
        $("cancelItemEdit").hidden = false;
        $("itemEditorMessage").textContent = "Edit PCS qty or enter another lot to replace this item.";
        $("itemLot").focus();
        $("itemEditor").scrollIntoView?.({block:"center",behavior:"smooth"});
        return;
      }
      const b = e.target.closest("[data-del]");
      if (!b || !body.contains(b)) return;
      const i = Number(b.dataset.del),
        x = lines[i];
      if (!x) return;
      if (
        !confirm(
          `Are you sure?\nDelete Lot ${x.lot_no}?\nThis will remove the complete row and all its fields.`,
        )
      )
        return;
      if (lines.length === 1) {
        $("msg").textContent = "Keep at least one item in the PI, or replace this item.";
        return;
      }
      lines.splice(i, 1);
      draftNeedsSave = true;
      resetItemEditor();
      render();
      save(false, true);
    };
  }
  function remarks() {
    const a = [];
    lines.forEach((x, i) => {
      if (x.box > 0 && x.qty % x.box !== 0)
        a.push(
          `${i + 1}. Lot ${x.lot_no} | Pack ${x.box} PCS/Box | Sale ${x.qty} | Reason: ${x.reason || "REASON REQUIRED"}`,
        );
      if (x.approved > 0 && x.rate !== x.approved)
        a.push(
          `${i + 1}. Lot ${x.lot_no} | Approved ${money(x.approved)} → Customer ${money(x.rate)}`,
        );
    });
    $("autoRemarks").textContent = a.join("\n") || "No exception.";
  }
  async function boot() {
    try {
      await RR.requireRoles(["owner", "superadmin", "super_admin", "admin", "sales"]);
      await loadTest();
      await loadRequirementUrl();
      const ac = await rpc("rr_pi_actor_context_v9526");
      isSuper = !!ac.superadmin;
      $("customer").value = ctx.customer_name || "";
      $("dispatch").value = ctx.dispatch_details || "";
      $("value").value = +ctx.value_added_pct || 0;
      $("freight").value = +ctx.freight_amount || 0;
      $("other").value = +ctx.packing_other || 0;
      $("piDate").textContent = new Date().toLocaleDateString("en-IN");
      await contexts(!!piId);
      if (piNo) $("piNo").textContent = "PI No. " + piNo;
      bindDelete();
      bindLotSuggestions();
      $("partyDiscount").onchange = () => { setPartyDiscount(Number($("partyDiscount").value)); render(); };
      $("addItem").onclick = addOrReplaceItem;
      $("cancelItemEdit").onclick = resetItemEditor;
      render();
      ["value", "freight", "other"].forEach((id) => ($(id).oninput = () => { draftNeedsSave = true; render(); }));
      ["dispatch", "remarks"].forEach((id) => ($(id).oninput = () => { draftNeedsSave = true; }));
      $("save").onclick = () => save(false);
      $("convertCi").onclick = () => save(true);
      $("retryPartySend").onclick = retryPartySend;
      $("resendBill").onclick = () => invoiceAction(false);
      $("shareBill").onclick = () => invoiceAction(true);
      $("resendBill").hidden = $("shareBill").hidden = !piId;
      $("retryDraftSave").onclick = () => save(false, true);
      if (finalized) {
        $("itemEditor").hidden = true;
        document.querySelectorAll("input,textarea,button.del").forEach((el) => (el.disabled = true));
        $("save").disabled = $("convertCi").disabled = true;
        $("msg").textContent = "Finalized bill · saved discount snapshot.";
      }
      if (piId) {
        const action=new URLSearchParams(location.search).get("invoice_action");
        if(action){$(action==="share"?"shareBill":"resendBill").scrollIntoView?.({block:"center"});$("msg").textContent=action==="share"?"Tap SHARE JPG OUTSIDE to attach the saved bill.":"Tap RESEND to send the saved bill again.";}
        try {
          const status = await rpc("rr_pi_customer_document_test71", {
            p_pi_id: piId,
            p_chat_id: ctx.chat_id || new URLSearchParams(location.search).get("chat_id") || null,
          });
          $("retryPartySend").hidden = status?.already_sent !== false;
        } catch (_) {
          $("retryPartySend").hidden = false;
        }
      }
    } catch (e) {
      $("msg").textContent = e.message;
    }
  }
  async function getReasons() {
    if (!lines.length) throw Error("PI me kam se kam ek Lot required hai.");
    for (const x of lines)
      if (!Number.isSafeInteger(x.qty) || x.qty < 1)
        throw Error(`${x.lot_no}: enter whole PCS qty greater than zero.`);
    for (const x of lines)
      if (x.qty > x.available)
        throw Error(
          `${x.lot_no}: Sale Qty ${x.qty} exceeds stock ${x.available}.`,
        );
    for (const x of exceptions())
      if (!x.reason) {
        const r = prompt(
          `WARNING · ${x.lot_no}\nPack: ${x.box} PCS/Box\nSale: ${x.qty}\nLoose/non-box sale reason mandatory:`,
          "",
        );
        if (!r || !r.trim())
          throw Error(`${x.lot_no}: quantity exception reason required.`);
        x.reason = r.trim();
      }
  }
  async function invoiceAction(outside) {
    if(saving||!piId)return;
    if(draftNeedsSave){$("msg").textContent="Save current changes before Resend / Share.";return;}
    saving=true;const button=$(outside?"shareBill":"resendBill");button.disabled=true;
    try {
      const chat=ctx.chat_id||new URLSearchParams(location.search).get("chat_id")||null;
      const result=outside?await window.RRPIReceipt71.share(piId,chat):await window.RRPIReceipt71.send(piId,chat,m=>$("msg").textContent=m,{resend:true});
      $("msg").textContent=outside?(result.downloaded?"JPG downloaded · attach it in your outside app.":"Outside share completed."):"Bill resent to party · sent ✓.";
    }catch(e){$("msg").textContent=e.name==="AbortError"?"Share cancelled.":e.message;}finally{saving=false;button.disabled=false;}
  }
  async function sendSavedBillToParty() {
    if (draftNeedsSave) throw Error("Current item changes need saving before sending.");
    if (!window.RRPIReceipt71) throw Error("Receipt sender did not load. Reload and retry sending.");
    const chat = ctx.chat_id || new URLSearchParams(location.search).get("chat_id") || null;
    const result = await window.RRPIReceipt71.send(piId, chat, message => ($("msg").textContent = message));
    if (!result?.sent) throw Error("Party send could not be confirmed.");
    $("retryPartySend").hidden = true;
    $("retryDraftSave").hidden = true;
    $("itemEditorMessage").textContent = "Saved bill sent to party.";
    return result;
  }
  async function retryPartySend() {
    if (saving || !piId) return;
    if (draftNeedsSave) { await save(false); return; }
    saving = true;
    $("retryPartySend").disabled = true;
    try {
      const result = await sendSavedBillToParty();
      $("msg").textContent = result.already_sent ? "Bill already sent to party." : "JPG and details sent to party · sent ✓.";
    } catch(e) {
      $("retryPartySend").hidden = false;
      $("msg").textContent = "Bill saved · party send failed: " + e.message;
    } finally {
      saving = false;
      $("retryPartySend").disabled = false;
    }
  }
  async function save(finalize = false, autoDraft = false) {
    if (saving || finalized) return;
    saving = true;
    let billSaved = false;
    try {
      $("msg").textContent = "Revalidating stock/rate…";
      await contexts(true);
      if (lines.some((x) => x.context_error))
        throw Error("Party/stock context could not be verified. Please retry.");
      if (autoDraft) {
        if (!lines.length || lines.some(x => !Number.isSafeInteger(x.qty) || x.qty < 1 || x.qty > x.available))
          throw Error("Check item PCS qty and available stock before saving.");
      } else await getReasons();
      const payload = lines.map((x) => ({
        lot_no: x.lot_no,
        short_item_name: x.category || x.lot_no,
        stock_type: x.stock_type || "REGULAR",
        qty: x.qty,
        rate: x.rate,
      }));
      const valuePct = Number($("value").value);
      if (!Number.isFinite(valuePct) || valuePct < -100)
        throw Error("Value Added % must be a number of at least -100.");
      const manual = ($("remarks").value || "").trim(),
        dispatch = [$("dispatch").value, manual && `Remarks: ${manual}`]
          .filter(Boolean)
          .join(" | ");
      const saveArgs = {
        p_pi_id: piId,
        p_customer_name: ctx.customer_name,
        p_dispatch_details: dispatch,
        p_lines: payload,
        p_party_discount: isSuper && discountDirty ? partyDiscount : null,
        p_freight_amount: +$("freight").value || 0,
        p_packing_other: +$("other").value || 0,
        p_value_added_pct: valuePct,
        p_gst_pct: 0,
        p_finalize: finalize,
        p_data_mode: "TEST",
      };
      if (ctx.requirement_id) saveArgs.p_requirement_id = ctx.requirement_id;
      const res = await rpc(ctx.requirement_id ? "rr_pi_requirement_save_test71" : "rr_fg_save_pi_value_adjustment_test71", saveArgs);
      discountDirty = false;
      partyDiscount = +res.party_discount_per_piece || 0;
      lines.forEach((x) => {
        x.discount = x.allowed = +res.party_discount_per_piece || 0;
      });
      render();
      piId = res.pi_id || piId;
      billSaved = true;
      $("resendBill").hidden = $("shareBill").hidden = false;
      draftNeedsSave = false;
      if (piId) {
        const savedUrl = new URL(location.href);
        savedUrl.searchParams.set("pi_id", piId);
        history.replaceState(null, "", savedUrl.href);
      }
      if (finalize) {
        finalized = true;
        $("save").disabled = $("convertCi").disabled = true;
        $("itemEditor").hidden = true;
      }
      if (piId && !piNo) {
        piNo = await rpc("rr_pi_apply_display_no_v9540", { p_pi_id: piId });
        $("piNo").textContent = "PI No. " + piNo;
      } else if (piNo) $("piNo").textContent = "PI No. " + piNo;
      if (autoDraft) {
        $("retryDraftSave").hidden = true;
        $("itemEditorMessage").textContent = "Items auto-saved to PI draft.";
        $("msg").textContent = "PI draft auto-saved · ready to Send to Party.";
        $("convertCi").disabled = !piId;
        return true;
      }
      for (const x of lines) {
        if (customerId && x.rate !== x.approved)
          await rpc("rr_customer_lot_rate_set_v9517", {
            p_customer_id: customerId,
            p_lot_no: x.lot_no,
            p_rate: x.rate,
            p_approved_rate: x.approved,
            p_source_type: "PI",
            p_source_id: piId,
            p_data_mode: "TEST",
          });
        await rpc("rr_pi_record_rrq_v9518", {
          p_pi_id: piId,
          p_lot_no: x.lot_no,
          p_approved_rate: x.approved,
          p_pi_rate: x.rate,
          p_qty: x.qty,
          p_data_mode: "TEST",
        });
      }
      for (const x of exceptions())
        await rpc("rr_pi_record_qty_exception_v9516", {
          p_pi_id: piId,
          p_requirement_id: ctx.requirement_id || null,
          p_lot_no: x.lot_no,
          p_box_qty: x.box,
          p_sale_qty: x.qty,
          p_reason: x.reason,
          p_snapshot: {
            approved_rate: x.approved,
            customer_lot_rate: x.customerRate,
            entered_rate: x.rate,
            discount: x.discount,
            available_qty: x.available,
          },
        });
      const convert = $("convertCi");
      if (convert) convert.disabled = !piId || finalize;
      if (finalize) {
        finalized = true;
        render();
        $("itemEditor").hidden = true;
        $("piNo").textContent = `CI No. ${res.cpi_no || res.ci_no || piNo}`;
        $("save").disabled = true;
        $("msg").textContent = `CI ${res.cpi_no || res.ci_no || ""} finalised.`;
      }
      $("retryDraftSave").hidden = true;
      const sent = await sendSavedBillToParty();
      $("msg").textContent = sent.already_sent ? "Bill saved · already sent to party." : "Bill saved · JPG and details sent to party · sent ✓.";
      return true;
    } catch (e) {
      if (autoDraft) {
        draftNeedsSave = true;
        $("retryDraftSave").hidden = false;
        $("msg").textContent = "Draft auto-save failed: " + e.message + ". Retry Auto-Save.";
      } else if (billSaved) {
        $("retryPartySend").hidden = false;
        $("msg").textContent = "Bill saved · follow-up failed: " + e.message + ". Retry Send to Party.";
      } else $("msg").textContent = e.message;
      return false;
    } finally {
      saving = false;
    }
  }
  boot();
})();
