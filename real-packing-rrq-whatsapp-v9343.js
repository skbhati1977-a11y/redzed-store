(()=>{
  'use strict';
  if(window.__RR_PACK_RRQ_WA_V9357__)return;
  window.__RR_PACK_RRQ_WA_V9357__=true;

  const MODE='TEST';
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String(document.getElementById('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const show=(t,cls='')=>{const m=document.getElementById('message');if(m){m.textContent=t;m.className='fg-msg '+cls}const x=document.getElementById('rrPicLocalMsg');if(x){x.textContent=t;x.className='fg-msg '+cls}};
  let lastOpenPayload=[];

  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}

  function normalizePhone(value){
    let x=String(value||'').replace(/\D/g,'');
    if(x.length===10)x='91'+x;
    return x;
  }

  function waHref(item){
    const mobile=normalizePhone(item?.mobile);
    if(!mobile)return'';
    return `https://wa.me/${mobile}?text=${encodeURIComponent(String(item?.message_text||''))}`;
  }

  function roleRank(item){
    const r=String(item?.recipient_role||'').toLowerCase();
    if(/owner|super admin/.test(r))return 1;
    if(/accounts|admin/.test(r))return 2;
    if(/sales/.test(r))return 3;
    return 9;
  }

  function cleanItems(items){
    const seen=new Set();
    return (items||[])
      .filter(x=>waHref(x))
      .sort((a,b)=>roleRank(a)-roleRank(b))
      .filter(x=>{
        const key=`${normalizePhone(x.mobile)}|${String(x.recipient_role||'').toLowerCase()}|${String(x.message_text||'')}`;
        if(seen.has(key))return false;
        seen.add(key);return true;
      });
  }

  async function markOpened(item){
    if(!item?.message_id)return;
    try{await rpc('rr_comm_mark_whatsapp_opened_v853',{p_message_id:item.message_id});}catch(e){console.warn('WhatsApp audit mark failed',e);}
  }

  function renderRemaining(items,primaryOpened){
    const clean=cleanItems(items);
    lastOpenPayload=clean;
    const host=document.getElementById('rrPicLocalMsg')||document.getElementById('message');
    if(!host)return;
    host.className='fg-msg '+(primaryOpened?'ok':'');
    host.innerHTML='';
    const text=document.createElement('span');
    text.textContent=primaryOpened
      ? (clean.length?'Primary WhatsApp opened. Remaining prepared messages niche hain.':'WhatsApp prepared message opened.')
      : 'Rate request saved. Prepared WhatsApp message open karein.';
    host.appendChild(text);
    clean.forEach((item,i)=>{
      const a=document.createElement('a');
      a.className='fg-btn primary';
      a.style.marginLeft='8px';
      a.target='_blank';a.rel='noopener';a.href=waHref(item);
      a.textContent=`OPEN WHATSAPP${clean.length>1?' '+(i+1):''}`;
      a.addEventListener('click',()=>{markOpened(item);},{once:true});
      host.appendChild(a);
    });
  }

  async function openPrimaryLikeDamage(items){
    const clean=cleanItems(items);
    if(!clean.length){show('Rate request saved. WhatsApp recipient/message unavailable.','error');return;}
    lastOpenPayload=clean;
    const primary=clean[0],remaining=clean.slice(1),href=waHref(primary);

    // Same proven Damage/GR pattern: try new tab, then same-tab fallback on mobile popup block.
    let win=null;
    try{win=window.open(href,'_blank','noopener,noreferrer');}catch(_){win=null;}
    if(win){
      markOpened(primary);
      renderRemaining(remaining,true);
      return;
    }

    // Mark before leaving the page, then navigate to the prepared WhatsApp compose.
    try{await markOpened(primary);}finally{window.location.assign(href);}
  }

  async function deliverPayload(payload){
    const open=Array.isArray(payload?.whatsapp_open)?payload.whatsapp_open:[];
    if(!open.length){show('Rate request saved, but WhatsApp payload unavailable.','error');return;}
    await openPrimaryLikeDamage(open);
  }

  function installRpcBridge(){
    const c=db();
    if(!c?.rpc||c.__rrRrqWaBridge9357)return false;
    const original=c.rpc.bind(c);
    c.rpc=async function(name,args,options){
      const res=await original(name,args,options);
      if(name==='rr_pack_request_rate_v9340'&&!res?.error&&res?.data){
        // No Meta Cloud send here. Use the same direct wa.me flow already proven in Damage/GR.
        setTimeout(()=>deliverPayload(res.data).catch(e=>show('WhatsApp: '+String(e?.message||e),'error')),0);
      }
      return res;
    };
    c.__rrRrqWaBridge9357=true;
    return true;
  }

  async function openFromPending(l){
    if(!l)return;
    try{
      const q=await rpc('rr_pack_rrq_wa_pending_v9343',{p_lot_no:l,p_data_mode:MODE});
      const items=Array.isArray(q?.items)?q.items:[];
      if(items.length){await openPrimaryLikeDamage(items);return;}
      if(lastOpenPayload.length){await openPrimaryLikeDamage(lastOpenPayload);return;}
      show('Koi pending WhatsApp message nahi mila.','ok');
    }catch(e){show('WhatsApp: '+String(e?.message||e),'error');}
  }

  document.addEventListener('click',e=>{
    if(!e.target?.closest?.('#rrRateRefresh'))return;
    setTimeout(()=>openFromPending(lot()),150);
  },true);

  [0,120,300,700,1400].forEach(ms=>setTimeout(installRpcBridge,ms));
})();
