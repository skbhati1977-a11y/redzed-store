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
  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}
  function renderSummary(s){
    const cams=(s?.media||[]).filter(x=>x.media_role==='CAMERA').slice(0,3),p=$('rrCameraPreview');
    if(!p)return;
    p.innerHTML=cams.length?cams.map((m,i)=>`<div class="rr-thumb"><span>FINAL ${i+1}</span><img src="${esc(m.image_url||m.storage_path||'')}" alt=""><button class="rr-del" data-cam-del="${esc(m.media_id)}" data-path="${esc(m.storage_path||'')}" type="button">×</button></div>`).join(''):`<p class="fg-muted">Abhi final garment pics nahi hain.</p>`;
  }
  async function refreshPhotos(){const l=lot();if(!l)return null;const s=await rpc('rr_pack_media_summary_v9330',{p_lot_no:l,p_data_mode:MODE});renderSummary(s);return s;}
  async function uploadFile(file,path){const c=db();const up=await c.storage.from(BUCKET).upload(path,file,{contentType:file.type||'image/jpeg',upsert:false});if(up.error)throw up.error;return{path,image_url:c.storage.from(BUCKET).getPublicUrl(path).data.publicUrl};}
  async function uploadSelected(){
    const b=$('rrUploadPics'); if(!b||b.dataset.rrUploading==='1')return;
    try{
      if(!algoReady())throw Error('Pehle Packing Algorithm/Table complete karein.');
      const l=lot();if(!l)throw Error('Lot select karein.');
      const files=[...($('rrCameraPics')?.files||[]),...($('rrGalleryPics')?.files||[])].filter(f=>/^image\//i.test(f.type||''));
      if(!files.length)throw Error('Camera/Gallery images select karein.');
      const cur=await refreshPhotos(),have=Number(cur?.camera_count||0);
      if(have+files.length>3)throw Error(`Total final garment photos 3 hi rahengi. Current ${have}/3.`);
      b.dataset.rrUploading='1';b.disabled=true;b.textContent='UPLOADING…';show('Final garment photos upload ho rahi hain…');
      const items=[];
      for(let i=0;i<files.length;i++){
        const f=files[i],ext=(f.name.split('.').pop()||'jpg').replace(/[^a-z0-9]/gi,'').toLowerCase()||'jpg';
        const path=`packing-final/${MODE}/${encodeURIComponent(l)}/${Date.now()}-${crypto.randomUUID()}.${ext}`;
        const u=await uploadFile(f,path);
        items.push({media_role:'CAMERA',variant_no:have+i+1,image_url:u.image_url,storage_path:u.path,caption:'[CAMERA] Final packing image',customer_caption:'Final packing image'});
      }
      const saved=await rpc('rr_pack_save_media_v9332',{p_lot_no:l,p_items:items,p_data_mode:MODE});
      if($('rrCameraPics'))$('rrCameraPics').value='';if($('rrGalleryPics'))$('rrGalleryPics').value='';
      renderSummary(saved);show(`Final garment photos saved · ${Number(saved?.camera_count||0)}/3.`,'ok');
    }catch(e){show(String(e?.message||e),'error');}
    finally{if(b){delete b.dataset.rrUploading;b.disabled=false;b.textContent='UPLOAD SELECTED FINAL PICS';}}
  }
  function patch(){
    const source=$('rrSourcePics');
    if(source&&algoReady())source.hidden=false;
    const title=source?.querySelector('p.fg-muted');if(title)title.textContent='Packing algorithm ke baad Camera/Gallery se exactly 3 product-truth photos upload karein. Inke baad Final Rate Approval request bheji jayegi.';
    const rate=$('rrRequestRate');
    if(rate&&algoReady()) refreshPhotos().then(s=>{rate.disabled=Number(s?.camera_count||0)!==3;}).catch(()=>{});
  }
  document.addEventListener('click',e=>{
    const b=e.target?.closest?.('#rrUploadPics');if(!b)return;
    e.preventDefault();e.stopImmediatePropagation();uploadSelected();
  },true);
  document.addEventListener('change',e=>{if(e.target?.matches?.('#rrCameraPics,#rrGalleryPics')){const n=[...($('rrCameraPics')?.files||[]),...($('rrGalleryPics')?.files||[])].filter(f=>/^image\//i.test(f.type||'')).length;show(`${n} image selected.`);}},true);
  new MutationObserver(()=>setTimeout(patch,0)).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden','disabled']});
  document.addEventListener('click',()=>setTimeout(patch,100),true);setInterval(patch,900);setTimeout(()=>{patch();refreshPhotos().catch(()=>{})},600);
})();
