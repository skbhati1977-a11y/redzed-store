(()=>{
  'use strict';
  const isDespatch=()=>new URLSearchParams(location.search).get('view')==='despatch';
  if(!isDespatch())return;
  const $=id=>document.getElementById(id);
  let packerByLot=new Map(), applying=false;

  function removeFilters(){
    const view=document.querySelector('[data-view="despatch"]');
    if(!view)return;
    view.querySelectorAll('.rr-gsheet-toolbar,.rr-gsheet-filter-btn,[data-filter-row],.filter-row,.table-filter,.fg-filter').forEach(n=>n.remove());
    view.querySelectorAll('table').forEach(t=>{t.dataset.rrNoGsheet='1';t.dataset.rrGoogleSheetReady='1';});
  }

  function ensureSearch(){
    const view=document.querySelector('[data-view="despatch"]');
    const host=$('dispatchLotSummary');
    if(!view||!host||$('dispatchSearch'))return;
    const wrap=document.createElement('div');
    wrap.className='fg-field fg-despatch-search';
    wrap.innerHTML='<label for="dispatchSearch">Search</label><input id="dispatchSearch" type="search" autocomplete="off" inputmode="search" placeholder="Lot No. / Box Type / Packer name…">';
    host.parentNode.insertBefore(wrap,host);
    $('dispatchSearch').addEventListener('input',applySearch,{passive:true});
  }

  async function loadPackers(){
    try{
      if(!window.supabaseClient?.rpc)return;
      const {data,error}=await window.supabaseClient.rpc('rr_fg_ready_packing_cards_v788',{p_data_mode:'TEST'});
      if(error)throw error;
      packerByLot=new Map((data||[]).map(x=>[String(x.lot_no||'').trim().toLowerCase(),String(x.worker_name||'').trim()]));
      decorateRows();
    }catch(e){console.warn('Despatch packer search:',e);}
  }

  function ensurePackerHeader(table){
    const head=table?.querySelector('thead tr');
    if(!head||head.querySelector('[data-despatch-packer-head]'))return;
    const th=document.createElement('th');
    th.dataset.despatchPackerHead='1';th.textContent='Packer';
    const typeTh=[...head.children].find(x=>x.textContent.trim().toLowerCase()==='type');
    if(typeTh?.nextSibling)head.insertBefore(th,typeTh.nextSibling);else head.appendChild(th);
  }

  function decorateRows(){
    if(applying)return;applying=true;
    try{
      const body=$('dispatchBoxRows');if(!body)return;
      const table=body.closest('table');ensurePackerHeader(table);
      [...body.querySelectorAll('tr[data-box-id]')].forEach(row=>{
        const cells=[...row.children];
        const lot=(cells[2]?.textContent||'').trim();
        const packer=packerByLot.get(lot.toLowerCase())||'—';
        let td=row.querySelector('[data-despatch-packer]');
        if(!td){td=document.createElement('td');td.dataset.despatchPacker='1';td.dataset.label='Packer';const typeCell=cells[3];if(typeCell?.nextSibling)row.insertBefore(td,typeCell.nextSibling);else row.appendChild(td);}
        td.textContent=packer;
        row.dataset.despatchSearch=[cells[1]?.textContent,lot,cells[3]?.textContent,packer].join(' ').toLowerCase();
        [...row.children].forEach((c,i)=>{if(!c.dataset.label){const labels=['Select','Box ID','Lot','Type','Packer','Packing Qty','Send Qty'];c.dataset.label=labels[i]||'';}});
      });
      applySearch();
    }finally{applying=false;}
  }

  function applySearch(){
    const q=($('dispatchSearch')?.value||'').trim().toLowerCase();
    const body=$('dispatchBoxRows');if(!body)return;
    [...body.querySelectorAll('tr[data-box-id]')].forEach(row=>{row.hidden=!!q&&!String(row.dataset.despatchSearch||row.textContent).toLowerCase().includes(q);});
    const summary=$('dispatchLotSummary');
    if(summary){[...summary.querySelectorAll('.fg-table-wrap')].forEach(w=>{const lot=(w.querySelector('thead th')?.textContent||'').replace(/^LOT\s*/i,'').trim().toLowerCase();w.hidden=!!q&&!(lot.includes(q)||[...body.querySelectorAll('tr[data-box-id]:not([hidden])')].some(r=>(r.children[2]?.textContent||'').trim().toLowerCase()===lot));});}
  }

  function init(){
    ensureSearch();removeFilters();decorateRows();loadPackers();
    const view=document.querySelector('[data-view="despatch"]');
    if(!view)return;
    new MutationObserver(()=>{removeFilters();ensureSearch();decorateRows();}).observe(view,{childList:true,subtree:true});
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
