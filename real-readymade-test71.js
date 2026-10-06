(() => {
  'use strict';
  const $ = id => document.getElementById(id), esc = RF853.esc;
  const money = n => n == null ? '—' : '₹' + Number(n).toLocaleString('en-IN', {maximumFractionDigits: 2});
  let purchaseId = null, cards = [], drafts = [], busy = false, returnKey = null;
  const rpc = (name, args) => RF853.rpc(name, args);
  function message(text) { $('rmMessage').textContent = text; }
  async function action(button, fn) {
    if (busy) return; busy = true; button.disabled = true;
    try { await fn(); } catch (e) { message(e.message || 'Please try again.'); }
    finally { busy = false; button.disabled = false; }
  }
  function line() {
    return `<tr><td><input data-field="lot_no" placeholder="Lot No." required></td><td><input data-field="item_name" placeholder="Garment name" required></td><td><input data-field="qty" type="number" min="1" step="1" inputmode="numeric" required></td><td><input data-field="purchase_rate" type="number" min="0.01" step="0.01" required></td><td><input data-field="final_image_url" type="url" placeholder="Garment image URL" required></td><td><button type="button" data-remove>Remove</button></td></tr>`;
  }
  function addLine() { $('rmPurchaseLines').insertAdjacentHTML('beforeend', line()); }
  function payload() {
    return [...$('rmPurchaseLines').rows].map(row => {
      const value = Object.fromEntries([...row.querySelectorAll('[data-field]')].map(i => [i.dataset.field, i.value.trim()]));
      value.qty = Number(value.qty); value.purchase_rate = Number(value.purchase_rate);
      value.markup_mode = 'DEFAULT_22';
      if (!value.lot_no || !value.item_name || !Number.isInteger(value.qty) || value.qty <= 0 || value.purchase_rate <= 0 || !value.final_image_url) throw Error('Lot, garment, whole PCS, purchase rate and image required.');
      return value;
    });
  }
  async function save(post) {
    if (!RF853.mode || RF853.mode() !== 'TEST') throw Error('Readymade test build uses TEST mode.');
    const data = await rpc('rr_rm_purchase_save_test71', {p_purchase_id: purchaseId, p_supplier_name: $('rmSupplier').value.trim(), p_bill_no: $('rmBill').value.trim(), p_purchase_date: $('rmDate').value, p_lines: payload(), p_post: post});
    purchaseId = data.purchase_id;
    message(post ? 'Purchase posted · stock and supplier account updated.' : 'Purchase draft saved.');
    if (post) { purchaseId = null; $('rmPurchaseForm').reset(); $('rmDate').value = new Date().toISOString().slice(0, 10); $('rmPurchaseLines').innerHTML = ''; addLine(); }
    await refresh();
  }
  async function refresh() {
    if (RF853.mode() !== 'TEST') { $('rmCards').innerHTML = ''; message('Select TEST mode for Readymade audit build.'); return; }
    cards = await rpc('rr_rm_cards_test71', {p_search: $('rmSearch').value.trim()});
    if (['owner','super_admin','superadmin','admin','accounts','account'].includes(role)) {
      drafts = await rpc('rr_rm_purchase_drafts_test71', {});
      $('rmDraft').innerHTML = '<option value="">New Purchase</option>' + drafts.map(d => `<option value="${esc(d.purchase_id)}">${esc(d.purchase_no)} · ${esc(d.supplier_name)} · ${esc(d.bill_no || '')}</option>`).join('');
      $('rmDraft').value = purchaseId || '';
    }
    $('rmCards').innerHTML = cards.map((x, i) => {
      const c = x.costing || {}, privateCost = c.purchase_cost_per_pc != null;
      return `<article class="card"><h3>${esc(x.lot_no)} · ${esc(x.item_name)}</h3>${x.image_url ? `<img alt="Garment" src="${esc(x.image_url)}" style="width:90px;height:90px;object-fit:contain">` : ''}<p>Received ${x.received_qty} · Available <b>${x.available_qty}</b></p><p>Base sales rate <b>${money(c.source_rate)}</b> · Approved <b>${money(x.approved_rate)}</b></p>${privateCost ? `<p>Purchase ${money(c.purchase_cost_per_pc)} + Salary ${money(c.salary_per_pc)} + Overhead ${money(c.overhead_per_pc)} + Owner margin ₹22</p><details><summary>Weighted overhead heads</summary>${(c.overhead_heads || []).map(h => `<p>${esc(h.label)} · ${money(h.per_pc)}/pc</p>`).join('')}${(c.salary_heads || []).map(h => `<p>${esc(h.head)} salary · ${money(h.per_pc)}/pc</p>`).join('')}<p>Total shared salary: ${money(c.salary_per_pc)}/pc</p></details>` : ''}<p>${c.costing_complete ? (c.frozen ? 'Costing finalized' : 'Costing ready for approval') : 'Monthly inward value allocation pending'}</p><div data-rm-approval><input aria-label="Final sales rate" data-rate="${i}" type="number" min="0" step="1" value="${x.approved_rate ?? c.source_rate ?? ''}"><button type="button" data-approve="${i}">Approve final rate</button></div><div data-rm-purchase-role><input aria-label="Purchase return PCS" data-return-qty="${i}" type="number" min="1" max="${x.available_qty}" step="1" placeholder="Return PCS"><input aria-label="Return reason" data-return-reason="${i}" placeholder="Return reason"><button type="button" data-return="${i}">Purchase Return</button></div></article>`;
    }).join('') || '<p>No Readymade lots available.</p>';
    applyRole();
  }
  let role = '';
  function applyRole() {
    const purchase = ['owner','super_admin','superadmin','admin','accounts','account'].includes(role);
    document.querySelectorAll('[data-rm-purchase-role]').forEach(x => x.hidden = !purchase);
    document.querySelectorAll('[data-rm-approval]').forEach(x => x.hidden = !['owner','super_admin','superadmin','admin'].includes(role));
  }
  async function boot() {
    try {
      const auth = await RR.requireRoles(['owner','super_admin','superadmin','admin','sales','accounts','account','manager']);
      role = String(auth.profile.role_code || '').toLowerCase();
      $('rmDate').value = new Date().toISOString().slice(0,10);
      $('rmMonth').value = new Date().toISOString().slice(0,7);
      addLine(); applyRole();
      $('rmAddLine').onclick = addLine;
      $('rmDraft').onchange = () => {
        purchaseId = $('rmDraft').value || null;
        const d = drafts.find(x => x.purchase_id === purchaseId);
        $('rmSupplier').value = d?.supplier_name || ''; $('rmBill').value = d?.bill_no || '';
        $('rmDate').value = d?.purchase_date || new Date().toISOString().slice(0,10);
        $('rmPurchaseLines').innerHTML = '';
        if (!d?.lines?.length) addLine();
        else for (const value of d.lines) { addLine(); const row = $('rmPurchaseLines').lastElementChild; row.querySelectorAll('[data-field]').forEach(i => i.value = value[i.dataset.field] ?? ''); }
      };
      $('rmPurchaseLines').onclick = e => { if (e.target.closest('[data-remove]') && $('rmPurchaseLines').rows.length > 1) e.target.closest('tr').remove(); };
      $('rmSaveDraft').onclick = e => action(e.currentTarget, () => save(false));
      $('rmPostPurchase').onclick = e => action(e.currentTarget, () => save(true));
      $('rmRefresh').onclick = e => action(e.currentTarget, refresh);
      $('rmSaveOverhead').onclick = e => action(e.currentTarget, async () => {
        await rpc('rr_rm_overhead_save_test71', {p_head: $('rmHead').value, p_month: $('rmMonth').value+'-01', p_amount: Number($('rmAmount').value), p_stream: $('rmStream').value});
        message('Monthly overhead saved. Finalized costing retains its approved snapshot.'); await refresh();
      });
      $('rmCards').onclick = e => {
        const approve = e.target.closest('[data-approve]'), ret = e.target.closest('[data-return]');
        if (approve) action(approve, async () => {
          const i = Number(approve.dataset.approve), c = cards[i], rate = Number($('rmCards').querySelector(`[data-rate="${i}"]`).value);
          const d = await rpc('rr_rm_approve_rate_test71', {p_lot_no:c.lot_no,p_final_rate:rate,p_reason:'Readymade final rate approval'});
          message(`Final rate approved · RRQ change ${money(d.quota_delta)} · RRQ balance ${money(d.rrq_balance)}`); await refresh();
        });
        if (ret) action(ret, async () => {
          const i = Number(ret.dataset.return), c = cards[i], qty = Number($('rmCards').querySelector(`[data-return-qty="${i}"]`).value), reason = $('rmCards').querySelector(`[data-return-reason="${i}"]`).value.trim();
          const fingerprint = JSON.stringify([c.stock_id,qty,reason]);
          if (!returnKey || returnKey.fingerprint !== fingerprint) returnKey = {fingerprint,key:crypto.randomUUID()};
          await rpc('rr_rm_purchase_return_test71', {p_stock_id:c.stock_id,p_qty:qty,p_reason:reason,p_return_date:new Date().toISOString().slice(0,10),p_remarks:null,p_idempotency_key:returnKey.key});
          message('Purchase Return posted · stock, supplier account and RRQ updated.'); await refresh(); returnKey = null;
        });
      };
      await refresh();
    } catch(e) { message(e.message); }
  }
  boot();
})();
