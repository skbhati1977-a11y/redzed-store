(()=>{
  "use strict";
  const initialParams=new URLSearchParams(location.search);
  const targetFromRaw=raw=>{
    if(!raw)return null;
    try{const url=new URL(raw,location.href);return url.origin===location.origin?url.pathname+url.search+url.hash:null}catch{return null}
  };
  // Capture before canonical forms rewrite their URL after gaining an ID.
  const returnTarget=targetFromRaw(initialParams.get("return"));
  const successTarget=targetFromRaw(initialParams.get("success_return"));
  const embedded=window.parent!==window&&initialParams.get("embed")==="1";
  const action=initialParams.get("rr_action")||"";
  const success=(options={})=>{let url=successTarget||returnTarget,status=String(options?.status||"").toUpperCase(),focus=String(options?.focus||"").trim();if(url&&(status||focus)){const next=new URL(url,location.href);if(status)next.searchParams.set("rc_status",status);if(focus)next.searchParams.set("rc_focus_cb",focus);url=next.pathname+next.search+next.hash}if(embedded){window.parent.postMessage({type:"RR_REAL_CHAT_ACTION_SUCCESS",action,status,focus},location.origin);return}if(url)location.replace(url);else history.back()};
  window.RRActionReturn={back:()=>history.back(),success,hasReturn:()=>!!(successTarget||returnTarget)};
})();

/* Receipt V2 owns only CB requirement share buttons; old direct/text fallback is unreachable.
   Installed synchronously before the CB inline handlers, so slow module loading cannot fall back. */
(()=>{
  'use strict';
  if(!/\/real-cb-new-v9130-fix2\.html$/.test(location.pathname)||window.__CB_RECEIPT_ROUTER_V2__)return;
  window.__CB_RECEIPT_ROUTER_V2__=true;
  let sheet=null,frame=null,opener=null,opening=false;
  const notify=text=>{const box=document.getElementById('msg');if(box){box.className='message';box.textContent=text}};
  function refresh(){const b=document.getElementById('refreshDerivedRequirement');if(typeof b?.onclick!=='function')return Promise.reject(new Error('CB अभी load हो रहा है.'));return Promise.resolve(b.onclick())}
  function close(){if(!sheet)return;sheet.close();sheet.remove();sheet=null;frame=null;opening=false;opener?.focus();opener=null}
  function installLabels(){document.querySelectorAll('#derivedRequirementSummary .wa-send').forEach(b=>{if(b.dataset.receiptOwner==='v2')return;const old=b.textContent||'';b.dataset.receiptOwner='v2';b.onclick=null;b.textContent=/RESEND/i.test(old)?'RECEIPT · '+old:/REVISED/i.test(old)?'REVISED RECEIPT':'RECEIPT · SHARE';b.setAttribute('aria-haspopup','dialog');b.title='Receipt JPG/PDF + clickable reference images';})}
  function open(button){
    if(opening||sheet)return;opening=true;opener=button;
    const q=new URLSearchParams(location.search),cb=q.get('cb_id');
    if(!cb){opening=false;notify('पहले CB Draft Save करें, फिर receipt खोलें.');return}
    document.activeElement?.blur();
    sheet=document.createElement('dialog');sheet.setAttribute('aria-label','CB requirement receipt');sheet.style.cssText='inset:0;margin:0;padding:0;border:0;width:100vw;max-width:100vw;height:100dvh;max-height:100dvh;background:#e8edf2;color:#172333;display:flex;flex-direction:column';
    const bar=document.createElement('div');bar.style.cssText='padding:12px 16px;display:flex;align-items:center;justify-content:space-between;background:#102033;color:white';const title=document.createElement('b');title.textContent='Order Receipt · V2';const cancel=document.createElement('button');cancel.type='button';cancel.textContent='×';cancel.setAttribute('aria-label','Back to CB');cancel.style.cssText='background:transparent;color:white;border:0;font-size:28px;min-width:44px;min-height:44px';cancel.onclick=close;bar.append(title,cancel);
    const loading=document.createElement('p');loading.textContent='Saved quantities और images तैयार हो रही हैं…';loading.style.padding='20px';sheet.append(bar,loading);document.body.append(sheet);sheet.showModal();sheet.addEventListener('cancel',e=>{e.preventDefault();close()});
    const current=sheet;
    // Reuse the original flushFieldAutosave + requirement refresh handler, not a second quantity engine.
    refresh().then(()=>{
      if(sheet!==current)return;
      if(!document.getElementById('msg')?.classList.contains('ok'))throw new Error('CB save/refresh पूरा नहीं हुआ. पहले उसे ठीक करें.');
      const url=new URL('test71-cb-receipt.html',location.href);url.searchParams.set('cb_id',cb);url.searchParams.set('type',button.dataset.type);url.searchParams.set('source_id',button.dataset.sourceId);url.searchParams.set('embed','1');url.searchParams.set('v','2');
      try{if(window.frameElement&&!window.frameElement.allow.includes('web-share'))window.frameElement.allow+='; web-share'}catch{}
      frame=document.createElement('iframe');frame.title='Receipt preview and file sharing';frame.allow='web-share; clipboard-write';frame.style.cssText='flex:1;min-height:0;width:100%;border:0;background:#e8edf2';frame.src=url.href;loading.replaceWith(frame);opening=false;
    }).catch(e=>{if(sheet===current){loading.textContent=e?.message||'Receipt open नहीं हुई. CB दोबारा खोलें.';opening=false}});
  }
  document.addEventListener('click',event=>{
    const button=event.target.closest?.('#derivedRequirementSummary .wa-send');if(!button)return;
    event.preventDefault();event.stopImmediatePropagation();open(button);
  },true);
  window.addEventListener('message',event=>{
    if(event.origin!==location.origin||event.source!==frame?.contentWindow)return;
    if(event.data?.type==='RR_CB_RECEIPT_CLOSE')close();
    if(event.data?.type==='RR_CB_RECEIPT_SHARED')refresh().catch(()=>notify('Share record saved. CB list refresh दोबारा करें.'));
  });
  new MutationObserver(installLabels).observe(document.documentElement,{childList:true,subtree:true});
  installLabels();
})();
