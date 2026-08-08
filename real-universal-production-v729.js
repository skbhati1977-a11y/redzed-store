// ==========================================
// CENTRAL UNIVERSAL PRODUCTION BOARD ENGINE
// Verified Table: rr_cutting_lots_v3 (Zero-Assumption Mapping)
// ==========================================

async function loadOpenRandomQueue() {
  const container = document.getElementById('board-container');
  if (!container) return;

  container.innerHTML = '<div class="loading-state">Loading Open Random Queue...</div>';

  try {
    const { data, error } = await supabase
      .from('rr_cutting_lots_v3')
      .select('id, lot_no, style_name, art_no, print_no, operator_name, planned_pcs, status, created_at')
      .eq('status', 'released')
      .order('created_at', { ascending: false });

    if (error) {
      console.error("Supabase Fetch Error:", error);
      container.innerHTML = `<div class="error-state">Error fetching data: ${error.message}</div>`;
      return;
    }

    renderOpenQueueCards(data);
  } catch (err) {
    console.error("Runtime Error:", err);
    container.innerHTML = `<div class="error-state">Runtime Error occurred.</div>`;
  }
}

function renderOpenQueueCards(lots) {
  const container = document.getElementById('board-container');
  container.innerHTML = '';

  if (!lots || lots.length === 0) {
    container.innerHTML = `<div class="no-data">Open Random Queue me koi lot available nahi hai.</div>`;
    return;
  }

  lots.forEach(lot => {
    const cardHtml = `
      <div class="lot-card" data-id="${lot.id}">
        <div class="card-header" style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
          <span class="badge-dept" style="background:#e74c3c; color:#fff; padding:2px 8px; border-radius:4px; font-size:11px; font-weight:bold;">OPEN RANDOM QUEUE</span>
          <span class="lot-no" style="font-weight:bold; font-size:16px;">${lot.lot_no}</span>
        </div>
        <div class="card-body" style="font-size:13px; line-height:1.5; color:#333;">
          <p style="margin:2px 0;"><strong>Style:</strong> ${lot.style_name || 'N/A'}</p>
          <p style="margin:2px 0;"><strong>Art No:</strong> ${lot.art_no || 'N/A'} | <strong>Print:</strong> ${lot.print_no || 'N/A'}</p>
          <p style="margin:2px 0;"><strong>Planned Pcs:</strong> ${lot.planned_pcs}</p>
          <p style="margin:2px 0;"><strong>Cutting Master:</strong> ${lot.operator_name || 'N/A'}</p>
        </div>
        <div class="card-actions" style="margin-top:12px;">
          <button class="btn-assign" 
                  style="width:100%; background:#27ae60; color:#fff; border:none; padding:8px; border-radius:4px; cursor:pointer; font-weight:bold;"
                  onclick="openAssignModal('${lot.id}', '${lot.lot_no}')">
            READY TO ASSIGN
          </button>
        </div>
      </div>
    `;
    container.insertAdjacentHTML('beforeend', cardHtml);
  });
}

// Function to handle Top Dropdown Selection
function onDepartmentFilterChange(selectedDept) {
  const dept = (selectedDept || '').toUpperCase();
  
  if (dept === 'OPEN_RANDOM_QUEUE' || dept === 'OPEN RANDOM QUEUE' || dept === 'RANDOM QUEUE') {
    loadOpenRandomQueue();
  } else {
    console.log("Other department selected:", dept);
    // Other dept active logic handles here
  }
}
