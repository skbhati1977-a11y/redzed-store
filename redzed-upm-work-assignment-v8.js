(() => {
  'use strict';

  const VERSION = '8.0.0';
  const $ = (id) => document.getElementById(id);
  const safe = (value) => String(value ?? '').replace(/[&<>"']/g, (ch) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[ch]));

  const state = {
    client: null,
    lotId: '',
    lotNo: '',
    department: '',
    context: [],
    selected: new Set(),
    workers: [],
    commonWorkerId: ''
  };

  function client() {
    return window.supabaseClient || window.sb;
  }

  async function rpc(name, args) {
    const { data, error } = await state.client.rpc(name, args);
    if (error) throw error;
    return data;
  }

  function injectStyles() {
    if ($('rrAssignV8Styles')) return;
    const style = document.createElement('style');
    style.id = 'rrAssignV8Styles';
    style.textContent = `
      .rr-assign-open{background:#274b79!important;border-color:#4a83c2!important}
      .rr-assign-sheet{width:min(940px,100%);max-height:94vh;overflow:auto}
      .rr-assign-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
      .rr-colour-toolbar{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}
      .rr-colour-pick{display:flex;gap:8px;flex-wrap:wrap}
      .rr-colour-chip{border:1px solid #454550;background:#17171d;color:#fff;
        border-radius:999px;padding:9px 12px;font-weight:900}
      .rr-colour-chip.selected{background:#8e2632;border-color:#e05a68}
      .rr-colour-chip.locked{opacity:.55;cursor:not-allowed;text-decoration:line-through}
      .rr-assign-row{border:1px solid #383842;border-radius:13px;padding:12px;margin:10px 0;background:#111116}
      .rr-assign-row-head{display:flex;justify-content:space-between;gap:10px;align-items:center;flex-wrap:wrap}
      .rr-size-line{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:9px 0}
      .rr-size-pill{border:1px solid #383842;border-radius:999px;padding:6px 9px;white-space:nowrap}
      .rr-worker-line{display:grid;grid-template-columns:minmax(260px,1fr) 180px;gap:10px;align-items:end}
      .rr-worker-line select,.rr-worker-line input{width:100%}
      .rr-lock-note{color:#ffbd77;font-size:12px;margin-top:6px}
      .rr-assigned-banner{border:1px solid #2f8654;background:#102319;padding:10px;border-radius:10px;margin:10px 0}
      @media(max-width:700px){
        .rr-assign-grid,.rr-worker-line{grid-template-columns:1fr}
        .rr-assign-sheet{height:100vh;max-height:100vh;border-radius:0}
      }
    `;
    document.head.appendChild(style);
  }

  function injectModal() {
    if ($('rrAssignV8Modal')) return;
    const wrap = document.createElement('div');
    wrap.id = 'rrAssignV8Modal';
    wrap.className = 'modal hidden';
    wrap.innerHTML = `
      <form id="rrAssignV8Form" class="sheet rr-assign-sheet">
        <div class="top">
          <div>
            <small style="color:#d9a93d;font-weight:900">WORK ASSIGN V8</small>
            <h2 style="margin:4px 0">Assign Work — <span id="rrAssignLotNo">—</span></h2>
          </div>
          <button type="button" id="rrAssignClose">Close</button>
        </div>

        <div class="rr-assign-grid">
          <label class="field">
            <span>Department</span>
            <select id="rrAssignDept" required></select>
          </label>
          <label class="field">
            <span>Worker — one time select, selected rows me auto-copy</span>
            <select id="rrAssignCommonWorker">
              <option value="">Select worker</option>
            </select>
          </label>
        </div>

        <div class="rr-colour-toolbar">
          <button type="button" id="rrAssignAll">ALL COLOURS</button>
          <button type="button" id="rrAssignClear">CLEAR</button>
          <button type="button" class="primary" id="rrAssignOk">OK</button>
        </div>

        <div id="rrAssignColourPick" class="rr-colour-pick"></div>
        <div id="rrAssignRows"></div>

        <label class="field full">
          <span>Remarks</span>
          <textarea id="rrAssignRemarks" placeholder="Optional assignment remarks"></textarea>
        </label>

        <div id="rrAssignStatus" class="status-line">Select single, multiple or all colours.</div>
        <div class="actions">
          <button type="button" id="rrAssignCancel">Cancel</button>
          <button type="submit" class="primary" id="rrAssignSave">ASSIGN WORK</button>
        </div>
      </form>
    `;
    document.body.appendChild(wrap);

    $('rrAssignClose').onclick = closeModal;
    $('rrAssignCancel').onclick = closeModal;
    $('rrAssignDept').onchange = async () => {
      state.department = $('rrAssignDept').value;
      await loadWorkers();
      await loadContext();
    };
    $('rrAssignCommonWorker').onchange = () => {
      state.commonWorkerId = $('rrAssignCommonWorker').value;
      document.querySelectorAll('[data-row-worker]').forEach((el) => {
        el.value = state.commonWorkerId;
      });
    };
    $('rrAssignAll').onclick = () => {
      state.selected = new Set(state.context.filter((x) => !x.is_locked).map((x) => x.colour_code));
      renderColourPick();
    };
    $('rrAssignClear').onclick = () => {
      state.selected.clear();
      renderColourPick();
      $('rrAssignRows').innerHTML = '';
    };
    $('rrAssignOk').onclick = renderAssignmentRows;
    $('rrAssignV8Form').onsubmit = saveAssignments;
  }

  function closeModal() {
    $('rrAssignV8Modal')?.classList.add('hidden');
  }

  function departmentOptions() {
    const source = $('eDept');
    if (!source) return '<option value="">Department unavailable</option>';
    return [...source.options].map((o) =>
      `<option value="${safe(o.value)}">${safe(o.textContent)}</option>`
    ).join('');
  }

  async function openAssign(lotId, lotNo) {
    state.client = client();
    if (!state.client) return alert('Supabase client unavailable.');
    state.lotId = lotId;
    state.lotNo = lotNo;
    state.selected.clear();
    state.commonWorkerId = '';
    $('rrAssignLotNo').textContent = lotNo || '—';
    $('rrAssignDept').innerHTML = departmentOptions();
    state.department = $('rrAssignDept').value;
    $('rrAssignRemarks').value = '';
    $('rrAssignRows').innerHTML = '';
    $('rrAssignV8Modal').classList.remove('hidden');
    await loadWorkers();
    await loadContext();
  }

  async function loadWorkers() {
    $('rrAssignStatus').textContent = 'Loading workers…';
    const rows = await rpc('rr_upm_worker_list_v8', {
      p_department_code: state.department || null
    });
    state.workers = Array.isArray(rows) ? rows : [];
    const options = '<option value="">Select worker</option>' + state.workers.map((w) =>
      `<option value="${safe(w.worker_id)}">${safe(w.worker_name)} — ${safe(w.worker_code)}</option>`
    ).join('');
    $('rrAssignCommonWorker').innerHTML = options;
    state.commonWorkerId = '';
  }

  async function loadContext() {
    $('rrAssignStatus').textContent = 'Loading colour-size quantities…';
    const rows = await rpc('rr_upm_get_work_assign_context_v8', {
      p_canonical_lot_id: state.lotId,
      p_department_code: state.department
    });
    state.context = Array.isArray(rows) ? rows : [];
    state.selected.clear();
    renderColourPick();
    $('rrAssignRows').innerHTML = '';
    $('rrAssignStatus').textContent = state.context.length
      ? 'Tap one colour, multiple colours, or ALL COLOURS; then press OK.'
      : 'Cutting colour-size mapping not found for this Lot.';
  }

  function renderColourPick() {
    $('rrAssignColourPick').innerHTML = state.context.map((row) => {
      const selected = state.selected.has(row.colour_code);
      const cls = `rr-colour-chip${selected ? ' selected' : ''}${row.is_locked ? ' locked' : ''}`;
      const lock = row.is_locked
        ? ` — Assigned: ${safe(row.assigned_worker_name)} (${safe(row.assigned_worker_code)})`
        : ` — ${Number(row.total_qty || 0)} PCS`;
      return `<button type="button" class="${cls}" data-colour="${safe(row.colour_code)}"
        ${row.is_locked ? 'disabled' : ''}>${safe(row.colour_name || row.colour_code)}${lock}</button>`;
    }).join('');

    document.querySelectorAll('[data-colour]').forEach((btn) => {
      btn.onclick = () => {
        const code = btn.dataset.colour;
        if (state.selected.has(code)) state.selected.delete(code);
        else state.selected.add(code);
        renderColourPick();
      };
    });
  }

  function workerOptions(selectedId = '') {
    return '<option value="">Select worker</option>' + state.workers.map((w) =>
      `<option value="${safe(w.worker_id)}" ${w.worker_id === selectedId ? 'selected' : ''}>
        ${safe(w.worker_name)} — ${safe(w.worker_code)}
      </option>`
    ).join('');
  }

  function sizeHtml(row) {
    const sizes = Array.isArray(row.size_breakup) ? row.size_breakup : [];
    return sizes.map((s) =>
      `<span class="rr-size-pill"><b>${safe(s.size_code)}</b> ${Number(s.qty || 0)} PCS</span>`
    ).join('');
  }

  function renderAssignmentRows() {
    const selectedRows = state.context.filter((x) => state.selected.has(x.colour_code) && !x.is_locked);
    if (!selectedRows.length) {
      $('rrAssignRows').innerHTML = '';
      $('rrAssignStatus').textContent = 'Select at least one unassigned colour.';
      return;
    }

    $('rrAssignRows').innerHTML = selectedRows.map((row) => `
      <section class="rr-assign-row" data-assign-row="${safe(row.colour_code)}">
        <div class="rr-assign-row-head">
          <h3 style="margin:0">Colour ${safe(row.colour_name || row.colour_code)}</h3>
          <b>Total ${Number(row.total_qty || 0)} PCS</b>
        </div>
        <div class="rr-size-line">${sizeHtml(row)}</div>
        <div class="rr-worker-line">
          <label class="field">
            <span>Worker Name + Auto ID</span>
            <select data-row-worker required>${workerOptions(state.commonWorkerId)}</select>
          </label>
          <label class="field">
            <span>Assigned Qty — Auto</span>
            <input data-row-qty type="number" value="${Number(row.total_qty || 0)}" readonly>
          </label>
        </div>
      </section>
    `).join('');

    $('rrAssignStatus').textContent =
      `${selectedRows.length} colour selected. Qty auto-filled; common worker selected rows me copied.`;
  }

  async function saveAssignments(event) {
    event.preventDefault();
    try {
      const nodes = [...document.querySelectorAll('[data-assign-row]')];
      if (!nodes.length) throw new Error('Press OK after selecting colours.');

      const rows = nodes.map((node) => {
        const colour = node.dataset.assignRow;
        const workerId = node.querySelector('[data-row-worker]').value;
        const qty = Number(node.querySelector('[data-row-qty]').value || 0);
        if (!workerId) throw new Error(`Worker is required for colour ${colour}.`);
        return {
          colour_code: colour,
          worker_id: workerId,
          assigned_qty: qty
        };
      });

      $('rrAssignSave').disabled = true;
      $('rrAssignSave').textContent = 'ASSIGNING…';

      await rpc('rr_upm_assign_colours_v8', {
        p_canonical_lot_id: state.lotId,
        p_department_code: state.department,
        p_rows: rows,
        p_remarks: $('rrAssignRemarks').value || null
      });

      alert('Work assigned successfully.');
      await loadContext();
      $('refresh')?.click();
      closeModal();
    } catch (error) {
      alert(error.message || String(error));
    } finally {
      $('rrAssignSave').disabled = false;
      $('rrAssignSave').textContent = 'ASSIGN WORK';
    }
  }

  function enhanceCards() {
    document.querySelectorAll('[data-entry]').forEach((entryButton) => {
      const lotId = entryButton.dataset.entry;
      if (!lotId || entryButton.parentElement.querySelector(`[data-work-assign="${CSS.escape(lotId)}"]`)) return;

      const card = entryButton.closest('.card');
      const lotNo = card?.querySelector('.lot-number,h3')?.textContent?.trim() || lotId;
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'rr-assign-open';
      button.dataset.workAssign = lotId;
      button.textContent = 'Assign Work';
      button.onclick = () => openAssign(lotId, lotNo);
      entryButton.parentElement.insertBefore(button, entryButton);
    });
  }

  async function showEntryAssignment() {
    const lotId = $('eLot')?.value;
    const dept = $('eDept')?.value;
    const colour = $('eColour')?.value;
    if (!lotId || !dept || !colour) return;

    let box = $('rrEntryAssignmentV8');
    if (!box) {
      box = document.createElement('div');
      box.id = 'rrEntryAssignmentV8';
      box.className = 'rr-assigned-banner';
      $('eColour')?.closest('.grid')?.insertAdjacentElement('afterend', box);
    }

    try {
      const rows = await rpc('rr_upm_get_work_assign_context_v8', {
        p_canonical_lot_id: lotId,
        p_department_code: dept
      });
      const row = (rows || []).find((x) => String(x.colour_code).toUpperCase() === String(colour).toUpperCase());
      box.innerHTML = row?.is_locked
        ? `<b>Assigned Worker:</b> ${safe(row.assigned_worker_name)} — ${safe(row.assigned_worker_code)}
           <br><b>Colour:</b> ${safe(row.colour_name || row.colour_code)}
           · <b>Assigned Qty:</b> ${Number(row.total_qty || 0)} PCS`
        : `<b>Work assignment missing.</b> Assign this Department + Colour before Production Submit.`;
    } catch (error) {
      box.textContent = error.message || String(error);
    }
  }

  function bindEntryWatch() {
    $('eDept')?.addEventListener('change', showEntryAssignment);
    $('eColour')?.addEventListener('change', showEntryAssignment);

    const modal = $('entryModal');
    if (modal) {
      new MutationObserver(() => {
        if (!modal.classList.contains('hidden')) setTimeout(showEntryAssignment, 0);
      }).observe(modal, { attributes: true, attributeFilter: ['class'] });
    }
  }

  function start() {
    injectStyles();
    injectModal();
    enhanceCards();
    bindEntryWatch();

    new MutationObserver(enhanceCards).observe(document.body, {
      childList: true,
      subtree: true
    });

    console.info(`REDZED UPM Work Assignment V${VERSION} loaded`);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();
