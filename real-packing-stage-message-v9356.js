(()=>{
  'use strict';
  if(window.__RR_PACKING_STAGE_MESSAGE_V9356__)return;
  window.__RR_PACKING_STAGE_MESSAGE_V9356__=true;
  if(!/real-finished-goods-v787\.html$/i.test(location.pathname))return;
  const qs=new URLSearchParams(location.search);
  if((qs.get('view')||'').toLowerCase()!=='packing')return;
  const MODE='TEST',$=id=>document.getElementById(id);
  let busy=false,lastKey='',confirmBypass=false,stageCache={key:'none',text:'',allowSubmit:false,a:null,cam:0,ai:0,rate:null,aiItems:[]};
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const isOpen=()=>!!lot()&&!$('packWorkspace')?.hidden;
  function installStyle(){
    if(document.getElementById('rrStageMsg9356Style'))return;
    const s=document.createElement('style');
    s.id='rrStageMsg9356Style';
    s.textContent='body{padding-bottom:118px}#message.fg-msg{position:fixed;left:14px;right:14px;bottom:14px;z-index:2147483000;margin:0;padding:14px 16px;border-radius:14px;background:#0d1117;border:1px solid #334155;box-shadow:0 12px 30px rgba(0,0,0,.45);font-size:17px;font-weight:900;line-height:1.35;color:#e5e7eb;max-height:30vh;overflow:auto}#message.fg-msg.ok{color:#5fe08c;border-color:#1d7a4a;background:#07150e}#message.fg-msg.error{color:#ff7d8c;border-color:#7f1d2d;background:#17080c}@media(min-width:760px){#message.fg-msg{left:50%;right:auto;bottom:22px;transform:translateX(-50%);width:min(720px,calc(100vw - 44px))}}';
    document.head.appendChild(s);
  }
  function show(text,type='ok'){installStyle();const m=$('message');if(m&&text){m.textContent=text;m.className='fg-msg '+type;}}
  function keepError(){const m=$('message'),t=String(m?.textContent||'');if(!m?.className?.includes('error'))return false;return !/Re-run allowed before submit|Existing algorithm table loaded|Equal packing algorithm chal raha|SUBMIT PACKING|Ready Packing/i.test(t);}
  async function rpc(name,args={}){const r=await db().rpc(name,args);if(r.error)throw r.error;return r.data;}
  async function assignment(l){const r=await db().from('rr_fg_packing_assignments_v788').select('id,lot_no,status,worker_user_id,worker_name,pack_plan_id').eq('data_mode',MODE).ilike('lot_no',l).in('status',['ASSIGNED','ACCEPTED','SUBMITTED']).limit(1);if(r.error)throw r.error;return (r.data||[])[0]||null;}
  async function rate(l){try{return await rpc('rr_pack_rate_status_v9340',{p_lot_no:l,p_data_mode:MODE})}catch(_){return {status:'NOT_REQUESTED',approved:false}}}
  async function media(l){try{return await rpc('rr_pack_media_summary_v9330',{p_lot_no:l,p_data_mode:MODE})}catch(_){return {camera_count:0}}}
  async function aiList(l){try{return (await rpc('rr_pack_ai_list_v9340',{p_lot_no:l,p_data_mode:MODE}))?.items||[]}catch(_){return []}}
  function aiFinalCount(items){return new Set((items||[]).filter(i=>i.is_final&&[1,2,3].includes(Number(i.style_no))).map(i=>Number(i.style_no))).size}
  function applyWorker(a){const sel=$('packWorker');if(!sel||!a?.worker_user_id)return;const id=String(a.worker_user_id);if(![...sel.options].some(o=>String(o.value)===id)){const opt=document.createElement('option');opt.value=id;opt.textContent=a.worker_name||'Selected Packing Worker';sel.appendChild(opt);}sel.value=id;}
  async function currentStage(){
    const l=lot();if(!l||!db()?.rpc)return {key:'none',text:'',allowSubmit:false,a:null,cam:0,ai:0,rate:null,aiItems:[]};
    const a=await assignment(l);applyWorker(a);
    if(!a)return {key:'assign',text:'Packing Worker select karke ASSIGN WORK karein.',allowSubmit:false,a:null,cam:0,ai:0,rate:null,aiItems:[]};
    if(a.status==='ASSIGNED')return {key:'accept:'+a.id,text:`Packer ${a.worker_name||'selected'} fixed hai. ACCEPT WORK karein.`,allowSubmit:false,a,cam:0,ai:0,rate:null,aiItems:[]};
    if(a.status==='SUBMITTED')return {key:'submitted:'+a.id,text:'Packing submitted. Ab Despatch stage open karein.',allowSubmit:false,a,cam:3,ai:3,rate:{approved:true},aiItems:[]};
    if(!a.pack_plan_id&&!document.querySelector('#packRows tr'))return {key:'algo:'+a.id,text:`Packer ${a.worker_name||'selected'} fixed hai. Equal packing algorithm run karein.`,allowSubmit:false,a,cam:0,ai:0,rate:null,aiItems:[]};
    const m=await media(l),cam=Math.min(3,Number(m?.camera_count||0));
    if(cam<3)return {key:'photos:'+cam,text:`Algorithm ready. 3 final photos upload karein. Current ${cam}/3.`,allowSubmit:false,a,cam,ai:0,rate:null,aiItems:[]};
    const r=await rate(l);
    if(!r?.approved)return {key:'rate:'+String(r?.status||''),text:r?.status&&r.status!=='NOT_REQUESTED'?'Final Rate Approval pending hai. Approval ke baad AI images generate karein.':'3 final photos complete. REQUEST FINAL RATE APPROVAL bhejein.',allowSubmit:false,a,cam,ai:0,rate:r,aiItems:[]};
    const items=await aiList(l),ai=aiFinalCount(items);
    if(ai<3)return {key:'ai:'+ai,text:`Rate approved. 3 AI final style images complete/select karein. Current ${ai}/3.`,allowSubmit:false,a,cam,rate:r,ai,aiItems:items};
    return {key:'submit-ready',text:'All gates complete. SUBMIT PACKING karein.',allowSubmit:true,a,cam,rate:r,ai,aiItems:items};
  }
  async function compute(force=false){
    if(!isOpen()||!db()?.rpc||busy)return;
    busy=true;
    try{const s=await currentStage();stageCache=s;const submit=$('submitPack');if(submit)submit.disabled=!s.allowSubmit;if(!keepError()&&(force||s.key!==lastKey||/Re-run allowed before submit|Existing algorithm table loaded|Equal packing algorithm chal raha|Ready Packing/i.test(String($('message')?.textContent||'')))){show(s.text,s.allowSubmit?'ok':'');lastKey=s.key;}}
    catch(e){if(!keepError())show(e.message||String(e),'error')}finally{busy=false;}
  }
  function styleOf(target){return Number(target.dataset.gen||target.dataset.aiUpload||target.closest?.('[data-style]')?.dataset.style||0)}
  function questionFor(target){
    const s=stageCache||{},a=s.a||null,items=s.aiItems||[];
    if(target.matches('#assignPack')&&a?.worker_user_id)return `Packer ${a.worker_name||'selected'} already fixed hai. Kya aap worker reselect/change karna chahte hain?`;
    if(target.matches('#acceptPack')&&a?.status&&a.status!=='ASSIGNED')return 'Work already accepted hai. Kya aap accept action dobara run karna chahte hain?';
    if(target.matches('#runPackAlgo')&&(a?.pack_plan_id||document.querySelector('#packRows tr')))return 'Algorithm already ready hai. Kya aap re-run/reset algorithm karna chahte hain?';
    if(target.matches('#rrUploadPics')&&Number(s.cam||0)>=3)return '3 final photos already uploaded hain. Kya aap replace/re-upload karna chahte hain?';
    if(target.matches('#rrRequestRate')&&s.rate?.status&&s.rate.status!=='NOT_REQUESTED')return s.rate.approved?'Final rate already approved hai. Kya aap rate approval request dobara bhejna chahte hain?':'Rate approval request already pending hai. Kya aap request dobara bhejna chahte hain?';
    if(target.matches('[data-gen]')){const st=styleOf(target);if(st&&items.some(i=>Number(i.style_no)===st))return `Style ${st} AI image already generated hai. Kya aap regenerate karna chahte hain?`;}
    if(target.matches('[data-ai-upload]')){const st=styleOf(target);if(st&&items.some(i=>Number(i.style_no)===st))return `Style ${st} me AI/manual image already hai. Kya aap replace/upload karna chahte hain?`;}
    if(target.matches('[data-final]')){const st=styleOf(target);if(st&&items.some(i=>Number(i.style_no)===st&&i.is_final))return `Style ${st} final already selected hai. Kya aap final image reselect karna chahte hain?`;}
    if(target.matches('#submitPack')&&!s.allowSubmit)return 'Packing submit ke gates complete nahi hain. Current stage complete kiye bina submit nahi hoga.';
    return '';
  }
  function replay(target){
    confirmBypass=true;
    setTimeout(()=>{
      try{target.click()}finally{setTimeout(()=>{confirmBypass=false;compute(true)},650)}
    },0);
  }
  function watchAction(target){
    const started=Date.now();
    const poll=()=>{
      if(window.__RR_ACTION_OWNER__!==target)return;
      const done=!document.body.contains(target)||(!target.disabled&&Date.now()-started>900);
      if(done||Date.now()-started>120000){window.__RR_ACTION_BUSY__=false;window.__RR_ACTION_OWNER__=null;compute(true);return}
      setTimeout(poll,350);
    };
    setTimeout(poll,350);
  }
  function guardRepeat(e){
    if(confirmBypass||!isOpen())return;
    const target=e.target?.closest?.('#assignPack,#acceptPack,#runPackAlgo,#rrUploadPics,#rrRequestRate,[data-gen],[data-ai-upload],[data-final],#submitPack');
    if(!target)return;
    if(window.__RR_ACTION_BUSY__&&window.__RR_ACTION_OWNER__!==target){e.preventDefault();e.stopImmediatePropagation();show('Ek action already chal raha hai. Pehle uske complete hone ka wait karein.','error');return}
    if(!window.__RR_ACTION_BUSY__){window.__RR_ACTION_BUSY__=true;window.__RR_ACTION_OWNER__=target;watchAction(target)}
    const question=questionFor(target);
    if(!question)return;
    e.preventDefault();e.stopImmediatePropagation();
    if(target.matches('#submitPack')&&question.includes('gates complete nahi')){show(question,'error');compute(true);return;}
    if(!window.confirm(question)){if(window.__RR_ACTION_OWNER__===target){window.__RR_ACTION_BUSY__=false;window.__RR_ACTION_OWNER__=null}compute(true);return;}
    replay(target);
  }
  function start(){
    if(!document.body)return;
    installStyle();
    document.addEventListener('click',guardRepeat,true);
    new MutationObserver(()=>setTimeout(()=>compute(false),150)).observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:['hidden','disabled','class']});
    document.addEventListener('click',()=>setTimeout(()=>compute(false),250),true);
    document.addEventListener('change',()=>setTimeout(()=>compute(false),250),true);
    setInterval(()=>compute(false),1800);setTimeout(()=>compute(true),500);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start);else start();
})();
