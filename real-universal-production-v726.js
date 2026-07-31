(() => {
"use strict";

const $ = id => document.getElementById(id);
const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const arr = value => Array.isArray(value) ? value : [];
const num = value => Number(value || 0);
const upper = value => String(value || "").trim().toUpperCase();
const rowKey = row => String(row.colour_id || row.colour_code || "");
const requestId = () => globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(16).slice(2)}`;

const state = {
  sb: null,
  lots: [],
  departments: [],
  lot: null,
  context: null,
  visuals: new Map(),
  images: [],
  imageIndex: 0,
  scale: 1,
  startX: 0,
  busy: false
};

function errorText(error) {
  return [error?.message, error?.details, error?.hint, error?.code].filter(Boolean).join(" — ") || String(error || "Unknown error");
}

async function rpc(name, args = {}) {
  const {data, error} = await state.sb.rpc(name, args);
  if (error) throw error;
  return data;
}

function setMessage(text = "", type = "") {
  const box = $("message");
  box.innerHTML = text ? `<div class="msg ${type}">${esc(text)}</div>` : "";
}

function setFormMessage(text = "", type = "") {
  const box = $("formMsg");
  box.textContent = text;
  box.className = `msg ${type}`.trim();
}

function uniqueUrls(values) {
  return [...new Set(arr(values).flat(Infinity).filter(v => typeof v === "string" && /^https?:\/\//i.test(v.trim())).map(v => v.trim()))];
}

async function loadVisual(lot) {
  try {
    const data = await rpc("rr_upm_get_lot_visuals_v6", {
      p_canonical_lot_id: lot.canonical_lot_id,
      p_art_no: lot.art_no || null
    });
    const row = arr(data)[0] || data || {};
    state.visuals.set(lot.canonical_lot_id, {
      art: uniqueUrls([row.garment_url, row.art_url]),
      prints: uniqueUrls([row.print_urls, row.print_image_urls])
    });
  } catch (error) {
    console.warn("Lot visual mapping unavailable", lot.lot_no, error);
    state.visuals.set(lot.canonical_lot_id, {art: [], prints: []});
  }
}

function visualItems(lot) {
  const visual = state.visuals.get(lot.canonical_lot_id) || {art: [], prints: []};
  return [
    ...visual.art.map((url, index) => ({url, label: index ? `ART ${index + 1}` : "ART"})),
    ...visual.prints.map((url, index) => ({url, label: `PRINT ${index + 1}`}))
  ];
}

function thumbnails(lot, limit = 8) {
  const items = visualItems(lot);
  if (!items.length) return '<span class="muted">Art/Print image mapping pending</span>';
  return items.slice(0, limit).map((item, index) => `
    <button class="thumb" data-lot-img="${esc(lot.canonical_lot_id)}" data-img="${index}" type="button">
      <span class="thumb-label">${esc(item.label)}</span>
      <img loading="lazy" src="${esc(item.url)}" alt="${esc(item.label)}">
    </button>`).join("");
}

function cbNo(lot) {
  return lot?.cb_no || lot?.cb_number || lot?.cb_base_no || "—";
}

async function load() {
  if (state.busy) return;
  state.busy = true;
  try {
    setMessage("Loading lots…");
    const [departmentResult, lotResult] = await Promise.all([
      state.sb.from("rr_upm_departments").select("*").eq("is_active", true).order("sequence_no"),
      state.sb.from("rr_upm_lot_board_v1").select("*").order("board_updated_at", {ascending: false})
    ]);
    if (departmentResult.error) throw departmentResult.error;
    if (lotResult.error) throw lotResult.error;
    state.departments = departmentResult.data || [];
    state.lots = lotResult.data || [];
    await Promise.all(state.lots.map(loadVisual));
    fillDepartments();
    renderBoard();
    setMessage();
  } catch (error) {
    console.error(error);
    setMessage(errorText(error), "error");
  } finally {
    state.busy = false;
  }
}

function fillDepartments() {
  const options = state.departments.map(department => `<option value="${esc(department.department_code)}">${esc(department.department_name)}</option>`).join("");
  $("homeDept").innerHTML = '<option value="">All departments</option>' + options;
  $("dept").innerHTML = options;
}

function lotMatchesDepartment(lot, departmentCode) {
  if (!departmentCode) return true;
  return arr(lot.colours).some(colour => upper(colour.current_department_code) === upper(departmentCode));
}

function lotCard(lot) {
  return `<article class="lot-card" data-lot="${esc(lot.canonical_lot_id)}">
    <div class="lot-head">
      <div><div class="lot-no">${esc(lot.lot_no)}</div><div class="cb-no">CB NO · ${esc(cbNo(lot))}</div><div class="art-no">ART ${esc(lot.art_no || "—")}</div></div>
      <div style="text-align:right"><small class="muted">TOTAL CUT</small><div class="cut">${num(lot.total_qty)} PCS</div></div>
    </div>
    <div class="thumbs">${thumbnails(lot, 5)}</div>
    <button class="primary checkin" data-open-lot="${esc(lot.canonical_lot_id)}" type="button">CHECK IN</button>
  </article>`;
}

function renderBoard() {
  const query = $("search").value.toLowerCase().trim();
  const department = $("homeDept").value;
  const rows = state.lots.filter(lot => {
    const text = `${lot.lot_no} ${cbNo(lot)} ${lot.art_no || ""} ${lot.item_name || ""}`.toLowerCase();
    return (!query || text.includes(query)) && lotMatchesDepartment(lot, department);
  });
  $("board").innerHTML = rows.map(lotCard).join("") || '<div class="msg">No lots found.</div>';
  document.querySelectorAll("[data-open-lot]").forEach(button => button.onclick = event => {
    event.stopPropagation();
    openLot(button.dataset.openLot);
  });
  document.querySelectorAll(".lot-card").forEach(card => card.onclick = () => openLot(card.dataset.lot));
  wireImages();
}

function wireImages(scope = document) {
  scope.querySelectorAll("[data-lot-img]").forEach(button => button.onclick = event => {
    event.stopPropagation();
    const lot = state.lots.find(row => row.canonical_lot_id === button.dataset.lotImg);
    openGallery(visualItems(lot).map(item => item.url), Number(button.dataset.img || 0));
  });
}

async function openLot(id) {
  try {
    state.lot = state.lots.find(row => row.canonical_lot_id === id);
    if (!state.lot) throw new Error("Lot not found.");
    const preferred = $("homeDept").value || arr(state.lot.colours)[0]?.current_department_code || state.departments[0]?.department_code;
    if ([...$("dept").options].some(option => option.value === preferred)) $("dept").value = preferred;
    $("traveller").classList.remove("hidden");
    renderIdentity();
    await loadContext();
  } catch (error) {
    console.error(error);
    setFormMessage(errorText(error), "error");
  }
}

function renderIdentity() {
  const lot = state.lot;
  $("identity").innerHTML = `
    <div class="box"><small>LOT NO</small><b>${esc(lot.lot_no)}</b></div>
    <div class="box"><small>CB NO</small><b id="identityCb">${esc(cbNo(lot))}</b></div>
    <div class="box"><small>ART NO</small><b>${esc(lot.art_no || "—")}</b></div>
    <div class="box"><small>TOTAL CUTTING</small><b>${num(lot.total_qty)} PCS</b></div>
    <div class="box"><small>ITEM</small><b>${esc(lot.item_name || "—")}</b></div>`;
  $("entryThumbs").innerHTML = thumbnails(lot, 20);
  wireImages($("entryThumbs"));
}

async function loadContext() {
  if (!state.lot || !$("dept").value) return;
  try {
    setFormMessage("Verified Single/Multi Cutting mapping and workflow balances loading…");
    state.context = await rpc("rr_upm_universal_form_v726", {
      p_canonical_lot_id: state.lot.canonical_lot_id,
      p_department_code: $("dept").value
    });
    if (state.context?.lot?.cb_no) {
      state.lot.cb_no = state.context.lot.cb_no;
      if ($("identityCb")) $("identityCb").textContent = state.context.lot.cb_no;
    }
    $("actualRate").value = state.context.actual_rate ?? 0;
    $("standardRate").value = state.context.standard_rate ?? "";
    $("ownerMargin").value = state.context.owner_margin ?? "";
    const showOwner = Boolean(state.context.can_view_standard);
    $("stdWrap").classList.toggle("hidden", !showOwner);
    $("marginWrap").classList.toggle("hidden", !showOwner);
    fillBulkWorker();
    const nextDepartment = state.context.next_department_code || "FINAL / COMPLETE";
    $("routeNote").textContent = `Current: ${state.context.department_code} · Next after Submit: ${nextDepartment} · Downstream assignment remains locked until this Colour is submitted.`;
    renderColours();
    const source = arr(state.context.rows)[0]?.source_type || "NO SOURCE";
    setFormMessage(`${state.context.department_code} · ${source} Cutting source · Full-colour assignment · Transaction-safe work actions.`, "success");
  } catch (error) {
    console.error(error);
    state.context = null;
    $("colours").innerHTML = "";
    setFormMessage(errorText(error), "error");
  }
}

function workerOptions(selectedWorkerId = "", placeholder = "Select worker") {
  return `<option value="">${esc(placeholder)}</option>${arr(state.context?.workers).map(worker => `
    <option value="${esc(worker.worker_id)}" data-name="${esc(worker.worker_name)}" data-code="${esc(worker.worker_code || "")}" ${String(worker.worker_id) === String(selectedWorkerId || "") ? "selected" : ""}>
      ${esc(worker.worker_name)}${worker.worker_code ? ` · ${esc(worker.worker_code)}` : ""}
    </option>`).join("")}`;
}

function fillBulkWorker() {
  const select = $("bulkWorker");
  if (!select) return;
  const selected = select.value;
  select.innerHTML = workerOptions(selected, "Select one worker for selected Colours");
  if (![...select.options].some(option => option.value === selected)) select.value = "";
}

function renderSummary() {
  const total = state.context?.summary || {};
  $("summary").innerHTML = [
    ["Inbound", total.inbound],
    ["Assigned", total.assigned],
    ["Good", total.good],
    ["Ready Submit", total.ready_to_submit],
    ["Outbound", total.outbound],
    ["Alter Open", total.alter],
    ["Remake Open", total.remake],
    ["Damage", total.damage],
    ["Pending", total.pending]
  ].map(([label, value]) => `<div class="box"><small>${label}</small><b>${num(value)} PCS</b></div>`).join("");
}

function groups() {
  const map = new Map();
  arr(state.context?.rows).forEach((row, index) => {
    const key = rowKey(row);
    if (!map.has(key)) map.set(key, {
      ...row, rows: [], indexes: [], total: 0, inboundTotal: 0, pendingTotal: 0,
      submitReadyTotal: 0, outboundTotal: 0, unresolvedTotal: 0, canAssign: false
    });
    const group = map.get(key);
    group.rows.push(row);
    group.indexes.push(index);
    group.total += num(row.cutting_qty);
    group.inboundTotal += num(row.inbound_qty);
    group.pendingTotal += num(row.pending_qty);
    group.submitReadyTotal += num(row.submit_ready_qty);
    group.outboundTotal += num(row.outbound_qty);
    group.unresolvedTotal += num(row.pending_qty) + num(row.alter_open_qty ?? row.alter_qty) + num(row.remake_open_qty ?? row.remake_qty) + num(row.submit_ready_qty);
    group.canAssign = group.canAssign || Boolean(row.can_assign);
  });
  return [...map.values()];
}

function statusBadge(group) {
  if (!group.is_locked && !group.canAssign) return '<span class="badge warn">WAITING PREVIOUS SUBMIT</span>';
  if (!group.is_locked) return '<span class="badge ok">OPEN FOR ASSIGNMENT</span>';
  if (group.unresolvedTotal <= 0) return '<span class="badge ok">SUBMITTED / CAUGHT UP</span>';
  return '<span class="badge lock">ASSIGNED / IN PROGRESS</span>';
}

function renderColours() {
  renderSummary();
  const colourGroups = groups();
  $("colours").innerHTML = colourGroups.map(group => {
    const assigned = Boolean(group.is_locked);
    const canAssign = !assigned && Boolean(group.canAssign);
    const done = assigned && group.unresolvedTotal <= 0;
    return `<article class="colour-card ${assigned ? "assigned" : ""} ${done ? "done" : ""} ${!assigned && !canAssign ? "waiting" : ""}" data-colour-key="${esc(rowKey(group))}">
      <div class="colour-head">
        <div class="colour-title">
          ${assigned
            ? `<input class="work-pick" type="checkbox" ${done ? "disabled" : ""} title="Select this assigned colour for work actions or Submit">`
            : `<input class="assign-pick" type="checkbox" ${canAssign ? "" : "disabled"} title="${canAssign ? "Select complete colour" : "Waiting for previous department Submit"}">`}
          <div><h3>${esc(group.colour_name || group.colour_code)} <span class="badge">${esc(group.colour_code)}</span></h3>
          <div class="muted">${esc(group.source_type)} · Cutting ${group.total} PCS · ${group.rows.length} Sizes permanently bound</div></div>
        </div>
        <div class="worker-block">
          <label>${assigned ? "Current Worker" : "Worker — complete Colour + all Sizes"}
            <select class="colour-worker" ${assigned || !canAssign ? "disabled" : ""}>${workerOptions(group.worker_id)}</select>
          </label>
          <label>${assigned ? "Reassign all direct Pending to" : "Route gate"}
            ${assigned
              ? `<select class="reassign-worker" ${done ? "disabled" : ""}>${workerOptions("", "Select new worker")}</select>`
              : `<input value="${canAssign ? "OPEN AFTER UPSTREAM SUBMIT" : "LOCKED · WAITING PREVIOUS SUBMIT"}" disabled>`}
          </label>
        </div>
      </div>
      <div class="colour-meta">${statusBadge(group)}
        <span class="muted">Inbound ${group.inboundTotal} · Pending ${group.pendingTotal} · Ready Submit ${group.submitReadyTotal} · Outbound ${group.outboundTotal}</span>
        <span class="muted">Worker ownership never splits by size.</span>
      </div>
      <div class="size-wrap"><table>
        <thead><tr><th>Size</th><th>Cut</th><th>Inbound</th><th>Pending</th><th>Alter Entry</th><th>Remake Issue</th><th>Remake Complete</th><th>Damage Qty</th><th>Damage From</th><th>Good Total</th><th>Ready Submit</th><th>Outbound</th><th>Alter Open</th><th>Remake Open</th><th>Damage Total</th><th>Status</th></tr></thead>
        <tbody>${group.rows.map((row, rowIndex) => {
          const enabled = assigned && !done;
          const alterOpen = num(row.alter_open_qty ?? row.alter_qty);
          const remakeOpen = num(row.remake_open_qty ?? row.remake_qty);
          return `<tr data-row-index="${group.indexes[rowIndex]}">
            <td><b>${esc(row.size_code)}</b></td><td>${num(row.cutting_qty)}</td><td>${num(row.inbound_qty)}</td><td>${num(row.pending_qty)}</td>
            <td><input class="alterEntry" type="number" min="0" max="${num(row.pending_qty)}" value="0" ${enabled ? "" : "disabled"}></td>
            <td><input class="remakeIssueEntry" type="number" min="0" max="${alterOpen}" value="0" ${enabled && alterOpen > 0 ? "" : "disabled"}></td>
            <td><input class="remakeCompleteEntry" type="number" min="0" max="${remakeOpen}" value="0" ${enabled && remakeOpen > 0 ? "" : "disabled"}></td>
            <td><input class="damageEntry" type="number" min="0" value="0" ${enabled ? "" : "disabled"}></td>
            <td><select class="damageSource source-select" ${enabled ? "" : "disabled"}><option value="PENDING">Pending</option><option value="ALTER">Alter</option><option value="REMAKE">Remake</option></select></td>
            <td>${num(row.good_qty)}</td><td>${num(row.submit_ready_qty)}</td><td>${num(row.outbound_qty)}</td><td>${alterOpen}</td><td>${remakeOpen}</td><td>${num(row.damage_qty)}</td><td>${esc(row.status)}</td>
          </tr>`;
        }).join("")}</tbody>
      </table></div>
    </article>`;
  }).join("") || '<div class="empty"><h3>No Colour × Size mapping found</h3><p>Run Flow Debug. Server checks Single and Multi Lot Cutting sources.</p></div>';
}

function selectedOpenGroups() {
  const groupList = groups();
  return [...document.querySelectorAll(".colour-card")].filter(card => card.querySelector(".assign-pick")?.checked).map(card => {
    const group = groupList.find(item => String(rowKey(item)) === String(card.dataset.colourKey));
    const select = card.querySelector(".colour-worker");
    const option = select?.options[select.selectedIndex];
    return {
      group,
      worker_id: select?.value || null,
      worker_name: option?.dataset.name || "",
      worker_code: option?.dataset.code || ""
    };
  });
}

function selectedAssignedGroups() {
  const groupList = groups();
  return [...document.querySelectorAll(".colour-card")].filter(card => card.querySelector(".work-pick")?.checked).map(card => ({
    card,
    group: groupList.find(item => String(rowKey(item)) === String(card.dataset.colourKey))
  }));
}

function selectedRows() {
  const rows = [];
  selectedAssignedGroups().forEach(selection => {
    selection.card.querySelectorAll("[data-row-index]").forEach(tableRow => {
      rows.push({
        row: state.context.rows[Number(tableRow.dataset.rowIndex)],
        tableRow
      });
    });
  });
  return rows;
}

function setBusy(on) {
  state.busy = on;
  document.querySelectorAll(".actions button").forEach(button => button.disabled = on);
}

async function runBusy(work, successText) {
  if (state.busy) return null;
  setBusy(true);
  try {
    const result = await work();
    await loadContext();
    if (successText) setFormMessage(successText, "success");
    return result;
  } catch (error) {
    console.error(error);
    setFormMessage(errorText(error), "error");
    return null;
  } finally {
    setBusy(false);
  }
}

async function assignWork() {
  await runBusy(async () => {
    const selected = selectedOpenGroups();
    if (!selected.length) throw new Error("Select at least one open colour.");
    const rows = selected.map(item => {
      if (!item.worker_id) throw new Error(`${item.group.colour_name}: worker required.`);
      return {
        colour_id: item.group.colour_id,
        colour_code: item.group.colour_code,
        worker_id: item.worker_id,
        assigned_qty: item.group.total,
        actual_rate: num($("actualRate").value)
      };
    });
    await rpc("rr_upm_assign_colours_v8_3", {
      p_canonical_lot_id: state.lot.canonical_lot_id,
      p_lot_no: state.lot.lot_no,
      p_department_code: $("dept").value,
      p_rows: rows,
      p_remarks: "Universal Lot Form complete-colour assignment"
    });
  }, "Selected colours assigned with all sizes.");
}

function buildActionRows(actionType, inputClass) {
  const selected = selectedRows();
  if (!selected.length) throw new Error("Select at least one assigned colour using its Work checkbox.");
  const actions = [];
  selected.forEach(({row, tableRow}) => {
    const input = tableRow.querySelector(`.${inputClass}`);
    const qty = num(input?.value);
    if (qty <= 0) return;
    const pending = num(row.pending_qty);
    const alterOpen = num(row.alter_open_qty ?? row.alter_qty);
    const remakeOpen = num(row.remake_open_qty ?? row.remake_qty);
    let sourceBucket = "PENDING";
    let maximum = pending;
    if (actionType === "REMAKE_ISSUE") maximum = alterOpen;
    if (actionType === "REMAKE_COMPLETE") maximum = remakeOpen;
    if (actionType === "DAMAGE") {
      sourceBucket = upper(tableRow.querySelector(".damageSource")?.value || "PENDING");
      maximum = sourceBucket === "ALTER" ? alterOpen : sourceBucket === "REMAKE" ? remakeOpen : pending;
    }
    if (qty > maximum) throw new Error(`${row.colour_name}/${row.size_code}: ${actionType} ${qty} exceeds available ${maximum} in ${sourceBucket}.`);
    actions.push({
      request_id: requestId(),
      colour_id: row.colour_id,
      colour_code: row.colour_code,
      colour_name: row.colour_name,
      size_code: row.size_code,
      action_type: actionType,
      source_bucket: sourceBucket,
      qty
    });
  });
  if (!actions.length) throw new Error(`Enter quantity for ${actionType.replaceAll("_", " ")}.`);
  return actions;
}

async function applyAction(actionType, inputClass, successText) {
  await runBusy(async () => {
    const actions = buildActionRows(actionType, inputClass);
    await rpc("rr_upm_apply_actions_batch_v726", {
      p_canonical_lot_id: state.lot.canonical_lot_id,
      p_department_code: $("dept").value,
      p_actions: actions,
      p_rate: num($("actualRate").value),
      p_remarks: "Universal Lot Form"
    });
  }, successText);
}

async function reassignPending() {
  await runBusy(async () => {
    const selected = selectedAssignedGroups();
    if (!selected.length) throw new Error("Select at least one assigned colour.");
    const rows = selected.map(({card, group}) => {
      const select = card.querySelector(".reassign-worker");
      if (!select?.value) throw new Error(`${group.colour_name}: select new worker.`);
      if (String(select.value) === String(group.worker_id)) throw new Error(`${group.colour_name}: new worker is the same as current worker.`);
      if (group.pendingTotal <= 0) throw new Error(`${group.colour_name}: no pending work to reassign.`);
      return {colour_id: group.colour_id, colour_code: group.colour_code, new_worker_id: select.value};
    });
    await rpc("rr_upm_reassign_colours_v726", {
      p_canonical_lot_id: state.lot.canonical_lot_id,
      p_department_code: $("dept").value,
      p_rows: rows,
      p_remarks: "Pending work reassignment from Universal Lot Form"
    });
  }, "Remaining pending work reassigned. Previous worker history is preserved.");
}

function selectAllOpenColours() {
  document.querySelectorAll(".assign-pick:not(:disabled)").forEach(input => input.checked = true);
}

function applyBulkWorker() {
  const workerId = $("bulkWorker")?.value || "";
  if (!workerId) {
    setFormMessage("Select one worker first.", "error");
    return;
  }
  const selectedCards = [...document.querySelectorAll(".colour-card")].filter(card => card.querySelector(".assign-pick")?.checked);
  if (!selectedCards.length) {
    setFormMessage("Select one, multiple or ALL open Colours first.", "error");
    return;
  }
  selectedCards.forEach(card => {
    const select = card.querySelector(".colour-worker:not(:disabled)");
    if (select) select.value = workerId;
  });
  setFormMessage(`Worker applied to ${selectedCards.length} selected Colour(s). All Cutting sizes remain bound.`, "success");
}

async function submitSelectedColours() {
  const result = await runBusy(async () => {
    const selected = selectedAssignedGroups();
    if (!selected.length) throw new Error("Select at least one assigned Colour using its Work checkbox.");
    const rows = selected.map(({group}) => ({colour_id: group.colour_id, colour_code: group.colour_code}));
    return rpc("rr_upm_submit_colours_v727", {
      p_canonical_lot_id: state.lot.canonical_lot_id,
      p_department_code: $("dept").value,
      p_rows: rows,
      p_rate: num($("actualRate").value),
      p_remarks: "Universal Lot Form Colour Submit"
    });
  });
  if (!result) return;
  const next = result.next_department_code || "FINAL / COMPLETE";
  setFormMessage(`${result.colours_submitted || 0} Colour(s) submitted · ${num(result.qty_forwarded)} PCS opened in ${next}. Open Alter/Remake stayed in current department.`, "success");
}

async function saveRates() {
  await runBusy(async () => {
    await rpc("rr_upm_set_department_rate_v2", {
      p_canonical_lot_id: state.lot.canonical_lot_id,
      p_department_code: $("dept").value,
      p_actual_rate: num($("actualRate").value)
    });
    if (state.context.can_change_standard && $("standardRate").value !== "") {
      await rpc("rr_upm_set_standard_rate_v723", {
        p_canonical_lot_id: state.lot.canonical_lot_id,
        p_department_code: $("dept").value,
        p_standard_rate: num($("standardRate").value),
        p_reason: "Universal Lot Form"
      });
    }
    if (state.context.can_change_margin && $("ownerMargin").value !== "") {
      await rpc("rr_upm_set_owner_margin_v723", {
        p_amount: num($("ownerMargin").value),
        p_reason: "Universal Lot Form owner margin update"
      });
    }
  }, "Rates saved.");
}

async function runDebug() {
  if (!state.lot) return;
  try {
    $("debugOutput").textContent = "Running server checks…";
    const output = await rpc("rr_upm_debug_lot_flow_v726", {
      p_canonical_lot_id: state.lot.canonical_lot_id,
      p_department_code: $("dept").value
    });
    $("debugOutput").textContent = JSON.stringify(output, null, 2);
    setFormMessage(output?.ok ? "Flow debug passed." : "Flow debug found issues. Open Technical flow debug.", output?.ok ? "success" : "error");
  } catch (error) {
    console.error(error);
    $("debugOutput").textContent = errorText(error);
    setFormMessage(errorText(error), "error");
  }
}

function openGallery(images, index) {
  if (!images.length) return;
  state.images = images;
  state.imageIndex = index;
  state.scale = 1;
  showImage();
  $("gallery").classList.remove("hidden");
}

function showImage() {
  const image = $("galleryImg");
  image.src = state.images[state.imageIndex];
  image.style.transform = `scale(${state.scale})`;
  $("galleryCount").textContent = `${state.imageIndex + 1} / ${state.images.length}`;
}

function moveImage(direction) {
  state.imageIndex = (state.imageIndex + direction + state.images.length) % state.images.length;
  state.scale = 1;
  showImage();
}

function bindGallery() {
  const gallery = $("gallery");
  const image = $("galleryImg");
  gallery.querySelector(".close").onclick = () => gallery.classList.add("hidden");
  gallery.querySelector(".prev").onclick = () => moveImage(-1);
  gallery.querySelector(".next").onclick = () => moveImage(1);
  image.ondblclick = () => { state.scale = state.scale === 1 ? 2 : 1; showImage(); };
  gallery.addEventListener("wheel", event => {
    event.preventDefault();
    state.scale = Math.min(4, Math.max(1, state.scale + (event.deltaY < 0 ? .25 : -.25)));
    showImage();
  }, {passive: false});
  gallery.addEventListener("touchstart", event => state.startX = event.changedTouches[0].clientX, {passive: true});
  gallery.addEventListener("touchend", event => {
    const distance = event.changedTouches[0].clientX - state.startX;
    if (Math.abs(distance) > 45) moveImage(distance < 0 ? 1 : -1);
  }, {passive: true});
}

async function boot() {
  try {
    state.sb = window.supabaseClient || window.supabaseDb || window.redzedSupabase || window.sb;
    if (!state.sb) throw new Error("Supabase client unavailable.");
    const sessionResult = await state.sb.auth.getSession();
    if (sessionResult.error || !sessionResult.data?.session) {
      location.replace("real-login.html");
      throw new Error("Login required.");
    }
    const access = await rpc("rr_upm_access_context_v727");
    if (!access?.allowed) throw new Error(access?.reason || "Production access denied by Role & Permission.");
    $("refresh").onclick = load;
    $("search").oninput = renderBoard;
    $("homeDept").onchange = renderBoard;
    $("dept").onchange = loadContext;
    document.querySelector("[data-close]").onclick = () => $("traveller").classList.add("hidden");
    document.querySelectorAll("[data-link]").forEach(button => button.onclick = () => location.href = button.dataset.link);
    $("packingTab").onclick = () => setMessage("Existing Smart Packing remains unchanged.");
    $("costingTab").onclick = () => setMessage("Costing uses existing ledgers.");
    $("reportsTab").onclick = () => setMessage("Use Worker and Department ledger views.");
    $("selectAllBtn").onclick = selectAllOpenColours;
    $("applyBulkWorkerBtn").onclick = applyBulkWorker;
    $("assignBtn").onclick = assignWork;
    $("submitBtn").onclick = submitSelectedColours;
    $("alterBtn").onclick = () => applyAction("ALTER", "alterEntry", "Alter registered and removed from direct pending.");
    $("remakeIssueBtn").onclick = () => applyAction("REMAKE_ISSUE", "remakeIssueEntry", "Remake issued from open Alter.");
    $("remakeCompleteBtn").onclick = () => applyAction("REMAKE_COMPLETE", "remakeCompleteEntry", "Remake completed and added to Good total.");
    $("damageBtn").onclick = () => applyAction("DAMAGE", "damageEntry", "Damage saved from the selected source bucket.");
    $("reassignBtn").onclick = reassignPending;
    $("saveRates").onclick = saveRates;
    $("debugBtn").onclick = runDebug;
    bindGallery();
    await load();
  } catch (error) {
    console.error(error);
    setMessage(errorText(error), "error");
  }
}

document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", boot) : boot();
})();
