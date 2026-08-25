(()=>{
  'use strict';
  if(window.__RR_PACK_RRQ_WA_V9355__)return;
  window.__RR_PACK_RRQ_WA_V9355__=true;
  const MODE='TEST';
  const BTN_ID='rrWaSuperAdminBtn';
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String(document.getElementById('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const show=(t,cls='')=>{const m=document.getElementById('message');if(m){m.textContent=t;m.className='fg-msg '+cls}const x=document.getElementById('rrPicLocalMsg');if(x){x.textContent=t;x.className='fg-msg '+cls}};
  const inflight=new Map(),cache=new Map();
  const sleep=ms=>new Promise(r=>setTimeout(r,ms));
  const transient=e=>/abort|aborted|AbortError|Failed to fetch|FunctionsFetchError|NetworkError/i.test(String(e?.name||'')+' '+String(e?.message||e||''));

  function normalizePhone(value){let x=String(value||'').replace(/\D/g,'');if(x.length===10)x='91'+x;return x}
  function whatsappUrl(phone,message){const number=normalizePhone(phone);if(!number)throw Error('WhatsApp number required.');return 'https://wa.me/'+number+'?text='+encodeURIComponent(message)}
  function openWhatsapp(phone,message,{sameTabFallback=false}={}){
    const url=whatsappUrl(phone,message);
    const win=window.open(url,'_blank','noopener,noreferrer');
    if(win)return true;
    if(sameTabFallback){window.location.assign(url);return false}
    throw Error('Browser ne WhatsApp popup block kiya. WhatsApp SuperAdmin button se dobara kholein.');
  }

  const waText=item=>String(item?.message_text||item?.message||item?.text||'').trim();
  const waPhone=item=>normalizePhone(item?.mobile||item?.recipient_mobile||item?.phone||item?.recipient_phone||'');
  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}
  function pickOwner(items){return items.find(x=>String(x?.recipient_role||x?.role||'').toLowerCase()==='owner')||items.find(x=>waPhone(x).includes('9654401954'))||items[0]}
  function mapOutbox(r){const meta=r?.meta||{};return{message_id:r?.message_id,mobile:r?.recipient_mobile,message_text:r?.message_text,send_status:r?.send_status,recipient_name:meta.recipient_name||'',recipient_role:meta.recipient_role||'',approval_link:meta.approval_link||''}}
  async function latestOutbox(l){const c=db();if(!c?.from)return null;const {data,error}=await c.from('rr_comm_outbox_v853').select('message_id,recipient_mobile,message_text,send_status,meta,created_at').eq('data_mode',MODE).eq('channel_code','WHATSAPP').contains('meta',{source_module:'PACKING_RRQ',lot_no:l,packing_rrq_rate_approval:true}).order('created_at',{ascending:false}).limit(20);if(error)throw error;const rows=(data||[]).map(mapOutbox);return rows.length?pickOwner(rows):null}
  async function resolveItem(l){for(let attempt=0;attempt<8;attempt++){await sleep(attempt?700:250);let q;try{q=await rpc('rr_pack_rrq_wa_pending_v9343',{p_lot_no:l,p_data_mode:MODE})}catch(e){if(transient(e))continue;throw e}const items=Array.isArray(q?.items)?q.items:[];const item=items.length?pickOwner(items):await latestOutbox(l);if(item)return item}return null}

  function ensureButton(){
    const req=document.getElementById('rrRequestRate');
    if(!req)return null;
    let btn=document.getElementById(BTN_ID);
    if(btn)return btn;
    btn=document.createElement('button');
    btn.id=BTN_ID;
    btn.type='button';
    btn.className='fg-btn';
    btn.style.marginTop='10px';
    btn.style.background='#20242d';
    btn.textContent='WhatsApp SuperAdmin';
    btn.hidden=true;
    req.insertAdjacentElement('afterend',btn);
    btn.addEventListener('click',()=>{
      const l=lot(),item=cache.get(l);
      if(!item){show('WhatsApp message abhi ready nahi hai. Pehle Request/Refresh dabayein.','error');return}
      try{openWhatsapp(waPhone(item),waText(item),{sameTabFallback:true});show('WhatsApp open ho raha hai. Chat khulne par Send dabayein.','ok')}catch(e){show(String(e?.message||e),'error')}
    });
    return btn;
  }
  function renderButton(item){
    const btn=ensureButton();
    if(!btn)return;
    btn.hidden=!item;
    if(item)btn.textContent='WhatsApp SuperAdmin';
  }
  async function prepareMessage(l){
    if(!l)return;
    if(inflight.has(l))return inflight.get(l);
    const task=(async()=>{try{const item=await resolveItem(l);if(item){cache.set(l,item);renderButton(item);show('WhatsApp SuperAdmin ready. Button dabakar message open karein.','ok')}else{renderButton(null);show('Rate request saved. WhatsApp link pending hai; Refresh se retry karein.','error')}}finally{inflight.delete(l)}})();
    inflight.set(l,task);
    return task;
  }

  document.addEventListener('click',e=>{const b=e.target?.closest?.('#rrRequestRate,#rrRateRefresh');if(!b)return;const l=lot();if(!l)return;setTimeout(()=>prepareMessage(l).catch(err=>show('WhatsApp ready: '+String(err?.message||err),'error')),650);},true);
  document.addEventListener('click',()=>setTimeout(()=>{ensureButton();const l=lot();if(l&&cache.has(l))renderButton(cache.get(l));},200),true);
  [600,1400,2600].forEach(ms=>setTimeout(()=>{ensureButton();const l=lot();if(l)prepareMessage(l).catch(()=>{})},ms));
})();