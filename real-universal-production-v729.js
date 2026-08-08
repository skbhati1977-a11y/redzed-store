// ============================================================================
// REDZED REAL — UNIVERSAL PRODUCTION MANAGEMENT (UPM v729)
// Open Random Queue Engine & Clean Mapping Message
// ============================================================================

// 1. Initial State Setup
let currentSelectedDepartment = 'OPEN_RANDOM_QUEUE';

// 2. DOM Ready Listener
document.addEventListener('DOMContentLoaded', () => {
  initDepartmentDropdown();
  loadDepartmentView('OPEN_RANDOM_QUEUE');
});

// 3. Dropdown Event Listener
function initDepartmentDropdown() {
  const deptDropdown = document.getElementById('dept-select-filter');
  if (deptDropdown) {
    deptDropdown.addEventListener('change', (e) => {
      const selected = e.target.value;
      currentSelectedDepartment = selected;
      loadDepartmentView(selected);
    });
  }
}

// 4. Central Router
async function loadDepartmentView(deptCode) {
  const cleanDept = (deptCode || '').toUpperCase().trim();
  
  if (cleanDept === 'OPEN_RANDOM_QUEUE' || cleanDept === 'OPEN RANDOM QUEUE' || cleanDept === 'RANDOM QUEUE') {
    await loadOpenRandomQueue();
  } else if (cleanDept === 'ALL' || cleanDept === 'ALL DEPARTMENTS' || cleanDept === '') {
    await loadAllDepartmentsView();
  } else {
    await loadSpecificDepartmentView(cleanDept);
  }
}

// 5. Fetch Open Random Queue (Direct from rr_cutting_lots_v3)
async function loadOpenRandomQueue() {
  const container = document.getElementById('board-container');
  if (!container) return;

  container.innerHTML = '<div class="loading-state" style="padding:20px; color:#f1c40f;">Loading Open Random Queue...</div>';

  try {
    const { data, error } = await supabase
      .from('rr_cutting_lots_v3')
      .select('id, lot_no, style_name, art_no, print_no, operator_name, planned_pcs, status, created_at')
      .or('status.eq.released,status.eq.RELEASED')
      .order('created_at', { ascending: false });

    if (error) {
      console.error("Supabase Error fetching Open Queue:", error);
      container.innerHTML = `<div class="error-state" style="padding:20px; color:#e74c3c;">Error: ${error.message}</div>`;
      return;
    }

    renderOpenQueueCards(data);
  } catch (err) {
    console.error("Runtime Exception:", err);
    container.innerHTML = `<div class="error-state" style="padding:20px; color:#e74c3c;">Failed to load data.</div>`;
  }
}

// 6. Render Cards with 'READY TO ASSIGN' Button
function renderOpenQueueCards(lots) {
  const container = document.getElementById('board-container');
  container.innerHTML = '';

  if (!lots || lots.length === 0) {
    container.innerHTML = `
      <div class="empty-state" style="text-align:center; padding:40px; color:#888; grid-column: 1 / -1;">
        <h3>Open Random Queue mein koi lot available nahi hai.</h3>
        <p>Cutting Master se Lot Release hone par wo yahan automatic dikhegi.</p>
      </div>`;
    return;
  }

  lots.forEach(lot => {
    const cardHtml = `
      <div class="lot-card" data-id="${lot.id}" style="border:1px solid #333; background:#1e1e24; border-radius:8px; padding:15px; margin-bottom:12px; color:#fff;">
        <div class="card-header" style="display:flex; justify-content:space-between; align-items:center; border-bottom:1px solid #333; padding-bottom:8px; margin-bottom:10px;">
          <span class="badge" style="background:#e74c3c; color:#fff; padding:3px 8px; border-radius:4px; font-size:11px; font-weight:bold;">OPEN RANDOM QUEUE</span>
          <span class="lot-title" style="font-size:18px; font-weight:bold; color:#00ffcc;">${lot.lot_no}</span>
        </div>
        <div class="card-body" style="font-size:13px; line-height:1.6;">
          <p style="margin:2px 0;"><strong>Style:</strong> ${lot.style_name || 'N/A'}</p>
          <p style="margin:2px 0;"><strong>Art No:</strong> ${lot.art_no || 'N/A'} | <strong>Print:</strong> ${lot.print_no || 'N/A'}</p>
          <p style="margin:2px 0;"><strong>Planned Pcs:</strong> <span style="font-size:15px; font-weight:bold; color:#f1c40f;">${lot.planned_pcs}</span></p>
          <p style="margin:2px 0;"><strong>Cutting Master:</strong> ${lot.operator_name || 'N/A'}</p>
        </div>
        <div class="card-actions" style="margin-top:12px;">
          <button class="btn-assign" 
                  style="width:100%; background:#27ae60; color:#fff; border:none; padding:10px; border-radius:6px; cursor:pointer; font-weight:bold; font-size:14px;"
                  onclick="openAssignModal('${lot.id}', '${lot.lot_no}')">
            READY TO ASSIGN
          </button>
        </div>
      </div>`;
    container.insertAdjacentHTML('beforeend', cardHtml);
  });
}

