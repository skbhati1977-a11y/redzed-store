(()=>{
  'use strict';
  if(window.__RR_PACKING_FINAL_PHOTO_FIRST_V9351__)return;
  window.__RR_PACKING_FINAL_PHOTO_FIRST_V9351__=true;
  const MODE='TEST',BUCKET='redzed-media',$=id=>document.getElementById(id),db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  let photoCount=0,uploading=false,lastLot='',refreshing=false,rateBypass=false;
  const show=(t,cls='')=>{const a=$('rrPicLocalMsg'),b=$('message');if(a){a.textContent=t;a.className='fg-msg '+cls}if(b){b.textContent=t;b.className='fg-msg '+cls}};

  async function nativeRpc(name,args={}){
    const c=db();if(!c?.auth)throw Error('Supabase client unavailable');
    const {data:sess,error:se}=await c.auth.getSession();if(se)throw se;
    const token=sess?.session?.access_token;if(!token)throw Error('Login session required');
    const base=(typeof SUPABASE_URL!=='undefined'&&SUPABASE_URL)||c.supabaseUrl;
    const key=(typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_ANON_KEY)||c.supabaseKey;
    const ctl=new AbortController(),timer=setTimeout(()=>ctl.abort(),10000);
    try{
      const res=await fetch(`${base}/rest/v1/rpc/${encodeURIComponent(name)}`,{method:'POST',headers:{'Content-Type':'application/json','apikey':key,'Authorization':`Bearer ${token}`},body:JSON.stringify(args||{}),signal:ctl.signal,cache:'no-store'});
      const raw=await res.text();let data=null;try{data=raw?JSON.parse(raw):null}catch(_){data=raw}
      if(!res.ok)throw Error(data?.message||data?.hint||raw||`HTTP ${res.status}`);
      return data;
    }finally{clearTimeout(timer)}
  }

  function installBootBridges(){
    const c=db();
    if(c?.rpc&&!c.__rrFgReadyBridge9348){
      const originalRpc=c.rpc.bind(c);
      c.rpc=async function(name,args,options){
        if(name!=='rr_fg_ready_packing_cards_v788')return originalRpc(name,args,options);
        try{return {data:await nativeRpc(name,args),error:null,status:200}}catch(error){console.warn('FG Ready Lots native bridge failed',error);return originalRpc(name,args,options)}
      };
      c.__rrFgReadyBridge9348=true;
    }
    /* Keep this bridge scoped to Ready Lots RPC only. Auth/role boot stays with real-common.js. */
  }

  installBootBridges();

  async function rpc(name,args={}){return nativeRpc(name,args)}
  function patchLayout(){const root=$('rrCatalogEngine'),pics=$('rrSourcePics'),rate=root?.querySelector('.rr-rate-gate');if(!root||!pics||!rate)return false;if(pics.nextElementSibling!==rate)root.insertBefore(pics,rate);pics.hidden=false;const p=pics.querySelector('.fg-muted');if(p)p.textContent='Final Rate Approval request se pehle exactly 3 final garment photos Camera/Gallery se select karke save karein.';if(!$('rrPicCount')){const x=document.createElement('div');x.id='rrPicCount';x.className='fg-summary';x.textContent=`Final photos: ${photoCount}/3`;pics.querySelector('.fg-title-row')?.insertAdjacentElement('afterend',x)}return true}
  function previewUrl(m){const raw=String(m.image_url||m.storage_path||'');try{const u=new URL(raw,location.href);u.searchParams.set('width','420');u.searchParams.set('quality','55');u.searchParams.set('resize','contain');return u.href}catch(_){return raw}}
  async function refreshPhotos(){const l=lot();if(!l||refreshing)return null;refreshing=true;try{const s=await rpc('rr_pack_media_summary_v9330',{p_lot_no:l,p_data_mode:MODE});photoCount=Number(s?.camera_count||0);const n=$('rrPicCount');if(n)n.textContent=`Final photos: ${photoCount}/3`;const req=$('rrRequestRate');if(req)req.disabled=photoCount!==3||!document.querySelector('#packRows tr');const p=$('rrCameraPreview'),cams=(s?.media||[]).filter(x=>x.media_role==='CAMERA').slice(0,3);if(p)p.innerHTML=cams.length?cams.map((m,i)=>`<div class="rr-thumb"><span>FINAL ${i+1}</span><img loading="lazy" decoding="async" src="${previewUrl(m).replace(/"/g,'&quot;')}" alt=""><button class="rr-del" data-cam-del="${m.media_id}" data-path="${String(m.storage_path||'').replace(/"/g,'&quot;')}" type="button">×</button></div>`).join(''):`<p class="fg-muted">Abhi final garment pics nahi hain.</p>`;return s}finally{refreshing=false}}
  async function compactImage(file){
    if(!file||!/^image\//i.test(file.type||''))return file;
    const max=1024,quality=0.68;
    try{
      const url=URL.createObjectURL(file),img=new Image();
      await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;img.src=url});
      const w=img.naturalWidth||img.width,h=img.naturalHeight||img.height;
      if(!w||!h){URL.revokeObjectURL(url);return file}
      const scale=Math.min(1,max/Math.max(w,h));
      if(scale===1&&file.size<1100000){URL.revokeObjectURL(url);return file}
      const canvas=document.createElement('canvas');
      canvas.width=Math.max(1,Math.round(w*scale));canvas.height=Math.max(1,Math.round(h*scale));
      canvas.getContext('2d',{alpha:false}).drawImage(img,0,0,canvas.width,canvas.height);
      URL.revokeObjectURL(url);img.onload=null;img.onerror=null;img.src='';
      const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',quality));
      canvas.width=1;canvas.height=1;canvas.remove?.();
      if(!blob)return file;
      const base=(file.name||'photo').replace(/\.[^.]+$/,'');
      return new File([blob],`${base}-final.jpg`,{type:'image/jpeg',lastModified:Date.now()});
    }catch(_){return file}
  }
  async function uploadBeforeApproval(e){const btn=e.target?.closest?.('#rrUploadPics');if(!btn)return;e.preventDefault();e.stopImmediatePropagation();if(uploading)return;uploading=true;try{const l=lot();if(!l)throw Error('Lot select karein.');if(!document.querySelector('#packRows tr'))throw Error('Pehle Packing Algorithm/Table complete karein.');const files=[...($('rrCameraPics')?.files||[]),...($('rrGalleryPics')?.files||[])].filter(f=>/^image\//i.test(f.type||''));if(!files.length)throw Error('Camera/Gallery images select karein.');if(files.length>1)show('Mobile safety: photos one-by-one optimize + save hongi.');btn.disabled=true;btn.textContent='CHECKING…';show('Final photos check ho rahi hain…');await refreshPhotos();if(photoCount+files.length>3)throw Error(`Total final garment photos 3 hi rahengi. Current ${photoCount}/3.`);btn.textContent='SAVING…';show('Photos mobile-safe size me ready ho rahi hain…');const items=[];for(let i=0;i<files.length;i++){show(`Photo ${i+1}/${files.length} optimize + save ho rahi hai…`);const f=await compactImage(files[i]),path=`packing-final/${MODE}/${encodeURIComponent(l)}/${Date.now()}-${crypto.randomUUID()}.jpg`,up=await db().storage.from(BUCKET).upload(path,f,{contentType:f.type||'image/jpeg',upsert:false});if(up.error)throw up.error;const image_url=db().storage.from(BUCKET).getPublicUrl(path).data.publicUrl;items.push({media_role:'CAMERA',variant_no:photoCount+i+1,image_url,storage_path:path,caption:'[CAMERA] Final packing image',customer_caption:'Final packing image'})}const saved=await rpc('rr_pack_save_media_v9332',{p_lot_no:l,p_items:items,p_data_mode:MODE});if($('rrCameraPics'))$('rrCameraPics').value='';if($('rrGalleryPics'))$('rrGalleryPics').value='';photoCount=Number(saved?.camera_count||0);show(`Final garment photos saved · ${photoCount}/3.`,'ok');await refreshPhotos()}catch(err){show(String(err?.name==='AbortError'?'Photo server response timeout. Retry karein.':err?.message||err),'error')}finally{uploading=false;if(btn){btn.disabled=false;btn.textContent='SAVE SELECTED FINAL PICS'}}}
  async function gateRequest(e){const btn=e.target?.closest?.('#rrRequestRate');if(!btn||rateBypass)return;e.preventDefault();e.stopImmediatePropagation();try{await refreshPhotos()}catch(err){show(String(err?.message||err),'error');return}if(photoCount!==3){show(`Final Rate Approval se pehle 3 final garment photos mandatory. Current ${photoCount}/3.`,'error');$('rrSourcePics')?.scrollIntoView({behavior:'smooth',block:'center'});return}rateBypass=true;try{btn.click()}finally{setTimeout(()=>rateBypass=false,0)}}
  function syncLot(){installBootBridges();if(!patchLayout())return;const l=lot();if(!l||l===lastLot)return;lastLot=l;refreshPhotos().catch(()=>{})}
  document.addEventListener('click',uploadBeforeApproval,true);document.addEventListener('click',gateRequest,true);document.addEventListener('click',()=>setTimeout(syncLot,180),true);document.addEventListener('change',e=>{if(e.target?.matches?.('#rrCameraPics,#rrGalleryPics'))patchLayout()},true);[100,300,600,1000,1600,2800].forEach(ms=>setTimeout(()=>{installBootBridges();syncLot()},ms));
})();
