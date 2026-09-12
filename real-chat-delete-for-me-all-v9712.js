(() => {
  'use strict';
  if (window.__RR_CHAT_DELETE_V9712__) return;
  window.__RR_CHAT_DELETE_V9712__ = true;
  const $ = id => document.getElementById(id);
  function flash(text) {
    const f = $('flash');
    if (!f) return;
    f.textContent = text;
    f.style.display = 'block';
    clearTimeout(f._deleteTimer);
    f._deleteTimer = setTimeout(() => { f.style.display = 'none'; }, 2200);
  }
  function refresh() {
    const b = $('privateTab')?.classList.contains('on') ? $('privateTab') : $('groupTab');
    b?.click();
  }
  async function remove(node) {
    const messageId = node.dataset.rrMsgid || node.dataset.msgid9482 || node.dataset.msgId;
    const chatId = document.querySelector('#inboxRows .chatrow.on')?.dataset.chat;
    if (!messageId || !chatId) return flash('Message mapping unavailable.');
    const all = confirm('DELETE FOR ALL?\n\nOK = Delete for all\nCancel = choose Delete for me');
    if (!all && !confirm('DELETE FOR ME only?')) return;
    try {
      await RF853.rpc('rr_chat_staff_delete_v9712', {
        p_chat_id: chatId,
        p_message_id: messageId,
        p_scope: all ? 'ALL' : 'ME',
      });
      node.remove();
      flash(all ? 'Deleted for all ✓' : 'Deleted for me ✓');
      setTimeout(refresh, 80);
    } catch (error) {
      flash(error?.message || 'Delete failed.');
    }
  }
  function decorate() {
    document.querySelectorAll('#msgs > .msg').forEach(node => {
      const id = node.dataset.rrMsgid || node.dataset.msgid9482 || node.dataset.msgId;
      if (!id || node.querySelector(':scope > .rrDelete9712')) return;
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'rrDelete9712';
      button.textContent = 'DELETE';
      button.onclick = event => {
        event.preventDefault();
        event.stopPropagation();
        remove(node);
      };
      node.appendChild(button);
    });
  }
  const style = document.createElement('style');
  style.textContent = '.rrDelete9712{display:block;margin-top:7px;border:1px solid #76505a!important;background:#2b171c!important;color:#ffbec7!important;border-radius:8px!important;padding:5px 8px!important;font-size:10px!important;font-weight:900!important}';
  document.head.appendChild(style);
  new MutationObserver(() => setTimeout(decorate, 40)).observe(document.documentElement, { childList: true, subtree: true });
  setInterval(decorate, 500);
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', decorate, { once: true }) : decorate();
})();
