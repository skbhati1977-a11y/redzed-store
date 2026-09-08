(() => {
  'use strict';
  if (window.__RR_CHAT_FOCUS_SENT_V9707__) return;
  window.__RR_CHAT_FOCUS_SENT_V9707__ = true;
  const q = new URLSearchParams(location.search), chat = q.get('open_chat') || '', message = q.get('focus_message') || '';
  if (!chat || !message) return;
  const style = document.createElement('style');
  style.textContent = '.rrSentFocus9707{animation:rrSentFocus9707 2.8s ease 2}@keyframes rrSentFocus9707{20%,70%{box-shadow:0 0 0 4px #5bd68c,0 0 32px #5bd68c99;background:#315843}100%{box-shadow:none}}';
  document.head.appendChild(style);
  let tries = 0;
  const timer = setInterval(() => {
    const row = document.querySelector(`#inboxRows .chatrow[data-chat="${CSS.escape(chat)}"]`);
    if (row && window.__RR_CURRENT_CHAT_ID__ !== chat) row.click();
    const bubble = document.querySelector(`#msgs .msg[data-msg-id="${CSS.escape(message)}"]`);
    if (bubble) { clearInterval(timer); bubble.scrollIntoView({ behavior: 'smooth', block: 'center' }); bubble.classList.add('rrSentFocus9707'); history.replaceState(null, '', 'real-sales-live-chat-v9434.html?v=9707#rr-chat'); }
    else if (++tries > 40) clearInterval(timer);
  }, 250);
})();
