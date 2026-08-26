(()=>{
  'use strict';
  if(window.__RR_DESPATCH_PACKER_LINEMAN_V9378__)return;
  window.__RR_DESPATCH_PACKER_LINEMAN_V9378__=true;
  const qsa=s=>[...document.querySelectorAll(s)];
  const mode=()=>new URLSearchParams(location.search).get('mode')==='REAL'?'REAL':'TEST';
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  let lotPacker=new Map(),packers=new Map(),selectedPacker='',syncTimer=null,submitBound=false;
  function msg(t,cls=''){const el=document.getElementById('message');if(el){el.textContent=t||'';el.className=`fg-msg ${cls}`;}}
  async function loadAssignments(){
    const c=db();if(!c?.from)throw Error('Supabase client unavailable');
    const r=await c.from('rr_fg_packing_assignments_v788').select('lot_no,worker_user_id,worker_name,worker_code,pack_plan_id,status,submitted_at').eq('data_mode',mode()).eq('status','SUBMITTED').order('submitted_at',{ascending:false});
    if(r.error)throw r.error;
    lotPacker=new Map();packers=new Map();
    (r.data||[]).forEach(a=>{const lot=String(a.lot_no||'').trim(),wid=String(a.worker_user_id||'').trim();if(!lot||!wid||lotPacker.has(lot))return;lotPacker.set(lot,a);if(!packers.has(wid))packers.set(wid,a);});
  }
  async function loadLineMen(){
    const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');
    const r=await c.rpc('rr_fg_despatch_line_men_v9361');if(r.error)throw r.error;
    const sel=document.getElementById('dispatchLineMan');if(!sel)return;
    sel.innerHTML='<option value="">Select Delivery Lineman…</option>'+(r.data||[]).map(x=>`<option value="${x.worker_id}">${String(x.worker_name||'Line Man')}${x.worker_code?' · '+String(x.worker_code):''}</option>`).join('');
  }
  function ensureControls(){
    const dest=document.getElementById('dispatchDestination');
    const remarks=document.getElementById('dispatchRemarks');
    if(!dest||!remarks)return false;
    const grid=dest.closest('.fg-grid')||dest.parentElement?.parentElement;
    if(!grid)return false;
    if(!document.getElementById('dispatchPackerQueue')){
      const p=document.createElement('div');p.className='fg-field';p.id='dispatchPackerQueueField';p.innerHTML='<label for="dispatchPackerQueue">Packer Queue *</label><select id="dispatchPackerQueue"><option value="">Select Packer Queue…</option></select>';
      grid.insertBefore(p,dest.closest('.fg-field')||grid.firstChild);
    }
    if(!document.getElementById('dispatchLineMan')){
      const l=document.createElement('div');l.className='fg-field';l.id='dispatchLineManField';l.innerHTML='<label for="dispatchLineMan">Delivery Lineman *</label><select id="dispatchLineMan"><option value="">Select Delivery Lineman…</option></select>';
      const remarksField=remarks.closest('.fg-field');grid.insertBefore(l,remarksField||null);
    }
    const pq=document.getElementById('dispatchPackerQueue');
    if(pq&&!pq.dataset.bound){pq.dataset.bound='1';pq.addEventListener('change',e=>{selectedPacker=String(e.target.value||'');applyQueueFilter(true);});}
    return true;
  }
  function refreshPackerOptions(){
    const sel=document.getElementById('dispatchPackerQueue');if(!sel)return;
    const keep=selectedPacker||sel.value||'';
    const opts=[...packers.entries()];
    sel.innerHTML='<option value="">Select Packer Queue…</option>'+opts.map(([id,a])=>`<option value="${id}">${String(a.worker_name||'Packer')}${a.worker_code?' · '+String(a.worker_code):''}</option>`).join('');
    if(keep&&opts.some(([id])=>id===keep)){selectedPacker=keep;sel.value=keep;}else{selectedPacker='';sel.value='';}
  }
  function applyQueueFilter(clearOthers=false){
    qsa('#dispatchConsolidated [data-dc-lot]').forEach(sec=>{
      const lot=sec.dataset.dcLot,a=lotPacker.get(lot),match=!selectedPacker||String(a?.worker_user_id||'')===selectedPacker;
      if(clearOthers&&!match){sec.querySelectorAll('[data-dc-send]').forEach(inp=>{if(inp.value!=='0'){inp.value='0';inp.dispatchEvent(new Event('input',{bubbles:true}));}});}
      sec.style.display=match?'':'none';
    });
  }
  function scheduleSync(delay=80){clearTimeout(syncTimer);syncTimer=setTimeout(()=>{ensureControls();refreshPackerOptions();applyQueueFilter(false);},delay);}
  function selectedEntries(){return qsa('#dispatchBoxRows tr[data-box-id]').filter(r=>r.querySelector('[data-dispatch-check]')?.checked).map(r=>({box_id:r.dataset.boxId,qty:Number(r.querySelector('[data-dispatch-qty]')?.value||0),lot:String(r.children[2]?.textContent||'').trim()}));}
  async function submitQueue(e){
    e.preventDefault();e.stopImmediatePropagation();
    try{
      const packer=document.getElementById('dispatchPackerQueue')?.value||'',lineman=document.getElementById('dispatchLineMan')?.value||'';
      if(!packer)throw Error('Packer Queue selection mandatory');if(!lineman)throw Error('Delivery Lineman selection mandatory');
      const entries=selectedEntries();if(!entries.length)throw Error('Kam se kam ek Box select karein.');
      for(const x of entries){const a=lotPacker.get(x.lot);if(String(a?.worker_user_id||'')!==String(packer))throw Error(`Lot ${x.lot} selected Packer Queue ka nahi hai.`);if(!Number.isInteger(x.qty)||x.qty<=0)throw Error('Selected boxes ki Send Qty mandatory hai.');}
      const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');
      const r=await c.rpc('rr_fg_create_despatch_queue_v9375',{p_boxes:entries.map(({box_id,qty})=>({box_id,qty})),p_packer_worker_id:packer,p_line_man_worker_id:lineman,p_destination:document.getElementById('dispatchDestination').value,p_remarks:document.getElementById('dispatchRemarks').value||null,p_data_mode:mode()});
      if(r.error)throw r.error;const d=r.data||{};
      msg(`Challan ${d.challan_no||''} locked · ${d.total_boxes||entries.length} boxes / ${d.total_qty||0} PCS · Packer ${d.packer_name||''} → Lineman ${d.line_man_name||''}`,'ok');
      setTimeout(()=>document.getElementById('loadReadyBoxes')?.click(),80);
    }catch(err){msg(err.message||String(err),'error');}
  }
  function bindSubmit(){const btn=document.getElementById('submitDispatch');if(btn&&!submitBound){btn.addEventListener('click',submitQueue,true);submitBound=true;}}
  async function hydrate(){
    if(!ensureControls())return false;
    bindSubmit();
    try{await loadAssignments();refreshPackerOptions();}catch(e){console.warn('Packer queue init',e);}
    try{await loadLineMen();}catch(e){console.warn('Lineman init',e);}
    applyQueueFilter(false);return true;
  }
  function init(){
    let tries=0;
    const boot=()=>{tries++;hydrate().then(ok=>{if(!ok&&tries<20)setTimeout(boot,150);});};boot();
    const raw=document.getElementById('dispatchBoxRows');if(raw)new MutationObserver(()=>scheduleSync(100)).observe(raw,{childList:true});
    document.getElementById('loadReadyBoxes')?.addEventListener('click',()=>setTimeout(()=>hydrate(),450));
    window.addEventListener('redzed:supabase-ready',()=>setTimeout(()=>hydrate(),0),{passive:true});
    setTimeout(()=>hydrate(),600);setTimeout(()=>hydrate(),1400);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();