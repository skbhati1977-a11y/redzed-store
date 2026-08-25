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
  function uid(){return (crypto&&crypto.randomUUID)?crypto.randomUUID():String(Date.now())+'-'+Math.random().toString(16).slice(2)}
  function imageFromFile(file){
    return new Promise((resolve,reject)=>{
      const url=URL.createObjectURL(file),img=new Image();
      img.onload=()=>{URL.revokeObjectURL(url);resolve(img)};
      img.onerror=err=>{URL.revokeObjectURL(url);reject(err)};
      img.src=url;
    });
  }
  async function optimizeImage(file){
    if(!file||!/image\//i.test(file.type||''))return file;
    let src,w,h;
    if(window.createImageBitmap){
      try{src=await createImageBitmap(file);w=src.width;h=src.height}catch(e){src=null}
    }
    if(!src){src=await imageFromFile(file);w=src.naturalWidth||src.width;h=src.naturalHeight||src.height}
    if(!w||!h)return file;
    const maxSide=1600,scale=Math.min(1,maxSide/Math.max(w,h));
    if(scale===1&&file.size<=650000)return file;
    const canvas=document.createElement('canvas');
    canvas.width=Math.max(1,Math.round(w*scale));
    canvas.height=Math.max(1,Math.round(h*scale));
    const ctx=canvas.getContext('2d',{alpha:false});
    ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);
    ctx.drawImage(src,0,0,canvas.width,canvas.height);
    if(src&&src.close)try{src.close()}catch(e){}
    const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',0.78));
    if(!blob||blob.size>=file.size)return file;
    const base=String(file.name||'photo').replace(/\.[^.]+$/,'').replace(/[^a-z0-9_-]+/gi,'-').slice(0,50)||'photo';
    return new File([blob],base+'.jpg',{type:'image/jpeg',lastModified:Date.now()});
  }
  function selectedFiles(){
    return [...($('rrCameraPics')?.files||[]),...($('rrGalleryPics')?.files||[])].filter(f=>/^image\//i.test(f.type||''));
  }
  async function currentPhotoCount(lotNo){
    const data=await rpc('rr_pack_media_summary_v9330',{p_lot_no:lotNo,p_data_mode:MODE});
    return Number(data?.camera_count||0);
  }
  let uploading=false;
  async function handleFastUpload(e){
    const btn=e.target?.closest?.('#rrUploadPics');
    if(!btn)return;
    e.preventDefault();
    e.stopImmediatePropagation();
    if(uploading)return;
    const lotNo=lot(),files=selectedFiles();
    if(!lotNo){show('Lot select karein.','error');return}
    if(!document.querySelector('#packRows tr')){show('Pehle packing algorithm table ready karein.','error');return}
    if(!files.length){show('Camera/Gallery se photo select karein.','error');return}
    uploading=true;
    const oldText=btn.textContent;
    try{
      btn.disabled=true;btn.textContent='OPTIMIZING...';
      const existing=await currentPhotoCount(lotNo);
      if(existing>=3){
        if(window.confirm('3 final photos already uploaded hain. Replace ke liye pehle old photo delete karni hogi. Delete ke bina upload continue nahi hoga.'))show('Replacement ke liye pehle old photo delete karein.','error');
        return;
      }
      if(existing+files.length>3)throw Error(`Total final garment photos 3 hi rahengi. Abhi ${existing}/3 hain; ${3-existing} photo upload karein.`);
      const items=[];
      for(let i=0;i<files.length;i++){
        show(`Photo ${i+1}/${files.length} optimize/upload ho rahi hai...`,'');
        const f=await optimizeImage(files[i]);
        const path=`packing-final/${MODE}/${encodeURIComponent(lotNo)}/${Date.now()}-${uid()}.jpg`;
        const up=await db().storage.from(BUCKET).upload(path,f,{contentType:f.type||'image/jpeg',upsert:false});
        if(up.error)throw up.error;
        const pub=db().storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
        items.push({media_role:'CAMERA',variant_no:existing+i+1,image_url:pub,storage_path:path,source:'FAST_OPTIMIZED_UPLOAD'});
      }
      await rpc('rr_pack_save_media_v9332',{p_lot_no:lotNo,p_data_mode:MODE,p_items:items});
      if($('rrCameraPics'))$('rrCameraPics').value='';
      if($('rrGalleryPics'))$('rrGalleryPics').value='';
      const n=$('rrPicCount');
      if(n)n.textContent=`Final photos: ${existing+items.length}/3`;
      show(`Final garment photos saved fast · ${existing+items.length}/3.`,'ok');
      setTimeout(()=>document.getElementById('rrPicRefresh')?.click(),250);
      setTimeout(()=>document.getElementById('rrPicRefresh')?.click(),900);
    }catch(err){
      show(err.message||String(err),'error');
    }finally{
      uploading=false;
      btn.disabled=false;
      btn.textContent=oldText||'UPLOAD PHOTOS';
    }
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
  document.addEventListener('click',handleFastUpload,true);
  document.addEventListener('click',handleDelete,true);
})();
