(() => {
  const $ = id => document.getElementById(id);
  let client, state = {groups:[],categories:[],ledgers:[],material_types:[],materials:[],transactions:[],name_requests:[]};
  let moneyMode = "RECEIPT";

  function optionRows(rows, valueKey="id", labelKey="ledger_name") {
    return `<option value="">Select…</option>` + rows.map(x =>
      `<option value="${RR.escapeHtml(x[valueKey])}">${RR.escapeHtml(x[labelKey])}</option>`
    ).join("");
  }

  function category(code) { return state.categories.find(x => x.category_code === code); }
  function ledgersByKind(...kinds) { return state.ledgers.filter(x => kinds.includes(x.ledger_kind)); }
  function purchaseLedgerForType(typeCode) {
    const map = {
      REGULAR_CLOTH:"REGULAR_CLOTH_PURCHASE",
      MATCHING_CLOTH:"MATCHING_CLOTH_PURCHASE",
      STICKER:"STICKER_PURCHASE",
      METAL_ID:"METAL_ID_PURCHASE"
    };
    const cat = category(map[typeCode] || "OTHER_MATERIAL_PURCHASE");
    return state.ledgers.find(x => x.category_id === cat?.id);
  }

  async function identifyUser() {
    const user = await RR.requireLogin();
    const { data, error } = await client.from("rr_user_profiles")
      .select("full_name,role_code,is_active,access_status")
      .eq("auth_user_id", user.id).maybeSingle();
    if (error) throw error;
    if (!data?.is_active) throw new Error("Active profile required.");
    $("who").textContent = `${data.full_name || user.email} · ${RR.friendlyRole(data.role_code)}`;
  }

  async function load() {
    client = client || RR.getClient();
    await identifyUser();
    const { data, error } = await client.rpc("rr_accounts_bootstrap_v805", { p_data_mode: $("dataMode").value });
    if (error) throw error;
    state = data || state;
    render();
  }

  function render() {
    $("pSupplier").innerHTML = optionRows(state.ledgers.filter(x => ["SUPPLIER","PARTY","GENERAL"].includes(x.ledger_kind)));
    $("pType").innerHTML = `<option value="">Select…</option>` + state.material_types.map(x =>
      `<option value="${RR.escapeHtml(x.type_code)}">${RR.escapeHtml(x.type_name)}</option>`).join("");
    $("pCash").innerHTML = optionRows(ledgersByKind("CASH","BANK"));
    $("mCash").innerHTML = optionRows(ledgersByKind("CASH","BANK"));
    $("mAgainst").innerHTML = optionRows(state.ledgers);
    renderMaterials();

    $("txBody").innerHTML = state.transactions.length ? state.transactions.map(t => `
      <tr><td>${RR.escapeHtml(new Date(t.transaction_datetime).toLocaleString())}</td>
      <td>${RR.escapeHtml(t.voucher_no)}</td><td>${RR.escapeHtml(t.transaction_type)}</td>
      <td>${RR.escapeHtml(t.source_module)}</td><td>${RR.escapeHtml(t.bill_no || "—")}</td>
      <td>${RR.money(t.total_amount)}</td><td>${RR.escapeHtml(t.status)}</td></tr>`).join("") :
      `<tr><td colspan="7">No posted entries.</td></tr>`;

    $("reqBody").innerHTML = state.name_requests.length ? state.name_requests.map(r => `
      <tr><td>${RR.escapeHtml(new Date(r.requested_at).toLocaleString())}</td>
      <td>${RR.escapeHtml(r.entity_type)}</td><td>${RR.escapeHtml(r.requested_name)}</td>
      <td>${RR.escapeHtml((r.suggested_matches || []).slice(0,3).map(x => x.display_name).join(", ") || "—")}</td>
      <td>${RR.escapeHtml(r.status)}</td><td>${RR.escapeHtml(r.super_admin_remark || "—")}</td></tr>`).join("") :
      `<tr><td colspan="6">No pending approvals.</td></tr>`;
  }

  function renderMaterials() {
    const type = $("pType").value;
    const rows = state.materials.filter(x => x.material_type === type);
    $("pMaterial").innerHTML = `<option value="">Select…</option>` + rows.map(m =>
      `<option value="${m.material_id}">${RR.escapeHtml([m.material_no,m.material_name].filter(Boolean).join(" · "))}</option>`
    ).join("");

    const labels = {
      REGULAR_CLOTH:"Cloth Name",
      MATCHING_CLOTH:"Matching Cloth Name",
      STICKER:"Sticker Name",
      METAL_ID:"Metal ID Name",
      PANNI:"Panni Name",
      GATTA:"Gatta Name",
      BOX:"Box Name",
      PASTING_ROLL:"Pasting Roll Name",
      KANDHI_TAPE:"Kandhi Tape Name"
    };
    $("pMaterialLabel").childNodes[0].nodeValue = labels[type] || "Material Name";
    const pl = purchaseLedgerForType(type);
    if (pl) $("pPurchaseLedger").value = pl.id;
    calcPurchase();
  }

  function calcPurchase() {
    const m = state.materials.find(x => x.material_id === $("pMaterial").value);
    $("pUom").value = m?.purchase_unit || "";
    const total = Number($("pQty").value || 0) * Number($("pRate").value || 0) + Number($("pGst").value || 0);
    $("pTotal").value = total.toFixed(2);
  }

  async function postPurchase() {
    const { data, error } = await client.rpc("rr_accounts_post_material_purchase_v805", {
      p_supplier_ledger_id: $("pSupplier").value || null,
      p_material_id: $("pMaterial").value || null,
      p_purchase_ledger_id: $("pPurchaseLedger").value || null,
      p_purchase_qty: Number($("pQty").value || 0),
      p_rate: Number($("pRate").value || 0),
      p_bill_no: $("pBill").value || null,
      p_bill_date: $("pDate").value || null,
      p_gst_amount: Number($("pGst").value || 0),
      p_payment_status: $("pStatus").value,
      p_paid_amount: Number($("pPaid").value || 0),
      p_cash_bank_ledger_id: $("pCash").value || null,
      p_source_module: "ACCOUNTS_TEMPLATE",
      p_source_record_id: null,
      p_data_mode: $("dataMode").value
    });
    if (error) throw error;
    $("purchaseMsg").textContent = `Posted · ${data.voucher_no}`;
    await load();
  }

  async function postMoney() {
    const params = moneyMode === "RECEIPT" ? {
      p_party_ledger_id: $("mAgainst").value,
      p_cash_bank_ledger_id: $("mCash").value,
      p_amount: Number($("mAmount").value || 0),
      p_ref_no: $("mRef").value || null,
      p_narration: $("mNote").value || null,
      p_data_mode: $("dataMode").value
    } : {
      p_against_ledger_id: $("mAgainst").value,
      p_cash_bank_ledger_id: $("mCash").value,
      p_amount: Number($("mAmount").value || 0),
      p_ref_no: $("mRef").value || null,
      p_narration: $("mNote").value || null,
      p_data_mode: $("dataMode").value
    };
    const fn = moneyMode === "RECEIPT" ? "rr_accounts_post_receipt_v805" : "rr_accounts_post_payment_v805";
    const { data, error } = await client.rpc(fn, params);
    if (error) throw error;
    $("moneyMsg").textContent = `Posted · ${data.voucher_no}`;
    await load();
  }

  document.querySelectorAll("[data-tab]").forEach(b => b.addEventListener("click", () => {
    document.querySelectorAll("[data-tab]").forEach(x => x.classList.remove("active"));
    b.classList.add("active");
    document.querySelectorAll(".tabpage").forEach(x => x.classList.add("hidden"));
    $(b.dataset.tab).classList.remove("hidden");
  }));

  $("pType").addEventListener("change", renderMaterials);
  $("pMaterial").addEventListener("change", calcPurchase);
  ["pQty","pRate","pGst"].forEach(id => $(id).addEventListener("input", calcPurchase));
  $("pStatus").addEventListener("change", () => {
    const s = $("pStatus").value;
    $("pPaidWrap").classList.toggle("hidden", s !== "PART_PAID");
    $("pCashWrap").classList.toggle("hidden", s === "CREDIT");
  });

  $("receiptMode").addEventListener("click", () => {
    moneyMode = "RECEIPT"; $("againstLabel").childNodes[0].nodeValue = "Received From";
    $("postMoney").textContent = "Post Receipt";
  });
  $("paymentMode").addEventListener("click", () => {
    moneyMode = "PAYMENT"; $("againstLabel").childNodes[0].nodeValue = "Paid To / Expense Ledger";
    $("postMoney").textContent = "Post Payment";
  });

  $("postPurchase").addEventListener("click", () => postPurchase().catch(e => $("purchaseMsg").textContent = e.message));
  $("postMoney").addEventListener("click", () => postMoney().catch(e => $("moneyMsg").textContent = e.message));
  $("refresh").addEventListener("click", () => load().catch(e => alert(e.message)));
  $("dataMode").addEventListener("change", () => load().catch(e => alert(e.message)));

  $("pDate").value = new Date().toISOString().slice(0,10);
  RR.enableZeroClean(document);
  RR.enableEnterNext($("purchase"));
  RR.enableEnterNext($("money"));
  load().catch(e => alert(e.message));
})();
