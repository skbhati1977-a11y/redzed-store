(()=>{
  'use strict';
  if(window.__RR_PACK_PHOTO_FIRST_9346__)return;
  window.__RR_PACK_PHOTO_FIRST_9346__=true;

  const MODE='TEST',BUCKET='redzed-media';
  const $=id=>document.getElementById(id);
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
  const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const algoReady=()=>!!document.querySelector('#packRows tr');
  const show=(t,cls='')=>{const x=$('rrPicLocalMsg');if(x){x.textContent=t;x.className='fg-msg '+cls}const m=$('message');if(m){m.textContent=t;m.className='fg-msg '+cls}};

  let refreshPromise=null,lastSummary=null,lastLot='',patchTimer=0;

  async function rpc(name,args={}){
    const c=db();
    if(!c?.rpc)throw Error('Supabase client unavailable');
    const {data,error}=await c.rpc(name,args);
    if(error)throw error;
    return data;
  }

  function renderSummary(s){
    lastSummary=s||null;
    const cams=(s?.media||[]).filter(x=>x.media_role==='CAMERA').slice(0,3),p=$('rrCameraPreview');
    if(p){
      p.innerHTML=cams.length?cams.map((m,i)=>`<div class="rr-thumb"><span>FINAL ${i+1}</span><img src="${esc(m.image_url||m.storage_path||'')}" alt=""><button class="rr-del" data-cam-del="${esc(m.media_id)}" data-path="${esc(m.storage_path||'')}" type="button">×</button></div>`).join(''):`<p class="fg-muted">Abhi final garment pics nahi hain.</p>`;
    }
    const count=$('rrPicCount');
    if(count)count.textContent=`Final photos: ${Number(s?.camera_count||0)}/3`;
    const rate=$('rrRequestRate');
    if(rate&&algoReady())rate.disabled=Number(s?.camera_count||0)!==3;
  }

  async function refreshPhotos(force=false){
    const l=lot();
    if(!l)return null;
    if(!force&&refreshPromise)return refreshPromise;
    refreshPromise=(async()=>{
      const s=await rpc('rr_pack_media_summary_v9330',{p_lot_no:l,p_data_mode:MODE});
      if(l===lot())renderSummary(s);
      return s;
    })();
    try{return await refreshPromise}finally{refreshPromise=null}
  }

  async function uploadFile(file,path){
    const c=db();
    const up=await c.storage.from(BUCKET).upload(path,file,{contentType:file.type||'image/jpeg',upsert:false});
    if(up.error)throw up.error;
    return{path,image_url:c.storage.from(BUCKET).getPublicUrl(path).data.publicUrl};
  }

  async function cleanupUploaded(paths){
    const clean=(paths||[]).filter(Boolean);
    if(!clean.length)return;
    try{await db().storage.from(BUCKET).remove(clean)}catch(_){/* best effort orphan cleanup */}
  }

  async function uploadSelected(){
    const b=$('rrUploadPics');
    if(!b||b.dataset.rrUploading==='1')return;
    const uploadedPaths=[];
    try{
      if(!algoReady())throw Error('Pehle Packing Algorithm/Table complete karein.');
      const l=lot();if(!l)throw Error('Lot select karein.');
      const files=[...($('rrCameraPics')?.files||[]),...($('rrGalleryPics')?.files||[])].filter(f=>/^image\//i.test(f.type||''));
      if(!files.length)throw Error('Camera/Gallery images select karein.');

      b.dataset.rrUploading='1';b.disabled=true;b.textContent='CHECKING…';
      show('Final photos check ho rahi hain…');
      const cur=await refreshPhotos(true),have=Number(cur?.camera_count||0);
      if(have+files.length>3)throw Error(`Total final garment photos 3 hi rahengi. Current ${have}/3.`);

      b.textContent='UPLOADING…';show('Final garment photos upload ho rahi hain…');
      const items=[];
      for(let i=0;i<files.length;i++){
        const f=files[i],ext=(f.name.split('.').pop()||'jpg').replace(/[^a-z0-9]/gi,'').toLowerCase()||'jpg';
        const path=`packing-final/${MODE}/${encodeURIComponent(l)}/${Date.now()}-${crypto.randomUUID()}.${ext}`;
        const u=await uploadFile(f,path);uploadedPaths.push(u.path);
        items.push({media_role:'CAMERA',variant_no:have+i+1,image_url:u.image_url,storage_path:u.path,content_type:f.type||'image/jpeg',caption:'[CAMERA] Final packing image',customer_caption:'Final packing image'});
      }

      b.textContent='SAVING…';show('Photos database me save ho rahi hain…');
      await rpc('rr_pack_save_media_v9332',{p_lot_no:l,p_items:items,p_data_mode:MODE});
      const verified=await refreshPhotos(true),actual=Number(verified?.camera_count||0),expected=have+files.length;
      if(actual!==expected)throw Error(`Photo save verify failed. Expected ${expected}/3, server par ${actual}/3 mila.`);

      if($('rrCameraPics'))$('rrCameraPics').value='';
      if($('rrGalleryPics'))$('rrGalleryPics').value='';
      show(`Final garment photos saved & verified · ${actual}/3.`,'ok');
    }catch(e){
      if(uploadedPaths.length&&Number(lastSummary?.camera_count||0)===0)await cleanupUploaded(uploadedPaths);
      show(String(e?.message||e),'error');
    }finally{
      if(b){delete b.dataset.rrUploading;b.disabled=false;b.textContent='UPLOAD SELECTED FINAL PICS'}
      schedulePatch();
    }
  }

  function patch(){
    const source=$('rrSourcePics');
    if(source&&algoReady()&&source.hidden)source.hidden=false;
    const title=source?.querySelector('p.fg-muted');
    if(title)title.textContent='Packing algorithm ke baad Camera/Gallery se exactly 3 product-truth photos upload karein. Inke baad Final Rate Approval request bheji jayegi.';
    if(source&&!$('rrPicCount')){
      const x=document.createElement('div');x.id='rrPicCount';x.className='fg-summary';x.textContent=`Final photos: ${Number(lastSummary?.camera_count||0)}/3`;
      source.querySelector('.fg-title-row')?.insertAdjacentElement('afterend',x);
    }
    const l=lot();
    if(l&&l!==lastLot){lastLot=l;refreshPhotos(true).catch(e=>show(String(e?.message||e),'error'));}
  }

  function schedulePatch(){clearTimeout(patchTimer);patchTimer=setTimeout(patch,60)}

  document.addEventListener('click',e=>{
    const b=e.target?.closest?.('#rrUploadPics');if(!b)return;
    e.preventDefault();e.stopImmediatePropagation();uploadSelected();
  },true);

  document.addEventListener('change',e=>{
    if(!e.target?.matches?.('#rrCameraPics,#rrGalleryPics'))return;
    const n=[...($('rrCameraPics')?.files||[]),...($('rrGalleryPics')?.files||[])].filter(f=>/^image\//i.test(f.type||'')).length;
    show(`${n} image selected.`);schedulePatch();
  },true);

  const mo=new MutationObserver(muts=>{
    if(muts.some(m=>m.type==='childList'||(m.type==='attributes'&&m.target?.id==='rrSourcePics')))schedulePatch();
  });
  mo.observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden']});
  document.addEventListener('click',()=>setTimeout(schedulePatch,120),true);
  [250,600,1200].forEach(ms=>setTimeout(schedulePatch,ms));
})();
