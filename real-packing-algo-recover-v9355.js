(()=>{
  'use strict';
  if(!/real-finished-goods-v787\.html$/i.test(location.pathname))return;
  const qs=new URLSearchParams(location.search);
  if((qs.get('view')||'').toLowerCase()!=='packing')return;
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const n=v=>Number(v||0);
  const SIZE_ORDER=['L','XL','XXL'];
  let recovered=null, busy=false;
  function sb(){return window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;}
  function setMsg(text,type='ok'){
    const m=$('message');
    if(!m)return;
    m.textContent=text||'';
    m.className='fg-msg '+type;
  }
  function selectedLot(){
    const text=String($('selectedPackLot')?.textContent||'').trim();
    const m=text.match(/Lot\s+(.+)/i);
    return (m?m[1]:text).trim().toUpperCase();
  }
  function packMatrix(cells){
    const rows={};
    (cells||[]).forEach(x=>{
      const colour=String(x.colour_code||'').trim(), size=String(x.size_code||'').trim(), qty=n(x.qty);
      if(!colour||!size||!qty)return;
      rows[colour] ||= {};
      rows[colour][size]=(rows[colour][size]||0)+qty;
    });
    const colours=Object.keys(rows).sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}));
    const found=(cells||[]).map(x=>String(x.size_code||'').trim()).filter(Boolean);
    const sizes=[...new Set([...SIZE_ORDER,...found])].sort((a,b)=>(SIZE_ORDER.indexOf(a)<0?99:SIZE_ORDER.indexOf(a))-(SIZE_ORDER.indexOf(b)<0?99:SIZE_ORDER.indexOf(b))||a.localeCompare(b,undefined,{numeric:true}));
    return {rows,colours,sizes};
  }
  function compositionTable(cells){
    const m=packMatrix(cells);
    if(!m.colours.length||!m.sizes.length)return '';
    return '<div class="fg-pack-matrix-wrap"><table class="fg-pack-matrix"><thead><tr><th>Colour</th>'+m.sizes.map(s=>'<th>'+esc(s)+'</th>').join('')+'</tr></thead><tbody>'+m.colours.map(c=>'<tr><th>'+esc(c)+'</th>'+m.sizes.map(s=>'<td>'+n(m.rows[c][s])+'</td>').join('')+'</tr>').join('')+'</tbody></table></div>';
  }
  function boxNo(code){const m=String(code||'').match(/-BOX-(\d+)$/);return m?Number(m[1]):null;}
  function boxLabel(code){const x=boxNo(code);return x?'BOX '+x:String(code||'');}
  function cellsKey(cells){return (cells||[]).map(x=>`${x.colour_code}|${x.size_code}|${n(x.qty)}|${String(x.pack_mark||'')}`).sort((a,b)=>a.localeCompare(b,undefined,{numeric:true})).join('~');}
  function boxType(box){
    const type=String(box.box_type||'').toUpperCase();
    const cells=box.cells||[];
    if(cells.some(x=>String(x.pack_mark||'').toUpperCase()==='MIX')||n(box.qty)>18)return 'MIX';
    if(cells.some(x=>String(x.pack_mark||'').toUpperCase()==='ASST'))return 'ASST';
    return type==='REGULAR'?'FRESH':(type||'ASST');
  }
  function groups(boxes){
    const out=[], map=new Map();
    (boxes||[]).forEach(box=>{
      const type=boxType(box), key=`${type}|${n(box.qty)}|${cellsKey(box.cells)}`;
      let g=map.get(key);
      if(!g){g={type,boxes:[],nos:[],total:0,sample:box};map.set(key,g);out.push(g);}
      g.boxes.push(box);g.total+=n(box.qty);const no=boxNo(box.box_code);if(no)g.nos.push(no);
    });
    return out;
  }
  function ranges(nums){
    const a=[...new Set(nums)].sort((x,y)=>x-y), r=[];
    for(let i=0;i<a.length;i++){let s=a[i],e=s;while(i+1<a.length&&a[i+1]===e+1)e=a[++i];r.push(s===e?String(s):`${s}-${e}`);}return r.join(', ');
  }
  function render(detail,status){
    const boxes=detail?.boxes||[];
    const packRows=$('packRows'), summary=$('packSummary'), submit=$('submitPack'), block=$('packAlgoBlock');
    if(!packRows||!summary||!submit)return false;
    packRows.innerHTML=groups(boxes).map(g=>'<tr><td data-label="Box">'+esc(g.nos.length?'BOX '+ranges(g.nos):boxLabel(g.sample.box_code))+'</td><td data-label="Type">'+esc(g.type)+'</td><td data-label="PCS">'+esc(g.boxes.length>1?`${n(g.sample.qty)} x ${g.boxes.length} = ${g.total}`:String(n(g.sample.qty)))+'</td><td data-label="Composition">'+compositionTable(g.sample.cells)+'</td></tr>').join('');
    summary.innerHTML='<span class="fg-chip">Boxes <b>'+boxes.length+'</b></span><span class="fg-chip">PCS <b>'+esc(detail?.total_qty||boxes.reduce((s,b)=>s+n(b.qty),0))+'</b></span><span class="fg-chip">View <b>'+esc(status||'RECOVERED')+'</b></span>';
    if(block)block.hidden=false;
    submit.disabled=String(status||'').toUpperCase()==='SUBMITTED';
    return true;
  }
  async function loadAssignment(lot){
    const c=sb();
    if(!c||!lot)return null;
    const r=await c.from('rr_fg_packing_assignments_v788').select('id,lot_no,status,pack_plan_id').eq('data_mode','TEST').ilike('lot_no',lot).in('status',['ACCEPTED','SUBMITTED']).order('accepted_at',{ascending:false}).limit(1);
    if(r.error)throw r.error;
    return (r.data||[])[0]||null;
  }
  async function recover(reason=''){
    if(busy)return;
    const lot=selectedLot();
    if(!lot)return;
    busy=true;
    try{
      const a=await loadAssignment(lot);
      if(!a?.pack_plan_id)return;
      const c=sb();
      const d=await c.rpc('rr_fg_pack_plan_detail_v787',{p_plan_id:a.pack_plan_id});
      if(d.error)throw d.error;
      if(render(d.data,a.status)){
        recovered={assignment_id:a.id,plan_id:a.pack_plan_id,lot_no:a.lot_no,status:a.status};
        const stuck=/Equal packing algorithm chal raha/i.test(String($('message')?.textContent||''));
        if(stuck||reason)setMsg('Existing algorithm table loaded. Submit Packing karein.','ok');
      }
    }catch(e){setMsg(e.message||String(e),'error');}
    finally{busy=false;}
  }
  function needsRecover(){
    const text=String($('message')?.textContent||'');
    const rows=String($('packRows')?.innerHTML||'').trim();
    return /Equal packing algorithm chal raha/i.test(text)||(!rows&&selectedLot());
  }
  document.addEventListener('click',e=>{
    if(e.target&&e.target.closest&&e.target.closest('#runPackAlgo'))setTimeout(()=>{if(needsRecover())recover('run-timeout');},8000);
  },true);
  document.addEventListener('click',async e=>{
    const btn=e.target&&e.target.closest&&e.target.closest('#submitPack');
    if(!btn||!recovered)return;
    e.preventDefault();e.stopImmediatePropagation();
    try{
      btn.disabled=true;btn.textContent='SUBMITTING...';
      const r=await sb().rpc('rr_fg_submit_assigned_pack_v788',{p_assignment_id:recovered.assignment_id,p_plan_id:recovered.plan_id});
      if(r.error)throw r.error;
      const x=r.data||{};
      setMsg(`${x.total_boxes||''} boxes / ${x.total_qty||''} PCS Ready for Despatch.`,'ok');
      setTimeout(()=>location.reload(),700);
    }catch(err){btn.disabled=false;btn.textContent='SUBMIT PACKING';setMsg(err.message||String(err),'error');}
  },true);
  const obs=new MutationObserver(()=>{if(needsRecover())setTimeout(()=>recover('observer'),1200);});
  document.addEventListener('DOMContentLoaded',()=>{obs.observe(document.body,{childList:true,subtree:true,characterData:true});setInterval(()=>{if(needsRecover())recover('interval');},5000);});
})();
