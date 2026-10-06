(() => {
  'use strict';
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money = n => n == null ? '—' : '₹' + Number(n).toLocaleString('en-IN',{maximumFractionDigits:2});
  // Existing CB size-family dropdown authority (rr_cb_cat_def_size_chk).
  const sizeFamilies=['L, XL, XXL','2XL, 3XL, 4XL','3XL, 4XL, 5XL','M, L, XL, XXL','M, L, XL','L, XL','L, XXL','FREE SIZE'];
  const roles = ['OWNER','SUPER_ADMIN','ADMIN','ACCOUNTS','SALES','MANAGER'];
  const roleOf = s => String(window.RR_EFFECTIVE_ROLE ? window.RR_EFFECTIVE_ROLE(s.actor?.role || s.actor?.role_code) : window.RR_VIEW_AS_ROLE || s.actor?.role || s.actor?.role_code || '').toUpperCase();
  const state = {selection:new Set(),category:'',cols:2,seq:0,busy:false,returnKeys:new Map()};
  const caption = c => ['REDZED · '+c.lot_no,c.item_name,c.category,c.art_no && 'Art '+c.art_no,c.size_text && 'Size '+c.size_text,c.cloth_name,c.colours_text && 'Colours '+c.colours_text,c.caption_note,'Available '+c.available_qty+' PCS','Sales rate '+(c.approval_ready ? money(c.approved_rate) : 'Approval pending')].filter(Boolean).join('\n');
  function directory(s) {
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
    .rm-working .rm-chat-card details{margin:0;border-top:1px solid #293e52;padding:10px;font-size:12px;line-height:1.5;color:#b7cbdc}.rm-working .rm-chat-card summary{font-weight:650;cursor:pointer;color:#d0e3f3;font-size:11px}.rm-working .rm-chat-card details input{width:100%;min-width:0;box-sizing:border-box;margin:7px 0 0;padding:8px;border:1px solid #3c5970;border-radius:8px;background:#0b1926;color:#e9f2fa;font:inherit;min-height:36px}.rm-working .rm-chat-card details button{display:block;width:100%;padding:8px;margin:8px 0 0;border:1px solid #4779a8;border-radius:8px;background:#1d4a74;color:#e9f4ff;font:600 11px system-ui;min-height:36px}.rm-working .rm-chat-card button:disabled{opacity:.45;cursor:default}.rm-working .rm-chat-card [data-return]{background:#442e32;border-color:#80515c;color:#ffd9dc}
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
    const field=(key,label,type='text')=>`<label>${label}<input data-field="${key}" type="${type}" value="${esc(x[key]??'')}" ${['qty','purchase_rate'].includes(key)?'min="0.01" step="'+(key==='qty'?'1':'0.01')+'"':''}></label>`;
    return `<section class="rm-chat-line"><div class="rm-fields">${field('lot_no','Lot No. *')}${field('item_name','Garment name *')}<label>Category *<select data-field="category" data-saved-category="${esc(x.category||'')}" disabled><option value="">Loading existing categories…</option></select></label><label>Sizes *<select data-field="size_text"><option value="">Select size family</option>${sizeFamilies.map(v=>`<option value="${esc(v)}" ${v.replace(/[\s,\/]/g,'').toUpperCase()===String(x.size_text||'').replace(/[\s,\/]/g,'').toUpperCase()?'selected':''}>${esc(v)}</option>`).join('')}</select></label>${field('colours_text','Colours')}${field('cloth_name','Cloth / Fabric')}${field('art_no','Art No.')}${field('qty','Final purchase quantity · PCS *','number')}${field('purchase_rate','Purchase rate / PCS *','number')}${field('final_rate','Final sales rate / PCS · optional','number')}</div><label>Final garment photo *<input data-photo type="file" accept="image/*"></label><img data-preview ${x.final_image_url?'':'hidden'} src="${esc(x.final_image_url||'')}" alt="Final garment preview"><label>Image URL<input data-field="final_image_url" type="url" value="${esc(x.final_image_url||'')}" placeholder="Upload photo or enter image URL"></label><label>Caption note<textarea data-field="caption_note">${esc(x.caption_note||'')}</textarea></label><p data-line-total>Purchase value —</p><button type="button" data-remove>Remove garment</button></section>`;
  }
  function purchase(ctx,draft=null) {
    const m=modal(draft?'Continue Readymade Purchase':'New Readymade Purchase'),body=m.querySelector('[data-body]'),msg=m.querySelector('[data-message]');let pid=draft?.purchase_id||null;
    body.innerHTML=`<div class="rm-fields"><label>Supplier / Seller *<select data-supplier disabled><option value="">Loading existing suppliers…</option></select></label><label>Supplier bill number *<input data-bill value="${esc(draft?.bill_no||'')}"></label><label>Purchase / bill date *<input data-date type="date" value="${esc(draft?.purchase_date||new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'}))}"></label></div><div data-lines></div><button type="button" data-add>Add garment</button><section class="card" data-costing-status><b>Monthly costing / Final rate</b><p data-cost-month></p><p>Purchase cost + monthly weighted Sales/Admin/Accounts salary + applicable overhead = total cost.</p>${['OWNER','SUPER_ADMIN'].includes(roleOf(ctx.s))?'<p>Fixed Owner margin: ₹22/PCS. Base sales rate = total cost + ₹22.</p>':''}<p>Actual weighted base rate is calculated after purchase confirmation and shown in WORKING. Missing monthly values keep approval pending. Final-rate approval changes RRQ on available PCS.</p></section>`;
    const supplierSelect=body.querySelector('[data-supplier]');
    let supplierNames=new Set();
    async function loadSuppliers(){
      supplierSelect.disabled=true;
      try{
        const result=await ctx.s.db.from('rr_suppliers').select('id,supplier_name').eq('is_active',true).order('supplier_name');
        if(result.error)throw result.error;
        const rows=(result.data||[]).filter(x=>String(x.supplier_name||'').trim());
        supplierNames=new Set(rows.map(x=>x.supplier_name));
        supplierSelect.innerHTML='<option value="">Select existing supplier</option>'+rows.map(x=>`<option value="${esc(x.supplier_name)}">${esc(x.supplier_name)}</option>`).join('');
        supplierSelect.value=supplierNames.has(draft?.supplier_name)?draft.supplier_name:'';
        supplierSelect.disabled=false;
        if(!rows.length)msg.textContent='No active suppliers in Supplier Master.';
        else if(draft?.supplier_name&&!supplierNames.has(draft.supplier_name))msg.textContent='Saved supplier is inactive or unavailable. Select an active supplier.';
      }catch(e){msg.textContent='Supplier list could not load. Tap Retry suppliers.';supplierSelect.innerHTML='<option value="">Suppliers unavailable</option>';}
    }
    const retry=document.createElement('button');retry.type='button';retry.textContent='Retry suppliers';retry.dataset.retrySuppliers='';retry.onclick=()=>loadSuppliers();supplierSelect.parentElement.appendChild(retry);
    loadSuppliers();
    const lines=body.querySelector('[data-lines]');let categories=[],categoryDefaults=new Map(),mastersReady=false;
    function fillCategory(row){
      const sel=row.querySelector('[data-field="category"]'),saved=sel.dataset.savedCategory;
      sel.innerHTML='<option value="">Select existing category</option>'+categories.map(c=>`<option value="${esc(c.category_name)}">${esc(c.category_name)}</option>`).join('');
      sel.value=categories.some(c=>c.category_name===saved)?saved:'';sel.disabled=!mastersReady;
      sel.onchange=()=>{const cat=categories.find(c=>c.category_name===sel.value),def=categoryDefaults.get(String(cat?.id)),sizes=row.querySelector('[data-field="size_text"]');if(def){const v=sizeFamilies.find(x=>x.replace(/\s/g,'')===String(def.default_size_family).replace(/\s/g,''));if(v)sizes.value=v}};
    }
    function addLine(x={}){lines.insertAdjacentHTML('beforeend',lineMarkup(x));if(mastersReady)fillCategory(lines.lastElementChild)}
    (draft?.lines?.length?draft.lines:[{}]).forEach(addLine);
    async function loadCategories(){
      try{
        const [result,defaults]=await Promise.all([ctx.s.db.from('rr_art_categories').select('id,category_code,category_name').eq('is_active',true).order('category_name'),ctx.rpc('rr_cb_category_defaults_get_v1',{})]);
        if(result.error)throw result.error;categories=result.data||[];categoryDefaults=new Map((defaults?.rows||[]).map(x=>[String(x.art_category_id),x]));mastersReady=true;
        [...lines.children].forEach(fillCategory);if(!categories.length)msg.textContent='No active garment categories in existing Category Master.';
      }catch(e){msg.textContent='Category mapping could not load. Tap Retry categories.';}
    }
    body.querySelector('[data-add]').onclick=()=>addLine();
    const retryCategories=document.createElement('button');retryCategories.type='button';retryCategories.textContent='Retry categories';retryCategories.onclick=loadCategories;body.querySelector('[data-add]').after(retryCategories);loadCategories();
    const month=()=>{body.querySelector('[data-cost-month]').textContent='Costing month: '+(body.querySelector('[data-date]').value.slice(0,7)||'Select bill date')};month();body.querySelector('[data-date]').addEventListener('change',month);
    body.addEventListener('click',e=>{if(e.target.closest('[data-remove]')&&lines.children.length>1)e.target.closest('.rm-chat-line').remove()});
    body.addEventListener('input',e=>{const row=e.target.closest('.rm-chat-line');if(!row)return;const qty=Number(row.querySelector('[data-field="qty"]').value),rate=Number(row.querySelector('[data-field="purchase_rate"]').value);row.querySelector('[data-line-total]').textContent='Purchase value '+money(qty*rate);if(e.target.dataset.field==='final_image_url'){const img=row.querySelector('[data-preview]');img.src=/^https?:\/\//.test(e.target.value)?e.target.value:'';img.hidden=!img.src}});
    body.addEventListener('change',e=>{if(!e.target.matches('[data-photo]'))return;const row=e.target.closest('.rm-chat-line'),file=e.target.files[0];if(!file)return;const img=row.querySelector('[data-preview]');if(img.dataset.blob)URL.revokeObjectURL(img.dataset.blob);img.dataset.blob=URL.createObjectURL(file);img.src=img.dataset.blob;img.hidden=false});
    m.querySelector('[data-footer]').innerHTML='<button type="button" data-draft>Save draft</button><button type="button" data-post>Save & Confirm Purchase</button>';
    async function save(post,button) {
      await action(button,msg,async()=>{
        const supplier=body.querySelector('[data-supplier]').value.trim(),bill=body.querySelector('[data-bill]').value.trim(),date=body.querySelector('[data-date]').value;
        if(supplierSelect.disabled||!supplierNames.has(supplier))throw Error('Select an existing active supplier from the dropdown.');
        if(!bill||!date)throw Error('Supplier bill number and date required.');
        const payload=[];
        for(const row of lines.children){
          const x=Object.fromEntries([...row.querySelectorAll('[data-field]')].map(i=>[i.dataset.field,i.value.trim()]));x.qty=Number(x.qty);x.purchase_rate=Number(x.purchase_rate);x.final_rate=x.final_rate===''?null:Number(x.final_rate);x.markup_mode='DEFAULT_22';
          if(!mastersReady||!categories.some(c=>c.category_name===x.category)||!sizeFamilies.includes(x.size_text))throw Error('Select existing category and size family.');
          if(!x.lot_no||!x.item_name||!x.category||!Number.isInteger(x.qty)||x.qty<=0||!Number.isFinite(x.purchase_rate)||x.purchase_rate<=0)throw Error('Lot, garment, category, whole PCS and positive purchase rate required.');
          if(x.final_rate!=null&&(!Number.isFinite(x.final_rate)||x.final_rate<0))throw Error('Valid final sales rate required.');
          const file=row.querySelector('[data-photo]').files[0];
          if(file){if(!file.type.startsWith('image/')||file.size>10*1024*1024)throw Error('Choose an image up to 10 MB.');const path='readymade/test71/'+crypto.randomUUID()+'.'+(file.name.split('.').pop().replace(/[^a-z0-9]/gi,'')||'jpg');const storage=ctx.s.db.storage.from('redzed-media'),up=await storage.upload(path,file,{contentType:file.type,upsert:false});if(up.error)throw up.error;x.final_image_url=storage.getPublicUrl(path).data.publicUrl;row.querySelector('[data-field="final_image_url"]').value=x.final_image_url;row.querySelector('[data-photo]').value='';}
          if(!/^https?:\/\//i.test(x.final_image_url))throw Error('Final garment photo required.');payload.push(x);
        }
        if(new Set(payload.map(x=>x.lot_no.toUpperCase())).size!==payload.length)throw Error('Each garment lot number must be unique.');
        const j=await ctx.rpc('rr_rm_chat_save_test71',{p_purchase_id:pid,p_supplier_name:supplier,p_bill_no:bill,p_purchase_date:date,p_lines:payload,p_post:post});pid=j.purchase_id;
        if(post){m.remove();state.selection.clear();ctx.s.status='WORKING';ctx.s.userStatusLock='WORKING';ctx.changed();await ctx.refresh();ctx.notice('Purchase confirmed · Stock and Accounts updated.'+(j.rate_notes?.length?' '+j.rate_notes.join(' · '):''));}
        else{msg.textContent='Draft saved. Continue here or reopen from OPEN.';ctx.s.departmentCountCache.delete('READYMADE');}
      });
    }
    m.querySelector('[data-draft]').onclick=e=>save(false,e.currentTarget);m.querySelector('[data-post]').onclick=e=>save(true,e.currentTarget);
  }
  function marketUrl(lots=[]) {
    const url=new URL('real-web-window-v9329.html',location.href);
    url.searchParams.set('share_mode','chooser');url.searchParams.set('from','READYMADE');
    lots.forEach(lot=>url.searchParams.append('selected_lot',lot));return url.href;
  }
  async function send(ctx,cards) {
    const chosen=cards.filter(c=>state.selection.has(c.lot_no)&&c.available_qty>0);
    if(!chosen.length){ctx.notice('Select garments with available stock.');return}
    const pending=chosen.filter(c=>!c.approval_ready);
    const m=modal('Send Readymade Collection'),body=m.querySelector('[data-body]'),msg=m.querySelector('[data-message]');
    body.innerHTML=`<p>${chosen.length} selected garments · image + caption collection</p>${pending.length?`<p>Final-rate approval pending: ${esc(pending.map(c=>c.lot_no).join(', '))}. Internal sales collection needs Super Admin approval. Outside preview uses the existing Market Window flow.</p>`:''}<a class="btn" data-outside href="${esc(marketUrl(chosen.map(c=>c.lot_no)))}">Outside / WhatsApp · Market Window</a><label>Search customer<input data-search type="search"></label><div data-customers>Loading customers…</div>`;
    try{
      const contacts=await ctx.rpc('rr_chat_staff_inbox_v9434',{});
      body.querySelector('[data-customers]').innerHTML=(contacts||[]).map(c=>`<label class="rm-chat-customer" data-name="${esc(c.customer_name)}"><input type="checkbox" data-chat="${esc(c.chat_id)}"><span>${esc(c.customer_name||'Customer')}</span></label>`).join('')||'No customer chats available.';
      body.querySelector('[data-search]').oninput=e=>body.querySelectorAll('[data-name]').forEach(row=>row.hidden=!row.dataset.name.toLowerCase().includes(e.target.value.toLowerCase()));
      m.querySelector('[data-footer]').innerHTML='<button type="button" data-send>Send selected collection</button>';
      m.querySelector('[data-send]').onclick=e=>action(e.currentTarget,msg,async()=>{
        if(pending.length)throw Error('Final-rate approval pending: '+pending.map(c=>c.lot_no).join(', ')+'. Ask Super Admin to approve before sending internally.');
        const selected=[...body.querySelectorAll('[data-chat]:checked')];if(!selected.length)throw Error('Select customer first.');const reports=[];
        for(const contact of selected){
          try{
            let off=0,context,eligible=new Set();
            for(;;){const page=await ctx.rpc('rr_sales_collection_cards_test71',{p_chat_id:contact.dataset.chat,p_limit:150,p_offset:off});context=page.context;(page.rows||[]).forEach(c=>eligible.add(String(c.lot_no).toUpperCase()));if(page.rows.length<150)break;off+=150;}
            const lots=chosen.map(c=>c.lot_no).filter(l=>eligible.has(l.toUpperCase()));
            if(!lots.length){reports.push(contact.closest('[data-name]').dataset.name+': no new eligible designs');continue}
            await ctx.rpc('rr_sales_collection_send_test71',{p_chat_id:contact.dataset.chat,p_customer_id:context.customer_id,p_collection_cycle_id:context.collection_cycle_id,p_requirement_id:context.requirement_id,p_lots:lots,p_origin:new URL(window.RR_CUSTOMER_SHARE_BASE||'https://redzed-customer-collection.jggfab2011.chatgpt.site/').origin});reports.push(contact.closest('[data-name]').dataset.name+': '+lots.length+' sent');
          }catch(error){reports.push(contact.closest('[data-name]').dataset.name+': '+error.message)}
        }
        msg.textContent=reports.join('\n');
      });
    }catch(e){msg.textContent=e.message}
  }
  async function render(ctx) {
    style();const seq=++state.seq,s=ctx.s,box=ctx.box,viewStatus=s.status,viewSearch=s.search;
    if(viewStatus==='OPEN'&&['OWNER','SUPER_ADMIN','ADMIN','ACCOUNTS'].includes(roleOf(s))){
      box.innerHTML='<section class="card rm-chat-home"><h3>New Readymade Purchase</h3><button data-new>+ New Purchase</button><p data-notice>Saved drafts loading…</p></section>';
      box.querySelector('[data-new]').onclick=()=>purchase(ctx);
    }else box.innerHTML='<div class="card">Readymade garments loading…</div>';
    try{
      const d=await ctx.rpc('rr_rm_chat_fast_queue_test71',{p_status:viewStatus,p_search:viewSearch||'',p_category:state.category});
      if(seq!==state.seq||!ctx.owned())return;
      s.departmentCountCache.set('READYMADE',{...d.counts,at:Date.now()});
      const privateHeads=['OWNER','SUPER_ADMIN'].includes(roleOf(s));
      const cards=d.cards||[],eligible=new Set(cards.filter(c=>c.available_qty>0).map(c=>c.lot_no));state.selection.forEach(l=>{if(!eligible.has(l))state.selection.delete(l)});
      const toolbar=`<div class="rm-chat-toolbar"><select data-category aria-label="Garment category"><option value="">All categories</option>${d.categories.map(c=>`<option ${c===state.category?'selected':''}>${esc(c)}</option>`).join('')}</select><select data-cols aria-label="Card layout">${[1,2,3].map(n=>`<option value="${n}" ${n===state.cols?'selected':''}>${n} card${n>1?'s':''}</option>`).join('')}</select><button data-refresh aria-label="Refresh balance" title="Refresh balance">↻</button></div>`;
      const draftCard=x=>`<article class="card work-card"><h3>${esc(x.purchase_no)}</h3><p>${esc(x.supplier_name)} · Bill ${esc(x.bill_no)} · ${esc(x.purchase_date)}</p><p>${x.lines.reduce((n,l)=>n+Number(l.qty),0)} PCS · Draft</p><button data-draft-id="${esc(x.purchase_id)}">Continue Purchase</button></article>`;
      const stockCard=c=>{const cost=c.costing||{};return `<article class="rm-chat-card work-card" data-lot="${esc(c.lot_no)}"><header class="rm-card-head"><b>${esc(c.lot_no)}</b><label><input aria-label="Select ${esc(c.lot_no)}" type="checkbox" data-select="${esc(c.lot_no)}" ${state.selection.has(c.lot_no)?'checked':''} ${eligible.has(c.lot_no)?'':'disabled'}></label></header>${/^https?:\/\//i.test(c.image_url||'')?`<button data-image="${esc(c.lot_no)}" aria-label="View ${esc(c.item_name)} image"><img src="${esc(c.image_url)}" alt="${esc(c.item_name)}" loading="lazy"></button>`:'<div class="rm-photo-pending">Photo pending</div>'}<section class="rm-caption"><h4>${esc(c.item_name)}</h4><span class="rm-category-tag">${esc(c.category||'Uncategorised')}</span><dl>${[['Art No.',c.art_no],['Sizes',c.size_text],['Fabric',c.cloth_name],['Colours',c.colours_text]].filter(([,v])=>v).map(([label,v])=>`<div><dt>${label}</dt><dd>${esc(v)}</dd></div>`).join('')}</dl>${c.caption_note?`<p class="rm-caption-note">${esc(c.caption_note)}</p>`:''}<div class="rm-card-rate"><small>Sales rate / PCS</small><b class="${c.approval_ready?'':'rm-pending-rate'}">${c.approval_ready?money(c.approved_rate):'Approval pending'}</b></div><p class="rm-balance">Available balance: <b>${c.available_qty} PCS</b></p><small class="rm-purchased">Purchased ${c.received_qty} PCS</small></section>${privateHeads&&d.can_view_cost?`<details data-cost-load="${esc(c.stock_id)}"><summary>Owner costing</summary><div data-cost-body>Open to load monthly costing.</div></details>`:''}${privateHeads&&d.can_approve?(c.approval_ready?`<details data-approved-rate><summary>Final sales rate / RRQ</summary><p>Approved final rate: <b>${money(c.approved_rate)}/PCS</b></p><p>Rate approved · Read only</p></details>`:`<details data-cost-load="${esc(c.stock_id)}"><summary>Final sales rate / RRQ</summary><p data-rate-status>${cost.costing_complete?'Rate approval adjusts RRQ on available stock.':'Open to check monthly costing.'}</p><input data-rate="${esc(c.stock_id)}" aria-label="Final sales rate" type="number" min="0" value="${esc(c.approved_rate??c.requested_rate??cost.source_rate??'')}"><button data-approve="${esc(c.stock_id)}" ${cost.costing_complete?'':'disabled'}>Approve final rate</button></details>`):''}${d.can_purchase&&c.available_qty>0?`<details><summary>Purchase Return</summary><input data-return-qty="${esc(c.stock_id)}" aria-label="Purchase return PCS" type="number" min="1" max="${c.available_qty}" step="1" placeholder="Return PCS"><input data-return-reason="${esc(c.stock_id)}" aria-label="Return reason" placeholder="Reason required"><button data-return="${esc(c.stock_id)}">Post Purchase Return</button></details>`:''}</article>`};
      box.innerHTML=`<section class="card rm-chat-home ${viewStatus==='WORKING'?'rm-working':''}"><h3>${viewStatus==='WORKING'?'Available collection':'Readymade Garments · OPEN'}</h3><p data-notice class="rm-chat-error" aria-live="polite"></p>${viewStatus==='OPEN'?(d.can_purchase?'<article class="card work-card"><h3>New Readymade Purchase</h3><p>Final garment photo · PCS · Supplier · Purchase rate · Final sales rate</p><button data-new>+ New Purchase</button></article>'+d.drafts.map(draftCard).join(''):'<p>Purchase entry is available to Owner/Admin/Accounts. Stock is in WORKING.</p>'):toolbar+'<div class="rm-chat-toolbar rm-selection-bar"><button data-all>Select all</button><button data-send-selected>Send selected <span data-count>'+state.selection.size+'</span></button><a data-market href="${esc(marketUrl([...state.selection]))}" aria-label="Market Window" title="Market Window">↗</a></div><div class="rm-chat-grid" style="--rm-cols:'+state.cols+'">'+(cards.map(stockCard).join('')||'<p>No Readymade garments found.</p>')+'</div>'}</section>`;
      const notice=box.querySelector('[data-notice]');
      box.querySelector('[data-new]')?.addEventListener('click',()=>purchase(ctx));
      box.querySelectorAll('[data-draft-id]').forEach(b=>b.onclick=()=>purchase(ctx,d.drafts.find(x=>x.purchase_id===b.dataset.draftId)));
      box.querySelector('[data-category]')?.addEventListener('change',e=>{state.category=e.target.value;ctx.refresh()});
      box.querySelector('[data-cols]')?.addEventListener('change',e=>{state.cols=Number(e.target.value);box.querySelector('.rm-chat-grid').style.setProperty('--rm-cols',state.cols)});
      box.querySelector('[data-refresh]')?.addEventListener('click',()=>ctx.refresh());
      box.querySelectorAll('[data-select]').forEach(i=>i.onchange=()=>{i.checked?state.selection.add(i.dataset.select):state.selection.delete(i.dataset.select);box.querySelector('[data-count]').textContent=state.selection.size;box.querySelector('[data-market]').href=marketUrl([...state.selection]);});
      box.querySelector('[data-all]')?.addEventListener('click',()=>{const all=[...box.querySelectorAll('[data-select]:not(:disabled)')],checked=all.length&&all.every(i=>i.checked);all.forEach(i=>{i.checked=!checked;i.onchange()})});
      box.querySelector('[data-send-selected]')?.addEventListener('click',()=>send(ctx,cards));
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
      box.querySelectorAll('[data-approve]').forEach(b=>b.onclick=()=>action(b,notice,async()=>{const c=cards.find(x=>x.stock_id===b.dataset.approve),rate=Number(box.querySelector(`[data-rate="${CSS.escape(c.stock_id)}"]`).value);if(!Number.isFinite(rate)||rate<0)throw Error('Valid final rate required.');if(c.approval_ready)throw Error('Final rate is already approved.');const j=await ctx.rpc('rr_rm_approve_rate_test71',{p_lot_no:c.lot_no,p_final_rate:rate,p_reason:'Readymade Real Chat final rate'});c.approval_ready=true;c.approved_rate=rate;const details=b.closest('details');details.removeAttribute('data-cost-load');details.setAttribute('data-approved-rate','');details.innerHTML='<summary>Final sales rate / RRQ</summary><p>Approved final rate: <b>'+money(rate)+'/PCS</b></p><p>Rate approved · Read only</p>';await ctx.refresh();ctx.notice('Approved · RRQ change '+money(j.quota_delta)+' · RRQ balance '+money(j.rrq_balance))}));
      box.querySelectorAll('[data-return]').forEach(b=>b.onclick=()=>action(b,notice,async()=>{const c=cards.find(x=>x.stock_id===b.dataset.return),qty=Number(box.querySelector(`[data-return-qty="${CSS.escape(c.stock_id)}"]`).value),reason=box.querySelector(`[data-return-reason="${CSS.escape(c.stock_id)}"]`).value.trim();if(!Number.isInteger(qty)||qty<=0||qty>c.available_qty||!reason)throw Error('Return whole PCS within available balance and enter reason.');const fingerprint=JSON.stringify([c.stock_id,qty,reason]);if(!state.returnKeys.has(fingerprint))state.returnKeys.set(fingerprint,crypto.randomUUID());await ctx.rpc('rr_rm_purchase_return_test71',{p_stock_id:c.stock_id,p_qty:qty,p_reason:reason,p_return_date:new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'}),p_idempotency_key:state.returnKeys.get(fingerprint),p_remarks:'Readymade Real Chat'});ctx.changed();await ctx.refresh();ctx.notice('Purchase Return posted · Balance, Accounts and RRQ updated.')}));
    }catch(e){if(seq===state.seq&&ctx.owned()&&viewStatus==='OPEN'&&box.querySelector('[data-new]')){box.querySelector('[data-notice]').textContent='Saved drafts could not load. New Purchase is available.';return}if(seq===state.seq&&ctx.owned())box.innerHTML='<div class="card">'+esc(e.message||'Readymade could not load.')+' <button data-retry>Retry</button></div>';box.querySelector('[data-retry]')?.addEventListener('click',()=>ctx.refresh())}
  }
  window.RRReadymadeChat={directory,counts,render,caption,roleOf};
})();
