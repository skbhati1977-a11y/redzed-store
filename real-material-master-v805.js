(() => {
  const $ = id => document.getElementById(id);
  let client, state = {material_types:[],materials:[]}, editId = null;

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
    $("type").innerHTML = `<option value="">Select…</option>` + state.material_types.map(x =>
      `<option value="${x.id}">${RR.escapeHtml(x.type_name)}</option>`).join("");
    render();
  }

  function render() {
    $("body").innerHTML = state.materials.length ? state.materials.map(m => `
      <tr>
        <td>${RR.escapeHtml(m.material_type_name)}</td>
        <td>${RR.escapeHtml(m.material_no || "—")}</td>
        <td><strong>${RR.escapeHtml(m.material_name)}</strong></td>
        <td>${RR.escapeHtml(m.purchase_unit)}</td>
        <td>${RR.escapeHtml(m.consumption_unit)}</td>
        <td>${Number(m.estimated_consumption_per_good_piece || 0)}</td>
        <td>${Number(m.weighted_avg_rate_per_base_unit || 0).toFixed(4)}</td>
        <td>${Number(m.weighted_avg_rate_per_consumption_unit || 0).toFixed(4)}</td>
        <td><strong>${RR.money(m.estimated_cost_per_good_piece || 0)}</strong></td>
        <td>${Number(m.physical_stock_base_qty || 0).toFixed(3)} ${RR.escapeHtml(m.base_stock_unit)}</td>
        <td>${RR.escapeHtml(m.consumption_basis)}</td>
        <td>${RR.escapeHtml((m.applicable_to?.tags || []).join(", ") || "—")}</td>
        <td><button type="button" data-edit="${m.material_id}">Edit</button></td>
      </tr>`).join("") : `<tr><td colspan="13">No materials created yet.</td></tr>`;

    document.querySelectorAll("[data-edit]").forEach(b => b.addEventListener("click", () => edit(b.dataset.edit)));
  }

  function edit(id) {
    const m = state.materials.find(x => x.material_id === id);
    if (!m) return;
    editId = id;
    const mt = state.material_types.find(x => x.type_code === m.material_type);
    $("type").value = mt?.id || "";
    $("name").value = m.material_name || "";
    $("no").value = m.material_no || "";
    $("pu").value = m.purchase_unit || "PCS";
    $("bu").value = m.base_stock_unit || "PCS";
    $("cu").value = m.consumption_unit || "PCS";
    $("est").value = m.estimated_consumption_per_good_piece || 0;
    $("basis").value = m.consumption_basis || "AUTO_STANDARD";
    $("applies").value = (m.applicable_to?.tags || []).join(", ");
    window.scrollTo({top:0,behavior:"smooth"});
  }

  async function save() {
    $("msg").textContent = "";
    const payload = {
      p_id: editId,
      p_material_type_id: $("type").value || null,
      p_material_name: $("name").value,
      p_material_no: $("no").value || null,
      p_purchase_unit: $("pu").value,
      p_base_stock_unit: $("bu").value,
      p_consumption_unit: $("cu").value,
      p_purchase_to_base: Number($("ptb").value || 1),
      p_consumption_to_base: Number($("ctb").value || 1),
      p_alt_unit_1: $("a1").value || null,
      p_alt_unit_1_to_base: Number($("a1b").value || 0) || null,
      p_alt_unit_2: $("a2").value || null,
      p_alt_unit_2_to_base: Number($("a2b").value || 0) || null,
      p_estimated_consumption_per_good_piece: Number($("est").value || 0),
      p_consumption_basis: $("basis").value,
      p_applicable_to: { tags: $("applies").value.split(",").map(x => x.trim()).filter(Boolean) },
      p_is_active: true
    };

    const { data, error } = await client.rpc("rr_upsert_material_v805", payload);
    if (error) throw error;
    $("msg").textContent = `Saved · ${data}`;
    editId = null;
    await load();
  }

  $("save").addEventListener("click", () => save().catch(e => $("msg").textContent = e.message));
  $("refresh").addEventListener("click", () => load().catch(e => alert(e.message)));
  $("dataMode").addEventListener("change", () => load().catch(e => alert(e.message)));

  RR.enableZeroClean(document);
  RR.enableEnterNext($("materialForm"));
  load().catch(e => alert(e.message));
})();
