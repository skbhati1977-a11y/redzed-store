(()=>{
  'use strict';
  if(window.__RR_PACK_WAME_V9361__)return;
  window.__RR_PACK_WAME_V9361__=true;
  const $=id=>document.getElementById(id);
  const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const MODE='TEST';
  let activeLot='',items=[],selectedId='',enabled=true,busy=false;
  function note(text){if($('rrWaNote'))$('rrWaNote').textContent=text;}
  function phone(value){let n=String(value||'').trim().replace(/[\s()+-]/g,'');if(n.startsWith('00'))n=n.slice(2);if(/^\d{10}$/.test(n))n='91'+n;return /^[1-9]\d{7,14}$/.test(n)?n:'';}
  function owners(payload){
    const source=Array.isArray(payload?.whatsapp_open)?payload.whatsapp_open:payload?.items;
    return (Array.isArray(source)?source:[]).filter(x=>['owner','superadmin','super admin'].includes(String(x.recipient_role||'').trim().toLowerCase()));
  }
  function selected(){return items.find(x=>String(x.message_id)===selectedId);}
  function urlFor(item){
    const n=phone(item?.mobile),text=String(item?.message_text||'').trim();
    return n&&text?'https://wa.me/'+n+'?text='+encodeURIComponent(text):'';
  }
  function render(){
    const select=$('rrWaRecipient'),link=$('rrWaOpen');if(!select||!link)return;
    select.replaceChildren();
    if(items.length!==1){const o=document.createElement('option');o.value='';o.textContent=items.length?'Select Superadmin…':'Request ke baad contact load hoga';select.appendChild(o);}
    items.forEach(x=>{const o=document.createElement('option');o.value=String(x.message_id);o.textContent=(x.recipient_name||'Superadmin')+' · '+(phone(x.mobile)?'ending '+phone(x.mobile).slice(-4):'mobile missing');select.appendChild(o);});
    select.value=selectedId;select.disabled=!enabled||!items.length;
    const url=activeLot===lot()?urlFor(selected()):'';
    link.hidden=!enabled||!url;if(url)link.href=url;else link.removeAttribute('href');
  }
  function mount(){
    const gate=document.querySelector('.rr-rate-gate');if(!gate)return;
    if(!$('rrWaControls')){
      const box=document.createElement('div');box.id='rrWaControls';box.className='rr-wa-controls';
      box.innerHTML='<label class="rr-wa-switch"><input id="rrWaEnabled" type="checkbox" role="switch" checked><span>Request save hone par Superadmin WhatsApp kholen</span></label><label class="fg-field"><span>Superadmin</span><select id="rrWaRecipient" aria-label="Superadmin WhatsApp recipient"></select></label><a id="rrWaOpen" class="fg-btn ok" target="_blank" rel="noopener noreferrer" hidden>OPEN SUPERADMIN WHATSAPP</a><p id="rrWaNote" class="fg-muted" role="status">Direct wa.me · WhatsApp mein Send aap dabayenge. Approval alag se required hai.</p>';
      gate.appendChild(box);
      $('rrWaEnabled').checked=enabled;
      $('rrWaEnabled').onchange=e=>{enabled=e.target.checked;render();note(enabled?'WhatsApp opening enabled. Message Send manually karein.':'WhatsApp opening OFF. Approval request save hogi; koi message auto-send nahi hoga.');};
      $('rrWaRecipient').onchange=e=>{selectedId=e.target.value;render();};
      $('rrWaOpen').onclick=e=>{if(activeLot!==lot()||!enabled||!urlFor(selected())){e.preventDefault();return;}note('WhatsApp khul raha hai. Send manually karein; approval status unchanged hai.');};
      render();
    }
    if(activeLot!==lot()){activeLot=lot();items=[];selectedId='';render();note('Direct wa.me · WhatsApp mein Send aap dabayenge. Approval alag se required hai.');}
  }
  function receive(l,payload){
    if(l!==lot()||$('packWorkspace')?.hidden)return false;
    mount();activeLot=l;items=owners(payload);selectedId=items.length===1?String(items[0].message_id):'';render();
    note(!items.length?'Request saved. Active Superadmin contact/link nahi mila; profile mapping check karein.':items.length>1?'Multiple Superadmins mile. Sahi recipient select karke WhatsApp kholen.':!urlFor(selected())?'Superadmin mobile missing/invalid. Profile mein correct WhatsApp mobile required.':'Superadmin message ready. WhatsApp kholen aur Send dabayein.');
    return true;
  }
  function close(popup){try{if(popup&&!popup.closed)popup.close();}catch(_){}}
  async function rpc(name,args){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}
  async function request(e){
    const button=e.target?.closest?.('#rrRequestRate');if(!button)return;
    // Existing photo-first capture gate runs first. This replaces only WhatsApp request delivery.
    e.preventDefault();e.stopImmediatePropagation();mount();
    if(busy)return;
    const l=lot();if(!l||!document.querySelector('#packRows tr')){note('Pehle Lot select aur Packing Algorithm/Table complete karein.');return;}
    if(window.__RR_PACK_UPLOAD_BUSY__){note('Photo upload complete hone dein.');return;}
    busy=true;button.disabled=true;
    let popup=null,saved=false;
    try{
      if(enabled){popup=window.open('about:blank','_blank');if(popup)popup.opener=null;}
      note('Approval request status check ho raha hai…');
      const args={p_lot_no:l,p_data_mode:MODE};
      const status=await rpc('rr_pack_rate_status_v9340',args);
      if(l!==lot()||$('packWorkspace')?.hidden)return;
      if(status?.approved){note('Rate already APPROVED. Nayi request ya WhatsApp message nahi banaya.');$('rrRateRefresh')?.click();return;}
      let payload=null;
      if(status?.status==='REQUESTED'){
        const pending=await rpc('rr_pack_rrq_wa_pending_v9343',args);
        if(owners(pending).length)payload=pending;
      }
      if(l!==lot()||$('packWorkspace')?.hidden)return;
      if(!payload)payload=await rpc('rr_pack_request_rate_v9340',args);
      saved=true;
      if(payload?.approved){note('Rate already APPROVED. WhatsApp opening required nahi hai.');if(l===lot())$('rrRateRefresh')?.click();return;}
      if(!receive(l,payload))return;
      $('rrRateRefresh')?.click(); // Existing read-only status refresh; never sends a message.
      const url=urlFor(selected());
      if(enabled&&url&&popup&&!popup.closed){popup.location.replace(url);popup=null;note('WhatsApp opened. Send manually karein; final approval abhi bhi required hai.');}
      else if(!enabled)note('Approval request saved. WhatsApp switch OFF hai.');
      else if(url)note('Request saved. OPEN SUPERADMIN WHATSAPP dabayein—message prefilled hai.');
    }catch(err){
      if(l===lot())note((saved?'Request saved; WhatsApp open nahi hua. ':'Request complete nahi hui. ')+String(err?.message||err));
    }finally{close(popup);busy=false;button.disabled=false;}
  }
  const style=document.createElement('style');
  style.textContent='.rr-wa-controls{display:grid;gap:12px;margin-top:16px;min-width:0;max-width:100%}.rr-wa-switch{display:flex;align-items:center;gap:12px;min-height:48px;cursor:pointer}.rr-wa-switch input{appearance:none;flex:0 0 48px;width:48px;height:28px;border-radius:18px;background:#4b5563;position:relative;cursor:pointer}.rr-wa-switch input:before{content:"";position:absolute;width:22px;height:22px;border-radius:50%;background:white;left:3px;top:3px;transition:transform .15s}.rr-wa-switch input:checked{background:#18794e}.rr-wa-switch input:checked:before{transform:translateX(20px)}.rr-wa-switch input:focus-visible{outline:2px solid #9ec5ff;outline-offset:3px}.rr-wa-controls select{width:100%;max-width:100%;min-height:44px;background:#10151d;color:#fff;border:1px solid #39424d;border-radius:10px;padding:10px}.rr-wa-controls .fg-btn{white-space:normal;overflow-wrap:anywhere;max-width:100%;text-align:center;text-decoration:none}.rr-wa-controls p{overflow-wrap:anywhere}.rr-wa-controls [hidden]{display:none!important}';
  document.head.appendChild(style);
  document.addEventListener('click',request,true);
  new MutationObserver(mount).observe(document.documentElement,{childList:true,subtree:true});
  mount();
  // No Cloud API invocation, automatic retries, or Refresh sending side effect.
})();
