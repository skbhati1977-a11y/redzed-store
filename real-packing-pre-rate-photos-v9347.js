(()=>{
  'use strict';
  if(window.__RR_PACK_PRE_RATE_PHOTOS_V9347__)return;
  window.__RR_PACK_PRE_RATE_PHOTOS_V9347__=true;
  const MODE='TEST',BUCKET='redzed-media';
  const $=id=>document.getElementById(id);
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  let busy=false;
  const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const show=(t,cls='')=>{const m=$('message');if(m){m.textContent=t;m.className='fg-msg '+cls}const x=$('rrPicLocalMsg');if(x){x.textContent=t;x.className='fg-msg '+cls}};
  async function rpc(name,args={}){const c=db();if(!c?.rpc)throw Error('Supabase client unavailable');const {data,error}=await c.rpc(name,args);if(error)throw error;return data;}
  function algoReady(){return !!document.querySelector('#packRows tr')}
  async function summary(){const l=lot();if(!l)return null;return rpc('rr_pack_media_summary_v9330',{p_lot_no:l,p_data_mode:MODE})}
  function cameraRows(s){return (s?.media||[]).filter(x=>x.media_role==='CAMERA')}
  async function uploadFile(file,path){const c=db();const up=await c.storage.from(BUCKET).upload(path,file,{contentType:file.type||'image/jpeg',upsert:false});if(up.error)throw up.error;return{path,image_url:c.storage.from(BUCKET).getPublicUrl(path).data.publicUrl}}
  function selected(){return [...($('rrCameraPics')?.files||[]),...($('rrGalleryPics')?.files||[])].filter(f=>/^image\//i.test(f.type||''))}
  async function uploadBeforeRate(){
    if(busy)return;busy=true;const b=$('rrUploadPics');
    try{
      if(!algoReady())throw Error('Pehle Packing Algorithm/Table complete karein.');
      const l=lot();if(!l)throw Error('Lot select karein');
      const s=await summary(),have=cameraRows(s).length,files=selected();
      if(!files.length)throw Error('Camera/Gallery images select karein');
      if(have+files.length>3)throw Error(`Total final garment photos exactly 3 rahengi. Current ${have}/3.`);
      if(b){b.disabled=true;b.textContent='UPLOADING…'}
      const items=[];
      for(let i=0;i<files.length;i++){
        const f=files[i],ext=(f.name.split('.').pop()||'jpg').replace(/[^a-z0-9]/gi,'').toLowerCase()||'jpg';
        const path=`packing-final/${MODE}/${encodeURIComponent(l)}/${Date.now()}-${crypto.randomUUID()}.${ext}`;
        const u=await uploadFile(f,path);
        items.push({media_role:'CAMERA',variant_no:have+i+1,image_url:u.image_url,storage_path:u.path,caption:'[CAMERA] Final packing image',customer_caption:'Final packing image'});
      }
      await rpc('rr_pack_save_media_v9332',{p_lot_no:l,p_items:items,p_data_mode:MODE});
      if($('rrCameraPics'))$('rrCameraPics').value='';if($('rrGalleryPics'))$('rrGalleryPics').value='';
      const now=await summary(),count=cameraRows(now).length;
      show(count===3?'3 final garment photos ready. Ab Final Rate Approval request bhej sakte hain.':`${count}/3 final garment photos saved.`,count===3?'ok':'');
      refreshUi(now);
    }catch(e){show(e?.message||String(e),'error')}finally{busy=false;if(b){b.disabled=false;b.textContent='UPLOAD SELECTED FINAL PICS'}}
  }
  function refreshUi(s){
    const panel=$('rrSourcePics'),rate=$('rrRateStatus')?.closest('.rr-rate-gate');
    if(panel&&algoReady()){
      panel.hidden=false;
      const engine=$('rrCatalogEngine');if(engine&&rate&&panel.previousElementSibling===rate)engine.insertBefore(panel,rate);
      const note=panel.querySelector('.fg-muted');if(note)note.textContent='Final Rate Approval se pehle Camera/Gallery se exactly 3 product-truth photos mandatory. Specific photo delete/replace ki ja sakti hai.';
    }
    const count=cameraRows(s).length,btn=$('rrRequestRate');
    if(btn&&!btn.hidden){btn.dataset.photoCount=String(count);btn.title=count===3?'3 final photos ready':`Pehle 3 final garment photos upload karein · ${count}/3`}
  }
  async function sync(){try{if(!lot()||!algoReady())return;const s=await summary();refreshUi(s)}catch(_){}
  document.addEventListener('click',async e=>{
    const up=e.target?.closest?.('#rrUploadPics');
    if(up){e.preventDefault();e.stopImmediatePropagation();uploadBeforeRate();return;}
    const req=e.target?.closest?.('#rrRequestRate');
    if(req){
      try{const s=await summary(),count=cameraRows(s).length;if(count!==3){e.preventDefault();e.stopImmediatePropagation();show(`Final Rate Approval se pehle exactly 3 final garment photos mandatory. Current ${count}/3.`,'error');$('rrSourcePics')?.scrollIntoView({behavior:'smooth',block:'center'});}}
      catch(err){e.preventDefault();e.stopImmediatePropagation();show(err?.message||String(err),'error')}
    }
  },true);
  new MutationObserver(()=>setTimeout(sync,80)).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden']});
  document.addEventListener('click',()=>setTimeout(sync,180),true);setInterval(sync,1200);setTimeout(sync,450);
})();