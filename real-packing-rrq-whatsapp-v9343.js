(()=>{
  'use strict';
  if(window.__RR_PACK_RRQ_WA_V9355__)return;
  window.__RR_PACK_RRQ_WA_V9355__=true;
  const MODE='TEST';
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String(document.getElementById('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const show=(t,cls='')=>{const m=document.getElementById('message');if(m){m.textContent=t;m.className='fg-msg '+cls}const x=document.getElementById('rrPicLocalMsg');if(x){x.textContent=t;x.className='fg-msg '+cls}};
  const inflight=new Map(),done=new Set();
  const sleep=ms=>new Promise(r=>setTimeout(r,ms));
  const transient=e=>/abort|aborted|AbortError|Failed to fetch|FunctionsFetchError|NetworkError/i.test(String(e?.name||'')+' '+String(e?.message||e||''));

  function normalizePhone(value){let x=String(value||'').replace(/\D/g,'');if(x.length===10)x='91'+x;return x}
  function whatsappUrl(phone,message){const number=normalizePhone(phone);if(!number)throw Error('WhatsApp number required.');return 'https://wa.me/'+number+'?text='+encodeURIComponent(message)}
  function openWhatsapp(phone,message,{sameTabFallback=false,preparedWindow=null}={}){
    const url=whatsappUrl(phone,message);
    if(preparedWindow&&!preparedWindow.closed){preparedWindow.location.replace(url);return true}
    const win=window.open(url,'_blank');
    if(win)return true;
    if(sameTabFallback){window.location.assign(url);return false}
    throw Error('Browser ne WhatsApp popup block kiya. WhatsApp button se dobara kholein.');
  }

  const waText=item=>String(item?.message_text||item?.message||item?.text||'').trim();
  const waPhone=item=>normalizePhone(item?.mobile||item?.recipient_mobile||item?.phone||item?.recipient_phone||'');
  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}
  function pickOwner(items){return items.find(x=>String(x?.recipient_role||x?.role||'').toLowerCase()==='owner')||items.find(x=>waPhone(x).includes('9654401954'))||items[0]}
  function mapOutbox(r){const meta=r?.meta||{};return{message_id:r?.message_id,mobile:r?.recipient_mobile,message_text:r?.message_text,send_status:r?.send_status,recipient_name:meta.recipient_name||'',recipient_role:meta.recipient_role||'',approval_link:meta.approval_link||''}}
  async function latestOutbox(l){const c=db();if(!c?.from)return null;const {data,error}=await c.from('rr_comm_outbox_v853').select('message_id,recipient_mobile,message_text,send_status,meta,created_at').eq('data_mode',MODE).eq('channel_code','WHATSAPP').contains('meta',{source_module:'PACKING_RRQ',lot_no:l,packing_rrq_rate_approval:true}).order('created_at',{ascending:false}).limit(20);if(error)throw error;const rows=(data||[]).map(mapOutbox);return rows.length?pickOwner(rows):null}
  async function resolveItem(l){for(let attempt=0;attempt<8;attempt++){await sleep(attempt?700:250);let q;try{q=await rpc('rr_pack_rrq_wa_pending_v9343',{p_lot_no:l,p_data_mode:MODE})}catch(e){if(transient(e))continue;throw e}const items=Array.isArray(q?.items)?q.items:[];const item=items.length?pickOwner(items):await latestOutbox(l);if(item)return item}return null}
  async function sendPending(l,preparedWindow){if(!l||done.has(l))return;if(inflight.has(l))return inflight.get(l);const task=(async()=>{try{const item=await resolveItem(l);if(!item){if(preparedWindow&&!preparedWindow.closed)preparedWindow.close();show('Rate request saved. WhatsApp link pending hai; Refresh se retry karein.','error');return}openWhatsapp(waPhone(item),waText(item),{sameTabFallback:true,preparedWindow});done.add(l);show('WhatsApp app open ho raha hai. Chat khulne par Send dabayein.','ok');}finally{inflight.delete(l)}})();inflight.set(l,task);return task;}
  function prepareWindow(){try{const w=window.open('about:blank','_blank');if(w){w.document.open();w.document.write('<!doctype html><title>WhatsApp</title><body style="font-family:sans-serif;padding:24px">WhatsApp message ready ho raha hai...</body>');w.document.close()}return w}catch{return null}}
  document.addEventListener('click',e=>{const b=e.target?.closest?.('#rrRequestRate');if(!b)return;const l=lot();if(!l)return;done.delete(l);const w=prepareWindow();setTimeout(()=>sendPending(l,w).catch(err=>{try{if(w&&!w.closed)w.close()}catch{}show('WhatsApp open: '+String(err?.message||err),'error')}),50);},true);
  document.addEventListener('click',e=>{if(!e.target?.closest?.('#rrRateRefresh'))return;const l=lot();if(!l)return;done.delete(l);const w=prepareWindow();setTimeout(()=>sendPending(l,w).catch(err=>{try{if(w&&!w.closed)w.close()}catch{}show('WhatsApp open: '+String(err?.message||err),'error')}),50);},true);
})();