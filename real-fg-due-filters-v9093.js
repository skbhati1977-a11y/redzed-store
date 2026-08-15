(() => {
  'use strict';

  const sb = window.supabaseClient || window.redzedSupabase || window.sb;
  if (!sb) return;

  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const upper = v => String(v || '').trim().toUpperCase();
  const mode = 'TEST';
  let activeFilter = 'ALL';
  let payload = null;
  let packCards = [];
  let readyBoxes = [];
  let activeView = new URL(location.href).searchParams.get('view') || 'packing';

  function ensureStyle(){
    if(document.getElementById('rr-v9093-style')) return;
    const s=document.createElement('style'); s.id='rr-v9093-style'; s.textContent=`
      .rr-v9093-bar{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0;padding:9px;border:1px solid #303641;border-radius:12px;background:#10151d}
      .rr-v9093-filter{border:1px solid #485364;background:#1b222d;color:#fff;border-radius:999px;padding:8px 11px;font-weight:900;cursor:pointer}
      .rr-v9093-filter.active{background:#6b1f2b;border-color:#d64559}.rr-v9093-filter.assign{border-color:#c8992d}.rr-v9093-filter.submit{border-color:#318b65}.rr-v9093-filter.alter{border-color:#9b7a16}
      .rr-v9093-alterbox{display:grid;gap:5px;margin:8px 0;padding:8px;border:1px solid #9b7a16;border-radius:10px;background:#332a08;font-size:11px}
      .rr-v9093-alterline{display:flex;gap:7px;flex-wrap:wrap}.rr-v9093-owner{font-weight:950;color:#fff}.rr-v9093-hidden{display:none!important}
    `; document.head.appendChild(s);
  }

  function currentDept(){ return activeView === 'despatch' ? 'DESPATCH' : 'PACKING'; }
  function totals(){
    const alter = Number(payload?.totals?.active_alter_count || 0);
    if(currentDept()==='PACKING'){
      return {
        assign: packCards.filter(x => !x.assignment_id).length,
        submit: packCards.filter(x => x.assignment_id && ['ASSIGNED','ACCEPTED'].includes(upper(x.assignment_status))).length,
        alter
      };
    }
    const lots = new Set(readyBoxes.map(x=>upper(x.lot_no)).filter(Boolean));
    return {assign: lots.size, submit: 0, alter};
  }

  function alterMap(){ return new Map((payload?.lots||[]).map(x=>[upper(x.lot_no),x.alter_journeys||[]])); }

  function renderBar(){
    ensureStyle();
    const view=document.querySelector(`.fg-view[data-view="${activeView}"]`);
    if(!view) return;
    let bar=view.querySelector('.rr-v9093-bar');
    if(!bar){ bar=document.createElement('div'); bar.className='rr-v9093-bar'; view.prepend(bar); }
    const t=totals();
    bar.innerHTML=`
      <button class="rr-v9093-filter ${activeFilter==='ALL'?'active':''}" data-f="ALL">ALL</button>
      <button class="rr-v9093-filter assign ${activeFilter==='ASSIGN'?'active':''}" data-f="ASSIGN">ASSIGN DUE · ${t.assign}</button>
      <button class="rr-v9093-filter submit ${activeFilter==='SUBMIT'?'active':''}" data-f="SUBMIT">SUBMIT DUE · ${t.submit}</button>
      <button class="rr-v9093-filter alter ${activeFilter==='ALTER'?'active':''}" data-f="ALTER">ALTER ACTIVE · ${t.alter}</button>
      <span style="margin-left:auto;align-self:center;font-size:11px;color:#98a2b3;font-weight:800">${currentDept()}</span>`;
    bar.querySelectorAll('[data-f]').forEach(b=>b.onclick=()=>{activeFilter=b.dataset.f;renderBar();applyFilter();});
  }

  function alterHtml(journeys){
    if(!journeys?.length) return '';
    return `<div class="rr-v9093-alterbox">${journeys.map(j=>`<div class="rr-v9093-alterline"><b>${esc(j.journey_code||'ALTER')}</b><span>${esc(j.colour_code||'')} ${esc(j.size_code||'')} · ${Number(j.qty||0)} PCS</span><span class="rr-v9093-owner">OWNER: ${esc(j.owner_name||'PENDING')} [${esc(String(j.owner_role||'').replaceAll('_',' '))}] · ${esc(j.owner_department_code||'')}</span><span>${esc(j.stage||'')}</span></div>`).join('')}</div>`;
  }

  function decoratePacking(){
    const map=alterMap();
    document.querySelectorAll('#packLotCards > *').forEach(card=>{
      card.querySelector?.('.rr-v9093-alterbox')?.remove();
      const text=upper(card.textContent);
      const row=packCards.find(x=>text.includes(upper(x.lot_no)));
      if(!row) return;
      const journeys=map.get(upper(row.lot_no))||[];
      if(journeys.length) card.insertAdjacentHTML('beforeend',alterHtml(journeys));
      let show=true;
      if(activeFilter==='ASSIGN') show=!row.assignment_id;
      if(activeFilter==='SUBMIT') show=!!row.assignment_id && ['ASSIGNED','ACCEPTED'].includes(upper(row.assignment_status));
      if(activeFilter==='ALTER') show=journeys.length>0;
      card.classList.toggle('rr-v9093-hidden',!show);
    });
  }

  function decorateDespatch(){
    const map=alterMap();
    const body=document.getElementById('dispatchBoxRows');
    if(!body) return;
    [...body.children].forEach(tr=>{
      const text=upper(tr.textContent);
      const box=readyBoxes.find(x=>text.includes(upper(x.lot_no)) || text.includes(upper(x.box_code)));
      const journeys=box ? (map.get(upper(box.lot_no))||[]) : [];
      let show=true;
      if(activeFilter==='ASSIGN') show=!!box;
      if(activeFilter==='SUBMIT') show=false;
      if(activeFilter==='ALTER') show=journeys.length>0;
      tr.classList.toggle('rr-v9093-hidden',!show);
    });
    let holder=document.querySelector('.fg-view[data-view="despatch"] .rr-v9093-alter-holder');
    if(!holder){ holder=document.createElement('div'); holder.className='rr-v9093-alter-holder'; document.querySelector('.fg-view[data-view="despatch"] .fg-panel')?.prepend(holder); }
    const active=(payload?.lots||[]).filter(x=>(x.alter_journeys||[]).length);
    holder.innerHTML=active.map(x=>`<div><b>${esc(x.lot_no)}</b>${alterHtml(x.alter_journeys)}</div>`).join('');
  }

  function applyFilter(){ currentDept()==='PACKING' ? decoratePacking() : decorateDespatch(); }

  async function loadData(){
    try{
      const dept=currentDept();
      const [dueRes, packRes, boxRes] = await Promise.all([
        sb.rpc('rr_upm_lot_card_due_alter_header_v9092',{p_department_code:dept}),
        dept==='PACKING' ? sb.rpc('rr_fg_ready_packing_cards_v788',{p_data_mode:mode}) : Promise.resolve({data:[]}),
        dept==='DESPATCH' ? sb.from('rr_fg_ready_box_v787').select('box_id,box_code,lot_no,box_type,qty,data_mode').eq('data_mode',mode) : Promise.resolve({data:[]})
      ]);
      if(dueRes.error) throw dueRes.error;
      payload=dueRes.data||{};
      packCards=Array.isArray(packRes.data)?packRes.data:[];
      readyBoxes=Array.isArray(boxRes.data)?boxRes.data:[];
      renderBar(); applyFilter();
    }catch(e){ console.warn('V9093 finished goods due filters unavailable',e); }
  }

  function setView(v){
    if(!['packing','despatch'].includes(v)) return;
    activeView=v; activeFilter='ALL'; loadData();
  }

  document.querySelectorAll('#tabs [data-tab]').forEach(b=>b.addEventListener('click',()=>setTimeout(()=>setView(b.dataset.tab),80)));
  document.getElementById('refreshPackLots')?.addEventListener('click',()=>setTimeout(loadData,250));
  document.getElementById('loadReadyBoxes')?.addEventListener('click',()=>setTimeout(loadData,250));
  new MutationObserver(()=>applyFilter()).observe(document.body,{childList:true,subtree:true});
  setTimeout(loadData,500);
  setInterval(loadData,15000);
})();
