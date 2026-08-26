(()=>{
  'use strict';
  const TYPES=['FRESH','ASST','MIX'];
  const typeOf=v=>{const t=String(v||'').trim().toUpperCase();return t==='REGULAR'||t==='FRESH'?'FRESH':t==='MIX'?'MIX':'ASST';};
  const qtyLabel=g=>{if(!g.boxes.length)return '0 BOX / 0 PCS';const qs=[...new Set(g.boxes.map(x=>x.qty))];return qs.length===1?`${g.boxes.length} × ${qs[0]} = ${g.pcs} PCS`:`${g.boxes.length} BOX / ${g.pcs} PCS`;};
  let rendering=false,retryTimer=null,retryCount=0,lastRawSignature='';
  const sendingState=new Map();
  function allowedLots(){const a=window.__RR_DESPATCH_ALLOWED_LOTS__;return Array.isArray(a)?new Set(a.map(String)):null;}
  function suppressLegacy(){
    let st=document.getElementById('rr-dc-legacy-suppress');
    if(!st){st=document.createElement('style');st.id='rr-dc-legacy-suppress';st.textContent='#dispatchLotSummary{display:none!important;height:0!important;min-height:0!important;margin:0!important;padding:0!important;overflow:hidden!important}';document.head.appendChild(st);}
    const legacy=document.getElementById('dispatchLotSummary');
    if(legacy){legacy.style.setProperty('display','none','important');legacy.setAttribute('aria-hidden','true');legacy.innerHTML='';}
  }
  function rawRows(){return [...document.querySelectorAll('#dispatchBoxRows tr[data-box-id]')];}
  function rawSignature(){return rawRows().map(row=>{const c=[...row.children];return `${row.dataset.boxId}|${String(c[2]?.textContent||'').trim()}|${typeOf(c[3]?.textContent)}|${Number(c[4]?.textContent||0)}`;}).sort().join('~');}
  function readGroups(){
    const map=new Map();
    rawRows().forEach(row=>{
      const c=[...row.children];
      const lot=String(c[2]?.textContent||'').trim();
      const type=typeOf(c[3]?.textContent);
      const qty=Number(c[4]?.textContent||0);
      if(!lot)return;
      const key=`${lot}||${type}`;
      if(!map.has(key))map.set(key,{lot,type,boxes:[],pcs:0});
      const g=map.get(key);g.boxes.push({row,qty});g.pcs+=qty;
    });
    return map;
  }
  function selectedCount(g){return g.boxes.filter(({row})=>row.querySelector('[data-dispatch-check]')?.checked).length;}
  function snapshotHost(host){
    if(!host)return;
    host.querySelectorAll('[data-dc-send]').forEach(inp=>{
      const n=Number(inp.value);
      if(Number.isFinite(n))sendingState.set(inp.dataset.dcSend,Math.max(0,n|0));
    });
  }
  function seedState(groups,reset=false){
    if(reset)sendingState.clear();
    groups.forEach((g,key)=>{
      if(!sendingState.has(key))sendingState.set(key,selectedCount(g));
      sendingState.set(key,Math.max(0,Math.min(g.boxes.length,Number(sendingState.get(key)||0)|0)));
    });
    [...sendingState.keys()].forEach(key=>{if(!groups.has(key))sendingState.delete(key);});
  }
  function clearFilteredSelections(groups){
    const allowed=allowedLots();if(!allowed)return;
    groups.forEach((g,key)=>{if(!allowed.has(String(g.lot)))sendingState.set(key,0);});
  }
  function applySelections(host){
    const groups=readGroups();
    clearFilteredSelections(groups);
    host.querySelectorAll('[data-dc-send]').forEach(inp=>{
      const g=groups.get(inp.dataset.dcSend);
      const n=g?Math.max(0,Math.min(g.boxes.length,Number(inp.value||0)|0)):0;
      sendingState.set(inp.dataset.dcSend,n);
      inp.value=String(n);
    });
    rawRows().forEach(row=>{const ch=row.querySelector('[data-dispatch-check]'),q=row.querySelector('[data-dispatch-qty]');if(ch)ch.checked=false;if(q)q.value='';});
    groups.forEach((g,key)=>{
      const n=Math.max(0,Math.min(g.boxes.length,Number(sendingState.get(key)||0)|0));
      g.boxes.slice(0,n).forEach(({row,qty})=>{const ch=row.querySelector('[data-dispatch-check]'),q=row.querySelector('[data-dispatch-qty]');if(ch)ch.checked=true;if(q)q.value=qty;});
    });
    const first=rawRows()[0]?.querySelector('[data-dispatch-check]');if(first)first.dispatchEvent(new Event('input',{bubbles:true}));
    renderBalances(host,groups);
  }
  function renderBalances(host,groups){
    host.querySelectorAll('tr[data-dc-group]').forEach(tr=>{
      const g=groups.get(tr.dataset.dcGroup);if(!g)return;
      const n=Math.max(0,Math.min(g.boxes.length,Number(sendingState.get(tr.dataset.dcGroup)||0)|0));
      const inp=tr.querySelector('[data-dc-send]');if(inp)inp.value=String(n);
      const sent=g.boxes.slice(0,n).reduce((s,x)=>s+x.qty,0);
      const sendCell=tr.querySelector('[data-dc-sent-pcs]'),balCell=tr.querySelector('[data-dc-balance]');
      if(sendCell)sendCell.textContent=`${n} BOX / ${sent} PCS`;
      if(balCell)balCell.textContent=`${g.boxes.length-n} BOX / ${g.pcs-sent} PCS`;
    });
    host.querySelectorAll('[data-dc-lot]').forEach(sec=>{
      const lot=sec.dataset.dcLot;
      let ab=0,ap=0,sb=0,sp=0;
      TYPES.forEach(type=>{
        const key=`${lot}||${type}`,g=groups.get(key)||{boxes:[],pcs:0};ab+=g.boxes.length;ap+=g.pcs;
        const n=Math.max(0,Math.min(g.boxes.length,Number(sendingState.get(key)||0)|0));sb+=n;sp+=g.boxes.slice(0,n).reduce((s,x)=>s+x.qty,0);
      });
      const row=sec.querySelector('[data-dc-total]');if(row)row.innerHTML=`<th>LOT TOTAL</th><td>${ab} BOX / ${ap} PCS</td><td></td><td>${sb} BOX / ${sp} PCS</td><td>${ab-sb} BOX / ${ap-sp} PCS</td>`;
    });
  }
  function requestReadyReload(){
    if(retryCount>=5)return;
    clearTimeout(retryTimer);
    retryTimer=setTimeout(()=>{
      retryCount++;
      const btn=document.getElementById('loadReadyBoxes');
      if(btn)btn.click();
      setTimeout(render,350);
    },retryCount===0?300:700);
  }
  function lotSection(lot,groups){
    const rows=TYPES.map(type=>{const key=`${lot}||${type}`;const g=groups.get(key)||{lot,type,boxes:[],pcs:0};const disabled=g.boxes.length?'':'disabled';const value=Math.max(0,Math.min(g.boxes.length,Number(sendingState.get(key)||0)|0));return `<tr data-dc-group="${key}"><th>${type==='FRESH'?'REGULAR / FRESH':type}</th><td>${qtyLabel(g)}</td><td><input class="fg-qty-input" data-dc-send="${key}" type="number" min="0" max="${g.boxes.length}" step="1" inputmode="numeric" value="${value}" ${disabled}></td><td data-dc-sent-pcs>0 BOX / 0 PCS</td><td data-dc-balance>${g.boxes.length} BOX / ${g.pcs} PCS</td></tr>`;}).join('');
    return `<section data-dc-lot="${lot}" style="margin:0 0 18px"><div class="fg-table-wrap"><table class="fg-box-table" data-rr-no-gsheet="1"><thead><tr><th colspan="5">LOT ${lot}</th></tr><tr><th>TYPE</th><th>AVAILABLE</th><th>SENDING BOXES</th><th>SENDING</th><th>BALANCE</th></tr></thead><tbody>${rows}<tr data-dc-total></tr></tbody></table></div></section>`;
  }
  function render(){
    if(rendering)return;rendering=true;
    try{
      suppressLegacy();
      const body=document.getElementById('dispatchBoxRows');if(!body)return;
      const wrap=body.closest('.fg-table-wrap');if(!wrap)return;
      let host=document.getElementById('dispatchConsolidated');
      if(!host){host=document.createElement('div');host.id='dispatchConsolidated';host.className='fg-table-wrap';wrap.parentNode.insertBefore(host,wrap);}
      snapshotHost(host);
      const groups=readGroups();
      const sig=rawSignature();
      const changed=Boolean(lastRawSignature&&sig!==lastRawSignature);
      lastRawSignature=sig;
      seedState(groups,changed);
      clearFilteredSelections(groups);
      const allowed=allowedLots();
      const lots=[...new Set([...groups.values()].map(g=>g.lot))].filter(lot=>!allowed||allowed.has(String(lot))).sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}));
      if(!lots.length){wrap.style.display='none';retryCount=0;clearTimeout(retryTimer);host.innerHTML='<div class="fg-muted" style="padding:12px">Selected Packer Queue me koi ready lot nahi hai.</div>';return;}
      retryCount=0;clearTimeout(retryTimer);wrap.style.display='none';
      host.innerHTML=lots.map(lot=>lotSection(lot,groups)).join('');
      host.querySelectorAll('[data-dc-send]').forEach(inp=>inp.addEventListener('input',()=>applySelections(host)));
      applySelections(host);
    }finally{rendering=false;}
  }
  function init(){
    const body=document.getElementById('dispatchBoxRows');if(!body)return;
    suppressLegacy();
    new MutationObserver(()=>{suppressLegacy();setTimeout(render,0);}).observe(document.body,{childList:true,subtree:true});
    document.getElementById('loadReadyBoxes')?.addEventListener('click',()=>setTimeout(render,450));
    window.addEventListener('redzed:supabase-ready',requestReadyReload,{passive:true});
    window.addEventListener('redzed:despatch-packer-filter',()=>setTimeout(render,0),{passive:true});
    window.addEventListener('focus',()=>{if(!rawRows().length)requestReadyReload();},{passive:true});
    window.addEventListener('online',()=>{if(!rawRows().length)requestReadyReload();},{passive:true});
    setTimeout(render,0);setTimeout(requestReadyReload,250);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();