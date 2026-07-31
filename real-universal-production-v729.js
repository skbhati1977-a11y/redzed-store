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
  busy: false, pendingSubmitRows: null, cameraStream: null, cameraBlobs: [], mapping: null
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
    <div class="box"><small>ART NO</small><b id="identityArt">${esc(lot.art_no || "MAPPING REQUIRED")}</b></div>
    <div class="box"><small>PRINT NO</small><b id="identityPrint">${esc(lot.print_no || "MAPPING REQUIRED")}</b></div>
    <div class="box"><small>FRAME NO</small><b id="identityFrame">${esc(lot.frame_no || "MAPPING REQUIRED")}</b></div>
    <div class="box"><small>TOTAL CUTTING</small><b>${num(lot.total_qty)} PCS</b></div>
    <div class="box"><small>ITEM</small><b>${esc(lot.item_name || "—")}</b></div>`;
  $("entryThumbs").innerHTML = thumbnails(lot, 20);
  wireImages($("entryThumbs"));
}

async function loadContext() {
  if (!state.lot || !$("dept").value) return;
  try {
    setFormMessage("Verified Single/Multi Cutting mapping and workflow balances loading…");
    state.context = await rpc("rr_upm_universal_form_v740", {
      p_canonical_lot_id: state.lot.canonical_lot_id,
      p_department_code: $("dept").value
    });
    if (state.context?.lot) {
      const identity = state.context.lot;
      [["cb_no","identityCb"],["art_no","identityArt"],["print_no","identityPrint"],["frame_no","identityFrame"]].forEach(([key,id]) => {
        const value = identity[key];
        if (value && !/MAPPING REQUIRED|^—$|^â€”$/i.test(String(value))) { if ($(id)) $(id).textContent = value; state.lot[key] = value; }
      });
    }
    $("actualRate").value = state.context.actual_rate ?? 0;
    $("standardRate").value = state.context.standard_rate ?? "";
    $("ownerMargin").value = state.context.owner_margin ?? "";
    const showOwner = Boolean(state.context.can_view_standard);
    $("stdWrap").classList.toggle("hidden", !showOwner);
    $("marginWrap").classList.toggle("hidden", !showOwner);
    fillBulkWorker();
    state.mapping = state.context.mapping_context || {};
    filterDepartmentDropdown();
    const lockedRoute = state.context.route_locked_to;
    $("routeNote").textContent = lockedRoute ? `Current Owner: ${state.context.department_code} · Submit Route Locked: ${lockedRoute}` : `Current Owner: ${state.context.department_code} · First Submit पर Next Department चुनें.`;
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

function currentDepartmentWorkers() {
  const department = upper($("dept")?.value || state.context?.department_code);
  return arr(state.context?.workers).filter(worker => upper(worker.department_code) === department);
}


function filterDepartmentDropdown(){
  const running=arr(state.context?.running_departments);
  if(!running.length)return;
  const current=upper(state.context?.department_code||$("dept").value);
  const allowed=new Set(running.map(x=>upper(x.department_code)));
  if(current)allowed.add(current);
  [...$("dept").options].forEach(o=>o.hidden=!allowed.has(upper(o.value)));
  const visible=[...$("dept").options].filter(o=>!o.hidden);
  if(visible.length&&![...visible].some(o=>o.value===$("dept").value))$("dept").value=visible[0].value;
}
function lmCandidates(){return arr(state.mapping?.line_man_candidates);}
function openWhatsApp(result){if(result?.whatsapp_url)window.open(result.whatsapp_url,"_blank","noopener");}

function workerOptions(selectedWorkerId = "", placeholder = "Select worker") {
  return `<option value="">${esc(placeholder)}</option>${currentDepartmentWorkers().map(worker => `
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

function responsibilityLabel(type) {
  return ({ALTER_PENDING:"ALTER PENDING",LINE_MAN_PENDING:"LINE MAN PENDING",WORKER_REMAKE_PENDING:"WORKER REMAKE PENDING",DAMAGE:"DAMAGE"})[type] || type;
}

function responsibilityKind(type) {
  return type === "ALTER_PENDING" ? "alter" : type === "DAMAGE" ? "damage" : "remake";
}

function renderSummary() {
  const total = state.context?.summary || {};
  $("summary").innerHTML = [
    ["Main Qty", total.main, ""], ["Good Qty", total.good, "good"],
    ["Alter Journey", num(total.alter)+num(total.line_man_pending)+num(total.remake), "alter"], ["Damage", total.damage, "damage"]
  ].map(([label,value,kind])=>`<div class="box summary-box ${kind} ${num(value)>0&&kind?"blink-live":""}"><small>${label}</small><b>${num(value)} PCS</b></div>`).join("");
  const rows=arr(state.context?.active_alter_summary), freeze=$("freezeSummary"); if(!freeze)return;
  const kinds={LM_ALTER_PENDING:"blink-alter",CM_REMAKE_READY:"blink-cm",LM_DELIVERY_PENDING:"blink-lm",KARIGAR_REMAKE_PENDING:"blink-karigar",UNTRACEABLE_APPROVAL:"blink-damage"};
  freeze.innerHTML=rows.length?rows.map(row=>`<section class="freeze-group ${kinds[row.stage]||""}">
    <div class="freeze-title"><span>${esc(row.responsible_name||"MAPPING")}${row.responsible_role_short?` · ${esc(row.responsible_role_short)}`:""}</span><strong>${num(row.qty)} PCS</strong></div>
    <div class="responsibility-row"><label><input class="journey-pick" type="checkbox" value="${esc(row.journey_id)}"> ${esc(row.stage_label)} · ${esc(row.colour_name||row.colour_code)} / ${esc(row.size_code)}</label></div>
  </section>`).join(""):'<section class="freeze-group"><div class="freeze-title"><span>ALTER JOURNEY</span><strong>NONE</strong></div></section>';
}
function groups() {
  const map = new Map();
  arr(state.context?.rows).forEach((row, index) => {
    const key = rowKey(row);
    if (!map.has(key)) map.set(key, {
      ...row, rows: [], indexes: [], total: 0, goodTotal: 0, alterTotal: 0, lineManTotal: 0, workerRemakeTotal: 0, damageTotal: 0, unresolvedTotal: 0, canAssign: false
    });
    const group = map.get(key);
    group.rows.push(row);
    group.indexes.push(index);
    group.total += num(row.cutting_qty);
    group.goodTotal += num(row.good_qty);
    group.alterTotal += num(row.alter_open_qty ?? row.alter_qty);
    group.lineManTotal += num(row.line_man_pending_qty);
    group.workerRemakeTotal += num(row.worker_remake_pending_qty ?? row.remake_qty);
    group.damageTotal += num(row.damage_qty);
    group.unresolvedTotal += num(row.alter_open_qty ?? row.alter_qty) + num(row.line_man_pending_qty) + num(row.worker_remake_pending_qty ?? row.remake_qty);
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
        <span class="muted">Main ${group.total} · Good ${group.goodTotal} · Alter ${group.alterTotal} · Line Man ${group.lineManTotal} · Worker Remake ${group.workerRemakeTotal} · Damage ${group.damageTotal}</span>
        <span class="muted">Worker ownership never splits by size.</span>
      </div>
      <div class="size-wrap"><table>
        <thead><tr><th>Size</th><th>Main Qty</th><th>Good Qty</th><th>Alter Fill</th><th>Alter Pending</th><th>Remake Issue · CM</th><th>Master Ready / LM Pending</th><th>Receive Master · LM</th><th>Deliver Karigar · LM</th><th>Karigar Pending</th><th>Receive Karigar · LM</th><th>Saved Damage</th><th>Add Damage</th><th>Damage From</th><th>Status</th></tr></thead>
        <tbody>${group.rows.map((row, rowIndex) => {
          const enabled = assigned && !done;
          const alterOpen = num(row.alter_open_qty ?? row.alter_qty);
          const remakeOpen = num(row.remake_open_qty ?? row.remake_qty);
          return `<tr data-row-index="${group.indexes[rowIndex]}">
            <td><b>${esc(row.size_code)}</b></td><td>${num(row.main_qty ?? row.cutting_qty)}</td><td><b>${num(row.good_qty)}</b></td>
            <td><input class="alterEntry" type="number" min="0" max="${Math.min(num(row.good_qty),num(row.pending_qty))}" value="0" ${enabled ? "" : "disabled"}></td>
            <td>${alterOpen}</td>
            <td><input class="remakeIssueEntry" type="number" min="0" max="${alterOpen}" value="0" ${enabled && alterOpen > 0 ? "" : "disabled"}></td>
            <td>${num(row.line_man_pending_qty)}</td>
            <td><input class="receiveMasterEntry" type="number" min="0" max="${num(row.line_man_pending_qty)}" value="0" ${enabled && num(row.line_man_pending_qty)>0 ? "" : "disabled"}></td>
            <td><input class="deliverKarigarEntry" type="number" min="0" max="${num(row.line_man_pending_qty)}" value="0" ${enabled && num(row.line_man_pending_qty)>0 ? "" : "disabled"}></td>
            <td>${num(row.worker_remake_pending_qty ?? remakeOpen)}</td>
            <td><input class="receiveKarigarEntry" type="number" min="0" max="${num(row.worker_remake_pending_qty ?? remakeOpen)}" value="0" ${enabled && num(row.worker_remake_pending_qty ?? remakeOpen)>0 ? "" : "disabled"}></td>
            <td>${num(row.damage_qty)}</td>
            <td><input class="damageEntry" type="number" min="0" value="0" ${enabled ? "" : "disabled"}></td>
            <td><select class="damageSource source-select" ${enabled ? "" : "disabled"}><option value="PENDING">Good Qty</option><option value="ALTER">Alter Pending</option><option value="REMAKE">Remake Pending</option></select></td>
            <td>${esc(row.status)}</td>
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
      p_evidence_urls: [],
      p_physical_confirmed: false,
      p_line_man_id: null,
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
    if (actionType === "DAMAGE") {
      await rpc("rr_upm_save_damage_v731", {
        p_canonical_lot_id: state.lot.canonical_lot_id,
        p_department_code: $("dept").value,
        p_rows: actions,
        p_rate: num($("actualRate").value),
        p_remarks: "Universal Lot Form bucket-wise Damage"
      });
      return;
    }
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
      p_evidence_urls: [],
      p_physical_confirmed: false,
      p_line_man_id: null,
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

async function doSubmitWithRoute(nextDepartment=null){
  const selected=state.pendingSubmitRows||selectedAssignedGroups();
  if(!selected.length)throw new Error("Select at least one assigned Colour using its Work checkbox.");
  const rows=selected.map(({group})=>({colour_id:group.colour_id,colour_code:group.colour_code}));
  return rpc("rr_upm_submit_colours_v740",{p_canonical_lot_id:state.lot.canonical_lot_id,p_department_code:$("dept").value,p_rows:rows,p_next_department_code:nextDepartment,p_rate:num($("actualRate").value),p_remarks:"Universal Lot Form Colour Submit"});
}
async function submitSelectedColours(){
  const selected=selectedAssignedGroups(); if(!selected.length){setFormMessage("Select at least one assigned Colour.","error");return;}
  state.pendingSubmitRows=selected;
  if(!state.context?.route_locked_to){
    const opts=state.departments.filter(d=>d.is_active!==false&&upper(d.department_code)!==upper($("dept").value));
    $("nextDepartmentSelect").innerHTML='<option value="">Select Next Department</option>'+opts.map(d=>`<option value="${esc(d.department_code)}">${esc(d.department_name)}</option>`).join("");
    $("routeModal").classList.remove("hidden");return;
  }
  const result=await runBusy(()=>doSubmitWithRoute(state.context.route_locked_to)); if(result)setFormMessage(`${result.colours_submitted||0} Colour(s) submitted to ${result.next_department_code}. Route locked.`,"success");
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
    const output = await rpc("rr_upm_debug_v740", {
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


function selectedStageRows(inputClass) {
  const selected = selectedRows();
  if (!selected.length) throw new Error("Select at least one assigned Colour using its Work checkbox.");
  return selected.map(({row, tableRow}) => ({
    colour_id: row.colour_id || null,
    colour_code: row.colour_code,
    colour_name: row.colour_name,
    size_code: row.size_code,
    qty: num(tableRow.querySelector(`.${inputClass}`)?.value)
  })).filter(row => row.qty > 0);
}

async function uploadAlterEvidence(files) {
  if (files.length < 1 || files.length > 3) throw new Error("Capture minimum 1 and maximum 3 live camera images.");
  const urls = [];
  for (const file of files) {
    if (!/^image\/(jpeg|png|webp)$/i.test(file.type || "")) throw new Error(`Unsupported evidence image: ${file.name}`);
    const ext = (file.name.split(".").pop() || "jpg").toLowerCase();
    const path = `${state.lot.canonical_lot_id}/${upper($("dept").value)}/${Date.now()}-${requestId()}.${ext}`;
    const {error} = await state.sb.storage.from("production-evidence").upload(path, file, {upsert: false, contentType: file.type});
    if (error) throw error;
    urls.push(path);
  }
  return urls;
}

function openAlterEvidenceModal() {
  const rows = selectedStageRows("alterEntry");
  if (!rows.length) throw new Error("Enter Alter Fill Qty in at least one selected size.");
  state.pendingAlterRows = rows;
  const candidates=lmCandidates(); const enrolled=state.mapping?.line_man_enrolment;
  $("alterLineManSelect").innerHTML=candidates.map(x=>`<option value="${esc(x.worker_id)}" ${String(enrolled?.person_id||"")===String(x.worker_id)?"selected":""}>${esc(x.worker_name)} · ${esc(x.worker_code||"")} · ${esc(x.department_code||"")}</option>`).join("");
  if(!candidates.length)throw new Error("No mapped Line Man found in Worker Directory / Fabrication.");
  if(enrolled)$("alterLineManSelect").disabled=true; else $("alterLineManSelect").disabled=candidates.length===1;
  state.cameraBlobs=[];
  $("alterEvidenceFiles").value = "";
  $("physicalEvidenceSubmitted").checked = false;
  $("alterEvidencePreview").innerHTML = "";
  $("alterEvidenceMsg").textContent = "";
  $("alterEvidenceModal").classList.remove("hidden");
}

async function saveAlterEvidence() {
  const files = state.cameraBlobs.length ? state.cameraBlobs : [...($("alterEvidenceFiles").files || [])].slice(0, 3);
  const physical = $("physicalEvidenceSubmitted").checked;
  if (!physical) throw new Error("Confirm physical evidence submission.");
  const paths = await uploadAlterEvidence(files);
  const result = await rpc("rr_upm_alter_stage_v740", {
    p_stage: "ALTER_FILL",
    p_canonical_lot_id: state.lot.canonical_lot_id,
    p_department_code: $("dept").value,
    p_rows: state.pendingAlterRows || [],
    p_evidence_urls: paths,
    p_physical_confirmed: true,
    p_line_man_id: $("alterLineManSelect").value || null,
    p_remarks: "Universal Lot Form Alter Fill by mapped Line Man"
  });
  $("alterEvidenceModal").classList.add("hidden");
  await loadContext();
  setFormMessage(`${result.rows_saved || 0} Alter row(s) saved with mapped Lot Line Man.`, "success"); openWhatsApp(result);
}

async function runRemakeStage(stage, inputClass, successText) {
  return runBusy(async () => {
    const rows = selectedStageRows(inputClass);
    if (!rows.length) throw new Error(`Enter Qty for ${successText}.`);
    return rpc("rr_upm_alter_stage_v740", {
      p_stage: stage,
      p_canonical_lot_id: state.lot.canonical_lot_id,
      p_department_code: $("dept").value,
      p_rows: rows,
      p_evidence_urls: [],
      p_physical_confirmed: false,
      p_line_man_id: null,
      p_remarks: `Universal Lot Form ${successText}`
    });
  }, successText);
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
    $("alterBtn").onclick = () => { try { openAlterEvidenceModal(); } catch (error) { setFormMessage(errorText(error), "error"); } };
    $("remakeIssueBtn").onclick=()=>runRemakeStage("REMAKE_ISSUE","remakeIssueEntry","Cutting Master Remake Issue saved.").then(openWhatsApp);
    $("remakeDeliveredBtn").onclick=()=>runRemakeStage("RECEIVE_FROM_MASTER","receiveMasterEntry","Line Man received from Master.").then(openWhatsApp);
    $("remakeCompleteBtn").onclick=()=>runRemakeStage("DELIVER_TO_KARIGAR","deliverKarigarEntry","Delivered to Karigar; responsibility started.").then(openWhatsApp);
    $("receiveKarigarBtn").onclick=()=>runRemakeStage("RECEIVE_FROM_KARIGAR","receiveKarigarEntry","Line Man final received; Qty returned to Good.").then(openWhatsApp);
    $("damageBtn").onclick = () => applyAction("DAMAGE", "damageEntry", "Damage saved from the selected source bucket.");
    $("reassignBtn").onclick = reassignPending;
    $("saveRates").onclick = saveRates;
    $("debugBtn").onclick = runDebug;
    $("closeAlterEvidence").onclick = () => $("alterEvidenceModal").classList.add("hidden");
    $("saveAlterEvidence").onclick = async () => { try { await saveAlterEvidence(); } catch (error) { $("alterEvidenceMsg").textContent = errorText(error); } };
    $("alterEvidenceFiles").onchange = () => { const files=[...($("alterEvidenceFiles").files||[])].slice(0,3); $("alterEvidencePreview").innerHTML=files.map(file=>`<span class="badge">${esc(file.name)}</span>`).join(""); };

    $("closeRouteModal").onclick=()=>$("routeModal").classList.add("hidden");
    $("confirmRouteSubmit").onclick=async()=>{try{const dep=$("nextDepartmentSelect").value;if(!dep)throw new Error("Select Next Department.");const result=await runBusy(()=>doSubmitWithRoute(dep));if(result){$("routeModal").classList.add("hidden");setFormMessage(`${result.colours_submitted||0} Colour(s) submitted to ${result.next_department_code}. Remaining Colours locked to same route.`,"success");}}catch(e){$("routeModalMsg").textContent=errorText(e)}};
    $("changeLmBtn").onclick=()=>{const c=lmCandidates(),cur=state.mapping?.line_man_enrolment;$("newLmSelect").innerHTML=c.filter(x=>String(x.worker_id)!==String(cur?.person_id||"")).map(x=>`<option value="${esc(x.worker_id)}">${esc(x.worker_name)} · ${esc(x.worker_code||"")}</option>`).join("");$("lmModal").classList.remove("hidden")};
    $("closeLmModal").onclick=()=>$("lmModal").classList.add("hidden");
    $("saveLmTransfer").onclick=async()=>{try{await rpc("rr_upm_transfer_lm_v740",{p_canonical_lot_id:state.lot.canonical_lot_id,p_department_code:$("dept").value,p_new_line_man_id:$("newLmSelect").value,p_mode:$("lmTransferMode").value,p_reason:$("lmTransferReason").value,p_physical_handover:$("lmPhysicalHandover").checked});$("lmModal").classList.add("hidden");await loadContext();}catch(e){$("lmModalMsg").textContent=errorText(e)}};
    $("untraceableBtn").onclick=async()=>{try{const ids=[...document.querySelectorAll(".journey-pick:checked")].map(x=>x.value);if(!ids.length)throw new Error("Select Alter summary rows.");const remark=prompt("Manager investigation / search remark");if(!remark)return;const r=await rpc("rr_upm_request_untraceable_v740",{p_canonical_lot_id:state.lot.canonical_lot_id,p_journey_ids:ids,p_manager_remark:remark});openWhatsApp(r);await loadContext();}catch(e){setFormMessage(errorText(e),"error")}};
    $("ownerApprovalBtn").onclick=async()=>{const {data,error}=await state.sb.from("rr_upm_untraceable_request_v740").select("*").eq("status","OWNER_PENDING").order("created_at",{ascending:false});if(error){setFormMessage(errorText(error),"error");return;}$("approvalList").innerHTML=arr(data).map(r=>`<div class="box"><b>${esc(r.lot_no)} · ${num(r.total_qty)} PCS</b><p>${esc(r.manager_name)}: ${esc(r.manager_remark)}</p><button data-decide="APPROVE" data-id="${r.id}">APPROVE COMPANY LOSS</button><button data-decide="DENY" data-id="${r.id}">DENY · MANAGER DEBIT</button><button data-decide="RECHECK" data-id="${r.id}">RETURN RECHECK</button></div>`).join("")||"No pending approvals.";$("approvalModal").classList.remove("hidden");$("approvalList").querySelectorAll("[data-decide]").forEach(b=>b.onclick=async()=>{const remark=prompt("Owner remark")||"";await rpc("rr_upm_decide_untraceable_v740",{p_request_id:b.dataset.id,p_decision:b.dataset.decide,p_owner_remark:remark});b.closest(".box").remove();await loadContext();});};
    $("closeApprovalModal").onclick=()=>$("approvalModal").classList.add("hidden");
    $("startCamera").onclick=async()=>{try{state.cameraStream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:"environment"}},audio:false});$("liveCamera").srcObject=state.cameraStream;$("liveCamera").classList.remove("hidden");$("captureCamera").disabled=false;$("stopCamera").disabled=false;}catch(e){$("alterEvidenceMsg").textContent="Live camera unavailable: "+errorText(e)}};
    $("captureCamera").onclick=()=>{if(state.cameraBlobs.length>=3){$("alterEvidenceMsg").textContent="Maximum 3 photos.";return;}const v=$("liveCamera"),c=$("cameraCanvas");c.width=v.videoWidth;c.height=v.videoHeight;c.getContext("2d").drawImage(v,0,0);c.toBlob(blob=>{blob.name=`alter-${Date.now()}.jpg`;state.cameraBlobs.push(blob);const url=URL.createObjectURL(blob);$("alterEvidencePreview").insertAdjacentHTML("beforeend",`<img src="${url}" class="thumb" alt="Evidence">`);},"image/jpeg",.85)};
    $("stopCamera").onclick=()=>{state.cameraStream?.getTracks().forEach(t=>t.stop());state.cameraStream=null;$("liveCamera").classList.add("hidden");$("captureCamera").disabled=true;$("stopCamera").disabled=true;};
    bindGallery();
    await load();
  } catch (error) {
    console.error(error);
    setMessage(errorText(error), "error");
  }
}

document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", boot) : boot();
})();
