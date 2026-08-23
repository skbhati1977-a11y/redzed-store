(()=>{
  'use strict';
  if(window.__RR_PACKING_FINAL_PHOTO_FIRST_V9345__)return;
  window.__RR_PACKING_FINAL_PHOTO_FIRST_V9345__=true;
  const MODE='TEST',BUCKET='redzed-media';
  const $=id=>document.getElementById(id);
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  let photoCount=0,uploading=false;
  const show=(t,cls='')=>{const a=$('rrPicLocalMsg'),b=$('message');if(a){a.textContent=t;a.className='fg-msg '+cls}if(b){b.textContent=t;b.className='fg-msg '+cls}};

  async function rpc(name,args={}){
    const c=db();if(!c?.auth)throw Error('Supabase client unavailable');
    const {data:sess,error:se}=await c.auth.getSession();if(se)throw se;
    const token=sess?.session?.access_token;if(!token)throw Error('Login session required');
    const base=(typeof SUPABASE_URL!=='undefined'&&SUPABASE_URL)||c.supabaseUrl;
    const key=(typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_ANON_KEY)||c.supabaseKey;
    const ctl=new AbortController();const timer=setTimeout(()=>ctl.abort(),10000);
    try{
      const res=await fetch(`${base}/rest/v1/rpc/${encodeURIComponent(name)}`,{method:'POST',headers:{'Content-Type':'application/json','apikey':key,'Authorization':`Bearer ${token}`},body:JSON.stringify(args||{}),signal:ctl.signal,cache:'no-store'});
      const raw=await res.text();let data=null;try{data=raw?JSON.parse(raw):null}catch(_){data=raw}
      if(!res.ok)throw Error(data?.message||data?.hint||raw||`HTTP ${res.status}`);
      return data;
    }finally{clearTimeout(timer)}
  }
  async function refreshPhotos(){
    const l=lot(); if(!l)return null;
    try{
      const s=await rpc('rr_pack_media_summary_v9330',{p_lot_no:l,p_data_mode:MODE});
      photoCount=Number(s?.camera_count||0);
      const n=$('rrPicCount'); if(n)n.textContent=`Final photos: ${photoCount}/3`;
      const req=$('rrRequestRate'); if(req)req.disabled=photoCount!==3 || !document.querySelector('#packRows tr');
      const p=$('rrCameraPreview'),cams=(s?.media||[]).filter(x=>x.media_role==='CAMERA').slice(0,3);
      if(p)p.innerHTML=cams.length?cams.map((m,i)=>`<div class="rr-thumb"><span>FINAL ${i+1}</span><img src="${String(m.image_url||m.storage_path||'').replace(/"/g,'&quot;')}" alt=""><button class="rr-del" data-cam-del="${m.media_id}" data-path="${String(m.storage_path||'').replace(/"/g,'&quot;')}" type="button">×</button></div>`).join(''):`<p class="fg-muted">Abhi final garment pics nahi hain.</p>`;
      return s;
    }catch(e){console.warn('V9345 photo count',e);throw e}
  }
  function patchLayout(){
    const root=$('rrCatalogEngine'),pics=$('rrSourcePics'),rate=root?.querySelector('.rr-rate-gate');
    if(!root||!pics||!rate)return;
    if(pics.nextElementSibling!==rate)root.insertBefore(pics,rate);
    pics.hidden=false;
    const p=pics.querySelector('.fg-muted'); if(p)p.textContent='Final Rate Approval request se pehle exactly 3 final garment photos Camera/Gallery se upload karein.';
    if(!$('rrPicCount')){const x=document.createElement('div');x.id='rrPicCount';x.className='fg-summary';x.textContent=`Final photos: ${photoCount}/3`;pics.querySelector('.fg-title-row')?.insertAdjacentElement('afterend',x)}
  }
  async function uploadBeforeApproval(e){
    const btn=e.target?.closest?.('#rrUploadPics'); if(!btn)return;
    e.preventDefault();e.stopImmediatePropagation();
    if(uploading)return; uploading=true;
    try{
      const l=lot();if(!l)throw Error('Lot select karein.');
      if(!document.querySelector('#packRows tr'))throw Error('Pehle Packing Algorithm/Table complete karein.');
      const files=[...($('rrCameraPics')?.files||[]),...($('rrGalleryPics')?.files||[])].filter(f=>/^image\//i.test(f.type||''));
      if(!files.length)throw Error('Camera/Gallery images select karein.');
      btn.disabled=true;btn.textContent='CHECKING…';show('Final photos check ho rahi hain…');
      await refreshPhotos();
      if(photoCount+files.length>3)throw Error(`Total final garment photos 3 hi rahengi. Current ${photoCount}/3.`);
      btn.textContent='UPLOADING…';show('Final garment photos upload ho rahi hain…');
      const items=[];
      for(let i=0;i<files.length;i++){
        const f=files[i],ext=(f.name.split('.').pop()||'jpg').replace(/[^a-z0-9]/gi,'').toLowerCase()||'jpg';
        const path=`packing-final/${MODE}/${encodeURIComponent(l)}/${Date.now()}-${crypto.randomUUID()}.${ext}`;
        const up=await db().storage.from(BUCKET).upload(path,f,{contentType:f.type||'image/jpeg',upsert:false}); if(up.error)throw up.error;
        const image_url=db().storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
        items.push({media_role:'CAMERA',variant_no:photoCount+i+1,image_url,storage_path:path,caption:'[CAMERA] Final packing image',customer_caption:'Final packing image'});
      }
      const saved=await rpc('rr_pack_save_media_v9332',{p_lot_no:l,p_items:items,p_data_mode:MODE});
      if($('rrCameraPics'))$('rrCameraPics').value=''; if($('rrGalleryPics'))$('rrGalleryPics').value='';
      photoCount=Number(saved?.camera_count||0);show(`Final garment photos saved · ${photoCount}/3.`,'ok');
      await refreshPhotos();
    }catch(err){show(String(err?.name==='AbortError'?'Photo server response timeout. Retry karein.':err?.message||err),'error')}
    finally{uploading=false;if(btn){btn.disabled=false;btn.textContent='UPLOAD SELECTED FINAL PICS'}setTimeout(()=>refreshPhotos().catch(()=>{}),300)}
  }
  async function gateRequest(e){
    const btn=e.target?.closest?.('#rrRequestRate'); if(!btn)return;
    try{await refreshPhotos()}catch(_){return}
    if(photoCount===3)return;
    e.preventDefault();e.stopImmediatePropagation();
    show(`Final Rate Approval se pehle 3 final garment photos mandatory. Current ${photoCount}/3.`,'error');
    $('rrSourcePics')?.scrollIntoView({behavior:'smooth',block:'center'});
  }
  document.addEventListener('click',uploadBeforeApproval,true);
  document.addEventListener('click',gateRequest,true);
  const tick=()=>{patchLayout();refreshPhotos().catch(()=>{})};
  new MutationObserver(()=>setTimeout(tick,0)).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden']});
  document.addEventListener('click',()=>setTimeout(tick,180),true);
  setInterval(tick,1800);setTimeout(tick,600);
})();