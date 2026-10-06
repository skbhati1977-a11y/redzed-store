(() => {
  'use strict';
  if (window.__RR_SALES_COLLECTION_CONTRACT_TEST71__) return;
  window.__RR_SALES_COLLECTION_CONTRACT_TEST71__ = true;
  const q = new URLSearchParams(location.search);
  const partner = q.get('rr_partner_mode');
  if (partner) return;
  const chatId = () => window.RRActiveSalesChat71?.() || document.getElementById('msgs')?.dataset.chatId || document.querySelector('#inboxRows .chatrow.on')?.dataset.chat || q.get('chat_id') || '';
  const selectedCycle = () => (!q.get('chat_id') || chatId() === q.get('chat_id')) ? q.get('collection_cycle_id') || null : null;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let windowContext = null;
  if (q.get('from_chat') === '1' && q.get('chat_id')) {
    document.body.classList.add('rr-followup71');
    const style=document.createElement('style');
    style.textContent='.rr-followup71 .ww-bucket,.rr-followup71 .ww-actions,.rr-followup71 #bucketBtn{display:none!important}';
    document.head.appendChild(style);
    const mode = document.getElementById('dataMode');
    if (mode) {mode.value='TEST';mode.disabled=true;}
  }
  window.RRSalesCollection = {
    async open(requirementId = null, cycleId = selectedCycle()) {
      const chat = chatId();
      if (!chat) throw Error('Open the party chat first.');
      const ctx = await RF853.rpc('rr_sales_collection_context_test71', {
        p_chat_id: chat, p_requirement_id: requirementId, p_collection_cycle_id: cycleId
      });
      if (chatId() !== chat) throw Error('Party changed. Open the collection again.');
      if (!ctx.can_send) throw Error('This collection is complete. Open a new collection.');
      const url = new URL('real-web-window-v9329.html', location.href);
      url.searchParams.set('from_chat', '1');
      url.searchParams.set('chat_id', ctx.chat_id);
      url.searchParams.set('customer_id', ctx.customer_id);
      url.searchParams.set('customer_name', ctx.customer_name);
      if (ctx.collection_cycle_id) url.searchParams.set('collection_cycle_id', ctx.collection_cycle_id);
      if (ctx.requirement_id) url.searchParams.set('append_requirement_id', ctx.requirement_id);
      url.searchParams.set('v', 'TEST71-FOLLOWUP-20261005');
      sessionStorage.setItem('rr_real_chat_return_v9507', JSON.stringify({chat_id: chat, collection_cycle_id: ctx.collection_cycle_id, ts: Date.now()}));
      location.href = url.href;
      return url.href;
    },
    context: () => windowContext
  };
  const base = RF853.rpc.bind(RF853);
  RF853.rpc = async (name, args = {}) => {
    if (name === 'rr_web_window_cards_v9329' && q.get('from_chat') === '1' && q.get('chat_id')) {
      const response = await base('rr_sales_collection_cards_test71', {
        p_chat_id: q.get('chat_id'), p_requirement_id: q.get('append_requirement_id') || null,
        p_collection_cycle_id: selectedCycle(), p_search: args.p_search || null,
        p_category: args.p_category || null, p_stock_status: args.p_stock_status || null,
        p_limit: args.p_limit || 150, p_offset: args.p_offset || 0
      });
      windowContext = response.context;
      const message = document.getElementById('rrCollectionContext71') || document.createElement('div');
      message.id = 'rrCollectionContext71';
      message.className = 'card';
      message.innerHTML = '<b>' + esc(windowContext.customer_name) + ' · ' + esc(windowContext.collection_display_no || 'NEW COLLECTION') + '</b><div class="muted">' +
        (windowContext.categories.length ? 'Requested categories: ' + windowContext.categories.map(esc).join(' / ') : 'All categories') +
        ' · Already sent designs hidden</div>';
      if (!message.parentNode) document.getElementById('cards')?.before(message);
      const sent=new Set((windowContext.sent_lots||[]).map(l=>String(l).trim().toUpperCase()));
      return response.rows.filter(r=>!sent.has(String(r.lot_no).trim().toUpperCase()));
    }
    return base(name, args);
  };
  // Every direct-chat Market Window entry uses the same identity and eligibility contract.
  document.addEventListener('click', event => {
    const button = event.target.closest?.('#marketWindowDitto,[data-rr-collection-open],[data-rr-mw9509=chat],[data-rr-mw9510]');
    if (!button) return;
    if (!chatId() && button.matches('[data-rr-mw9510],[data-rr-mw9509=chat]')) return;
    event.preventDefault(); event.stopImmediatePropagation();
    window.RRSalesCollection.open(null, button.dataset.rrCollectionOpen || selectedCycle()).catch(error => {
      const flash = document.getElementById('flash');
      if (flash) {flash.textContent = error.message; flash.style.display = 'block';}
    });
  }, true);
})();
