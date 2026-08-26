(()=>{
  'use strict';
  const qsa=s=>[...document.querySelectorAll(s)];
  const mode=()=>new URLSearchParams(location.search).get('mode')==='REAL'?'REAL':'TEST';
  let lotPacker=new Map(), packers=new Map(), selectedPacker='', syncTimer=null;
  function msg(t,cls=''){const el=document.getElementById('message');if(el){el.textContent=t||'';el.className=`fg-msg ${cls}`;}}
  async function loadAssignments(){
    const r=await supabaseClient.from('rr_fg_packing_assignments_v788').select('lot_no,worker_user_id,worker_name,worker_code,pack_plan_id,status,submitted_at').eq('data_mode',mode()).eq('status','SUBMITTED').order('submitted_at',{ascending:false});
    if(r.error)throw r.error;
    lotPacker=new Map();packers=new Map();
    (r.data||[]).forEach(a=>{const lot=String(a.lot_no||'').trim(),wid=String(a.worker_user_id||'');if(!lot||!wid||lotPacker.has(lot))return;lotPacker.set(lot,a);if(!packers.has(wid))packers.set(wid,a);});
  }
  async function loadLineMen(){
    const r=await supabaseClient.rpc('rr_fg_despatch_line_men_v9361');if(r.error)throw r.error;
    const sel=document.getElementById('dispatchLineMan');if(!sel)return;
    const html='<option value="">Select Delivery Lineman…</option>'+(r.data||[]).map(x=>`<option value="${x.worker_id}">${String(x.worker_name||'Line Man')}${x.worker_code?' · '+String(x.worker_code):''}</option>`).join('');
    if(sel.innerHTML!==html)sel.innerHTML=html;
  }
  function mountControls(){
    if(document.getElementById('dispatchPackerQueue'))return;
    const dest=document.getElementById('dispatchDestination')?.closest('.fg-field');if(!dest)return;
    const grid=dest.parentElement;
    const p=document.createElement('div');p.className='fg-field';p.innerHTML='<label>Packer Queue *</label><select id="dispatchPackerQueue"><option value="">Select Packer Queue…</option></select>';
    const l=document.createElement('div');l.className='fg-field';l.innerHTML='<label>Delivery Lineman *</label><select id="dispatchLineMan"><option value="">Select Delivery Lineman…</option></select>';
    grid.insertBefore(p,dest);grid.insertBefore(l,dest.nextSibling);
    document.getElementById('dispatchPackerQueue').addEventListener('change',e=>{selectedPacker=String(e.target.value||'');applyQueueFilter(true);});
  }
  function refreshPackerOptions(){
    const sel=document.getElementById('dispatchPackerQueue');if(!sel)return;
    const visibleLots=new Set(qsa('#dispatchConsolidated [data-dc-lot]').map(x=>x.dataset.dcLot));
    let opts=[...packers.entries()];
    if(visibleLots.size){opts=opts.filter(([,a])=>visibleLots.has(String(a.lot_no||''))||[...visibleLots].some(l=>String(lotPacker.get(l)?.worker_user_id||'')===String(a.worker_user_id||'')));}
    const keep=selectedPacker;
    const html='<option value="">Select Packer Queue…</option>'+opts.map(([id,a])=>`<option value="${id}">${String(a.worker_name||'Packer')}${a.worker_code?' · '+String(a.worker_code):''}</option>`).join('');
    if(sel.innerHTML!==html)sel.innerHTML=html;
    if(keep&&opts.some(([id])=>id===keep)){sel.value=keep;}else if(keep){selectedPacker='';sel.value='';}
  }
  function applyQueueFilter(clearOthers=false){
    qsa('#dispatchConsolidated [data-dc-lot]').forEach(sec=>{
      const lot=sec.dataset.dcLot,a=lotPacker.get(lot),match=!!selectedPacker&&String(a?.worker_user_id||'')===selectedPacker;
      if(clearOthers&&!match){sec.querySelectorAll('[data-dc-send]').forEach(inp=>{if(inp.value!=='0'){inp.value='0';inp.dispatchEvent(new Event('input',{bubbles:true}));}});}
      sec.style.display=selectedPacker?(match?'':'none'):'';
    });
  }
  function scheduleSync(delay=80){clearTimeout(syncTimer);syncTimer=setTimeout(()=>{refreshPackerOptions();applyQueueFilter(false);},delay);}
  function selectedEntries(){
    return qsa('#dispatchBoxRows tr[data-box-id]').filter(r=>r.querySelector('[data-dispatch-check]')?.checked).map(r=>({box_id:r.dataset.boxId,qty:Number(r.querySelector('[data-dispatch-qty]')?.value||0),lot:String(r.children[2]?.textContent||'').trim()}));
  }
  async function submitQueue(e){
    e.preventDefault();e.stopImmediatePropagation();
    try{
      const packer=document.getElementById('dispatchPackerQueue')?.value||'',lineman=document.getElementById('dispatchLineMan')?.value||'';
      if(!packer)throw Error('Packer Queue selection mandatory');if(!lineman)throw Error('Delivery Lineman selection mandatory');
      const entries=selectedEntries();if(!entries.length)throw Error('Kam se kam ek Box select karein.');
      for(const x of entries){const a=lotPacker.get(x.lot);if(String(a?.worker_user_id||'')!==String(packer))throw Error(`Lot ${x.lot} selected Packer Queue ka nahi hai.`);if(!Number.isInteger(x.qty)||x.qty<=0)throw Error('Selected boxes ki Send Qty mandatory hai.');}
      const payload=entries.map(({box_id,qty})=>({box_id,qty}));
      const r=await supabaseClient.rpc('rr_fg_create_despatch_queue_v9375',{p_boxes:payload,p_packer_worker_id:packer,p_line_man_worker_id:lineman,p_destination:document.getElementById('dispatchDestination').value,p_remarks:document.getElementById('dispatchRemarks').value,p_data_mode:mode()});
      if(r.error)throw r.error;const d=r.data||{};
      msg(`Challan ${d.challan_no||''} locked · ${d.total_boxes||entries.length} boxes / ${d.total_qty||0} PCS · Packer ${d.packer_name||''} → Lineman ${d.line_man_name||''}`,'ok');
      setTimeout(()=>document.getElementById('loadReadyBoxes')?.click(),50);
    }catch(err){msg(err.message||String(err),'error');}
  }
  async function init(){
    mountControls();
    try{await loadAssignments();refreshPackerOptions();}catch(e){console.warn('Packer queue init',e);msg(e.message||String(e),'error');}
    try{await loadLineMen();}catch(e){console.warn('Lineman init',e);msg(e.message||String(e),'error');}
    const btn=document.getElementById('submitDispatch');if(btn)btn.addEventListener('click',submitQueue,true);
    const raw=document.getElementById('dispatchBoxRows');if(raw)new MutationObserver(()=>scheduleSync(120)).observe(raw,{childList:true});
    document.getElementById('loadReadyBoxes')?.addEventListener('click',()=>setTimeout(async()=>{try{await loadAssignments();refreshPackerOptions();applyQueueFilter(false);}catch(e){console.warn(e);}},500));
    setTimeout(()=>scheduleSync(0),500);setTimeout(()=>scheduleSync(0),1200);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();