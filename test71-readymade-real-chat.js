(() => {
  'use strict';
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money = n => n == null ? '—' : '₹' + Number(n).toLocaleString('en-IN',{maximumFractionDigits:2});
  const roles = ['OWNER','SUPER_ADMIN','ADMIN','ACCOUNTS','SALES','MANAGER'];
  const roleOf = s => String(window.RR_EFFECTIVE_ROLE ? window.RR_EFFECTIVE_ROLE(s.actor?.role || s.actor?.role_code) : window.RR_VIEW_AS_ROLE || s.actor?.role || s.actor?.role_code || '').toUpperCase();
  const state = {selection:new Set(),category:'',cols:2,seq:0,busy:false,returnKeys:new Map()};
  const caption = c => ['REDZED · '+c.lot_no,c.item_name,c.category,c.art_no && 'Art '+c.art_no,c.size_text && 'Size '+c.size_text,c.cloth_name,c.colours_text && 'Colours '+c.colours_text,c.caption_note,'Available '+c.available_qty+' PCS','Sales rate '+(c.approval_ready ? money(c.approved_rate) : 'Approval pending')].filter(Boolean).join('\n');
  function directory(s) {
    s.departments = s.departments.filter(d => d.department_code !== 'READYMADE');
    if (roles.includes(roleOf(s))) s.departments.unshift({department_code:'READYMADE',department_name:'Readymade Garments',workers:[],staff:[],worker_count:0,staff_count:0});
  }
  async function counts(rpc) { return (await rpc('rr_rm_chat_queue_test71',{})).counts; }
  function style() {
    if(document.getElementById('rmChatStyle'))return;
    const el=document.createElement('style');el.id='rmChatStyle';el.textContent=`
    .rm-chat-toolbar{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin:12px 0}.rm-chat-toolbar select{max-width:100%}
    .rm-chat-grid{display:grid;grid-template-columns:repeat(var(--rm-cols,2),minmax(0,1fr));gap:12px}.rm-chat-card{min-width:0;padding:12px;border:1px solid #355066;border-radius:14px;background:#102131}.rm-chat-card img{width:100%;height:210px;object-fit:contain;background:#08121c;border-radius:10px}.rm-chat-card pre{white-space:pre-wrap;overflow-wrap:anywhere;font:inherit;line-height:1.5}.rm-chat-card label{display:flex;gap:8px;align-items:center}.rm-chat-card input[type=checkbox]{width:22px;height:22px}.rm-chat-card .rm-balance{font-size:18px;color:#a7edc3}.rm-chat-card input{max-width:100%;box-sizing:border-box}.rm-chat-card details{margin:10px 0}.rm-chat-card button{margin:5px 2px;white-space:normal}
    .rm-chat-modal{position:fixed;inset:0;background:#000b;z-index:2147483600;display:flex;justify-content:center;align-items:center;padding:12px}.rm-chat-sheet{background:#102131;color:#eef5ff;width:min(760px,100%);max-height:92dvh;overflow:auto;border:1px solid #48617a;border-radius:16px;padding:16px;box-sizing:border-box}.rm-chat-sheet header{display:flex;gap:12px;justify-content:space-between;align-items:center}.rm-chat-sheet label{display:grid;gap:5px;margin:10px 0}.rm-chat-sheet input,.rm-chat-sheet textarea,.rm-chat-sheet select{width:100%;box-sizing:border-box;background:#091824;color:#fff;border:1px solid #48617a;border-radius:8px;padding:10px;min-height:42px;font:inherit}.rm-chat-sheet .rm-fields{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.rm-chat-line{border:1px solid #39516a;padding:10px;border-radius:12px;margin:12px 0}.rm-chat-line img{max-width:100%;height:160px;object-fit:contain}.rm-chat-sheet footer{position:sticky;bottom:-16px;background:#102131;padding:12px 0;display:flex;gap:8px;flex-wrap:wrap}.rm-chat-error{white-space:pre-wrap;color:#ffd894;padding:10px 0}.rm-chat-customer{display:flex!important;grid-template-columns:22px 1fr;align-items:center;gap:10px!important}.rm-chat-customer input{width:22px!important;min-height:22px!important}.rm-chat-sheet [hidden]{display:none!important}
    @media(max-width:520px){.rm-chat-grid{gap:8px}.rm-chat-card{padding:8px}.rm-chat-card img{height:160px}.rm-chat-sheet .rm-fields{grid-template-columns:1fr}.rm-chat-modal{padding:5px}}`;
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
    return `<section class="rm-chat-line"><div class="rm-fields">${field('lot_no','Lot No. *')}${field('item_name','Garment name *')}${field('category','Category *')}${field('size_text','Sizes')}${field('colours_text','Colours')}${field('cloth_name','Cloth / Fabric')}${field('art_no','Art No.')}${field('qty','Final purchase quantity · PCS *','number')}${field('purchase_rate','Purchase rate / PCS *','number')}${field('final_rate','Final sales rate / PCS · optional','number')}</div><label>Final garment photo *<input data-photo type="file" accept="image/*"></label><img data-preview ${x.final_image_url?'':'hidden'} src="${esc(x.final_image_url||'')}" alt="Final garment preview"><label>Image URL<input data-field="final_image_url" type="url" value="${esc(x.final_image_url||'')}" placeholder="Upload photo or enter image URL"></label><label>Caption note<textarea data-field="caption_note">${esc(x.caption_note||'')}</textarea></label><p data-line-total>Purchase value —</p><button type="button" data-remove>Remove garment</button></section>`;
  }
  function purchase(ctx,draft=null) {
    const m=modal(draft?'Continue Readymade Purchase':'New Readymade Purchase'),body=m.querySelector('[data-body]'),msg=m.querySelector('[data-message]');let pid=draft?.purchase_id||null;
    body.innerHTML=`<div class="rm-fields"><label>Supplier / Seller *<input data-supplier value="${esc(draft?.supplier_name||'')}"></label><label>Supplier bill number *<input data-bill value="${esc(draft?.bill_no||'')}"></label><label>Purchase / bill date *<input data-date type="date" value="${esc(draft?.purchase_date||new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'}))}"></label></div><div data-lines></div><button type="button" data-add>Add garment</button><p>Final rate follows existing monthly weighted costing and RRQ approval. Missing costing stays pending. ${['OWNER','SUPER_ADMIN'].includes(roleOf(ctx.s))?'Owner margin remains ₹22/PCS.':''}</p>`;
    const lines=body.querySelector('[data-lines]');(draft?.lines?.length?draft.lines:[{}]).forEach(x=>lines.insertAdjacentHTML('beforeend',lineMarkup(x)));
    body.querySelector('[data-add]').onclick=()=>lines.insertAdjacentHTML('beforeend',lineMarkup());
    body.addEventListener('click',e=>{if(e.target.closest('[data-remove]')&&lines.children.length>1)e.target.closest('.rm-chat-line').remove()});
    body.addEventListener('input',e=>{const row=e.target.closest('.rm-chat-line');if(!row)return;const qty=Number(row.querySelector('[data-field="qty"]').value),rate=Number(row.querySelector('[data-field="purchase_rate"]').value);row.querySelector('[data-line-total]').textContent='Purchase value '+money(qty*rate);if(e.target.dataset.field==='final_image_url'){const img=row.querySelector('[data-preview]');img.src=/^https?:\/\//.test(e.target.value)?e.target.value:'';img.hidden=!img.src}});
    body.addEventListener('change',e=>{if(!e.target.matches('[data-photo]'))return;const row=e.target.closest('.rm-chat-line'),file=e.target.files[0];if(!file)return;const img=row.querySelector('[data-preview]');if(img.dataset.blob)URL.revokeObjectURL(img.dataset.blob);img.dataset.blob=URL.createObjectURL(file);img.src=img.dataset.blob;img.hidden=false});
    m.querySelector('[data-footer]').innerHTML='<button type="button" data-draft>Save draft</button><button type="button" data-post>Save & Confirm Purchase</button>';
    async function save(post,button) {
      await action(button,msg,async()=>{
        const supplier=body.querySelector('[data-supplier]').value.trim(),bill=body.querySelector('[data-bill]').value.trim(),date=body.querySelector('[data-date]').value;
        if(!supplier||!bill||!date)throw Error('Supplier, bill number and date required.');
        const payload=[];
        for(const row of lines.children){
          const x=Object.fromEntries([...row.querySelectorAll('[data-field]')].map(i=>[i.dataset.field,i.value.trim()]));x.qty=Number(x.qty);x.purchase_rate=Number(x.purchase_rate);x.final_rate=x.final_rate===''?null:Number(x.final_rate);x.markup_mode='DEFAULT_22';
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
  async function send(ctx,cards) {
    const chosen=cards.filter(c=>state.selection.has(c.lot_no)&&c.approval_ready&&c.available_qty>0);
    if(!chosen.length){ctx.notice('Select approved garments with available stock.');return}
    const m=modal('Send Readymade Collection'),body=m.querySelector('[data-body]'),msg=m.querySelector('[data-message]');
    body.innerHTML=`<p>${chosen.length} selected garments · image + caption collection</p><label>Search customer<input data-search type="search"></label><div data-customers>Loading customers…</div>`;
    try{
      const contacts=await ctx.rpc('rr_chat_staff_inbox_v9434',{});
      body.querySelector('[data-customers]').innerHTML=(contacts||[]).map(c=>`<label class="rm-chat-customer" data-name="${esc(c.customer_name)}"><input type="checkbox" data-chat="${esc(c.chat_id)}"><span>${esc(c.customer_name||'Customer')}</span></label>`).join('')||'No customer chats available.';
      body.querySelector('[data-search]').oninput=e=>body.querySelectorAll('[data-name]').forEach(row=>row.hidden=!row.dataset.name.toLowerCase().includes(e.target.value.toLowerCase()));
      m.querySelector('[data-footer]').innerHTML='<button type="button" data-send>Send selected collection</button>';
      m.querySelector('[data-send]').onclick=e=>action(e.currentTarget,msg,async()=>{
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
    box.innerHTML='<div class="card">Readymade garments loading…</div>';
    try{
      const d=await ctx.rpc('rr_rm_chat_queue_test71',{p_search:viewSearch||'',p_category:state.category});
      if(seq!==state.seq||!ctx.owned())return;
      s.departmentCountCache.set('READYMADE',{...d.counts,at:Date.now()});
      const cards=d.cards||[],eligible=new Set(cards.filter(c=>c.approval_ready&&c.available_qty>0).map(c=>c.lot_no));state.selection.forEach(l=>{if(!eligible.has(l))state.selection.delete(l)});
      const toolbar=`<div class="rm-chat-toolbar"><select data-category aria-label="Garment category"><option value="">All categories</option>${d.categories.map(c=>`<option ${c===state.category?'selected':''}>${esc(c)}</option>`).join('')}</select><select data-cols aria-label="Card layout">${[1,2,3].map(n=>`<option value="${n}" ${n===state.cols?'selected':''}>${n} card${n>1?'s':''}</option>`).join('')}</select><button data-refresh>Refresh balance</button></div>`;
      const draftCard=x=>`<article class="card work-card"><h3>${esc(x.purchase_no)}</h3><p>${esc(x.supplier_name)} · Bill ${esc(x.bill_no)} · ${esc(x.purchase_date)}</p><p>${x.lines.reduce((n,l)=>n+Number(l.qty),0)} PCS · Draft</p><button data-draft-id="${esc(x.purchase_id)}">Continue Purchase</button></article>`;
      const stockCard=c=>{const cost=c.costing||{};return `<article class="rm-chat-card work-card" data-lot="${esc(c.lot_no)}"><label><input type="checkbox" data-select="${esc(c.lot_no)}" ${state.selection.has(c.lot_no)?'checked':''} ${eligible.has(c.lot_no)?'':'disabled'}>Select ${esc(c.lot_no)}</label>${/^https?:\/\//i.test(c.image_url||'')?`<button data-image="${esc(c.lot_no)}"><img src="${esc(c.image_url)}" alt="${esc(c.item_name)}" loading="lazy"></button>`:'<p>Garment image pending</p>'}<pre>${esc(caption(c))}</pre><p class="rm-balance">Available balance: <b>${c.available_qty} PCS</b></p><small>Purchased ${c.received_qty} PCS</small>${cost.purchase_cost_per_pc!=null?`<details><summary>Owner costing</summary><p>Purchase ${money(cost.purchase_cost_per_pc)} + Salary ${money(cost.salary_per_pc)} + Overhead ${money(cost.overhead_per_pc)} + ₹22 margin</p><p>Base ${money(cost.source_rate)}</p>${(cost.salary_heads||[]).map(h=>`<p>${esc(h.head)} salary ${money(h.per_pc)}/pc</p>`).join('')}${(cost.overhead_heads||[]).map(h=>`<p>${esc(h.label)} ${money(h.per_pc)}/pc</p>`).join('')}</details>`:''}${d.can_approve?`<details><summary>Final sales rate / RRQ</summary><p>${cost.costing_complete?'Rate approval adjusts RRQ on available stock.':'Monthly weighted costing pending.'}</p><input data-rate="${esc(c.stock_id)}" aria-label="Final sales rate" type="number" min="0" value="${esc(c.approved_rate??c.requested_rate??cost.source_rate??'')}"><button data-approve="${esc(c.stock_id)}" ${cost.costing_complete?'':'disabled'}>Approve final rate</button></details>`:''}${d.can_purchase&&c.available_qty>0?`<details><summary>Purchase Return</summary><input data-return-qty="${esc(c.stock_id)}" aria-label="Purchase return PCS" type="number" min="1" max="${c.available_qty}" step="1" placeholder="Return PCS"><input data-return-reason="${esc(c.stock_id)}" aria-label="Return reason" placeholder="Reason required"><button data-return="${esc(c.stock_id)}">Post Purchase Return</button></details>`:''}</article>`};
      box.innerHTML=`<section class="card rm-chat-home"><h3>Readymade Garments · ${viewStatus}</h3><p data-notice class="rm-chat-error" aria-live="polite"></p>${viewStatus==='OPEN'?(d.can_purchase?'<article class="card work-card"><h3>New Readymade Purchase</h3><p>Final garment photo · PCS · Supplier · Purchase rate · Final sales rate</p><button data-new>+ New Purchase</button></article>'+d.drafts.map(draftCard).join(''):'<p>Purchase entry is available to Owner/Admin/Accounts. Stock is in WORKING.</p>'):toolbar+'<div class="rm-chat-toolbar"><button data-all>Select all available</button><button data-send-selected>Send selected · <span data-count>'+state.selection.size+'</span></button><a href="real-web-window-v9329.html?share_mode=choose&from=READYMADE">Market Window</a></div><div class="rm-chat-grid" style="--rm-cols:'+state.cols+'">'+(cards.map(stockCard).join('')||'<p>No Readymade garments found.</p>')+'</div>'}</section>`;
      const notice=box.querySelector('[data-notice]');
      box.querySelector('[data-new]')?.addEventListener('click',()=>purchase(ctx));
      box.querySelectorAll('[data-draft-id]').forEach(b=>b.onclick=()=>purchase(ctx,d.drafts.find(x=>x.purchase_id===b.dataset.draftId)));
      box.querySelector('[data-category]')?.addEventListener('change',e=>{state.category=e.target.value;ctx.refresh()});
      box.querySelector('[data-cols]')?.addEventListener('change',e=>{state.cols=Number(e.target.value);box.querySelector('.rm-chat-grid').style.setProperty('--rm-cols',state.cols)});
      box.querySelector('[data-refresh]')?.addEventListener('click',()=>ctx.refresh());
      box.querySelectorAll('[data-select]').forEach(i=>i.onchange=()=>{i.checked?state.selection.add(i.dataset.select):state.selection.delete(i.dataset.select);box.querySelector('[data-count]').textContent=state.selection.size});
      box.querySelector('[data-all]')?.addEventListener('click',()=>{const all=[...box.querySelectorAll('[data-select]:not(:disabled)')],checked=all.length&&all.every(i=>i.checked);all.forEach(i=>{i.checked=!checked;i.onchange()})});
      box.querySelector('[data-send-selected]')?.addEventListener('click',()=>send(ctx,cards));
      box.querySelectorAll('[data-image]').forEach(b=>b.onclick=()=>{const c=cards.find(x=>x.lot_no===b.dataset.image),m=modal(c.lot_no);m.querySelector('[data-body]').innerHTML=`<img src="${esc(c.image_url)}" alt="${esc(c.item_name)}" style="width:100%;max-height:65vh;object-fit:contain"><pre style="white-space:pre-wrap">${esc(caption(c))}</pre>`});
      box.querySelectorAll('[data-approve]').forEach(b=>b.onclick=()=>action(b,notice,async()=>{const c=cards.find(x=>x.stock_id===b.dataset.approve),rate=Number(box.querySelector(`[data-rate="${CSS.escape(c.stock_id)}"]`).value);if(!Number.isFinite(rate)||rate<0)throw Error('Valid final rate required.');const j=await ctx.rpc('rr_rm_approve_rate_test71',{p_lot_no:c.lot_no,p_final_rate:rate,p_reason:'Readymade Real Chat final rate'});await ctx.refresh();ctx.notice('Approved · RRQ change '+money(j.quota_delta)+' · RRQ balance '+money(j.rrq_balance))}));
      box.querySelectorAll('[data-return]').forEach(b=>b.onclick=()=>action(b,notice,async()=>{const c=cards.find(x=>x.stock_id===b.dataset.return),qty=Number(box.querySelector(`[data-return-qty="${CSS.escape(c.stock_id)}"]`).value),reason=box.querySelector(`[data-return-reason="${CSS.escape(c.stock_id)}"]`).value.trim();if(!Number.isInteger(qty)||qty<=0||qty>c.available_qty||!reason)throw Error('Return whole PCS within available balance and enter reason.');const fingerprint=JSON.stringify([c.stock_id,qty,reason]);if(!state.returnKeys.has(fingerprint))state.returnKeys.set(fingerprint,crypto.randomUUID());await ctx.rpc('rr_rm_purchase_return_test71',{p_stock_id:c.stock_id,p_qty:qty,p_reason:reason,p_return_date:new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'}),p_idempotency_key:state.returnKeys.get(fingerprint),p_remarks:'Readymade Real Chat'});ctx.changed();await ctx.refresh();ctx.notice('Purchase Return posted · Balance, Accounts and RRQ updated.')}));
    }catch(e){if(seq===state.seq&&ctx.owned())box.innerHTML='<div class="card">'+esc(e.message||'Readymade could not load.')+' <button data-retry>Retry</button></div>';box.querySelector('[data-retry]')?.addEventListener('click',()=>ctx.refresh())}
  }
  window.RRReadymadeChat={directory,counts,render,caption,roleOf};
})();
