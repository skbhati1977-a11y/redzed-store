(() => {
 'use strict';
 const query = new URLSearchParams(location.search);
 if(query.get('open') !== 'chat') return;
 let opening = false;
 async function openChat(){
  if(opening) return;
  opening = true;
  try {
   await window.RR_CUSTOMER_SECURE_SESSION_V9592.ensure();
   window.RR_FULL_SECURE_CHAT_V9648.open();
   const id = query.get('activity_id');
   if(id){
    let attempts=0;
    const timer=setInterval(()=>{
     const row=[...document.querySelectorAll('#fsMsgs [data-msg-id]')].find(el=>el.dataset.msgId===id);
     if(row){row.scrollIntoView({block:'center'});row.style.outline='2px solid #53bdff';clearInterval(timer);}
     else if(++attempts>=40)clearInterval(timer);
    },250);
   }
  }catch(error){
   opening=false;
   console.warn('Customer notification opening',error.message);
  }
 }
 document.addEventListener('rr:customer-secure-session-ready',openChat);
 openChat();
})();
