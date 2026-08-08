 // ============================================================================
// REDZED REAL — UNIVERSAL PRODUCTION MANAGEMENT & CUTTING ENGINE (v729 COMPLETE)
// Database Registered Table: rr_cutting_lots_v3
// Database Registered RPCs: rr_upm_worker_list_v8_3 | rr_release_multi_lots_v4
// ============================================================================

let currentSelectedDepartment = 'OPEN_RANDOM_QUEUE';

document.addEventListener('DOMContentLoaded', () => {
    initCuttingMasterWorkerDropdown();
    attachReleaseButtonListener();
    initMultiLotReleaseTrigger();
    initDepartmentDropdown();
    loadDepartmentView('OPEN_RANDOM_QUEUE');
});

// ----------------------------------------------------------------------------
// 1. WORKER DROPDOWN LOADER (Roles & Permissions Mapped)
// ----------------------------------------------------------------------------
async function initCuttingMasterWorkerDropdown() {
    const operatorSelect = document.getElementById('operator_name') || 
                           document.getElementById('cutting_master_select') || 
                           document.querySelector('select[name="operator_name"]') ||
                           document.querySelector('.operator-select');
                           
    if (!operatorSelect) return;

    try {
        const { data: workers, error } = await supabase.rpc('rr_upm_worker_list_v8_3');

        if (error || !workers || workers.length === 0) {
            console.warn("Worker list RPC returned empty/error:", error);
            return;
        }

        populateWorkerDropdown(operatorSelect, workers);
    } catch (err) {
        console.error("Worker Mapping Exception:", err);
    }
}

function populateWorkerDropdown(selectElement, workers) {
    if (!selectElement || !workers) return;
    selectElement.innerHTML = '<option value="">-- Select Mapped Cutting Master --</option>';
    
    workers.forEach(w => {
        const workerName = w.worker_name || w.name || w.full_name;
        if (workerName) {
            const opt = document.createElement('option');
            opt.value = workerName;
            opt.textContent = workerName;
            selectElement.appendChild(opt);
        }
    });
}

// ----------------------------------------------------------------------------
// 2. SINGLE LOT RELEASE ENGINE
// ----------------------------------------------------------------------------
function attachReleaseButtonListener() {
    const releaseButtons = document.querySelectorAll('#btn-release-lot, .btn-release-main, button[onclick*="release"]:not([onclick*="releaseMulti"]), .btn-release');
    
    releaseButtons.forEach(btn => {
        btn.removeAttribute('disabled');
        btn.onclick = async function(e) {
            e.preventDefault();
            await executeLotReleaseProcess();
        };
    });
}

async function executeLotReleaseProcess() {
    const lotInput = document.getElementById('manual_lot_no') || 
                     document.querySelector('input[placeholder*="2603"]') ||
                     document.querySelector('input[name="manual_lot_no"]') ||
                     document.querySelector('.lot-no-input');
                           
    const lotNoValue = lotInput ? lotInput.value.trim() : '';

    if (!lotNoValue) {
        alert("Kripya Manual Lot No bharein!");
        return;
    }

    const operatorSelect = document.getElementById('operator_name') || 
                           document.getElementById('cutting_master_select') || 
                           document.querySelector('select[name="operator_name"]');
    const selectedOperator = operatorSelect ? operatorSelect.value : '';

    const greenBanner = document.getElementById('status-message-green') || document.querySelector('.green-success-box');
    const redBanner = document.getElementById('status-message-red') || document.querySelector('.error-message-box');

    try {
        const updatePayload = {
            status: 'released',
            updated_at: new Date().toISOString()
        };
        if (selectedOperator) {
            updatePayload.operator_name = selectedOperator;
        }

        const { error } = await supabase
            .from('rr_cutting_lots_v3')
            .update(updatePayload)
            .eq('lot_no', lotNoValue);

        if (error) {
            if (redBanner) {
                redBanner.style.display = 'block';
                redBanner.innerText = "Release Error: " + error.message;
            } else {
                alert("Release Error: " + error.message);
            }
            return;
        }

        if (greenBanner) {
            greenBanner.style.display = 'block';
            greenBanner.style.background = '#2ecc71';
            greenBanner.style.color = '#ffffff';
            greenBanner.style.padding = '12px';
            greenBanner.style.borderRadius = '6px';
            greenBanner.style.fontWeight = 'bold';
            greenBanner.innerText = `Lot ${lotNoValue} Successfully Released — Open Random Queue Mapped!`;
        } else {
            alert(`Lot ${lotNoValue} Successfully Released — Open Random Queue Mapped!`);
        }

        setTimeout(() => {
            const modals = document.querySelectorAll('.modal-overlay, #releaseModal, .modal, [data-modal]');
            modals.forEach(m => m.style.display = 'none');
            
            if (typeof loadOpenRandomQueue === 'function') {
                loadOpenRandomQueue();
            }
        }, 1200);

    } catch (err) {
        console.error("Single Lot Release Error:", err);
    }
}

