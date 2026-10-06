(()=>{
 'use strict';
 const key='rr_market_recipients_test71';
 const clean=ids=>[...new Set((ids||[]).map(String).filter(Boolean))];
 const shared=window.RRMarketCustomer71={get(){try{const v=JSON.parse(window.sessionStorage.getItem(key)||'null');return v&&Date.now()-v.at<7200000?clean(v.ids):[]}catch(_){return[]}},set(ids){ids=clean(ids);try{if(ids.length)window.sessionStorage.setItem(key,JSON.stringify({ids,at:Date.now()}));else window.sessionStorage.removeItem(key)}catch(_){}return ids},clear(){this.set([])}};
 const q=new URL(location.href).searchParams;
 if(q.get('from_chat')==='1'&&q.get('chat_id')&&!q.get('rr_partner_mode'))shared.set([q.get('chat_id')]);
 document.addEventListener('change',e=>{if(e.target.matches('.rm-chat-modal [data-customers] input[data-chat]'))shared.set([...e.target.closest('.rm-chat-modal').querySelectorAll('[data-customers] input[data-chat]:checked')].map(c=>c.dataset.chat));},true);
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
  shared.set(ids);url.searchParams.delete('recipient_chat');ids.forEach(id=>url.searchParams.append('recipient_chat',id));
  e.preventDefault();e.stopImmediatePropagation();
  location.href=url.href;
 },true);
})();
