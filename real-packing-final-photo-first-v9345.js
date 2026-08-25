(()=>{
  'use strict';
  if(window.__RR_PACKING_FINAL_PHOTO_FIRST_V9345__)return;
  window.__RR_PACKING_FINAL_PHOTO_FIRST_V9345__=true;
  const MODE='TEST',BUCKET='redzed-media',$=id=>document.getElementById(id),db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  let photoCount=0,uploading=false,lastLot='',refreshing=false,rateBypass=false;
  const show=(t,cls='')=>{const a=$('rrPicLocalMsg'),b=$('message');if(a){a.textContent=t;a.className='fg-msg '+cls}if(b){b.textContent=t;b.className='fg-msg '+cls}};
  const isAbort=e=>e?.name==='AbortError'||/aborted|abort|user aborted/i.test(String(e?.message||e||''));
  const isFetchFail=e=>/failed to fetch|networkerror|load failed|fetch/i.test(String(e?.message||e||''));
  const clean=e=>isAbort(e)?'Photo/status server response timeout. Refresh karke retry karein.':String(e?.message||e||'Unknown error');
  const uid=()=>crypto?.randomUUID?crypto.randomUUID():String(Date.now())+'-'+Math.random().toString(16).slice(2);

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
    let src=null,w=0,h=0;
    if(window.createImageBitmap){
      try{src=await createImageBitmap(file);w=src.width;h=src.height}catch(_){src=null}
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
    if(src?.close)try{src.close()}catch(_){}
    const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',0.78));
    if(!blob||blob.size>=file.size)return file;
    const base=String(file.name||'photo').replace(/\.[^.]+$/,'').replace(/[^a-z0-9_-]+/gi,'-').slice(0,48)||'photo';
    return new File([blob],base+'.jpg',{type:'image/jpeg',lastModified:Date.now()});
  }

  async function nativeRpc(name,args={}){
    const c=db();if(!c?.auth)throw Error('Supabase client unavailable');
    const {data:sess,error:se}=await c.auth.getSession();if(se)throw se;
    const token=sess?.session?.access_token;if(!token)throw Error('Login session required');
    const base=(typeof SUPABASE_URL!=='undefined'&&SUPABASE_URL)||c.supabaseUrl;
    const key=(typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_ANON_KEY)||c.supabaseKey;
    const ctl=new AbortController(),timer=setTimeout(()=>ctl.abort(),20000);
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
    if(window.RR?.requireRoles&&!window.RR.__fgRequireRolesBridge9348){
      const originalRequire=window.RR.requireRoles.bind(window.RR);
      window.RR.requireRoles=async function(allowedRoles){
        try{return await originalRequire(allowedRoles)}catch(error){
          if(!/Required permission/i.test(String(error?.message||error)))throw error;
          const c=db();const {data:sess,error:se}=await c.auth.getSession();if(se||!sess?.session)throw error;
          let role='';try{role=String(await nativeRpc('rr_current_role')||'').trim().toLowerCase()}catch(_){throw error}
          const allowed=new Set((allowedRoles||[]).map(x=>String(x||'').trim().toLowerCase()));
          if(!role||!allowed.has(role))throw error;
          const user=sess.session.user;
          return {session:sess.session,user,profile:{id:null,full_name:role==='owner'?'Super Admin':'Authorized User',role_code:role,is_active:true}};
        }
      };
      window.RR.__fgRequireRolesBridge9348=true;
    }
  }

  installBootBridges();

  async function rpc(name,args={}){
    const c=db();
    if(c?.rpc){
      try{const r=await c.rpc(name,args);if(r.error)throw r.error;return r.data}catch(e){if(!isFetchFail(e)&&!isAbort(e))throw e;console.warn('Supabase rpc fallback to native fetch',name,e)}
    }
    return nativeRpc(name,args);
  }
  async function rpcRetry(name,args={}){try{return await rpc(name,args)}catch(e){if(!isAbort(e)&&!isFetchFail(e))throw e;await new Promise(r=>setTimeout(r,700));return await rpc(name,args)}}
  function patchLayout(){const root=$('rrCatalogEngine'),pics=$('rrSourcePics'),rate=root?.querySelector('.rr-rate-gate');if(!root||!pics||!rate)return false;if(pics.nextElementSibling!==rate)root.insertBefore(pics,rate);pics.hidden=false;const p=pics.querySelector('.fg-muted');if(p)p.textContent='Final Rate Approval request se pehle exactly 3 final garment photos Camera/Gallery se upload karein.';if(!$('rrPicCount')){const x=document.createElement('div');x.id='rrPicCount';x.className='fg-summary';x.textContent=`Final photos: ${photoCount}/3`;pics.querySelector('.fg-title-row')?.insertAdjacentElement('afterend',x)}return true}
  async function refreshPhotos(){const l=lot();if(!l||refreshing)return null;refreshing=true;try{const s=await rpcRetry('rr_pack_media_summary_v9330',{p_lot_no:l,p_data_mode:MODE});photoCount=Number(s?.camera_count||0);const n=$('rrPicCount');if(n)n.textContent=`Final photos: ${photoCount}/3`;const req=$('rrRequestRate');if(req)req.disabled=photoCount!==3||!document.querySelector('#packRows tr');const p=$('rrCameraPreview'),cams=(s?.media||[]).filter(x=>x.media_role==='CAMERA').slice(0,3);if(p)p.innerHTML=cams.length?cams.map((m,i)=>`<div class="rr-thumb"><span>FINAL ${i+1}</span><img loading="lazy" decoding="async" src="${String(m.image_url||m.storage_path||'').replace(/"/g,'&quot;')}" alt=""><button class="rr-del" data-cam-del="${m.media_id}" data-path="${String(m.storage_path||'').replace(/"/g,'&quot;')}" type="button">×</button></div>`).join(''):`<p class="fg-muted">Abhi final garment pics nahi hain.</p>`;return s}finally{refreshing=false}}
  async function uploadBeforeApproval(e){const btn=e.target?.closest?.('#rrUploadPics');if(!btn)return;e.preventDefault();e.stopImmediatePropagation();if(uploading)return;uploading=true;try{const l=lot();if(!l)throw Error('Lot select karein.');if(!document.querySelector('#packRows tr'))throw Error('Pehle Packing Algorithm/Table complete karein.');const files=[...($('rrCameraPics')?.files||[]),...($('rrGalleryPics')?.files||[])].filter(f=>/^image\//i.test(f.type||''));if(!files.length)throw Error('Camera/Gallery images select karein.');btn.disabled=true;btn.textContent='CHECKING...';show(`${files.length} photo selected. Upload prepare ho raha hai...`);try{await refreshPhotos()}catch(e){if(!isFetchFail(e)&&!isAbort(e))throw e;show('Status refresh slow hai. Upload continue ho raha hai...')};if(photoCount+files.length>3)throw Error(`Total final garment photos 3 hi rahengi. Current ${photoCount}/3.`);const items=[];for(let i=0;i<files.length;i++){btn.textContent=`PHOTO ${i+1}/${files.length}`;show(`Photo ${i+1}/${files.length} optimize/upload ho rahi hai...`);const f=await optimizeImage(files[i]),path=`packing-final/${MODE}/${encodeURIComponent(l)}/${Date.now()}-${uid()}.jpg`,up=await db().storage.from(BUCKET).upload(path,f,{contentType:f.type||'image/jpeg',upsert:false});if(up.error)throw up.error;const image_url=db().storage.from(BUCKET).getPublicUrl(path).data.publicUrl;items.push({media_role:'CAMERA',variant_no:photoCount+i+1,image_url,storage_path:path,caption:'[CAMERA] Final packing image',customer_caption:'Final packing image'})}const saved=await rpcRetry('rr_pack_save_media_v9332',{p_lot_no:l,p_items:items,p_data_mode:MODE});if($('rrCameraPics'))$('rrCameraPics').value='';if($('rrGalleryPics'))$('rrGalleryPics').value='';photoCount=Number(saved?.camera_count||photoCount+items.length||0);show(`Final garment photos saved · ${photoCount}/3.`,'ok');setTimeout(()=>refreshPhotos().catch(()=>{}),250);try{await refreshPhotos()}catch(_){}}
    catch(err){show(clean(err),'error')}finally{uploading=false;if(btn){btn.disabled=false;btn.textContent='UPLOAD SELECTED FINAL PICS'}}}
  async function gateRequest(e){const btn=e.target?.closest?.('#rrRequestRate');if(!btn||rateBypass)return;e.preventDefault();e.stopImmediatePropagation();try{await refreshPhotos()}catch(err){show(clean(err),'error');return}if(photoCount!==3){show(`Final Rate Approval se pehle 3 final garment photos mandatory. Current ${photoCount}/3.`,'error');$('rrSourcePics')?.scrollIntoView({behavior:'smooth',block:'center'});return}rateBypass=true;try{btn.click()}finally{setTimeout(()=>rateBypass=false,0)}}
  function syncLot(){installBootBridges();if(!patchLayout())return;const l=lot();if(!l||l===lastLot)return;lastLot=l;refreshPhotos().catch(()=>{})}
  document.addEventListener('click',uploadBeforeApproval,true);document.addEventListener('click',gateRequest,true);document.addEventListener('click',()=>setTimeout(syncLot,180),true);document.addEventListener('change',e=>{if(e.target?.matches?.('#rrCameraPics,#rrGalleryPics')){patchLayout();const files=[...($('rrCameraPics')?.files||[]),...($('rrGalleryPics')?.files||[])].filter(f=>/^image\//i.test(f.type||''));if(files.length)show(`${files.length} photo selected. UPLOAD SELECTED FINAL PICS dabayein.`,'ok')}},true);[100,300,600,1000,1600,2800].forEach(ms=>setTimeout(()=>{installBootBridges();syncLot()},ms));
})();