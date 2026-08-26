/* V9309/V9346 — locked FG Packing algorithm + manager behalf + Ready Lots REST bridge + final-photo-first RRQ flow. */
(()=>{
  'use strict';
  const canManage=()=>['owner','admin','manager'].includes(String(window.__rrProfile?.role_code||window.RR_CURRENT_PROFILE?.role_code||'').toLowerCase());
  const text=x=>String(x?.textContent||'').replace(/\s+/g,' ').trim();
  const roleFromOperator=()=>/SUPER ADMIN|ADMIN|MANAGER|OWNER/i.test(text(document.getElementById('operator')));
  const isManager=()=>canManage()||roleFromOperator();
  let pendingAssignedLot='';

  function installReadyLotsBridge(){
    if(window.__RR_PACK_READY_REST_BRIDGE_9344__)return true;
    const c=window.supabaseClient||window.redzedSupabase||window.sb;
    if(!c?.rpc||!c?.auth)return false;
    const originalRpc=c.rpc.bind(c);
    c.rpc=async function(name,args,options){
      if(name!=='rr_fg_ready_packing_cards_v788')return originalRpc(name,args,options);
      try{
        const sessionRes=await c.auth.getSession();
        const session=sessionRes?.data?.session;
        if(!session?.access_token)return originalRpc(name,args,options);
        const base=(typeof SUPABASE_URL!=='undefined'&&SUPABASE_URL)||c.supabaseUrl;
        const key=(typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_ANON_KEY)||c.supabaseKey;
        const ctl=new AbortController();
        const timer=setTimeout(()=>ctl.abort(),8000);
        const res=await fetch(`${base}/rest/v1/rpc/rr_fg_ready_packing_cards_v788`,{method:'POST',headers:{'Content-Type':'application/json','apikey':key,'Authorization':`Bearer ${session.access_token}`},body:JSON.stringify(args||{}),signal:ctl.signal,cache:'no-store'});
        clearTimeout(timer);
        const raw=await res.text();let data=null;try{data=raw?JSON.parse(raw):null}catch(_){data=raw}
        if(!res.ok)return{data:null,error:{message:data?.message||raw||`HTTP ${res.status}`,status:res.status}};
        return{data,error:null,status:res.status};
      }catch(error){console.warn('V9344 Ready Lots REST bridge fallback',error);return originalRpc(name,args,options);}
    };
    window.__RR_PACK_READY_REST_BRIDGE_9344__=true;return true;
  }
  function retryReadyLotsIfStuck(){if(!installReadyLotsBridge())return;const cards=document.getElementById('packLotCards'),msg=document.getElementById('message');const stuck=/Ready lots load ho rahe hain/i.test(text(cards))||/Press se Ready Lots fetch ho rahe hain/i.test(text(msg));if(stuck){const b=document.getElementById('refreshPackLots');if(b&&!b.disabled)b.click();}}
  function selectedLot(){return text(document.getElementById('selectedPackLot')).replace(/^Lot\s+/i,'').trim();}
  function focusAccept(){const btn=document.getElementById('acceptPack');if(!btn||btn.closest('[hidden]')||btn.hidden)return false;btn.scrollIntoView({behavior:'smooth',block:'center'});setTimeout(()=>btn.focus({preventScroll:true}),80);return true;}
  function addChip(id,label){const meta=document.getElementById('selectedPackMeta');if(!meta||document.getElementById(id))return;const chip=document.createElement('span');chip.id=id;chip.className='fg-chip';chip.textContent=label;meta.appendChild(chip);}
  function loadScript(id,src){if(document.getElementById(id))return;const s=document.createElement('script');s.id=id;s.src=src;s.async=false;(document.head||document.documentElement).appendChild(s);}
  function loadPicEngine(){return;}
  function reopenAssignedLot(){if(!pendingAssignedLot)return;const workspace=document.getElementById('packWorkspace');const current=selectedLot();if(workspace&&!workspace.hidden&&current===pendingAssignedLot){if(focusAccept())pendingAssignedLot='';return;}const card=[...document.querySelectorAll('[data-pack-lot]')].find(x=>String(x.dataset.packLot||'')===pendingAssignedLot);if(card){card.click();setTimeout(()=>{if(focusAccept())pendingAssignedLot='';},350);}}
  document.addEventListener('click',e=>{const btn=e.target?.closest?.('#assignPack');if(!btn||!/real-finished-goods-v787\.html/i.test(location.pathname))return;const worker=document.getElementById('packWorker')?.value;const lot=selectedLot();if(worker&&lot){pendingAssignedLot=lot;[450,900,1400,2200,3200].forEach(ms=>setTimeout(reopenAssignedLot,ms));}},true);
  function patch(){if(!/real-finished-goods-v787\.html/i.test(location.pathname))return;installReadyLotsBridge();loadPicEngine();const workspace=document.getElementById('packWorkspace');const block=document.getElementById('workerPackBlock');const accept=document.getElementById('acceptPack');const run=document.getElementById('runPackAlgo');const pcs=document.getElementById('packPcsPerBox');if(!workspace)return;const meta=text(document.getElementById('selectedPackMeta'));if(isManager()&&block&&accept&&/ASSIGNED/i.test(meta)&&!/ACCEPTED|SUBMITTED/i.test(meta)){block.hidden=false;accept.textContent='ACCEPT WORK & RUN ALGORITHM';addChip('rr9309BehalfChip','Admin/Manager behalf');if(pendingAssignedLot&&selectedLot()===pendingAssignedLot)focusAccept();}if(/ACCEPTED|SUBMITTED|ALGORITHM READY/i.test(meta))addChip('rr9328AlgoLockChip','Algorithm rule locked');if(/SUBMITTED/i.test(meta)){if(run){run.disabled=true;run.textContent='PACKING SUBMITTED · ALGORITHM LOCKED';}if(pcs)pcs.readOnly=true;}else if(run&&run.textContent==='PACKING SUBMITTED · ALGORITHM LOCKED'){run.disabled=false;run.textContent='RESET / RUN EQUAL PACKING ALGORITHM';if(pcs)pcs.readOnly=false;}reopenAssignedLot();}
  const obs=new MutationObserver(()=>setTimeout(patch,0));
  document.addEventListener('DOMContentLoaded',()=>{installReadyLotsBridge();loadPicEngine();obs.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden','disabled']});patch();[500,1200,2500].forEach(ms=>setTimeout(retryReadyLotsIfStuck,ms));setInterval(patch,1000);},{once:true});
  installReadyLotsBridge();loadPicEngine();
})();