// 7. Success Message Helper for Cutting Master Release
function getReleaseStatusMessage(lotNo) {
  return `<div style="color: #2ecc71; font-weight: bold; background: rgba(46, 204, 113, 0.1); padding: 10px; border-radius: 6px; border: 1px solid #2ecc71; margin-top: 10px;">
            Lot ${lotNo} Successfully Released — Open Random Queue Mapped!
          </div>`;
}

// 8. ALL DEPARTMENTS (Read-Only)
async function loadAllDepartmentsView() {
  const container = document.getElementById('board-container');
  if (!container) return;

  container.innerHTML = '<div class="loading-state" style="padding:20px; color:#f1c40f;">Loading All Lots...</div>';

  const { data, error } = await supabase
    .from('rr_cutting_lots_v3')
    .select('id, lot_no, style_name, art_no, planned_pcs, status, operator_name')
    .order('created_at', { ascending: false });

  if (error) {
    container.innerHTML = `<div class="error-state" style="padding:20px; color:#e74c3c;">Error: ${error.message}</div>`;
    return;
  }

  container.innerHTML = '';
  data.forEach(lot => {
    const cardHtml = `
      <div class="lot-card readonly-card" style="border:1px solid #444; background:#121212; border-radius:8px; padding:15px; margin-bottom:12px; opacity:0.85;">
        <div class="card-header" style="display:flex; justify-content:space-between; align-items:center;">
          <span class="badge" style="background:#555; color:#fff; padding:3px 8px; border-radius:4px; font-size:11px;">READ ONLY</span>
          <span style="font-weight:bold; color:#fff;">${lot.lot_no}</span>
        </div>
        <div class="card-body" style="font-size:13px; margin-top:8px; color:#ccc;">
          <p style="margin:2px 0;">Style: ${lot.style_name || 'N/A'} | Pcs: ${lot.planned_pcs}</p>
          <p style="margin:2px 0;">Status: <span style="color:#f39c12; font-weight:bold;">${lot.status}</span></p>
        </div>
      </div>`;
    container.insertAdjacentHTML('beforeend', cardHtml);
  });
}

// 9. Particular Active Department View
async function loadSpecificDepartmentView(deptCode) {
  const container = document.getElementById('board-container');
  if (!container) return;

  container.innerHTML = `<div class="loading-state" style="padding:20px; color:#f1c40f;">Loading Active Lots for ${deptCode}...</div>`;

  const { data, error } = await supabase
    .from('upm_registry')
    .select('*')
    .eq('status', 'ACTIVE');

  if (error || !data || data.length === 0) {
    container.innerHTML = `<div class="empty-state" style="text-align:center; padding:30px; color:#888; grid-column: 1 / -1;">${deptCode} department mein koi active work nahi hai.</div>`;
    return;
  }

  container.innerHTML = '';
  data.forEach(item => {
    const cardHtml = `
      <div class="lot-card active-card" style="border:1px solid #2980b9; background:#1c2833; border-radius:8px; padding:15px; margin-bottom:12px;">
        <div class="card-header" style="display:flex; justify-content:space-between;">
          <span style="background:#2980b9; color:#fff; padding:2px 6px; border-radius:3px; font-size:11px;">ACTIVE</span>
          <span style="font-weight:bold; color:#3498db;">${item.lot_no}</span>
        </div>
        <div class="card-body" style="font-size:13px; margin:8px 0; color:#ecf0f1;">
          <p style="margin:2px 0;">Colour: ${item.colour} | Size: ${item.size} | Qty: ${item.current_qty}</p>
        </div>
      </div>`;
    container.insertAdjacentHTML('beforeend', cardHtml);
  });
}

// 10. Assign Modal Action Helper
function openAssignModal(id, lotNo) {
  alert(`Lot ${lotNo} assign karne ke liye Assignment Modal open hoga.`);
}