// ----------------------------------------------------------------------------
// 3. MULTI-LOT RELEASE ENGINE (v4 RPC INTEGRATION)
// ----------------------------------------------------------------------------
function initMultiLotReleaseTrigger() {
    const multiBtns = document.querySelectorAll('#btn-release-multi, .btn-release-combo, button[onclick*="releaseMulti"], #btn_release_multi_lots');
    
    multiBtns.forEach(btn => {
        btn.removeAttribute('disabled');
        btn.addEventListener('click', async (e) => {
            e.preventDefault();
            await triggerMultiLotReleaseRPC();
        });
    });
}

async function triggerMultiLotReleaseRPC() {
    const cbInput = document.getElementById('cb_purchase_id') || 
                    document.getElementById('manual_lot_no') || 
                    document.querySelector('input[name="cb_purchase_id"]') ||
                    document.querySelector('.lot-no-input');
                    
    const cbValue = cbInput ? cbInput.value.trim() : '';

    if (!cbValue) {
        alert("Kripya Multi Lot Release ke liye Lot No / CB Purchase ID bharein!");
        return;
    }

    const greenBanner = document.getElementById('status-message-green') || document.querySelector('.green-success-box');
    const redBanner = document.getElementById('status-message-red') || document.querySelector('.error-message-box');

    try {
        const { data, error } = await supabase.rpc('rr_release_multi_lots_v4', {
            p_cb_purchase_id: cbValue
        });

        if (error) {
            console.warn("Multi-lot RPC signature notice, executing direct bulk release fallback:", error.message);
            
            const { error: bulkErr } = await supabase
                .from('rr_cutting_lots_v3')
                .update({ 
                    status: 'released', 
                    updated_at: new Date().toISOString() 
                })
                .ilike('lot_no', `%${cbValue}%`);

            if (bulkErr) {
                if (redBanner) {
                    redBanner.style.display = 'block';
                    redBanner.innerText = "Multi Release Error: " + bulkErr.message;
                } else {
                    alert("Multi Release Error: " + bulkErr.message);
                }
                return;
            }
        }

        if (greenBanner) {
            greenBanner.style.display = 'block';
            greenBanner.style.background = '#2ecc71';
            greenBanner.style.color = '#ffffff';
            greenBanner.style.padding = '12px';
            greenBanner.style.borderRadius = '6px';
            greenBanner.style.fontWeight = 'bold';
            greenBanner.innerText = `Multi Lots (${cbValue}) Successfully Released — Open Random Queue Mapped!`;
        } else {
            alert(`Multi Lots (${cbValue}) Successfully Released — Open Random Queue Mapped!`);
        }

        setTimeout(() => {
            const activeModals = document.querySelectorAll('.modal-overlay, #releaseModal, .modal, [data-modal]');
            activeModals.forEach(m => m.style.display = 'none');
            
            if (typeof loadOpenRandomQueue === 'function') {
                loadOpenRandomQueue();
            }
        }, 1200);

    } catch (err) {
        console.error("Multi Lot Release Fire Error:", err);
    }
}

// ----------------------------------------------------------------------------
// 4. OPEN RANDOM QUEUE DASHBOARD ENGINE
// ----------------------------------------------------------------------------
function initDepartmentDropdown() {
    const deptDropdown = document.getElementById('dept-select-filter');
    if (deptDropdown) {
        deptDropdown.addEventListener('change', (e) => {
            currentSelectedDepartment = e.target.value;
            loadDepartmentView(e.target.value);
        });
    }
}

async function loadDepartmentView(deptCode) {
    const cleanDept = (deptCode || '').toUpperCase().trim();
    if (cleanDept === 'OPEN_RANDOM_QUEUE' || cleanDept === 'OPEN RANDOM QUEUE' || cleanDept === 'RANDOM QUEUE' || cleanDept === '') {
        await loadOpenRandomQueue();
    }
}

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
            container.innerHTML = `<div class="error-state" style="padding:20px; color:#e74c3c;">Error: ${error.message}</div>`;
            return;
        }

        renderOpenQueueCards(data);
    } catch (err) {
        container.innerHTML = `<div class="error-state" style="padding:20px; color:#e74c3c;">Failed to load data.</div>`;
    }
}

function renderOpenQueueCards(lots) {
    const container = document.getElementById('board-container');
    if (!container) return;
    container.innerHTML = '';

    if (!lots || lots.length === 0) {
        container.innerHTML = `
            <div class="empty-state" style="text-align:center; padding:40px; color:#888; grid-column: 1 / -1;">
                <h3>Open Random Queue mein koi lot available nahi hai.</h3>
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
                    <p style="margin:2px 0;"><strong>Planned Pcs:</strong> <span style="font-size:15px; font-weight:bold; color:#f1c40f;">${lot.planned_pcs || 'N/A'}</span></p>
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

function openAssignModal(id, lotNo) {
    alert(`Lot ${lotNo} ko assign karne ke liye Line Man Assignment Modal khul raha hai.`);
}
