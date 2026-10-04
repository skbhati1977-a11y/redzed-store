(() => {
  'use strict';
  if (window.__RR_DIRECT_HISTORY_TEST71__) return;
  window.__RR_DIRECT_HISTORY_TEST71__ = true;
  const staff = /real-sales-live-chat-v9434\.html$/i.test(location.pathname);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  const chatId = () => document.querySelector('#inboxRows .chatrow.on')?.dataset.chat || new URLSearchParams(location.search).get('chat_id') || localStorage.getItem('rr_real_chat_last_group_v9507') || '';
  let state = null, busy = false, lastSignature = '', activeChat = '';
  const style = document.createElement('style');
  style.textContent = '.rrCycleHistory71{margin:8px 0;padding:9px;border:1px solid #40536b;border-radius:11px;background:#14202d;color:#fff;max-height:190px;overflow:auto}.rrCycleHistory71 summary{cursor:pointer;font-weight:800;padding:6px 0}.rrCycleHistory71 p{margin:5px 0;color:#b7c7d8;font-size:12px;overflow-wrap:anywhere}.rrCycleHistory71 small{display:block;color:#9fb0c2}.rrCycleHistory71 details+details{border-top:1px solid #33465b}';
  document.head.appendChild(style);
  function markup(data) {
    return `<b>${esc(data.collection_display_no || 'COLLECTION')} · UPDATES</b>` + (data.update_history || []).map(event => {
      const title = event.kind === 'COLLECTION' ? 'COLLECTION' : 'REQUIREMENT';
      const relation = event.kind === 'COLLECTION' ? `Requirement ${Number(event.requirement_update_no || 0)}` : `Collection ${Number(event.collection_update_no || 0)}`;
      const info = event.kind === 'COLLECTION' ? (event.lots || []).join(' / ') : `${Number(event.lot_count || 0)} styles · ${Number(event.total_qty || 0)} PCS · CONFIRMED ✓`;
      return `<details><summary>${title} · UPDATE ${Number(event.update_no || 0)}</summary><p>${esc(info)}</p><small>${esc(relation)} · ${esc(new Date(event.created_at).toLocaleString())}</small></details>`;
    }).join('');
  }
  function paint() {
    if (!state?.collection_cycle_id) return;
    let host;
    if (staff) {
      const messages = [...document.querySelectorAll('#msgs .msg')];
      host = messages.find(row => row.dataset.rrCycle71 === String(state.collection_cycle_id) && row.querySelector('.rrReqCard9508')) || messages.find(row => row.dataset.rrCycle71 === String(state.collection_cycle_id));
      if (!host) return;
      // A collection update belongs in the existing requirement card once it exists.
      messages.forEach(row => { if (row !== host && row.dataset.rrCycle71 === String(state.collection_cycle_id) && row.dataset.rrWorkflow71 === 'COLLECTION') row.style.display = 'none'; });
    } else {
      host = document.getElementById('fsCollectionCard');
      document.querySelectorAll('#fsMsgs .fsm[data-rr-cycle71]').forEach(row => {
        if (row.dataset.rrCycle71 === String(state.collection_cycle_id) && row.dataset.rrWorkflow71 === '1') row.style.display='none';
      });
    }
    if (!host) return;
    let panel = host.querySelector('.rrCycleHistory71');
    if (!panel) { panel = document.createElement('div'); panel.className = 'rrCycleHistory71'; host.appendChild(panel); }
    const html = markup(state);
    if (panel._rrHistoryHtml !== html) {
      const opened=new Set([...panel.querySelectorAll("details[open]")].map(el=>el.querySelector("summary")?.textContent));
      panel.innerHTML=html;panel._rrHistoryHtml=html;
      panel.querySelectorAll("details").forEach(el=>{if(opened.has(el.querySelector("summary")?.textContent))el.open=true;});
    }
  }
  async function refresh() {
    if (busy || (staff && !chatId())) return;
    busy = true;
    try {
      const chat = chatId();
      const q=new URLSearchParams(location.search);
      const data = staff ? await RF853.rpc('rr_chat_direct_cycle_state_test71', {p_chat_id:chat}) : await RF853.rpc('rr_collection_current_state_v9633',{p_token:q.get('t')||q.get('c')});
      if (!staff || chat === chatId()) { state = data; activeChat = chat; paint(); }
    } catch (_) {} finally { busy = false; }
  }
  function hook() {
    if (!window.RF853?.rpc || RF853.rpc.__rrHistory71) return;
    const base = RF853.rpc.bind(RF853);
    const wrapped = async (name,args={}) => {
      const data = await base(name,args);
      if (!staff && name === 'rr_collection_current_state_v9633') { state=data; setTimeout(()=>{paint();document.dispatchEvent(new CustomEvent('rr:v71-cycle-state',{detail:data}));},0); }
      if (staff && /rr_chat_staff_messages_v/.test(name) && Array.isArray(data)) {
        setTimeout(() => {
          data.forEach(message => {
            const row = document.querySelector(`#msgs .msg[data-msg-id="${CSS.escape(String(message.id))}"]`);
            if (row && message.payload?.direct_collection_cycle_id) {
              row.dataset.rrCycle71=message.payload.direct_collection_cycle_id;
              row.dataset.rrWorkflow71=message.payload.source==='DIRECT_MARKET_WINDOW'?'COLLECTION':'REQUIREMENT';
            }
          });
          const sig=JSON.stringify(data.map(m=>[m.id,m.created_at,m.payload?.collection_update_no,m.payload?.requirement_update_no]));
          if (sig !== lastSignature || activeChat !== chatId()) {lastSignature=sig;refresh();} else paint();
        },80);
      }
      if (!staff && /rr_chat_customer_messages/.test(name) && Array.isArray(data)) {
        const sig=JSON.stringify(data.map(m=>[m.id,m.created_at,m.body]));
        if(sig!==lastSignature){lastSignature=sig;setTimeout(refresh,80);}
      }
      return data;
    };
    wrapped.__rrHistory71=true;RF853.rpc=wrapped;
  }
  let scheduled=false;
  new MutationObserver(() => {if(scheduled)return;scheduled=true;requestAnimationFrame(()=>{scheduled=false;paint();});}).observe(document.body,{childList:true,subtree:true});
  hook();refresh();
  document.addEventListener('rr:v9605-requirement-sent',()=>setTimeout(paint,150));
})();
