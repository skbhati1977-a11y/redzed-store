(() => {
  'use strict';
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money = n => n == null ? '—' : '₹' + Number(n).toLocaleString('en-IN',{maximumFractionDigits:2});
  // Existing CB size-family dropdown authority (rr_cb_cat_def_size_chk).
  const sizeFamilies=['L, XL, XXL','2XL, 3XL, 4XL','3XL, 4XL, 5XL','M, L, XL, XXL','M, L, XL','L, XL','L, XXL','FREE SIZE'];
  const roles = ['OWNER','SUPER_ADMIN','ADMIN','ACCOUNTS','SALES','MANAGER'];
  const roleOf = s => String(window.RR_EFFECTIVE_ROLE ? window.RR_EFFECTIVE_ROLE(s.actor?.role || s.actor?.role_code) : window.RR_VIEW_AS_ROLE || s.actor?.role || s.actor?.role_code || '').toUpperCase();
  const state = {selection:new Set(),category:'',mapping:new URLSearchParams(location.search).get('rm_mapping')||'ALL',cols:2,seq:0,busy:false,returnKeys:new Map()};
  const supplierCaches=new WeakMap();
  function supplierCache(s){let scopes=supplierCaches.get(s.db);if(!scopes){scopes=new Map();supplierCaches.set(s.db,scopes)}const key=JSON.stringify([s.userId,s.actor?.id,roleOf(s),window.RR_VIEW_AS_ACTOR_ID]);if(!scopes.has(key))scopes.set(key,{rows:null,at:0,pending:null});return scopes.get(key)}
  function suppliers(s,force=false){const cache=supplierCache(s);if(cache.pending)return cache.pending;if(!force&&cache.rows&&Date.now()-cache.at<60000)return Promise.resolve(cache.rows);const request=(async()=>{let timer;const controller=new AbortController();try{let query=s.db.from('rr_suppliers').select('id,supplier_name').eq('is_active',true).order('supplier_name');if(query.abortSignal)query=query.abortSignal(controller.signal);const result=await Promise.race([Promise.resolve(query),new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(Error('Supplier request timed out'))},8000)})]);if(result.error)throw result.error;cache.rows=(result.data||[]).filter(x=>String(x.supplier_name||'').trim());cache.at=Date.now();return cache.rows}finally{clearTimeout(timer)}})();cache.pending=request;request.then(()=>{if(cache.pending===request)cache.pending=null},()=>{if(cache.pending===request)cache.pending=null});return request}
  function prefetchSuppliers(s){if(s.db&&['OWNER','SUPER_ADMIN','ADMIN','ACCOUNTS'].includes(roleOf(s)))suppliers(s).catch(()=>{})}
  const artKey=c=>String(c.art_no||'').trim().toUpperCase()||'LOT:'+c.lot_no;
  const groupCards=cards=>{const groups=new Map();for(const c of cards){const key=artKey(c);if(!groups.has(key))groups.set(key,[]);groups.get(key).push(c)}return [...groups.values()]};
  const caption = c => ['REDZED · '+c.lot_no,c.item_name,c.category,c.art_no && 'Art '+c.art_no,c.size_text && 'Size '+c.size_text,c.cloth_name,c.colours_text && 'Colours '+c.colours_text,c.caption_note,'Available '+c.available_qty+' PCS','Sales rate '+(c.approval_ready ? money(c.approved_rate) : 'Approval pending')].filter(Boolean).join('\n');
  function directory(s) {
    prefetchSuppliers(s);
    s.departments = s.departments.filter(d => d.department_code !== 'READYMADE');
    if (roles.includes(roleOf(s))) s.departments.unshift({department_code:'READYMADE',department_name:'Readymade Garments',workers:[],staff:[],worker_count:0,staff_count:0});
  }
  async function counts(rpc) { return (await rpc('rr_rm_chat_fast_queue_test71',{p_status:'COUNTS'})).counts; }
  function style() {
    if(document.getElementById('rmChatStyle'))return;
    const el=document.createElement('style');el.id='rmChatStyle';el.textContent=`
    .rm-working{padding:0!important;border:0!important;background:transparent!important;max-width:100%;font-size:14px}.rm-working>h3{font-size:17px;margin:8px 0 14px;font-weight:700}.rm-working [data-notice]:empty{display:none}.rm-working [data-notice]{font-size:13px;padding:10px 12px;background:#18332e;border:1px solid #2a6754;border-radius:10px;color:#a9e8ce;margin:8px 0 14px}
    .rm-working .rm-chat-toolbar{display:grid;grid-template-columns:minmax(0,1fr) 88px 42px;gap:8px;align-items:center;margin:10px 0}.rm-working .rm-chat-toolbar select,.rm-working .rm-chat-toolbar button,.rm-working .rm-chat-toolbar a{box-sizing:border-box;min-height:42px;margin:0;border:1px solid #35516a;border-radius:10px;background:#122536;color:#e4edf5;font:600 12px system-ui;padding:8px;max-width:100%;min-width:0;text-decoration:none;text-align:center}.rm-working .rm-chat-toolbar select{width:100%;text-align:left}.rm-working .rm-selection-bar{grid-template-columns:minmax(0,1fr) minmax(0,1.25fr) 42px;margin-bottom:16px}.rm-working .rm-selection-bar [data-send-selected]{background:#276cbd;border-color:#428bd9;color:white}.rm-working [data-count]{display:inline-grid;place-items:center;min-width:19px;padding:1px 4px;background:#ffffff24;border-radius:5px;margin-left:3px}
    .rm-working .rm-chat-grid{display:grid;grid-template-columns:repeat(var(--rm-cols,2),minmax(0,1fr));gap:12px;align-items:start}.rm-working .rm-chat-card{width:auto!important;min-width:0!important;margin:0!important;padding:0!important;display:block!important;border:1px solid #30465b;border-radius:16px;background:#112131;overflow:hidden;box-shadow:0 5px 18px #0002}.rm-working .rm-card-head{display:flex;align-items:center;justify-content:space-between;gap:6px;padding:10px;font-size:12px;border-bottom:1px solid #2c4054}.rm-working .rm-card-head b{min-width:0;overflow-wrap:anywhere;font-size:12px;line-height:1.4}.rm-working .rm-card-head label{display:flex;align-items:center;gap:0;flex:none;margin:0}.rm-working .rm-card-head input{width:20px;height:20px;min-height:20px;accent-color:#4b9aee;margin:0}.rm-working .rm-chat-card [data-image]{display:block;width:100%;padding:0;margin:0;border:0;border-radius:0;background:#0a1520;aspect-ratio:1/1;overflow:hidden;cursor:zoom-in}.rm-working .rm-chat-card img{display:block;width:100%!important;height:100%!important;max-height:none;object-fit:contain;background:#0a1520;border-radius:0;margin:0}.rm-working .rm-photo-pending{aspect-ratio:1/1;display:grid;place-items:center;background:#0a1520;color:#7e94a9;font-size:12px;margin:0}
    .rm-working .rm-caption{padding:12px;overflow-wrap:anywhere}.rm-working .rm-caption h4{font-size:14px;line-height:1.4;color:#f4f7fa;margin:0 0 7px;font-weight:700}.rm-working .rm-category-tag{display:inline-block;padding:3px 7px;border-radius:6px;background:#263e55;color:#b7d5f3;font-size:10px;line-height:1.4;margin-bottom:8px}.rm-working .rm-caption dl{margin:0;display:grid;gap:6px}.rm-working .rm-caption dl>div{display:block;min-width:0}.rm-working .rm-caption dt{font-size:10px;color:#8ca4ba;margin:0 0 2px}.rm-working .rm-caption dd{margin:0;font-size:12px;color:#d9e5ef;line-height:1.45}.rm-working .rm-caption-note{font-size:12px;color:#aabdd0;line-height:1.5;margin:8px 0}.rm-working .rm-card-rate{border-top:1px solid #2a3e50;padding-top:10px;margin-top:10px;display:grid;gap:3px}.rm-working .rm-card-rate small{font-size:10px;color:#8ca4ba}.rm-working .rm-card-rate b{font-size:18px;color:#f4f8ff}.rm-working .rm-card-rate .rm-pending-rate{font-size:12px;color:#edc383}.rm-working .rm-balance{font-size:11px;color:#9ee0c3;background:#17382f;border-radius:7px;padding:7px;margin:9px 0 0;line-height:1.5}.rm-working .rm-balance b{font-size:13px}.rm-working .rm-purchased{display:block;font-size:10px;color:#8ca4ba;margin-top:6px}
    .rm-working .rm-chat-card details{margin:0;border-top:1px solid #293e52;padding:10px;font-size:12px;line-height:1.5;color:#b7cbdc}.rm-working .rm-chat-card summary{font-weight:650;cursor:pointer;color:#d0e3f3;font-size:11px}.rm-working .rm-chat-card details input{width:100%;min-width:0;box-sizing:border-box;margin:7px 0 0;padding:8px;border:1px solid #3c5970;border-radius:8px;background:#0b1926;color:#e9f2fa;font:inherit;min-height:36px}.rm-working .rm-chat-card details button{display:block;width:100%;padding:8px;margin:8px 0 0;border:1px solid #4779a8;border-radius:8px;background:#1d4a74;color:#e9f4ff;font:600 11px system-ui;min-height:36px}.rm-working .rm-chat-card .rm-send-card{display:block;width:calc(100% - 20px);box-sizing:border-box;margin:10px;padding:10px 6px;min-height:40px;border:1px solid #428bd9;border-radius:9px;background:#276cbd;color:white;font:600 12px system-ui}.rm-working .rm-chat-card button:disabled{opacity:.45;cursor:default}.rm-working .rm-chat-card [data-return]{background:#442e32;border-color:#80515c;color:#ffd9dc}
    .rm-chat-modal{position:fixed;inset:0;background:#000b;z-index:2147483600;display:flex;justify-content:center;align-items:center;padding:12px}.rm-chat-sheet{background:#102131;color:#eef5ff;width:min(760px,100%);max-height:92dvh;overflow:auto;border:1px solid #48617a;border-radius:16px;padding:16px;box-sizing:border-box}.rm-chat-sheet header{display:flex;gap:12px;justify-content:space-between;align-items:center}.rm-chat-sheet label{display:grid;gap:5px;margin:10px 0}.rm-chat-sheet input,.rm-chat-sheet textarea,.rm-chat-sheet select{width:100%;box-sizing:border-box;background:#091824;color:#fff;border:1px solid #48617a;border-radius:8px;padding:10px;min-height:42px;font:inherit}.rm-chat-sheet .rm-fields{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.rm-chat-line{border:1px solid #39516a;padding:10px;border-radius:12px;margin:12px 0}.rm-chat-line img{max-width:100%;height:160px;object-fit:contain}.rm-chat-sheet footer{position:sticky;bottom:-16px;background:#102131;padding:12px 0;display:flex;gap:8px;flex-wrap:wrap}.rm-chat-error{white-space:pre-wrap;color:#ffd894;padding:10px 0}.rm-chat-customer{display:flex!important;grid-template-columns:22px 1fr;align-items:center;gap:10px!important}.rm-chat-customer input{width:22px!important;min-height:22px!important}.rm-chat-sheet [hidden]{display:none!important}
    @media(max-width:520px){.rm-working .rm-chat-grid{gap:10px}.rm-working .rm-caption{padding:10px}.rm-working .rm-card-head{padding:8px}.rm-chat-sheet .rm-fields{grid-template-columns:1fr}.rm-chat-modal{padding:5px}}`;
    document.head.appendChild(el);
  }
  function modal(title) {
    const backdrop=document.createElement('div');backdrop.className='rm-chat-modal';backdrop.innerHTML=`<section class="rm-chat-sheet" role="dialog" aria-modal="true" aria-label="${esc(title)}"><header><h2>${esc(title)}</h2><button type="button" data-close>×</button></header><div data-body></div><p class="rm-chat-error" data-message aria-live="polite"></p><footer data-footer></footer></section>`;
    const remove=backdrop.remove.bind(backdrop);backdrop.remove=()=>{backdrop.querySelectorAll('[data-blob]').forEach(img=>URL.revokeObjectURL(img.dataset.blob));remove()};
    document.body.appendChild(backdrop);backdrop.querySelector('[data-close]').onclick=()=>{if(!state.busy)backdrop.remove()};backdrop.addEventListener('keydown',e=>{if(e.key==='Escape'&&!state.busy)backdrop.remove()});return backdrop;
  }
  async function action(button,message,fn) {
    if(state.busy)return;state.busy=true;button.disabled=true;
    try{await fn()}catch(e){message.textContent=e.message||'Please retry.'}finally{state.busy=false;button.disabled=false}
  }
  function lineMarkup(x={}) {
    x={...x,bill_qty:x.bill_qty??x.bill_qty_test71??x.qty};const listId='rm-list-'+crypto.randomUUID();
    const field=(key,label,type='text')=>`<label>${label}<input data-field="${key}" type="${type}" ${key==='art_no'?'list="'+listId+'-arts" maxlength="80"':key==='item_name'?'list="'+listId+'-items" maxlength="200"':''} value="${esc(x[key]??'')}" ${['qty','bill_qty','purchase_rate'].includes(key)?'min="'+(key==='purchase_rate'?'0.01':'1')+'" step="'+(key==='purchase_rate'?'0.01':'1')+'"':''}></label>`;
    return `<section class="rm-chat-line" data-art-revision="${esc(x.art_revision??'')}" data-bound-art="${esc(x.art_no||'')}"><div class="rm-fields">${field('lot_no','Readymade Lot No. *')}<small data-lot-hint style="color:#8ca4ba">New Lots: RM + number · Previous Lot loading…</small>${field('art_no','Art No. · select or add new')}${field('item_name','Item Name · select or add new *')}<label>Category *<select data-field="category" data-saved-category="${esc(x.category||'')}" disabled><option value="">Loading existing categories…</option></select></label><label>Sizes *<select data-field="size_text"><option value="">Select size family</option>${sizeFamilies.map(v=>`<option value="${esc(v)}" ${v.replace(/[\s,\/]/g,'').toUpperCase()===String(x.size_text||'').replace(/[\s,\/]/g,'').toUpperCase()?'selected':''}>${esc(v)}</option>`).join('')}</select></label>${field('colours_text','Colours')}${field('cloth_name','Cloth / Fabric')}${field('bill_qty','Party Bill Quantity · PCS *','number')}${field('qty','Received Quantity · PCS *','number')}${field('purchase_rate','Purchase rate / PCS *','number')}${field('final_rate','Final sales rate / PCS · optional','number')}</div><datalist id="${listId}-arts" data-art-options></datalist><datalist id="${listId}-items" data-item-options></datalist><p data-art-effective></p><p data-art-balance aria-live="polite">Select Art No. to load live available PCS.</p><button type="button" data-refresh-art>Refresh live balance</button><button type="button" data-reload-art>Reload Art defaults</button><label>Final garment photo *<input data-photo type="file" accept="image/*"></label><img data-preview ${x.final_image_url?'':'hidden'} src="${esc(x.final_image_url||'')}" alt="Final garment preview"><label>Image URL<input data-field="final_image_url" type="url" value="${esc(x.final_image_url||'')}" placeholder="Upload photo or enter image URL"></label><label>Caption note<textarea data-field="caption_note" data-rr-uppercase="off">${esc(x.caption_note||'')}</textarea></label><p data-line-total>Purchase value —</p><button type="button" data-remove>Remove garment</button></section>`;
  }
  function updateReceipt(row) {
    const billInput=row.querySelector('[data-field="bill_qty"]'),qtyInput=row.querySelector('[data-field="qty"]'),rateInput=row.querySelector('[data-field="purchase_rate"]');
    if(!billInput||!qtyInput||!rateInput)return;
    const bill=Number(billInput.value),qty=Number(qtyInput.value),rate=Number(rateInput.value),total=row.querySelector('[data-line-total]');
    total.setAttribute('aria-live','polite');
    if(!Number.isSafeInteger(bill)||bill<=0||!Number.isSafeInteger(qty)||qty<=0||!Number.isFinite(rate)||rate<=0){total.textContent='Enter Party Bill Quantity, Received Quantity and Purchase Rate to calculate Short / Excess.';return}
    const billValue=Math.round((bill*rate+Number.EPSILON)*100)/100,receivedValue=Math.round((qty*rate+Number.EPSILON)*100)/100,diff=qty-bill;
    total.textContent='Party bill '+money(billValue)+' · Received stock '+qty+' PCS · '+(diff<0?'SHORT '+(-diff)+' PCS · Debit Note ':diff>0?'EXCESS '+diff+' PCS · Credit Note ':'MATCHED · Adjustment ')+money(Math.abs(receivedValue-billValue))+' · Net purchase / Supplier payable '+money(receivedValue);
  }
  function receiptView(receipt,ctx,options={}) {
    const m=modal('Proforma DR/CR Note · '+(receipt.bill_no||'')),body=m.querySelector('[data-body]');
    body.innerHTML=(receipt.lines||[]).map(l=>'<section class="rm-chat-line"><b>'+esc(l.lot_no)+'</b><p>Party Bill Quantity: '+esc(l.bill_qty)+' PCS<br>Received Quantity: '+esc(l.received_qty)+' PCS<br>Purchase Rate: '+money(l.purchase_rate)+'/PCS</p><p>'+esc(l.note_type==='MATCHED'?'MATCHED':l.note_type==='DEBIT_NOTE'?'SHORT · Debit Note':'EXCESS · Credit Note')+' · '+Math.abs(Number(l.difference_qty))+' PCS · '+money(l.note_amount)+'</p>'+(l.voucher_no?'<p>Accounts voucher: <b>'+esc(l.voucher_no)+'</b></p>':'')+'<p>Net purchase / Supplier payable: '+money(l.received_value)+'</p></section>').join('')+'<p>Party bill: '+money(receipt.bill_value)+' · Net received value: '+money(receipt.received_value)+'</p><p>Received stock and supplier accounts finalized together.</p>';
    if(ctx&&window.RRReadymadeReceipt71)window.RRReadymadeReceipt71.attach(ctx,m,receipt,options);
  }
  function purchase(ctx,draft=null) {
    const recoveryKey='RM_PENDING71:'+JSON.stringify([ctx.s.userId,ctx.s.actor?.id,roleOf(ctx.s)]);let recovered=false;if(!draft){try{const saved=JSON.parse(sessionStorage.getItem(recoveryKey)||'null');if(saved?.lines?.length){draft=saved;recovered=true}}catch{}}

    const m=modal(draft?'Continue Readymade Purchase':'New Readymade Purchase'),body=m.querySelector('[data-body]'),msg=m.querySelector('[data-message]');let pid=draft?.purchase_id||null;
    body.innerHTML=`<div class="rm-fields"><label>Supplier / Seller *<select data-supplier disabled><option value="">Loading existing suppliers…</option></select></label><label>Supplier bill number *<input data-bill value="${esc(draft?.bill_no||'')}"></label><label>Purchase / bill date *<input data-date type="date" value="${esc(draft?.purchase_date||new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'}))}"></label></div><div data-lines></div><button type="button" data-add>Add garment</button><section class="card" data-costing-status><b>Monthly costing / Final rate</b><p data-cost-month></p><p>Purchase cost + monthly weighted Sales/Admin/Accounts salary + applicable overhead = total cost.</p>${['OWNER','SUPER_ADMIN'].includes(roleOf(ctx.s))?'<p>Fixed Owner margin: ₹22/PCS. Base sales rate = total cost + ₹22.</p>':''}<p>Actual weighted base rate is calculated after purchase confirmation and shown in WORKING. Missing monthly values keep approval pending. Final-rate approval changes RRQ on available PCS.</p></section>`;
    if(recovered)msg.textContent='Unsaved entry recovered on this device. Review details; uploaded photo may need selecting again. This is not a confirmed purchase.';
    function keepPending(){try{const pending={purchase_id:pid,supplier_name:body.querySelector('[data-supplier]').value,bill_no:body.querySelector('[data-bill]').value,purchase_date:body.querySelector('[data-date]').value,lines:[...body.querySelectorAll('.rm-chat-line')].map(row=>({...Object.fromEntries([...row.querySelectorAll('[data-field]')].map(i=>[i.dataset.field,i.value.trim()])),art_revision:row.dataset.artRevision}))};sessionStorage.setItem(recoveryKey,JSON.stringify(pending))}catch{}}
    body.addEventListener('input',keepPending);body.addEventListener('change',keepPending);
    const supplierSelect=body.querySelector('[data-supplier]');
    let supplierNames=new Set();
    function showSuppliers(rows,preferred){supplierNames=new Set(rows.map(x=>x.supplier_name));supplierSelect.innerHTML='<option value="">Select existing supplier</option>'+rows.map(x=>`<option value="${esc(x.supplier_name)}">${esc(x.supplier_name)}</option>`).join('');supplierSelect.value=supplierNames.has(preferred)?preferred:'';supplierSelect.disabled=false;if(!rows.length)msg.textContent='No active suppliers in Supplier Master.';else if(draft?.supplier_name&&!supplierNames.has(draft.supplier_name))msg.textContent='Saved supplier is inactive or unavailable. Select an active supplier.';}
    async function loadSuppliers(preferred=supplierSelect.value||draft?.supplier_name,force=false){
      const cache=supplierCache(ctx.s);if(cache.rows)showSuppliers(cache.rows,preferred);else supplierSelect.disabled=true;
      try{const rows=await suppliers(ctx.s,force);if(!m.isConnected)return;showSuppliers(rows,supplierSelect.value||preferred)}catch(e){if(!m.isConnected)return;msg.textContent='Supplier list could not refresh. Tap Retry suppliers.';if(!cache.rows)supplierSelect.innerHTML='<option value="">Suppliers unavailable</option>';}
    }
    const retry=document.createElement('button');retry.type='button';retry.textContent='Retry suppliers';retry.dataset.retrySuppliers='';retry.onclick=()=>loadSuppliers(supplierSelect.value||draft?.supplier_name,true);supplierSelect.parentElement.appendChild(retry);
    function addMaster(kind,onSaved){
      const supplier=kind==='Supplier',dialog=modal('+ Add New '+kind),content=dialog.querySelector('[data-body]'),message=dialog.querySelector('[data-message]');
      content.innerHTML='<label>'+kind+' name *<input data-master-name maxlength="120"></label>'+(supplier?'<label>Mobile · optional<input data-master-mobile type="tel"></label><label>Address · optional<input data-master-address></label><label>GSTIN · optional<input data-master-gstin maxlength="15"></label>':'');
      dialog.querySelector('[data-footer]').innerHTML='<button type="button" data-master-save>Save '+kind+'</button><button type="button" data-master-cancel>Cancel</button>';
      dialog.querySelector('[data-master-cancel]').onclick=()=>{if(!state.busy)dialog.remove()};
      dialog.querySelector('[data-master-save]').onclick=e=>action(e.currentTarget,message,async()=>{
        const name=content.querySelector('[data-master-name]').value.trim().replace(/\s+/g,' ');
        if(!name)throw Error('Enter '+kind.toLowerCase()+' name.');
        const result=await ctx.rpc(supplier?'rr_supplier_upsert_v1':'rr_add_art_category',supplier?{p_supplier_name:name,p_mobile:content.querySelector('[data-master-mobile]').value.trim()||null,p_address:content.querySelector('[data-master-address]').value.trim()||null,p_gstin:content.querySelector('[data-master-gstin]').value.trim()||null}:{p_category_name:name,p_default_design_name:null});
        const saved=Array.isArray(result)?result[0]:result;
        if(!saved?.id)throw Error(kind+' could not be saved. Please retry.');
        await onSaved(saved);dialog.remove();
      });
      content.querySelector('[data-master-name]').focus();
    }
    const addSupplier=document.createElement('button');addSupplier.type='button';addSupplier.dataset.addSupplier='';addSupplier.textContent='+ Add New Supplier';
    addSupplier.onclick=()=>addMaster('Supplier',async saved=>{
      const cache=supplierCache(ctx.s);cache.rows=[...(cache.rows||[]).filter(x=>x.supplier_name!==saved.supplier_name),saved].sort((a,b)=>a.supplier_name.localeCompare(b.supplier_name));cache.at=Date.now();showSuppliers(cache.rows,saved.supplier_name);
      if(supplierSelect.disabled)throw Error('Supplier saved. Retry suppliers to refresh the list.');
      msg.textContent='Supplier saved and selected.';
    });supplierSelect.parentElement.appendChild(addSupplier);
    loadSuppliers();
    const lines=body.querySelector('[data-lines]');let categories=[],categoryDefaults=new Map(),mastersReady=false,artRows=[],itemNames=[],artLoaded=false;
    function artOf(row){const key=row.querySelector('[data-field="art_no"]').value.trim().toUpperCase();return artRows.find(a=>a.art_no.toUpperCase()===key)}
    function showArtBalance(row,a=artOf(row)){
      const art=row.querySelector('[data-field="art_no"]').value.trim(),out=row.querySelector('[data-art-balance]');
      out.textContent=!art?'Select Art No. to load live available PCS.':!artLoaded?'Live balance unavailable. Tap Refresh live balance.':'Team live available balance · Art '+art+': '+Number(a?.available_qty||0)+' PCS';
      const effective=row.querySelector('[data-art-effective]');
      effective.textContent=a?.effective_from?'Current Art defaults effective: '+new Date(a.effective_from).toLocaleString('en-IN',{timeZone:'Asia/Kolkata'})+' · New purchases use these defaults; previous purchases keep their rates.':art&&artLoaded?'New Art · Details entered here will become defaults after purchase confirmation.':'';
    }
    function fillArtLists(row){
      row.querySelector('[data-art-options]').innerHTML=artRows.map(a=>'<option value="'+esc(a.art_no)+'">'+esc(a.item_name)+'</option>').join('');
      row.querySelector('[data-item-options]').innerHTML=itemNames.map(name=>'<option value="'+esc(name)+'"></option>').join('');showArtBalance(row);
    }
    async function loadArtCatalog(silent=false){
      try{const result=await ctx.rpc('rr_rm_art_catalog_test71',{p_art_no:null});artRows=result.rows||[];itemNames=result.items||[];artLoaded=true;[...lines.children].forEach(fillArtLists)}
      catch{artLoaded=false;[...lines.children].forEach(row=>showArtBalance(row));if(!silent)msg.textContent='Art defaults could not load. Enter new details or tap Reload Art defaults.'}
    }
    function bindArt(row){
      const art=row.querySelector('[data-field="art_no"]').value.trim(),a=artOf(row);row.dataset.boundArt=art;
      row.dataset.artRevision=String(a?.art_revision||0);
      if(a){
        for(const key of ['item_name','category','size_text','cloth_name','colours_text','caption_note','purchase_rate','final_rate','final_image_url']){
          const input=row.querySelector('[data-field="'+key+'"]');input.value=a[key]??'';
          if(key==='category'){input.dataset.savedCategory=input.value}
        }
        row.querySelector('[data-photo]').value='';const img=row.querySelector('[data-preview]');if(img.dataset.blob){URL.revokeObjectURL(img.dataset.blob);delete img.dataset.blob}img.src=a.final_image_url||'';img.hidden=!a.final_image_url;
      }
      updateReceipt(row);showArtBalance(row,a);
    }
    async function loadArtDefaults(row){await loadArtCatalog();if(artLoaded)bindArt(row)}
    async function refreshArtBalance(row){
      try{
        const art=row.querySelector('[data-field="art_no"]').value.trim();if(!art){showArtBalance(row);return}
        const result=await ctx.rpc('rr_rm_art_catalog_test71',{p_art_no:art}),a=result.rows?.[0];artLoaded=true;
        if(a){artRows=artRows.filter(x=>x.art_no.toUpperCase()!==art.toUpperCase());artRows.push(a)}
        showArtBalance(row,a);
      }catch{row.querySelector('[data-art-balance]').textContent='Live balance could not refresh. Please retry.'}
    }
    function fillCategory(row){
      const sel=row.querySelector('[data-field="category"]'),saved=sel.value||sel.dataset.savedCategory;
      sel.innerHTML='<option value="">Select existing category</option>'+categories.map(c=>`<option value="${esc(c.category_name)}">${esc(c.category_name)}</option>`).join('');
      sel.value=categories.some(c=>c.category_name===saved)?saved:'';sel.disabled=!mastersReady;
      sel.onchange=()=>{sel.dataset.savedCategory=sel.value;const cat=categories.find(c=>c.category_name===sel.value),def=categoryDefaults.get(String(cat?.id)),sizes=row.querySelector('[data-field="size_text"]');if(def){const v=sizeFamilies.find(x=>x.replace(/\s/g,'')===String(def.default_size_family).replace(/\s/g,''));if(v)sizes.value=v}};
      if(!row.querySelector('[data-add-category]')){
        const add=document.createElement('button');add.type='button';add.dataset.addCategory='';add.textContent='+ Add New Category';
        add.onclick=()=>addMaster('Category',async saved=>{
          categories=categories.filter(c=>c.id!==saved.id);categories.push(saved);categories.sort((a,b)=>a.category_name.localeCompare(b.category_name));mastersReady=true;
          [...lines.children].forEach(fillCategory);sel.value=saved.category_name;sel.dataset.savedCategory=saved.category_name;sel.onchange();msg.textContent='Category saved and selected.';
        });sel.parentElement.appendChild(add);
      }
    }
    let lotHint=null;function applyLotHints(){if(!lotHint)return;[...lines.children].forEach((row,i)=>{const input=row.querySelector('[data-field="lot_no"]');if(!input)return;const match=/^RM(\d+)$/.exec(lotHint.suggested_lot||'');const next=match?'RM'+String(Number(match[1])+i).padStart(Math.max(3,match[1].length),'0'):'RM001';input.placeholder=next;row.querySelector('[data-lot-hint]').textContent='Previous Lot: '+(lotHint.previous_lot||'None')+' · Suggested next: '+next+' · Suggestion only; enter a new Lot.';})}
    ctx.rpc('rr_rm_lot_hint_test71').then(h=>{lotHint=h;if(m.isConnected)applyLotHints()}).catch(()=>{body.querySelectorAll('[data-lot-hint]').forEach(x=>x.textContent='New Readymade Lots: RM + number, e.g. RM001')});
    function addLine(x={}){lines.insertAdjacentHTML('beforeend',lineMarkup(x));const row=lines.lastElementChild;applyLotHints();updateReceipt(row);fillArtLists(row);if(mastersReady)fillCategory(row);row.querySelector('[data-refresh-art]').onclick=()=>refreshArtBalance(row);row.querySelector('[data-reload-art]').onclick=()=>loadArtDefaults(row)}
    (draft?.lines?.length?draft.lines:[{}]).forEach(addLine);
    async function loadCategories(){
      try{
        const [result,defaults]=await Promise.all([ctx.s.db.from('rr_art_categories').select('id,category_code,category_name').eq('is_active',true).order('category_name'),ctx.rpc('rr_cb_category_defaults_get_v1',{})]);
        if(result.error)throw result.error;categories=result.data||[];categoryDefaults=new Map((defaults?.rows||[]).map(x=>[String(x.art_category_id),x]));mastersReady=true;
        [...lines.children].forEach(fillCategory);if(!categories.length)msg.textContent='No active garment categories in existing Category Master.';
      }catch(e){msg.textContent='Category mapping could not load. Tap Retry categories.';}
    }
    body.querySelector('[data-add]').onclick=()=>addLine();
    loadArtCatalog();
    const liveTimer=setInterval(()=>{if(m.isConnected&&!document.hidden)loadArtCatalog(true)},10000);
    const recover=()=>{if(m.isConnected&&!document.hidden)loadArtCatalog(true)};document.addEventListener('visibilitychange',recover);
    const liveChannel=ctx.s.db.channel?ctx.s.db.channel('rm-art-modal-'+crypto.randomUUID()).on('postgres_changes',{event:'INSERT',schema:'public',table:'rr_fg_stock_ledger_v787',filter:'data_mode=eq.TEST'},recover).subscribe():null;
    const removePurchase=m.remove.bind(m);m.remove=()=>{clearInterval(liveTimer);document.removeEventListener('visibilitychange',recover);if(liveChannel)ctx.s.db.removeChannel(liveChannel);removePurchase()};
    const retryCategories=document.createElement('button');retryCategories.type='button';retryCategories.textContent='Retry categories';retryCategories.onclick=loadCategories;body.querySelector('[data-add]').after(retryCategories);loadCategories();
    const month=()=>{body.querySelector('[data-cost-month]').textContent='Costing month: '+(body.querySelector('[data-date]').value.slice(0,7)||'Select bill date')};month();body.querySelector('[data-date]').addEventListener('change',month);
    body.addEventListener('click',e=>{if(e.target.closest('[data-remove]')&&lines.children.length>1)e.target.closest('.rm-chat-line').remove()});
    body.addEventListener('input',e=>{const row=e.target.closest('.rm-chat-line');if(!row)return;updateReceipt(row);if(e.target.dataset.field==='final_image_url'){const img=row.querySelector('[data-preview]');img.src=/^https?:\/\//.test(e.target.value)?e.target.value:'';img.hidden=!img.src}});
    body.addEventListener('change',e=>{if(e.target.dataset.field==='art_no'){bindArt(e.target.closest('.rm-chat-line'));return}if(!e.target.matches('[data-photo]'))return;const row=e.target.closest('.rm-chat-line'),file=e.target.files[0];if(!file)return;const img=row.querySelector('[data-preview]');if(img.dataset.blob)URL.revokeObjectURL(img.dataset.blob);img.dataset.blob=URL.createObjectURL(file);img.src=img.dataset.blob;img.hidden=false});
    m.querySelector('[data-footer]').innerHTML='<button type="button" data-draft>Save draft</button><button type="button" data-post>Save & Confirm Purchase</button><button type="button" data-prepare-share>Save & Send · Proforma DR/CR Note</button><small>Save & Send opens the image picker. Purchase and Debit/Credit Note confirmation runs in the same flow.</small>';
    let preparedProforma=null,warmTimer=null,warmSeq=0;
    const warmNote=()=>{clearTimeout(warmTimer);const seq=++warmSeq;warmTimer=setTimeout(async()=>{
      const module=window.RRReadymadeReceipt71;if(!module?.prime)return;
      try{const rows=[...lines.children],entries=rows.map(row=>{const x=Object.fromEntries([...row.querySelectorAll('[data-field]')].map(i=>[i.dataset.field,i.value.trim()])),b=Number(x.bill_qty),q=Number(x.qty),r=Number(x.purchase_rate);return{...x,bill_qty:b,received_qty:q,purchase_rate:r,difference_qty:q-b,note_type:q<b?'DEBIT_NOTE':q>b?'CREDIT_NOTE':'MATCHED',note_amount:Math.round(Math.abs(q-b)*r*100)/100,bill_value:b*r,received_value:q*r}});
      const note={supplier_name:body.querySelector('[data-supplier]').value.trim(),bill_no:body.querySelector('[data-bill]').value.trim(),purchase_date:body.querySelector('[data-date]').value,lines:entries,bill_value:entries.reduce((n,x)=>n+x.bill_value,0),received_value:entries.reduce((n,x)=>n+x.received_value,0)};
      if(!note.supplier_name||!note.bill_no||entries.some(x=>!x.item_name||!x.bill_qty||!x.received_qty||!x.purchase_rate))return;
      const pack=await module.prime(note);if(seq===warmSeq&&m.isConnected)preparedProforma={key:JSON.stringify(note),pack};
      }catch{}},300)};
    body.addEventListener('input',warmNote);body.addEventListener('change',warmNote);warmNote();
    const removeForWarm=m.remove.bind(m);m.remove=()=>{clearTimeout(warmTimer);warmSeq++;removeForWarm()};
    function recordSentImage(sendResult,purchaseId){if(!sendResult)return;sendResult.then(async r=>{if(!r.shared)return;try{await window.RRReadymadeReceipt71.prepare(ctx,purchaseId);await ctx.rpc('rr_rm_receipt_share_record_test71',{p_purchase_id:purchaseId,p_event_id:crypto.randomUUID()})}catch{ctx.notice('Purchase saved. Share record save नहीं हुआ.')}})}
    let billCheck=null;function checkBill(){const supplier=body.querySelector('[data-supplier]').value.trim(),bill=body.querySelector('[data-bill]').value.trim(),key=JSON.stringify([supplier,bill]);if(!supplier||!bill)return;if(billCheck?.key===key)return;const check={key,result:null};billCheck=check;ctx.rpc('rr_rm_saved_bill_test71',{p_supplier_name:supplier,p_bill_no:bill}).then(result=>{if(billCheck===check)check.result=result},()=>{if(billCheck===check)billCheck=null})}body.addEventListener('input',checkBill);body.addEventListener('change',checkBill);
    function reopenSaved(saved,sendResult=null){
      if(!saved?.found||saved.purchase_id===pid)return false;
      if(saved.status==='POSTED'){
        const entered=[...lines.children].map(row=>Object.fromEntries([...row.querySelectorAll('[data-field]')].map(i=>[i.dataset.field,i.value.trim()])));if(entered.some(x=>x.item_name||Number(x.qty)>0)){const existing=saved.receipt?.lines||[];if(entered.length!==existing.length||entered.some(x=>!existing.some(l=>String(l.lot_no).toUpperCase()===x.lot_no.toUpperCase()&&Number(l.received_qty)===Number(x.qty)&&Number(l.bill_qty)===Number(x.bill_qty)&&Number(l.purchase_rate)===Number(x.purchase_rate)&&String(l.art_no||'').toUpperCase()===String(x.art_no||'').toUpperCase())))throw Error('This supplier Bill No. already has a different saved purchase. New entry was not saved. Check the original bill number; do not send this as a confirmed purchase.');}

        recordSentImage(sendResult,saved.purchase_id);m.remove();receiptView(saved.receipt,ctx,{shareStarted:!!sendResult});ctx.notice('Saved bill opened · Share its original receipt / Debit · Credit Note. No new purchase posted.');return true;
      }
      if(saved.status==='DRAFT'&&saved.draft){
        msg.textContent='इस bill का draft पहले से saved है. उसी draft को खोलें—नई entry नहीं बनेगी.';
        if(!m.querySelector('[data-open-saved-bill]')){const b=document.createElement('button');b.type='button';b.dataset.openSavedBill='';b.textContent='Open saved bill draft';b.onclick=()=>{m.remove();purchase(ctx,saved.draft)};m.querySelector('[data-footer]').prepend(b)}return true;
      }
      throw Error('इस bill का record पहले से है. Purchase records में उसकी status देखें.');
    }
    async function save(post,button,sendResult=null) {
      await action(button,msg,async()=>{
        const supplier=body.querySelector('[data-supplier]').value.trim(),bill=body.querySelector('[data-bill]').value.trim(),date=body.querySelector('[data-date]').value;
        if(supplierSelect.disabled||!supplierNames.has(supplier))throw Error('Select an existing active supplier from the dropdown.');
        if(!bill||!date)throw Error('Supplier bill number and date required.');
        if(post&&!pid){const saved=await ctx.rpc('rr_rm_saved_bill_test71',{p_supplier_name:supplier,p_bill_no:bill});if(reopenSaved(saved,sendResult))return;}
        const payload=[];
        for(const row of lines.children){
          const x=Object.fromEntries([...row.querySelectorAll('[data-field]')].map(i=>[i.dataset.field,i.value.trim()]));x.bill_qty=Number(x.bill_qty);x.qty=Number(x.qty);x.purchase_rate=Number(x.purchase_rate);x.final_rate=x.final_rate===''?null:Number(x.final_rate);x.markup_mode='DEFAULT_22';if(x.art_no){x.art_revision=Number(row.dataset.artRevision||artRows.find(a=>a.art_no.toUpperCase()===x.art_no.toUpperCase())?.art_revision||0)}
          if(!mastersReady||!categories.some(c=>c.category_name===x.category)||!sizeFamilies.includes(x.size_text))throw Error('Select existing category and size family.');
          if(!x.lot_no||!x.item_name||!x.category||!Number.isSafeInteger(x.bill_qty)||x.bill_qty<=0||!Number.isSafeInteger(x.qty)||x.qty<=0||!Number.isFinite(x.purchase_rate)||x.purchase_rate<=0)throw Error('Lot, garment, category, positive whole Party Bill PCS, Received PCS and purchase rate required.');
          if(x.final_rate!=null&&(!Number.isFinite(x.final_rate)||x.final_rate<0))throw Error('Valid final sales rate required.');
          const file=row.querySelector('[data-photo]').files[0];
          if(file){if(!file.type.startsWith('image/')||file.size>10*1024*1024)throw Error('Choose an image up to 10 MB.');const path='readymade/test71/'+crypto.randomUUID()+'.'+(file.name.split('.').pop().replace(/[^a-z0-9]/gi,'')||'jpg');const storage=ctx.s.db.storage.from('redzed-media'),up=await storage.upload(path,file,{contentType:file.type,upsert:false});if(up.error)throw up.error;x.final_image_url=storage.getPublicUrl(path).data.publicUrl;row.querySelector('[data-field="final_image_url"]').value=x.final_image_url;row.querySelector('[data-photo]').value='';}
          if(!/^https?:\/\//i.test(x.final_image_url))throw Error('Final garment photo required.');payload.push(x);
        }
        if(new Set(payload.map(x=>x.lot_no.toUpperCase())).size!==payload.length)throw Error('Each garment lot number must be unique.');
        let j;try{j=await ctx.rpc('rr_rm_chat_save_test71',{p_purchase_id:pid,p_supplier_name:supplier,p_bill_no:bill,p_purchase_date:date,p_lines:payload,p_post:post})}
        catch(e){if(post&&!pid&&String(e.message||'').includes('Supplier bill already exists')){const saved=await ctx.rpc('rr_rm_saved_bill_test71',{p_supplier_name:supplier,p_bill_no:bill});if(reopenSaved(saved,sendResult))return;}throw e}pid=j.purchase_id;
        if(post){try{sessionStorage.removeItem(recoveryKey)}catch{}recordSentImage(sendResult,j.purchase_id);m.remove();if(j.receipt)receiptView(j.receipt,ctx,{shareStarted:!!sendResult});state.selection.clear();ctx.s.status='WORKING';ctx.s.userStatusLock='WORKING';ctx.changed();await ctx.refresh();ctx.notice('Purchase confirmed · Received stock, supplier Accounts and Short / Excess notes updated.'+(j.rate_notes?.length?' '+j.rate_notes.join(' · '):''));}
        else{keepPending();msg.textContent='Draft saved. Continue here or reopen from OPEN.';ctx.s.departmentCountCache.delete('READYMADE');}
      });
    }
    m.querySelector('[data-draft]').onclick=e=>save(false,e.currentTarget);m.querySelector('[data-post]').onclick=e=>save(true,e.currentTarget);m.querySelector('[data-prepare-share]').onclick=e=>{
      if(state.busy)return;
      keepPending();
      try{
        const supplier=body.querySelector('[data-supplier]').value.trim(),bill=body.querySelector('[data-bill]').value.trim(),date=body.querySelector('[data-date]').value;
        if(supplierSelect.disabled||!supplierNames.has(supplier)||!bill||!date)throw Error('Supplier, bill number और date भरें.');
        const key=JSON.stringify([supplier,bill]);if(!billCheck||billCheck.key!==key||!billCheck.result){checkBill();msg.textContent='Checking supplier bill before image share. Purchase is not confirmed yet.';save(true,e.currentTarget);return}if(billCheck.result.found){reopenSaved(billCheck.result);return}
        const rows=[...lines.children],entries=rows.map(row=>{const x=Object.fromEntries([...row.querySelectorAll('[data-field]')].map(i=>[i.dataset.field,i.value.trim()]));const b=Number(x.bill_qty),q=Number(x.qty),r=Number(x.purchase_rate);if(!/^RM[0-9]+$/i.test(x.lot_no)&&!(draft?.purchase_id&&draft.lines?.some(l=>l.lot_no===x.lot_no)))throw Error('New Readymade Lot: RM + number, e.g. RM001.');const finalRate=x.final_rate===''?null:Number(x.final_rate),photo=row.querySelector('[data-photo]').files[0];if(finalRate!=null&&(!Number.isFinite(finalRate)||finalRate<0))throw Error('Valid final sales rate required.');if(photo&&(!photo.type.startsWith('image/')||photo.size>10*1024*1024))throw Error('Choose an image up to 10 MB.');if(!mastersReady||!categories.some(c=>c.category_name===x.category)||!sizeFamilies.includes(x.size_text)||!x.lot_no||!x.item_name||!Number.isSafeInteger(b)||b<=0||!Number.isSafeInteger(q)||q<=0||!Number.isFinite(r)||r<=0)throw Error('Garment, category, size, bill/received PCS और purchase rate भरें.');if(!row.querySelector('[data-photo]').files.length&&!/^https?:\/\//i.test(x.final_image_url))throw Error('Garment photo भरें.');return{...x,bill_qty:b,received_qty:q,purchase_rate:r,difference_qty:q-b,note_type:q<b?'DEBIT_NOTE':q>b?'CREDIT_NOTE':'MATCHED',note_amount:Math.round(Math.abs(q-b)*r*100)/100,bill_value:b*r,received_value:q*r}});
        if(new Set(entries.map(x=>x.lot_no.toUpperCase())).size!==entries.length)throw Error('हर garment का lot number अलग रखें.');
        const note={supplier_name:supplier,bill_no:bill,purchase_date:date,lines:entries,bill_value:entries.reduce((n,x)=>n+x.bill_value,0),received_value:entries.reduce((n,x)=>n+x.received_value,0)};
        const module=window.RRReadymadeReceipt71;if(!module?.proforma||!module?.shareNow){save(true,e.currentTarget);return}
        const pack=preparedProforma?.key===JSON.stringify(note)?preparedProforma.pack:module.proforma(note,rows.map(r=>{const img=r.querySelector('[data-preview]');return img?.src.startsWith('blob:')?img:null}));
        let sendResult;try{sendResult=module.shareNow(pack.files,pack.png)}catch(error){msg.textContent=error.message;save(true,e.currentTarget);return}
        msg.textContent='Image picker opened. Purchase confirmation is still saving; return here to check success or errors.';save(true,e.currentTarget,sendResult);sendResult.then(r=>{if(r.error)ctx.notice('Image picker नहीं खुला. Saved Proforma JPG पर long-press करके Share करें.');});
      }catch(error){msg.textContent=error.message;save(true,e.currentTarget)}
    };
  }
  async function completeMapping(ctx,c,owner) {
    const m=modal('Complete mapping · '+c.lot_no),body=m.querySelector('[data-body]'),msg=m.querySelector('[data-message]');
    body.innerHTML='<p>Missing: '+esc((c.missing_fields||[]).join(' · '))+'</p>'+lineMarkup({...c,final_image_url:c.image_url})+'<p>Purchase quantity and purchase rate are posted records. Financial correction uses Purchase Return / corrected purchase.</p><p>Final approval uses monthly weighted costing and fixed ₹22/PCS owner margin.</p>';
    ['lot_no','bill_qty','qty','purchase_rate','final_rate'].forEach(k=>body.querySelector('[data-field="'+k+'"]').closest('label').remove());body.querySelector('[data-remove]').remove();body.querySelector('[data-line-total]').remove();body.querySelector('[data-art-balance]').remove();body.querySelector('[data-art-effective]').remove();body.querySelector('[data-refresh-art]').remove();body.querySelector('[data-reload-art]').remove();
    try {const r=await ctx.s.db.from('rr_art_categories').select('id,category_name').eq('is_active',true).order('category_name');if(r.error)throw r.error;const sel=body.querySelector('[data-field="category"]');sel.innerHTML='<option value="">Select existing category</option>'+(r.data||[]).map(x=>'<option>'+esc(x.category_name)+'</option>').join('');sel.value=c.category;sel.disabled=false;}catch(e){msg.textContent='Category master unavailable. Close and retry.';}
    const costing=new URL('real-accounts-costing-v850.html',location.href);costing.searchParams.set('lot',c.lot_no);costing.searchParams.set('data_mode','TEST');
    m.querySelector('[data-footer]').innerHTML='<button data-save-mapping>Save mapping</button>'+(!c.approval_ready?(owner?'<a href="'+esc(costing.href)+'" target="_blank" rel="noopener">Complete monthly costing</a><button data-open-approval>Go to final approval</button>':'<button data-request-approval>Request Super Admin approval</button>'):'');
    body.querySelector('[data-photo]').onchange=e=>{const file=e.target.files[0],im=body.querySelector('[data-preview]');if(file){if(im.dataset.blob)URL.revokeObjectURL(im.dataset.blob);im.dataset.blob=URL.createObjectURL(file);im.src=im.dataset.blob;im.hidden=false;}};
    m.querySelector('[data-save-mapping]').onclick=e=>action(e.currentTarget,msg,async()=>{
      const fields=Object.fromEntries([...body.querySelectorAll('[data-field]')].map(i=>[i.dataset.field,i.value.trim()])),file=body.querySelector('[data-photo]').files[0];
      if(file){if(!file.type.startsWith('image/')||file.size>10*1024*1024)throw Error('Choose an image up to 10 MB.');const path='readymade/test71/'+crypto.randomUUID()+'.'+(file.name.split('.').pop().replace(/[^a-z0-9]/gi,'')||'jpg'),storage=ctx.s.db.storage.from('redzed-media'),up=await storage.upload(path,file,{contentType:file.type,upsert:false});if(up.error)throw up.error;fields.final_image_url=storage.getPublicUrl(path).data.publicUrl;body.querySelector('[data-field="final_image_url"]').value=fields.final_image_url;body.querySelector('[data-photo]').value='';}
      const result=await ctx.rpc('rr_rm_complete_mapping_test71',{p_lot_no:c.lot_no,p_fields:fields});await ctx.refresh();msg.textContent=result.market_ready?'Fully mapped and approved · Ready for Market Window.':'Mapping saved. Remaining: '+(result.missing_fields||[]).join(' · ');
    });
    m.querySelector('[data-request-approval]')?.addEventListener('click',e=>action(e.currentTarget,msg,async()=>{await ctx.rpc('rr_rm_request_approval_test71',{p_lot_no:c.lot_no});msg.textContent='Super Admin follow-up requested. Duplicate requests will not send repeated notifications.';}));
    m.querySelector('[data-open-approval]')?.addEventListener('click',async()=>{m.remove();await ctx.refresh();const a=[...ctx.box.querySelectorAll('[data-lot]')].find(x=>x.dataset.lot===c.lot_no),detail=a?.querySelector('[data-rate]')?.closest('details');if(detail){detail.open=true;detail.scrollIntoView({block:'center',behavior:'smooth'});}});
  }
  function marketUrl(lots=[]) {
    const url=new URL('real-web-window-v9329.html',location.href);
    url.searchParams.set('share_mode','chooser');url.searchParams.set('from','READYMADE');
    (window.RRMarketCustomer71?.get()||[]).forEach(id=>url.searchParams.append('recipient_chat',id));
    lots.forEach(lot=>url.searchParams.append('selected_lot',lot));return url.href;
  }
  function validateMarketSelection(ctx,cards) {
    const bad=[...state.selection].map(lot=>cards.find(c=>String(c.lot_no)===String(lot))).filter(c=>!c||!c.market_ready||!c.approval_ready||!Number.isFinite(Number(c.approved_rate))||Number(c.approved_rate)<=0);
    if(!bad.length)return true;
    const warning=bad.map(c=>{if(!c)return 'Selected garment unavailable. Refresh balance.';const reason=c.missing_fields?.length?'Complete in Working: '+c.missing_fields.join(', ')+'.':c.costing?.costing_complete===false?'Monthly costing pending. Complete costing, then approve a positive sale rate.':!c.approval_ready?'Final sale-rate approval pending. Approve a positive sale rate first.':'Sale rate is zero. Correct and approve a positive sale rate first.';return c.lot_no+': '+reason;}).join('\n');
    ctx.notice(warning);alert(warning);return false;
  }
  async function send(ctx,cards) {
    if(!validateMarketSelection(ctx,cards))return;
    const url=marketUrl([...state.selection]);if(ctx.navigate)ctx.navigate(url);else location.assign(url);
  }
  async function render(ctx, options={}) {
    const viewKey=JSON.stringify([ctx.s.userId,ctx.s.actor?.id,roleOf(ctx.s),window.RR_VIEW_AS_ACTOR_ID,ctx.s.status,ctx.s.search||'',state.category,state.mapping]);
    if(!options.rebuild&&state.viewKey===viewKey&&state.liveBox===ctx.box&&state.liveUpdate&&ctx.box.querySelector('.rm-working')){
      Object.assign(state.liveCtx,ctx);return state.liveUpdate(true);
    }
    const retainWorking=state.viewKey===viewKey&&state.liveBox===ctx.box;
    state.liveUpdate=null;state.viewKey=viewKey;state.liveBox=ctx.box;state.liveCtx=ctx;
    state.liveCleanup?.();state.liveCleanup=null;
    if(ctx.s.status==='OPEN')prefetchSuppliers(ctx.s);
    style();const seq=++state.seq,s=ctx.s,box=ctx.box,viewStatus=s.status,viewSearch=s.search;
    if(viewStatus==='OPEN'&&['OWNER','SUPER_ADMIN','ADMIN','ACCOUNTS'].includes(roleOf(s))){
      box.innerHTML='<section class="card rm-chat-home"><h3>New Readymade Purchase</h3><button data-new>+ New Purchase</button><p data-notice>Saved drafts loading…</p></section>';
      box.querySelector('[data-new]').onclick=()=>purchase(ctx);
    }else if(!retainWorking||!box.querySelector('.rm-working'))box.innerHTML='<div class="card">Readymade garments loading…</div>';
    try{
      const d=options.data||await ctx.rpc('rr_rm_chat_fast_queue_test71',{p_status:viewStatus,p_search:viewSearch||'',p_category:state.category});
      if(seq!==state.seq||!ctx.owned())return;
      s.departmentCountCache.set('READYMADE',{...d.counts,at:Date.now()});
      const privateHeads=['OWNER','SUPER_ADMIN'].includes(roleOf(s));
      const allCards=d.cards||[],cards=allCards.filter(c=>state.mapping==='ALL'||(state.mapping==='READY'?c.market_ready:!c.market_ready)),eligible=new Set(cards.filter(c=>c.available_qty>0&&c.market_ready).map(c=>c.lot_no));state.selection.forEach(l=>{if(!eligible.has(l))state.selection.delete(l)});
      const toolbar=`<label>Mapping status <select data-mapping style="width:100%;padding:10px;border-radius:10px;background:#122536;color:#e4edf5;border:1px solid #35516a">${[['ALL','All cards'],['READY','Fully mapped / Approved'],['PENDING','Mapping / Approval pending']].map(([v,label])=>`<option value="${v}" ${v===state.mapping?'selected':''}>${label} · ${groupCards(allCards.filter(c=>v==='ALL'||(v==='READY'?c.market_ready:!c.market_ready))).length}</option>`).join('')}</select></label><div class="rm-chat-toolbar"><select data-category aria-label="Garment category"><option value="">All categories</option>${d.categories.map(c=>`<option ${c===state.category?'selected':''}>${esc(c)}</option>`).join('')}</select><select data-cols aria-label="Card layout">${[1,2,3].map(n=>`<option value="${n}" ${n===state.cols?'selected':''}>${n} card${n>1?'s':''}</option>`).join('')}</select><button data-refresh aria-label="Refresh balance" title="Refresh balance">↻</button></div>`;
      const draftCard=x=>`<article class="card work-card"><h3>${esc(x.purchase_no)}</h3><p>${esc(x.supplier_name)} · Bill ${esc(x.bill_no)} · ${esc(x.purchase_date)}</p><p>${x.lines.reduce((n,l)=>n+Number(l.qty),0)} PCS · Draft</p><button data-draft-id="${esc(x.purchase_id)}">Continue Purchase</button></article>`;
      const stockCard=c=>{const cost=c.costing||{};return `<article class="rm-chat-card work-card" data-lot="${esc(c.lot_no)}"><header class="rm-card-head"><b>${esc(c.lot_no)}</b><label><input aria-label="Select ${esc(c.lot_no)}" type="checkbox" data-select="${esc(c.lot_no)}" ${state.selection.has(c.lot_no)?'checked':''} ${eligible.has(c.lot_no)?'':'disabled'}></label></header>${/^https?:\/\//i.test(c.image_url||'')?`<button data-image="${esc(c.lot_no)}" aria-label="View ${esc(c.item_name)} image"><img src="${esc(c.image_url)}" alt="${esc(c.item_name)}" loading="lazy"></button>`:'<div class="rm-photo-pending">Photo pending</div>'}<section class="rm-caption"><h4>${esc(c.item_name||'—')}</h4><span class="rm-category-tag">${esc(c.category||'—')}</span><dl>${[['Art No.',c.art_no],['Sizes',c.size_text],['Fabric',c.cloth_name],['Colours',c.colours_text]].map(([label,v])=>`<div><dt>${label}</dt><dd>${esc(String(v??'').trim()||'—')}</dd></div>`).join('')}</dl><p class="rm-caption-note"><small>Caption note</small><br>${esc(String(c.caption_note??'').trim()||'—')}</p><div class="rm-card-rate"><small>Sales rate / PCS</small><b class="${c.approval_ready?'':'rm-pending-rate'}">${c.approval_ready?money(c.approved_rate):'Approval pending'}</b></div><p class="rm-balance" data-lot-balance="${esc(c.lot_no)}">Available balance: <b>${c.display_available_qty??c.available_qty} PCS</b></p><small class="rm-purchased">Purchased ${c.received_qty} PCS</small><p class="rm-caption-note">${c.market_ready?'Ready for Market Window':'Pending: '+esc((c.missing_fields||['Final sale-rate approval']).join(' · '))}</p></section>${!c.market_ready&&d.can_complete_mapping?`<button class="rm-send-card" data-complete="${esc(c.lot_no)}">Complete mapping / approval</button>`:''}${privateHeads&&d.can_view_cost?`<details data-cost-load="${esc(c.stock_id)}"><summary>Owner costing</summary><div data-cost-body>Open to load monthly costing.</div></details>`:''}${privateHeads&&d.can_approve?(c.approval_ready?`<details data-approved-rate><summary>Final sales rate / RRQ</summary><p>Approved final rate: <b>${money(c.approved_rate)}/PCS</b></p><p>Rate approved · Read only</p></details>`:`<details data-cost-load="${esc(c.stock_id)}"><summary>Final sales rate / RRQ</summary><p data-rate-status>${cost.costing_complete?'Rate approval adjusts RRQ on available stock.':'Open to check monthly costing.'}</p><input data-rate="${esc(c.stock_id)}" aria-label="Final sales rate" type="number" min="0.01" value="${esc(c.approved_rate??c.requested_rate??cost.source_rate??'')}"><button data-approve="${esc(c.stock_id)}" ${cost.costing_complete?'':'disabled'}>Approve final rate</button></details>`):''}<button type="button" class="rm-send-card" data-send-selected>Choose customer <span data-count>${state.selection.size}</span></button>${d.can_purchase?`<button type="button" class="rm-send-card" data-receipt="${esc(c.stock_id)}">Proforma DR/CR Note · JPG</button>`:''}${d.can_purchase&&c.available_qty>0?`<details><summary>Purchase Return</summary><input data-return-qty="${esc(c.stock_id)}" aria-label="Purchase return PCS" type="number" min="1" max="${c.available_qty}" step="1" placeholder="Return PCS"><input data-return-reason="${esc(c.stock_id)}" aria-label="Return reason" placeholder="Reason required"><button data-return="${esc(c.stock_id)}">Post Purchase Return</button></details>`:''}</article>`};
      const groupedCard=members=>{
        if(members.length===1||!String(members[0].art_no||'').trim())return stockCard({...members[0],display_available_qty:members[0].art_available_qty});
        const latest=[...members].sort((a,b)=>String(b.purchase_created_at||'').localeCompare(String(a.purchase_created_at||'')))[0];
        const aggregate={...latest,available_qty:latest.art_available_qty??members.reduce((n,c)=>n+Number(c.available_qty||0),0),received_qty:members.reduce((n,c)=>n+Number(c.received_qty||0),0)};
        const template=document.createElement('template');template.innerHTML=stockCard(aggregate);const card=template.content.firstElementChild;
        card.dataset.artGroup=artKey(latest);card.querySelector('.rm-card-head b').textContent='Art '+latest.art_no;
        card.querySelector('.rm-balance').removeAttribute('data-lot-balance');card.querySelector('.rm-balance').dataset.artBalance=artKey(latest);
        card.querySelector('.rm-purchased').textContent=members.length+' purchases · Open Purchase history when needed';
        card.querySelectorAll('details,[data-complete],[data-receipt]').forEach(el=>el.remove());
        const checkbox=card.querySelector('[data-select]');checkbox.removeAttribute('data-select');checkbox.dataset.selectGroup=artKey(latest);checkbox.setAttribute('aria-label','Select Art '+latest.art_no);
        const ready=members.filter(c=>eligible.has(c.lot_no));checkbox.disabled=!ready.length;checkbox.checked=!!ready.length&&ready.every(c=>state.selection.has(c.lot_no));
        const image=card.querySelector('[data-image]');if(image){image.removeAttribute('data-image');image.dataset.imageArt=artKey(latest)}
        const detail=document.createElement('details');detail.dataset.purchaseEntries='';const summary=document.createElement('summary');summary.textContent='Purchase history · '+members.length;detail.appendChild(summary);const picker=document.createElement('select');picker.dataset.purchaseHistorySelect='';picker.setAttribute('aria-label','Choose purchase record');picker.innerHTML=members.map(c=>'<option value="'+esc(c.stock_id)+'">Lot '+esc(c.lot_no)+' · '+Number(c.available_qty)+' PCS · '+esc(c.purchase_created_at?new Date(c.purchase_created_at).toLocaleDateString('en-IN'):'')+'</option>').join('');detail.appendChild(picker);
        for(const c of members){const t=document.createElement('template');t.innerHTML=stockCard(c);const entry=t.content.firstElementChild;entry.className='rm-purchase-entry';entry.dataset.purchaseHistoryStock=c.stock_id;entry.hidden=c.stock_id!==members[0].stock_id;entry.querySelector('.rm-balance').dataset.lotBalance=c.lot_no;detail.appendChild(entry)}
        card.appendChild(detail);return card.outerHTML;
      };
      box.innerHTML=`<section class="card rm-chat-home ${viewStatus==='WORKING'?'rm-working':''}"><h3>${viewStatus==='WORKING'?'Available collection':'Readymade Garments · OPEN'}</h3><p data-notice class="rm-chat-error" aria-live="polite"></p>${viewStatus==='OPEN'?(d.can_purchase?'<article class="card work-card"><h3>New Readymade Purchase</h3><p>Final garment photo · PCS · Supplier · Purchase rate · Final sales rate</p><button data-new>+ New Purchase</button></article>'+d.drafts.map(draftCard).join(''):'<p>Purchase entry is available to Owner/Admin/Accounts. Stock is in WORKING.</p>'):toolbar+'<div class="rm-chat-toolbar rm-selection-bar"><button data-all>Select all</button><button data-send-selected>Choose customer <span data-count>'+state.selection.size+'</span></button><a data-market href="${esc(marketUrl([...state.selection]))}" aria-label="Market Window" title="Market Window">↗</a></div><div class="rm-chat-grid" style="--rm-cols:'+state.cols+'">'+(groupCards(cards).map(groupedCard).join('')||'<p>No Readymade garments found.</p>')+'</div>'}</section>`;
      box.querySelectorAll('[data-purchase-history-select]').forEach(select=>select.onchange=()=>{select.closest('[data-purchase-entries]').querySelectorAll('[data-purchase-history-stock]').forEach(entry=>entry.hidden=entry.dataset.purchaseHistoryStock!==select.value)});
      const notice=box.querySelector('[data-notice]');
      box.querySelector('[data-new]')?.addEventListener('click',()=>purchase(ctx));
      box.querySelectorAll('[data-draft-id]').forEach(b=>b.onclick=()=>purchase(ctx,d.drafts.find(x=>x.purchase_id===b.dataset.draftId)));
      box.querySelector('[data-mapping]')?.addEventListener('change',e=>{state.mapping=e.target.value;ctx.refresh()});
      box.querySelectorAll('[data-complete]').forEach(b=>b.onclick=()=>completeMapping(ctx,cards.find(c=>c.lot_no===b.dataset.complete),privateHeads));
      box.querySelector('[data-category]')?.addEventListener('change',e=>{state.category=e.target.value;ctx.refresh()});
      box.querySelector('[data-cols]')?.addEventListener('change',e=>{state.cols=Number(e.target.value);box.querySelector('.rm-chat-grid').style.setProperty('--rm-cols',state.cols)});
      box.querySelector('[data-refresh]')?.addEventListener('click',()=>ctx.refresh());
      box.querySelectorAll('[data-select]').forEach(i=>i.onchange=()=>{i.checked?state.selection.add(i.dataset.select):state.selection.delete(i.dataset.select);box.querySelectorAll('[data-count]').forEach(n=>n.textContent=state.selection.size);box.querySelector('[data-market]').href=marketUrl([...state.selection]);box.querySelectorAll('[data-select-group]').forEach(g=>{const rows=cards.filter(c=>artKey(c)===g.dataset.selectGroup&&eligible.has(c.lot_no));g.checked=!!rows.length&&rows.every(c=>state.selection.has(c.lot_no))});});
      box.querySelectorAll('[data-select-group]').forEach(i=>i.onchange=()=>{const members=cards.filter(c=>artKey(c)===i.dataset.selectGroup&&eligible.has(c.lot_no));const checked=i.checked;for(const c of members){const child=[...box.querySelectorAll('[data-select]')].find(x=>x.dataset.select===c.lot_no);if(child){child.checked=checked;child.onchange()}}});
      box.querySelectorAll('[data-image-art]').forEach(b=>b.onclick=()=>{const members=cards.filter(c=>artKey(c)===b.dataset.imageArt),c=members[0],m=modal('Art '+c.art_no);m.querySelector('[data-body]').innerHTML='<img src="'+esc(c.image_url)+'" style="width:100%;max-height:65vh;object-fit:contain"><pre style="white-space:pre-wrap">'+esc(caption({...c,available_qty:c.art_available_qty??members.reduce((n,x)=>n+Number(x.available_qty),0)}))+'</pre>'});
      box.querySelector('[data-all]')?.addEventListener('click',()=>{const all=[...box.querySelectorAll('[data-select]:not(:disabled)')],checked=all.length&&all.every(i=>i.checked);all.forEach(i=>{i.checked=!checked;i.onchange()})});
      box.querySelector('[data-market]')?.addEventListener('click',e=>{if(!validateMarketSelection(ctx,cards))e.preventDefault()});
      box.querySelectorAll('[data-send-selected]').forEach(b=>b.addEventListener('click',()=>send(ctx,cards)));
      box.querySelectorAll('[data-image]').forEach(b=>b.onclick=()=>{const c=cards.find(x=>x.lot_no===b.dataset.image),m=modal(c.lot_no);m.querySelector('[data-body]').innerHTML=`<img src="${esc(c.image_url)}" alt="${esc(c.item_name)}" style="width:100%;max-height:65vh;object-fit:contain"><pre style="white-space:pre-wrap">${esc(caption(c))}</pre>`});
      const costJobs=new Map();
      box.querySelectorAll('[data-cost-load]').forEach(details=>details.addEventListener('toggle',async()=>{
        if(!details.open)return;const id=details.dataset.costLoad,c=cards.find(x=>x.stock_id===id),article=details.closest('article');
        if(!costJobs.has(id))costJobs.set(id,ctx.rpc('rr_rm_costing_test71',{p_lot_no:c.lot_no,p_data_mode:'TEST'}).catch(e=>{costJobs.delete(id);throw e}));
        try{
          const cost=await costJobs.get(id);if(!ctx.owned()||!article.isConnected)return;c.costing=cost;
          const body=article.querySelector('[data-cost-body]');if(body)body.innerHTML=cost.purchase_cost_per_pc!=null?`<p>Purchase ${money(cost.purchase_cost_per_pc)} + Salary ${money(cost.salary_per_pc)} + Overhead ${money(cost.overhead_per_pc)} + ₹22 margin</p><p>Base ${money(cost.source_rate)}</p>${(cost.salary_heads||[]).map(h=>`<p>${esc(h.head)} salary ${money(h.per_pc)}/pc</p>`).join('')}${(cost.overhead_heads||[]).map(h=>`<p>${esc(h.label)} ${money(h.per_pc)}/pc</p>`).join('')}`:'Private costing unavailable.';
          const input=article.querySelector('[data-rate]');if(input&&!input.value&&cost.source_rate!=null)input.value=cost.source_rate;
          const button=article.querySelector('[data-approve]');if(button)button.disabled=!cost.costing_complete;
          const status=article.querySelector('[data-rate-status]');if(status)status.textContent=cost.costing_complete?'Costing ready · approval changes RRQ on available PCS.':'Monthly inward values pending · approval blocked.';
        }catch(e){const body=article.querySelector('[data-cost-body]')||article.querySelector('[data-rate-status]');if(body)body.textContent='Costing could not load. Close and reopen to retry.';}
      }));
      box.querySelectorAll('[data-approve]').forEach(b=>b.onclick=()=>action(b,notice,async()=>{const c=cards.find(x=>x.stock_id===b.dataset.approve),rate=Number(box.querySelector(`[data-rate="${CSS.escape(c.stock_id)}"]`).value);if(!Number.isFinite(rate)||rate<=0)throw Error('Valid final rate required.');if(c.approval_ready)throw Error('Final rate is already approved.');const j=await ctx.rpc('rr_rm_approve_rate_test71',{p_lot_no:c.lot_no,p_final_rate:rate,p_reason:'Readymade Real Chat final rate'});c.approval_ready=true;c.approved_rate=rate;const details=b.closest('details');details.removeAttribute('data-cost-load');details.setAttribute('data-approved-rate','');details.innerHTML='<summary>Final sales rate / RRQ</summary><p>Approved final rate: <b>'+money(rate)+'/PCS</b></p><p>Rate approved · Read only</p>';await ctx.refresh();ctx.notice('Approved · RRQ change '+money(j.quota_delta)+' · RRQ balance '+money(j.rrq_balance))}));
      box.querySelectorAll('[data-receipt]').forEach(b=>b.onclick=()=>action(b,notice,async()=>{receiptView(await ctx.rpc('rr_rm_stock_receipt_test71',{p_stock_id:b.dataset.receipt}),ctx)}));
      box.querySelectorAll('[data-return]').forEach(b=>b.onclick=()=>action(b,notice,async()=>{const c=cards.find(x=>x.stock_id===b.dataset.return),qty=Number(box.querySelector(`[data-return-qty="${CSS.escape(c.stock_id)}"]`).value),reason=box.querySelector(`[data-return-reason="${CSS.escape(c.stock_id)}"]`).value.trim();if(!Number.isInteger(qty)||qty<=0||qty>c.available_qty||!reason)throw Error('Return whole PCS within available balance and enter reason.');const fingerprint=JSON.stringify([c.stock_id,qty,reason]);if(!state.returnKeys.has(fingerprint))state.returnKeys.set(fingerprint,crypto.randomUUID());await ctx.rpc('rr_rm_purchase_return_test71',{p_stock_id:c.stock_id,p_qty:qty,p_reason:reason,p_return_date:new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'}),p_idempotency_key:state.returnKeys.get(fingerprint),p_remarks:'Readymade Real Chat'});ctx.changed();await ctx.refresh();ctx.notice('Purchase Return posted · Balance, Accounts and RRQ updated.')}));
      if(viewStatus==='WORKING'){
        const signature=(rows,data)=>JSON.stringify([data.can_purchase,data.can_approve,data.can_view_cost,data.can_complete_mapping,rows.map(c=>[c.stock_id,c.art_no,c.item_name,c.image_url,c.category,c.size_text,c.cloth_name,c.colours_text,c.caption_note,c.approval_ready,c.approved_rate,c.market_ready,c.missing_fields,c.costing?.costing_complete]).sort((a,b)=>String(a[0]).localeCompare(String(b[0])))]);const renderedSignature=signature(cards,d);
        let pending=null;const update=(force=false)=>{if(pending)return pending;pending=refreshLive(force).finally(()=>{pending=null});return pending};const refreshLive=async(force=false)=>{if(seq!==state.seq||!ctx.owned()||(document.hidden&&!force))return;try{const next=await ctx.rpc('rr_rm_chat_fast_queue_test71',{p_status:'WORKING',p_search:viewSearch||'',p_category:state.category});if(seq!==state.seq||!ctx.owned())return;
          const rows=next.cards||[];eligible.clear();rows.filter(c=>c.available_qty>0&&c.market_ready).forEach(c=>eligible.add(c.lot_no));state.selection.forEach(l=>{if(!eligible.has(l))state.selection.delete(l)});for(const c of cards){const fresh=rows.find(x=>x.stock_id===c.stock_id);if(fresh)Object.assign(c,fresh)}
          for(const el of box.querySelectorAll('[data-art-balance]')){const members=rows.filter(c=>artKey(c)===el.dataset.artBalance);const balance=members[0]?.art_available_qty??members.reduce((n,c)=>n+Number(c.available_qty||0),0);el.querySelector('b').textContent=balance+' PCS'}
          for(const el of box.querySelectorAll('[data-lot-balance]')){const c=rows.find(x=>x.lot_no===el.dataset.lotBalance);if(c)el.querySelector('b').textContent=(el.closest('.rm-purchase-entry')?c.available_qty:(c.art_available_qty??c.available_qty))+' PCS'}
          for(const input of box.querySelectorAll('[data-return-qty]')){const c=rows.find(x=>x.stock_id===input.dataset.returnQty);if(c)input.max=c.available_qty}
          for(const i of box.querySelectorAll('[data-select]')){i.disabled=!eligible.has(i.dataset.select);i.checked=state.selection.has(i.dataset.select)}box.querySelectorAll('[data-count]').forEach(n=>n.textContent=state.selection.size);box.querySelector('[data-market]').href=marketUrl([...state.selection]);
          if(signature(rows.filter(c=>state.mapping==='ALL'||(state.mapping==='READY'?c.market_ready:!c.market_ready)),next)!==renderedSignature&&!box.querySelector('details[open]')&&!box.contains(document.activeElement))await render(ctx,{rebuild:true,data:next});
        }catch{if(notice)notice.textContent='Live balance update delayed. Existing cards remain available.'}};state.liveUpdate=update;const timer=setInterval(update,15000);const visible=()=>{if(!document.hidden)update()};document.addEventListener('visibilitychange',visible);state.liveCleanup=()=>{clearInterval(timer);document.removeEventListener('visibilitychange',visible)};
      }
    }catch(e){if(seq===state.seq&&ctx.owned()&&viewStatus==='OPEN'&&box.querySelector('[data-new]')){box.querySelector('[data-notice]').textContent='Saved drafts could not load. New Purchase is available.';return}if(seq===state.seq&&ctx.owned())box.innerHTML='<div class="card">'+esc(e.message||'Readymade could not load.')+' <button data-retry>Retry</button></div>';box.querySelector('[data-retry]')?.addEventListener('click',()=>ctx.refresh())}
  }
  window.RRReadymadeChat={directory,counts,render,caption,roleOf};
})();
