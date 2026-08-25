(()=>{
  'use strict';
  if(window.__RR_PACKING_INSTANT_DELETE_V9356__)return;
  window.__RR_PACKING_INSTANT_DELETE_V9356__=true;
  if(!/real-finished-goods-v787\.html$/i.test(location.pathname))return;
  const qs=new URLSearchParams(location.search);
  if((qs.get('view')||'').toLowerCase()!=='packing')return;
  const MODE='TEST',BUCKET='redzed-media';
  const $=id=>document.getElementById(id);
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const show=(t,cls='')=>{const a=$('rrPicLocalMsg'),b=$('message');if(a){a.textContent=t;a.className='fg-msg '+cls}if(b){b.textContent=t;b.className='fg-msg '+cls}};
  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const r=await c.rpc(name,args);if(r.error)throw r.error;return r.data;}
  async function removePath(path){if(!path)return;try{await db().storage.from(BUCKET).remove([path])}catch(e){console.warn('storage remove failed',e)}}
  function updateCount(delta){
    const n=$('rrPicCount');
    if(!n)return;
    const m=String(n.textContent||'').match(/(\d+)\s*\/\s*3/);
    const next=Math.max(0,Math.min(3,(m?Number(m[1]):3)+delta));
    n.textContent=`Final photos: ${next}/3`;
    const req=$('rrRequestRate');
    if(req)req.disabled=next!==3||!document.querySelector('#packRows tr');
  }
  function maybeEmpty(){
    const host=$('rrCameraPreview');
    if(host&&!host.querySelector('.rr-thumb'))host.innerHTML='<p class="fg-muted">Abhi final garment pics nahi hain.</p>';
  }
  async function handleDelete(e){
    const btn=e.target?.closest?.('[data-cam-del]');
    if(!btn)return;
    e.preventDefault();
    e.stopImmediatePropagation();
    const id=btn.dataset.camDel,path=btn.dataset.path||'';
    if(!id)return;
    if(!window.confirm('Final garment photo delete karein?'))return;
    const card=btn.closest('.rr-thumb');
    const oldHtml=card?.outerHTML||'';
    if(card)card.remove();
    updateCount(-1);
    maybeEmpty();
    show('Photo deleted. Replacement upload karein.','ok');
    try{
      const r=await rpc('rr_pack_camera_delete_v9340',{p_media_id:id,p_lot_no:lot(),p_data_mode:MODE});
      await removePath(r?.storage_path||path);
      setTimeout(()=>document.getElementById('rrPicRefresh')?.click(),250);
    }catch(err){
      const host=$('rrCameraPreview');
      if(host&&oldHtml&&!host.querySelector(`[data-cam-del="${CSS.escape(id)}"]`))host.insertAdjacentHTML('beforeend',oldHtml);
      updateCount(1);
      show(err.message||String(err),'error');
    }
  }
  document.addEventListener('click',handleDelete,true);
})();
