(()=>{
 'use strict';
 // Carry recipients from a previously loaded Readymade picker into the shared Market flow.
 document.addEventListener('click',e=>{
  const button=e.target.closest('[data-outside], [data-send]');
  if(!button)return;
  const picker=button.closest('.rm-chat-modal');
  if(!picker)return;
  const link=picker.querySelector('a[data-outside]');
  if(!link)return;
  const url=new URL(link.href,location.href);
  if(url.searchParams.get('from')!=='READYMADE')return;
  const ids=[...new Set([...picker.querySelectorAll('[data-customers] input[data-chat]:checked')].map(c=>c.dataset.chat).filter(Boolean))];
  url.searchParams.delete('recipient_chat');ids.forEach(id=>url.searchParams.append('recipient_chat',id));
  e.preventDefault();e.stopImmediatePropagation();
  location.href=url.href;
 },true);
})();
