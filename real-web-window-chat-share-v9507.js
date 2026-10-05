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
  let sending=false;
  async function send(){
    if(sending)return;
    const lots=selectedLots();
    if(!lots.length)return flash('SELECT AT LEAST ONE LOT');
    sending=true;
    const button=$('sendChatBtn');
    try{
      if(button){button.disabled=true;button.textContent='UPDATING COLLECTION…';}
      const context=await RF853.rpc('rr_sales_collection_context_test71',{p_chat_id:chatId,p_requirement_id:appendRequirementId||null,p_collection_cycle_id:window.RRSalesCollection?.context()?.collection_cycle_id||q.get('collection_cycle_id')||null});
      if(!context?.customer_id)throw Error('Party chat could not be verified. Return to Sales chat and reopen collection.');
      const result=await RF853.rpc('rr_sales_collection_send_test71',{
        p_chat_id:chatId,
        p_collection_cycle_id:window.RRSalesCollection?.context()?.collection_cycle_id||q.get('collection_cycle_id')||null,
        // The authenticated backend resolves missing identity from this chat.
        p_customer_id:context.customer_id,
        p_lots:lots,
        p_requirement_id:appendRequirementId||null,
        p_origin:new URL(window.RR_CUSTOMER_SHARE_BASE||'https://redzed-customer-collection.jggfab2011.chatgpt.site/').origin
      });
      if(!result?.token||!result?.collection_cycle_id)throw Error('COLLECTION UPDATE FAILED');
      try{
        sessionStorage.setItem('rr_real_chat_return_v9507',JSON.stringify({
          chat_id:chatId,customer_name:customerName,collection_cycle_id:result.collection_cycle_id,ts:Date.now()
        }));
      }catch(_){}
      flash(`${result.collection_display_no||'COLLECTION'} UPDATED ✓`);
      setTimeout(()=>{
        const back=new URL('real-sales-live-chat-v9434.html',location.href);
        back.search='';
        back.searchParams.set('v','9684');
        back.searchParams.set('chat_id',chatId);
        back.searchParams.set('followup','1');
        back.searchParams.set('collection_cycle_id',result.collection_cycle_id);
        back.searchParams.set('refresh','1');
        back.hash='rr-chat';
        location.href=back.href;
      },450);
    }catch(error){
      flash(error.message||'SEND FAILED');
    }finally{
      sending=false;
      if(button){
        button.disabled=false;
        button.textContent=customerName?`SEND TO ${customerName}`:'SEND TO REAL CHAT';
      }
    }
  }
  function bind(){
    const button=$('sendChatBtn');
    if(!button)return false;
    button.disabled=false;
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
