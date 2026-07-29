/* REDZED UPM SMART PACKING V1 — additive frontend */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const client = () => window.supabaseClient || window.sb || window.supabase?.createClient?.(window.SUPABASE_URL, window.SUPABASE_ANON_KEY);
  let currentPlanId = null;
  let currentRows = [];

  function msg(text, type='') { const el=$('packMessage'); if(el){el.textContent=text; el.dataset.type=type;} }
  function open(){ $('smartPackModal')?.classList.remove('hidden'); }
  function close(){ $('smartPackModal')?.classList.add('hidden'); }
  function compactComposition(value){ return value || '—'; }

  function render(rows){
    currentRows=rows||[];
    const body=$('packPlanBody');
    if(!body) return;
    body.innerHTML=currentRows.map(r=>{
      const c=r.size_composition||{};
      const sizes=Object.keys(c);
      return `<tr><td>${r.box_from===r.box_to?esc(r.box_from):esc(`${r.box_from}–${r.box_to}`)}</td><td><strong>${esc(r.pcs_per_box)} PCS (${esc(r.pack_mark)})</strong></td><td>${esc(r.box_count)}</td>${sizes.map(s=>`<td><small>${esc(s)}</small><br>${esc(compactComposition(c[s]))}</td>`).join('')}<td><strong>${esc(r.pcs_per_box)}</strong></td></tr>`;
    }).join('');
    const head=$('packPlanHead');
    const sizes=currentRows.length?Object.keys(currentRows[0].size_composition||{}):[];
    if(head) head.innerHTML=`<tr><th>Box No.</th><th>Pack Mark</th><th>No. of Boxes</th>${sizes.map(s=>`<th>${esc(s)} Composition</th>`).join('')}<th>PCS/Box</th></tr>`;
    const total=currentRows.reduce((n,r)=>n+Number(r.box_total_qty||0),0);
    const boxes=currentRows.reduce((n,r)=>n+Number(r.box_count||0),0);
    $('packSummary').textContent=`${boxes} Boxes · ${total} PCS`;
    $('submitPackPlan').disabled=!currentPlanId || !rows.length;
  }

  async function fetchMatrix(lotNo){
    const sb=client(); if(!sb) throw new Error('Supabase client unavailable.');
    const r=await sb.rpc('rr_get_packable_matrix_v1',{p_lot_no:lotNo});
    if(r.error) throw r.error;
    return Array.isArray(r.data)?r.data:[];
  }

  async function generate(){
    try{
      const lotNo=$('packLotNo').value.trim();
      if(!lotNo) throw new Error('Lot No required.');
      msg('PRESS quantity loading…');
      let matrix=await fetchMatrix(lotNo);
      const manual=$('packMatrixJson').value.trim();
      if(manual) matrix=JSON.parse(manual);
      if(!matrix.length) throw new Error('PRESS colour-size matrix not found. Paste matrix JSON for test.');
      const sb=client();
      const g=await sb.rpc('rr_generate_smart_pack_plan_v1',{p_lot_no:lotNo,p_matrix:matrix,p_carton_capacity:18});
      if(g.error) throw g.error;
      currentPlanId=g.data;
      const q=await sb.from('rr_pack_plan_worker_v').select('*').eq('plan_id',currentPlanId).order('display_order',{ascending:true});
      if(q.error) throw q.error;
      render(q.data||[]); msg('Packing table generated. Worker must submit this exact table.','ok');
    }catch(e){ console.error(e); msg(e.message||String(e),'error'); render([]); currentPlanId=null; }
  }

  async function submit(){
    try{
      if(!currentPlanId) throw new Error('Generate plan first.');
      const sb=client();
      const r=await sb.rpc('rr_submit_smart_pack_plan_v1',{p_plan_id:currentPlanId});
      if(r.error) throw r.error;
      msg(`Submitted: ${r.data.total_boxes} boxes · ${r.data.total_qty} PCS`,'ok');
      $('submitPackPlan').disabled=true;
    }catch(e){msg(e.message||String(e),'error');}
  }

  document.addEventListener('DOMContentLoaded',()=>{
    $('openSmartPack')?.addEventListener('click',open);
    $('generatePackPlan')?.addEventListener('click',generate);
    $('submitPackPlan')?.addEventListener('click',submit);
    document.querySelectorAll('[data-close="smartPackModal"]').forEach(b=>b.addEventListener('click',close));
  });
})();
