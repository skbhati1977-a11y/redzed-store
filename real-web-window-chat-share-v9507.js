(()=>{
  'use strict';
  if(window.__RR_MW_CHAT_SHARE_V9684__)return;
  window.__RR_MW_CHAT_SHARE_V9684__=true;
  const q=new URLSearchParams(location.search);
  const chatId=q.get('chat_id')||'';
  const customerName=q.get('customer_name')||'';
  const customerId=q.get('customer_id')||'';
  const appendRequirementId=q.get('append_requirement_id')||'';
  const fromChat=q.get('from_chat')==='1'&&!!chatId;
  const $=id=>document.getElementById(id);
  if(!fromChat)return;

  function flash(message){
    const el=$('flash');
    if(!el)return;
    el.textContent=message;
    el.style.display='block';
    clearTimeout(el._timer);
    el._timer=setTimeout(()=>el.style.display='none',2200);
  }
  function selectedLots(){
    return [...document.querySelectorAll('.ww-select:checked')]
      .map(el=>String(el.dataset.select||'').trim()).filter(Boolean);
  }
  async function send(){
    const lots=selectedLots();
    if(!lots.length)return flash('SELECT AT LEAST ONE LOT');
    if(!customerId)return flash('CUSTOMER IDENTITY MISSING');
    const button=$('sendChatBtn');
    try{
      if(button){button.disabled=true;button.textContent='UPDATING COLLECTION…';}
      const result=await RF853.rpc('rr_direct_collection_send_v9684',{
        p_chat_id:chatId,
        p_customer_id:customerId,
        p_lots:lots,
        p_requirement_id:appendRequirementId||null,
        p_origin:location.origin
      });
      if(!result?.token||!result?.collection_cycle_id)throw Error('COLLECTION UPDATE FAILED');
      try{
        sessionStorage.setItem('rr_real_chat_return_v9507',JSON.stringify({
          chat_id:chatId,customer_name:customerName,ts:Date.now()
        }));
      }catch(_){}
      flash(`${result.collection_display_no||'COLLECTION'} UPDATED ✓`);
      setTimeout(()=>{
        const back=new URL('real-sales-live-chat-v9434.html',location.href);
        back.search='';
        back.searchParams.set('v','9684');
        back.searchParams.set('chat_id',chatId);
        back.searchParams.set('refresh','1');
        back.hash='rr-chat';
        location.href=back.href;
      },450);
    }catch(error){
      flash(error.message||'SEND FAILED');
    }finally{
      if(button){
        button.disabled=false;
        button.textContent=customerName?`SEND TO ${customerName}`:'SEND TO REAL CHAT';
      }
    }
  }
  function bind(){
    const button=$('sendChatBtn');
    if(!button)return false;
    button.onclick=event=>{
      event.preventDefault();
      event.stopImmediatePropagation();
      send();
    };
    button.textContent=customerName?`SEND COLLECTION TO ${customerName}`:'SEND COLLECTION TO REAL CHAT';
    return true;
  }
  let attempts=0;
  const timer=setInterval(()=>{if(bind()||++attempts>60)clearInterval(timer)},100);
  if(document.readyState!=='loading')bind();
  else document.addEventListener('DOMContentLoaded',bind,{once:true});
})();
