(()=>{
  'use strict';
  if(window.__RR_PACKING_STAGE_MESSAGE_V9356__)return;
  window.__RR_PACKING_STAGE_MESSAGE_V9356__=true;
  if(!/real-finished-goods-v787\.html$/i.test(location.pathname))return;
  const qs=new URLSearchParams(location.search);
  if((qs.get('view')||'').toLowerCase()!=='packing')return;
  const MODE='TEST',$=id=>document.getElementById(id);
  let busy=false,lastKey='';
  const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const lot=()=>String($('selectedPackLot')?.textContent||'').replace(/^Lot\s+/i,'').trim();
  const isOpen=()=>!!lot()&&!$('packWorkspace')?.hidden;
  function show(text,type='ok'){
    const m=$('message');
    if(!m||!text)return;
    m.textContent=text;
    m.className='fg-msg '+type;
  }
  function keepError(){
    const m=$('message'),t=String(m?.textContent||'');
    if(!m?.className?.includes('error'))return false;
    return !/Re-run allowed before submit|Existing algorithm table loaded|Equal packing algorithm chal raha|SUBMIT PACKING|Ready Packing/i.test(t);
  }
  async function rpc(name,args={}){const r=await db().rpc(name,args);if(r.error)throw r.error;return r.data;}
  async function assignment(l){
    const r=await db().from('rr_fg_packing_assignments_v788')
      .select('id,lot_no,status,worker_user_id,worker_name,pack_plan_id')
      .eq('data_mode',MODE).ilike('lot_no',l)
      .in('status',['ASSIGNED','ACCEPTED','SUBMITTED'])
      .limit(1);
    if(r.error)throw r.error;
    return (r.data||[])[0]||null;
  }
  async function rate(l){try{return await rpc('rr_pack_rate_status_v9340',{p_lot_no:l,p_data_mode:MODE})}catch(_){return {status:'NOT_REQUESTED',approved:false}}}
  async function media(l){try{return await rpc('rr_pack_media_summary_v9330',{p_lot_no:l,p_data_mode:MODE})}catch(_){return {camera_count:0}}}
  async function aiFinals(l){try{const x=await rpc('rr_pack_ai_list_v9340',{p_lot_no:l,p_data_mode:MODE});return new Set((x?.items||[]).filter(i=>i.is_final&&[1,2,3].includes(Number(i.style_no))).map(i=>Number(i.style_no))).size}catch(_){return 0}}
  function applyWorker(a){
    const sel=$('packWorker');
    if(!sel||!a?.worker_user_id)return;
    const id=String(a.worker_user_id);
    if(![...sel.options].some(o=>String(o.value)===id)){
      const opt=document.createElement('option');
      opt.value=id;
      opt.textContent=a.worker_name||'Selected Packing Worker';
      sel.appendChild(opt);
    }
    sel.value=id;
  }
  async function compute(){
    if(!isOpen()||!db()?.rpc)return;
    if(busy)return;
    busy=true;
    try{
      const l=lot();
      const a=await assignment(l);
      applyWorker(a);
      const submit=$('submitPack');
      let text='',allowSubmit=false,key='';
      if(!a){
        text='Packing Worker select karke ASSIGN WORK karein.';
        key='assign';
      }else if(a.status==='ASSIGNED'){
        text=`Packer ${a.worker_name||'selected'} fixed hai. ACCEPT WORK karein.`;
        key='accept:'+a.id;
      }else if(a.status==='SUBMITTED'){
        text='Packing submitted. Ab Despatch stage open karein.';
        allowSubmit=false;key='submitted:'+a.id;
      }else if(!a.pack_plan_id&&!document.querySelector('#packRows tr')){
        text=`Packer ${a.worker_name||'selected'} fixed hai. Equal packing algorithm run karein.`;
        key='algo:'+a.id;
      }else{
        const m=await media(l),cam=Math.min(3,Number(m?.camera_count||0));
        if(cam<3){
          text=`Algorithm ready. 3 final photos upload karein. Current ${cam}/3.`;
          key='photos:'+cam;
        }else{
          const r=await rate(l);
          if(!r?.approved){
            text=r?.status&&r.status!=='NOT_REQUESTED'?'Final Rate Approval pending hai. Approval ke baad AI images generate karein.':'3 final photos complete. REQUEST FINAL RATE APPROVAL bhejein.';
            key='rate:'+String(r?.status||'');
          }else{
            const ai=await aiFinals(l);
            if(ai<3){
              text=`Rate approved. 3 AI final style images complete/select karein. Current ${ai}/3.`;
              key='ai:'+ai;
            }else{
              text='All gates complete. SUBMIT PACKING karein.';
              allowSubmit=true;key='submit-ready';
            }
          }
        }
      }
      if(submit)submit.disabled=!allowSubmit;
      if(!keepError()&&(key!==lastKey||/Re-run allowed before submit|Existing algorithm table loaded|Equal packing algorithm chal raha|Ready Packing/i.test(String($('message')?.textContent||'')))){
        show(text,allowSubmit?'ok':'');
        lastKey=key;
      }
    }catch(e){
      if(!keepError())show(e.message||String(e),'error');
    }finally{busy=false;}
  }
  function start(){
    if(!document.body)return;
    new MutationObserver(()=>setTimeout(compute,150)).observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:['hidden','disabled','class']});
    document.addEventListener('click',()=>setTimeout(compute,250),true);
    document.addEventListener('change',()=>setTimeout(compute,250),true);
    setInterval(compute,1800);
    setTimeout(compute,500);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start);else start();
})();
