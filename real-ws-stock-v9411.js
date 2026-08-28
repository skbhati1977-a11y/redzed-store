(() => {
  'use strict';
  if (window.__RR_WS_STOCK_V9411__) return;
  window.__RR_WS_STOCK_V9411__ = true;
  if (!/\/real-finished-goods-v787\.html$/i.test(location.pathname)) return;

  const qs = new URLSearchParams(location.search);
  const mode = qs.get('mode') === 'REAL' ? 'REAL' : 'TEST';
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const fmtDate = v => v ? new Intl.DateTimeFormat('en-IN',{day:'2-digit',month:'short',year:'numeric'}).format(new Date(v)) : '—';
  const state = { rows:[], search:'', multi:'', sort:'LOT_ASC', timer:0, tap:null };

  function style(){
    if(document.getElementById('rrWs9411Style')) return;
    const s=document.createElement('style');s.id='rrWs9411Style';s.textContent=`
      [data-view="stock"] .rr-ws-head{display:flex;gap:8px;align-items:center;margin:10px 0 4px;position:sticky;top:68px;z-index:8;background:#17191f;padding:5px 0}
      [data-view="stock"] .rr-ws-search{flex:1;min-width:0;height:42px;border:1px solid #30343d;border-radius:10px;background:#0f1115;color:#fff;padding:0 12px;font:inherit}
      [data-view="stock"] .rr-ws-icon{width:42px;height:42px;padding:0;border:1px solid #30343d;border-radius:10px;background:#20232b;color:#fff;font-size:19px;font-weight:900}
      [data-view="stock"] .rr-ws-table-wrap{overflow:auto;-webkit-overflow-scrolling:touch;border:1px solid #30343d;border-radius:12px;margin-top:10px}
      [data-view="stock"] #stockRowsV9411Table{min-width:790px;width:100%;border-collapse:collapse}
      [data-view="stock"] #stockRowsV9411Table th,[data-view="stock"] #stockRowsV9411Table td{padding:8px 9px;vertical-align:middle;white-space:nowrap}
      [data-view="stock"] #stockRowsV9411Table th{position:sticky;top:0;z-index:3;background:#20232b}
      [data-view="stock"] .rr-ws-thumb{width:42px;height:52px;object-fit:cover;border-radius:7px;background:#0f1115;border:1px solid #30343d;display:block}
      [data-view="stock"] .rr-ws-name{max-width:190px;overflow:hidden;text-overflow:ellipsis}
      [data-view="stock"] .rr-ws-drill{font-weight:900;text-decoration:underline;text-decoration-style:dotted;text-underline-offset:4px;cursor:pointer;touch-action:manipulation}
      [data-view="stock"] .rr-ws-badge{display:inline-flex;min-width:42px;justify-content:center;padding:4px 7px;border-radius:999px;font-size:11px;font-weight:950;border:1px solid #30343d}
      [data-view="stock"] .rr-ws-badge.IN{color:#53d98c;background:#123c29}.rr-ws-badge.LOW{color:#ffc763;background:#493712}.rr-ws-badge.OUT{color:#ff7d88;background:#471820}
      .rr-ws-modal{position:fixed;inset:0;z-index:9999;background:rgba(0,0,0,.72);display:flex;align-items:flex-end;justify-content:center;padding:12px}
      .rr-ws-sheet{width:min(760px,100%);max-height:82vh;overflow:auto;background:#17191f;border:1px solid #30343d;border-radius:16px;padding:14px;box-shadow:0 20px 70px rgba(0,0,0,.5)}
      .rr-ws-sheet-head{display:flex;align-items:center;justify-content:space-between;gap:10px;position:sticky;top:-14px;background:#17191f;padding:10px 0;z-index:2}
      .rr-ws-sheet h3{margin:0}.rr-ws-close{width:38px;height:38px;border-radius:10px;border:1px solid #30343d;background:#20232b;color:#fff;font-size:22px}
      .rr-ws-sheet table{min-width:580px}.rr-ws-sheet textarea{width:100%;min-height:120px;background:#0f1115;color:#fff;border:1px solid #30343d;border-radius:10px;padding:10px;font:inherit}
      .rr-ws-sort-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}.rr-ws-sort-grid button,.rr-ws-apply{border:1px solid #30343d;border-radius:10px;background:#20232b;color:#fff;padding:11px;font-weight:800}.rr-ws-apply{width:100%;margin-top:10px;background:#e32636;border-color:#e32636}
      .rr-ws-note{color:#a9adb7;font-size:12px;margin:5px 0 0}
      @media(max-width:650px){[data-view="stock"] .fg-panel{padding:10px}[data-view="stock"] .rr-ws-head{top:60px}[data-view="stock"] #stockRowsV9411Table{min-width:700px;font-size:12px}[data-view="stock"] #stockRowsV9411Table th,[data-view="stock"] #stockRowsV9411Table td{padding:7px 6px}[data-view="stock"] .rr-ws-thumb{width:34px;height:44px}[data-view="stock"] .rr-ws-name{max-width:135px}.rr-ws-modal{padding:6px}.rr-ws-sheet{max-height:88vh}}
    `;document.head.appendChild(s);
  }

  function modal(title,body){
    document.getElementById('rrWsModal9411')?.remove();
    const m=document.createElement('div');m.className='rr-ws-modal';m.id='rrWsModal9411';m.innerHTML=`<div class="rr-ws-sheet"><div class="rr-ws-sheet-head"><h3>${esc(title)}</h3><button class="rr-ws-close" aria-label="Close">×</button></div>${body}</div>`;
    m.querySelector('.rr-ws-close').onclick=()=>m.remove();
    m.addEventListener('click',e=>{if(e.target===m)m.remove()});
    document.body.appendChild(m);return m;
  }

  async function rpc(name,args){const r=await supabaseClient.rpc(name,args);if(r.error)throw r.error;return r.data||[];}
  function panel(){return document.querySelector('[data-view="stock"] .fg-panel');}

  function mount(){
    const p=panel(); if(!p || p.dataset.ws9411==='1') return;
    p.dataset.ws9411='1';
    p.innerHTML=`<div class="fg-title-row"><div><h2>WS · Webstore / Store Stock</h2><p class="fg-muted">One row per Lot · double tap Received / Sales for summary</p></div><button class="fg-btn" id="wsRefresh9411">↻</button></div>
      <div class="rr-ws-head"><input class="rr-ws-search" id="wsSearch9411" placeholder="Search lot / item / CB / challan / CPI / party / location…" autocomplete="off"><button class="rr-ws-icon" id="wsSort9411" title="Sort" aria-label="Sort">↕</button><button class="rr-ws-icon" id="wsMulti9411" title="Specific lots" aria-label="Specific lots">☷</button></div>
      <div class="rr-ws-table-wrap"><table id="stockRowsV9411Table" data-rr-no-gsheet="1"><thead><tr><th>Pic</th><th>Lot No.</th><th>Short Item</th><th>CB No.</th><th>TTL Rec PCS</th><th>TTL Sales PCS</th><th>Available</th><th>Stock</th></tr></thead><tbody id="stockRowsV9411"></tbody></table></div>`;
    p.querySelector('#wsRefresh9411').onclick=load;
    p.querySelector('#wsSearch9411').oninput=e=>{state.search=e.target.value;clearTimeout(state.timer);state.timer=setTimeout(load,260)};
    p.querySelector('#wsSort9411').onclick=openSort;
    p.querySelector('#wsMulti9411').onclick=openMulti;
    load();
  }

  async function load(){
    try{
      const body=document.getElementById('stockRowsV9411'); if(!body)return;
      body.innerHTML='<tr><td colspan="8" class="fg-muted">Loading…</td></tr>';
      state.rows=await rpc('rr_ws_stock_search_v9411',{p_search:state.search,p_multi_lots:state.multi,p_sort:state.sort,p_data_mode:mode});
      render();
    }catch(e){const b=document.getElementById('stockRowsV9411');if(b)b.innerHTML=`<tr><td colspan="8" style="color:#ff7d88">${esc(e.message)}</td></tr>`;}
  }

  function render(){
    const b=document.getElementById('stockRowsV9411');if(!b)return;
    b.innerHTML=state.rows.length?state.rows.map(x=>`<tr data-lot="${esc(x.lot_no)}"><td>${x.thumbnail?`<img class="rr-ws-thumb" src="${esc(x.thumbnail)}" alt="">`:'<span class="rr-ws-thumb"></span>'}</td><td><b>${esc(x.lot_no)}</b></td><td class="rr-ws-name" title="${esc(x.short_item_name)}">${esc(x.short_item_name)}</td><td>${esc(x.cb_no||'—')}</td><td class="rr-ws-drill" data-drill="receive" data-lot="${esc(x.lot_no)}">${Number(x.received_qty||0)}</td><td class="rr-ws-drill" data-drill="sales" data-lot="${esc(x.lot_no)}">${Number(x.sales_qty||0)}</td><td><b>${Number(x.available_qty||0)}</b></td><td><span class="rr-ws-badge ${esc(x.stock_status)}">${esc(x.stock_status)}</span></td></tr>`).join(''):'<tr><td colspan="8" class="fg-muted">No matching lot.</td></tr>';
  }

  function openSort(){
    const opts=[['LOT_ASC','Lot ↑'],['LOT_DESC','Lot ↓'],['RECEIVED_DESC','Received'],['SALES_DESC','Sales'],['AVAILABLE_DESC','Available'],['CB_ASC','CB']];
    const m=modal('Sort',`<div class="rr-ws-sort-grid">${opts.map(([v,t])=>`<button data-sort="${v}">${t}${state.sort===v?' ✓':''}</button>`).join('')}</div>`);
    m.querySelectorAll('[data-sort]').forEach(x=>x.onclick=()=>{state.sort=x.dataset.sort;m.remove();load()});
  }

  function openMulti(){
    const m=modal('☷ Specific Lots',`<textarea id="wsMultiText9411" placeholder="1110, 1114, 1121">${esc(state.multi)}</textarea><p class="rr-ws-note">Comma / space / new line se Lot Nos paste karein. Entered order preserve hoga.</p><button class="rr-ws-apply" id="wsMultiApply9411">APPLY</button><button class="rr-ws-apply" id="wsMultiClear9411" style="background:#20232b;border-color:#30343d">CLEAR</button>`);
    m.querySelector('#wsMultiApply9411').onclick=()=>{state.multi=String(m.querySelector('#wsMultiText9411').value||'').split(/[\s,]+/).filter(Boolean).join(',');m.remove();load()};
    m.querySelector('#wsMultiClear9411').onclick=()=>{state.multi='';m.remove();load()};
  }

  async function drill(kind,lot){
    try{
      if(kind==='receive'){
        const a=await rpc('rr_ws_receive_summary_v9411',{p_lot_no:lot,p_data_mode:mode});
        const total=a.reduce((n,x)=>n+Number(x.pcs||0),0),boxes=a.reduce((n,x)=>n+Number(x.boxes||0),0);
        modal(`${lot} · Receive`, `<div class="rr-ws-table-wrap"><table><thead><tr><th>Date</th><th>Challan</th><th>Location</th><th>Type</th><th>Box</th><th>PCS</th></tr></thead><tbody>${a.map(x=>`<tr><td>${fmtDate(x.date)}</td><td>${esc(x.challan_no)}</td><td>${esc(x.location)}</td><td>${esc(x.stock_type)}</td><td>${Number(x.boxes||0)}</td><td>${Number(x.pcs||0)}</td></tr>`).join('')}<tr><th colspan="4">TOTAL</th><th>${boxes}</th><th>${total}</th></tr></tbody></table></div>`);
      }else{
        const a=await rpc('rr_ws_sales_summary_v9411',{p_lot_no:lot,p_data_mode:mode});
        const total=a.reduce((n,x)=>n+Number(x.sales_pcs||0),0);
        modal(`${lot} · Sales`, `<div class="rr-ws-table-wrap"><table><thead><tr><th>Date</th><th>CPI No.</th><th>Party / Customer</th><th>Type</th><th>Sales PCS</th></tr></thead><tbody>${a.map(x=>`<tr><td>${fmtDate(x.date)}</td><td>${esc(x.cpi_no||'—')}</td><td>${esc(x.customer||'—')}</td><td>${esc(x.stock_type)}</td><td>${Number(x.sales_pcs||0)}</td></tr>`).join('')}<tr><th colspan="4">TOTAL SALES PCS</th><th>${total}</th></tr></tbody></table></div>`);
      }
    }catch(e){modal('Error',`<p style="color:#ff7d88">${esc(e.message)}</p>`)}
  }

  document.addEventListener('click',e=>{
    const c=e.target.closest?.('.rr-ws-drill');if(!c)return;
    const now=Date.now(),key=`${c.dataset.drill}|${c.dataset.lot}`;
    if(state.tap && state.tap.key===key && now-state.tap.at<420){state.tap=null;drill(c.dataset.drill,c.dataset.lot)}else state.tap={key,at:now};
  },true);
  document.addEventListener('dblclick',e=>{const c=e.target.closest?.('.rr-ws-drill');if(c){state.tap=null;drill(c.dataset.drill,c.dataset.lot)}},true);

  style();
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(mount,120));else setTimeout(mount,120);
  new MutationObserver(()=>{if(!document.querySelector('[data-view="stock"] .fg-panel[data-ws9411="1"]'))mount()}).observe(document.documentElement,{childList:true,subtree:true});
})();