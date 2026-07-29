(() => {
  'use strict';
  const VERSION='8.1.0';
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const state={client:null,lotId:'',lotNo:'',artItem:'',cutQty:0,department:'',context:[],workers:[],selected:new Set(),commonWorker:''};

  const modal=()=>$('rrAssignModalV8');

  async function rpc(name,args){
    const {data,error}=await state.client.rpc(name,args);
    if(error) throw error;
    return data;
  }

  function openModal(){
    modal().classList.add('is-open');
    modal().setAttribute('aria-hidden','false');
    document.body.style.overflow='hidden';
  }
  function closeModal(){
    modal().classList.remove('is-open');
    modal().setAttribute('aria-hidden','true');
    document.body.style.overflow='';
  }

  function getCardInfo(entryBtn){
    const card=entryBtn.closest('.card');
    const lotNo=card?.querySelector('.lot-number')?.textContent?.trim()
      || card?.querySelector('h3')?.textContent?.trim()
      || entryBtn.dataset.entry;
    const caption=card?.querySelector('.lot-caption')?.textContent?.trim()||'';
    const qtyText=[...card?.querySelectorAll('*')||[]].map(x=>x.textContent||'').find(t=>/Cut Qty\s*\d+/i.test(t))||'';
    const qtyMatch=qtyText.match(/Cut Qty\s*([0-9.]+)/i);
    return {card,lotNo,caption,cutQty:qtyMatch?Number(qtyMatch[1]):0};
  }

  function departmentOptions(){
    const source=$('eDept');
    if(!source) return '<option value="">Department unavailable</option>';
    return [...source.options].map(o=>`<option value="${esc(o.value)}">${esc(o.textContent)}</option>`).join('');
  }

  async function openAssign(entryBtn){
    state.client=window.supabaseClient||window.sb;
    if(!state.client){alert('Supabase client unavailable.');return}
    const info=getCardInfo(entryBtn);
    state.lotId=entryBtn.dataset.entry;
    state.lotNo=info.lotNo;
    state.artItem=info.caption;
    state.cutQty=info.cutQty;
    state.selected.clear(); state.commonWorker='';

    $('rrAssignLotNoV8').textContent=state.lotNo||'—';
    $('rrAssignMetaLotV8').textContent=state.lotNo||'—';
    $('rrAssignMetaArtV8').textContent=state.artItem||'—';
    $('rrAssignMetaQtyV8').textContent=`${state.cutQty||0} PCS`;
    $('rrAssignDeptV8').innerHTML=departmentOptions();
    state.department=$('rrAssignDeptV8').value;
    $('rrAssignRowsV8').innerHTML='';
    $('rrAssignRemarksV8').value='';
    openModal();
    await loadWorkers();
    await loadContext();
  }

  async function loadWorkers(){
    $('rrAssignStatusV8').textContent='Loading workers…';
    const rows=await rpc('rr_upm_worker_list_v8',{p_department_code:state.department||null});
    state.workers=Array.isArray(rows)?rows:[];
    $('rrAssignCommonWorkerV8').innerHTML='<option value="">Select worker</option>'+state.workers.map(w=>
      `<option value="${esc(w.worker_id)}">${esc(w.worker_name)} — ${esc(w.worker_code)}</option>`
    ).join('');
    state.commonWorker='';
  }

  async function loadContext(){
    $('rrAssignStatusV8').textContent='Loading Cutting colour-size mapping…';
    const rows=await rpc('rr_upm_get_work_assign_context_v8',{
      p_canonical_lot_id:state.lotId,
      p_department_code:state.department
    });
    state.context=Array.isArray(rows)?rows:[];
    state.selected.clear();
    renderPicks();
    $('rrAssignRowsV8').innerHTML='';
    $('rrAssignStatusV8').textContent=state.context.length
      ? 'Single colour tap, multiple colours tap, or ALL; then OK.'
      : 'Cutting colour-size mapping unavailable for this Lot.';
  }

  function renderPicks(){
    $('rrAssignColourPicksV8').innerHTML=state.context.map(r=>{
      const sel=state.selected.has(r.colour_code);
      const locked=Boolean(r.is_locked);
      const cls=`rr-colour-chip${sel?' is-selected':''}${locked?' is-locked':''}`;
      const suffix=locked
        ? ` — Assigned to ${esc(r.assigned_worker_name||'worker')} (${esc(r.assigned_worker_code||'')})`
        : ` — ${Number(r.total_qty||0)} PCS`;
      return `<button type="button" class="${cls}" data-rr-colour="${esc(r.colour_code)}" ${locked?'disabled':''}>${esc(r.colour_name||r.colour_code)}${suffix}</button>`;
    }).join('');
    document.querySelectorAll('[data-rr-colour]').forEach(btn=>{
      btn.onclick=()=>{
        const c=btn.dataset.rrColour;
        state.selected.has(c)?state.selected.delete(c):state.selected.add(c);
        renderPicks();
      };
    });
  }

  function workerOptions(selected=''){
    return '<option value="">Select worker</option>'+state.workers.map(w=>
      `<option value="${esc(w.worker_id)}" ${String(w.worker_id)===String(selected)?'selected':''}>${esc(w.worker_name)} — ${esc(w.worker_code)}</option>`
    ).join('');
  }

  function breakup(row){
    const arr=Array.isArray(row.size_breakup)?row.size_breakup:[];
    return arr.map(s=>`<span class="rr-size-pill"><b>${esc(s.size_code)}</b> ${Number(s.qty||0)} PCS</span>`).join('');
  }

  function renderRows(){
    const rows=state.context.filter(r=>state.selected.has(r.colour_code)&&!r.is_locked);
    if(!rows.length){$('rrAssignRowsV8').innerHTML='';$('rrAssignStatusV8').textContent='Select at least one unassigned colour.';return}
    $('rrAssignRowsV8').innerHTML=rows.map(r=>`
      <section class="rr-assign-row" data-rr-assign-row="${esc(r.colour_code)}">
        <div class="rr-assign-row-head"><h3 style="margin:0">Colour ${esc(r.colour_name||r.colour_code)}</h3><b>Total ${Number(r.total_qty||0)} PCS</b></div>
        <div class="rr-size-line">${breakup(r)}</div>
        <div class="rr-worker-line">
          <label class="field"><span>Worker Name + Worker ID</span><select data-rr-row-worker required>${workerOptions(state.commonWorker)}</select></label>
          <label class="field"><span>Assigned Qty — Auto</span><input data-rr-row-qty type="number" value="${Number(r.total_qty||0)}" readonly></label>
        </div>
      </section>`).join('');
    $('rrAssignStatusV8').textContent=`${rows.length} colour selected. Qty auto-filled from Cutting.`;
  }

  async function save(ev){
    ev.preventDefault();
    const nodes=[...document.querySelectorAll('[data-rr-assign-row]')];
    if(!nodes.length){alert('Select colour(s), then press OK.');return}
    try{
      const rows=nodes.map(n=>{
        const worker=n.querySelector('[data-rr-row-worker]').value;
        if(!worker) throw new Error(`Worker required for colour ${n.dataset.rrAssignRow}.`);
        return {colour_code:n.dataset.rrAssignRow,worker_id:worker,assigned_qty:Number(n.querySelector('[data-rr-row-qty]').value||0)};
      });
      $('rrAssignSaveV8').disabled=true;$('rrAssignSaveV8').textContent='ASSIGNING…';
      await rpc('rr_upm_assign_colours_v8',{
        p_canonical_lot_id:state.lotId,
        p_department_code:state.department,
        p_rows:rows,
        p_remarks:$('rrAssignRemarksV8').value||null
      });
      alert('Work assigned successfully.');
      closeModal();
      $('refresh')?.click();
    }catch(e){alert(e.message||String(e))}
    finally{$('rrAssignSaveV8').disabled=false;$('rrAssignSaveV8').textContent='ASSIGN WORK'}
  }

  function enhanceCards(){
    document.querySelectorAll('[data-entry]').forEach(entry=>{
      const lotId=entry.dataset.entry;
      const actions=entry.closest('.actions')||entry.parentElement;
      if(!lotId||actions.querySelector(`[data-rr-assign="${CSS.escape(lotId)}"]`)) return;
      const b=document.createElement('button');
      b.type='button';b.className='rr-assign-open';b.dataset.rrAssign=lotId;b.textContent='Assign Work';
      b.onclick=()=>openAssign(entry);
      actions.insertBefore(b,entry);
    });
  }

  async function showAssignedWorker(){
    const lotId=$('eLot')?.value,dept=$('eDept')?.value,colour=$('eColour')?.value,box=$('rrEntryAssignmentV8');
    if(!lotId||!dept||!colour||!box||!state.client) return;
    try{
      const rows=await rpc('rr_upm_get_work_assign_context_v8',{p_canonical_lot_id:lotId,p_department_code:dept});
      const row=(rows||[]).find(x=>String(x.colour_code).toUpperCase()===String(colour).toUpperCase());
      box.innerHTML=row?.is_locked
        ? `<b>Assigned Worker:</b> ${esc(row.assigned_worker_name)} — ${esc(row.assigned_worker_code)} · <b>Assigned Qty:</b> ${Number(row.total_qty||0)} PCS`
        : `<b>Assignment missing:</b> Assign this Department + Colour before Production Submit.`;
    }catch(e){box.textContent=e.message||String(e)}
  }

  function init(){
    state.client=window.supabaseClient||window.sb;
    closeModal(); // force-clean on every page load
    $('rrAssignCloseV8').onclick=closeModal;
    $('rrAssignCancelV8').onclick=closeModal;
    $('rrAssignDeptV8').onchange=async()=>{state.department=$('rrAssignDeptV8').value;await loadWorkers();await loadContext()};
    $('rrAssignCommonWorkerV8').onchange=()=>{
      state.commonWorker=$('rrAssignCommonWorkerV8').value;
      document.querySelectorAll('[data-rr-row-worker]').forEach(el=>el.value=state.commonWorker);
    };
    $('rrAssignAllV8').onclick=()=>{state.selected=new Set(state.context.filter(r=>!r.is_locked).map(r=>r.colour_code));renderPicks()};
    $('rrAssignClearV8').onclick=()=>{state.selected.clear();renderPicks();$('rrAssignRowsV8').innerHTML=''};
    $('rrAssignOkV8').onclick=renderRows;
    $('rrAssignFormV8').onsubmit=save;
    modal().addEventListener('click',e=>{if(e.target===modal())closeModal()});
    document.addEventListener('keydown',e=>{if(e.key==='Escape'&&modal().classList.contains('is-open'))closeModal()});
    $('eDept')?.addEventListener('change',showAssignedWorker);
    $('eColour')?.addEventListener('change',showAssignedWorker);

    enhanceCards();
    new MutationObserver(enhanceCards).observe($('board')||document.body,{childList:true,subtree:true});
    console.info(`REDZED UPM Work Assignment ${VERSION} loaded`);
  }

  document.readyState==='loading'
    ? document.addEventListener('DOMContentLoaded',init,{once:true})
    : init();
})();