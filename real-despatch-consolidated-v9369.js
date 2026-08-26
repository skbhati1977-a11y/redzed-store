(()=>{
  'use strict';
  const TYPES=['FRESH','ASST','MIX'];
  const typeOf=v=>{const t=String(v||'').trim().toUpperCase();return t==='REGULAR'||t==='FRESH'?'FRESH':t==='MIX'?'MIX':'ASST';};
  const qtyLabel=g=>{if(!g.boxes.length)return '0 BOX / 0 PCS';const qs=[...new Set(g.boxes.map(x=>x.qty))];return qs.length===1?`${g.boxes.length} × ${qs[0]} = ${g.pcs} PCS`:`${g.boxes.length} BOX / ${g.pcs} PCS`;};
  let rendering=false;
  function rawRows(){return [...document.querySelectorAll('#dispatchBoxRows tr[data-box-id]')];}
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
  function applySelections(host){
    const groups=readGroups();
    rawRows().forEach(row=>{const ch=row.querySelector('[data-dispatch-check]'),q=row.querySelector('[data-dispatch-qty]');if(ch)ch.checked=false;if(q)q.value='';});
    host.querySelectorAll('[data-dc-send]').forEach(inp=>{
      const g=groups.get(inp.dataset.dcSend);if(!g)return;
      let n=Math.max(0,Math.min(g.boxes.length,Number(inp.value||0)|0));inp.value=n||'';
      g.boxes.slice(0,n).forEach(({row,qty})=>{const ch=row.querySelector('[data-dispatch-check]'),q=row.querySelector('[data-dispatch-qty]');if(ch)ch.checked=true;if(q)q.value=qty;});
    });
    const first=rawRows()[0]?.querySelector('[data-dispatch-check]');if(first)first.dispatchEvent(new Event('input',{bubbles:true}));
    renderBalances(host,groups);
  }
  function renderBalances(host,groups){
    host.querySelectorAll('tr[data-dc-group]').forEach(tr=>{
      const g=groups.get(tr.dataset.dcGroup);if(!g)return;
      const inp=tr.querySelector('[data-dc-send]');const n=Math.max(0,Math.min(g.boxes.length,Number(inp?.value||0)|0));
      const sent=g.boxes.slice(0,n).reduce((s,x)=>s+x.qty,0);
      const sendCell=tr.querySelector('[data-dc-sent-pcs]'),balCell=tr.querySelector('[data-dc-balance]');
      if(sendCell)sendCell.textContent=`${n} BOX / ${sent} PCS`;
      if(balCell)balCell.textContent=`${g.boxes.length-n} BOX / ${g.pcs-sent} PCS`;
    });
    host.querySelectorAll('[data-dc-lot]').forEach(section=>{
      const lot=section.dataset.dcLot;
      const gs=TYPES.map(type=>groups.get(`${lot}||${type}`)||{boxes:[],pcs:0});
      const availableBoxes=gs.reduce((n,g)=>n+g.boxes.length,0),availablePcs=gs.reduce((n,g)=>n+g.pcs,0);
      let sendingBoxes=0,sendingPcs=0;
      TYPES.forEach(type=>{
        const g=groups.get(`${lot}||${type}`);if(!g)return;
        const inp=section.querySelector(`[data-dc-send="${CSS.escape(`${lot}||${type}`)}"]`);
        const n=Math.max(0,Math.min(g.boxes.length,Number(inp?.value||0)|0));
        sendingBoxes+=n;sendingPcs+=g.boxes.slice(0,n).reduce((s,x)=>s+x.qty,0);
      });
      const t=section.querySelector('[data-dc-lot-total]');if(t)t.innerHTML=`<th>LOT TOTAL</th><td>${availableBoxes} BOX / ${availablePcs} PCS</td><td></td><td>${sendingBoxes} BOX / ${sendingPcs} PCS</td><td>${availableBoxes-sendingBoxes} BOX / ${availablePcs-sendingPcs} PCS</td>`;
    });
  }
  function lotTable(lot,groups){
    const rows=TYPES.map(type=>{
      const key=`${lot}||${type}`,g=groups.get(key)||{lot,type,boxes:[],pcs:0};
      const disabled=g.boxes.length?'':'disabled';
      return `<tr data-dc-group="${key}"><th>${type==='FRESH'?'REGULAR / FRESH':type}</th><td>${qtyLabel(g)}</td><td><input class="fg-qty-input" data-dc-send="${key}" type="number" min="0" max="${g.boxes.length}" step="1" inputmode="numeric" placeholder="0" ${disabled}></td><td data-dc-sent-pcs>0 BOX / 0 PCS</td><td data-dc-balance>${g.boxes.length} BOX / ${g.pcs} PCS</td></tr>`;
    }).join('');
    return `<section class="dc-lot-section" data-dc-lot="${lot}" style="margin:0 0 18px"><div class="fg-table-wrap"><table class="fg-box-table" data-rr-no-gsheet="1"><thead><tr><th colspan="5">LOT ${lot}</th></tr><tr><th>TYPE</th><th>AVAILABLE</th><th>SENDING BOXES</th><th>SENDING</th><th>BALANCE</th></tr></thead><tbody>${rows}<tr data-dc-lot-total></tr></tbody></table></div></section>`;
  }
  function render(){
    if(rendering)return;rendering=true;
    try{
      const body=document.getElementById('dispatchBoxRows');if(!body)return;
      const wrap=body.closest('.fg-table-wrap');if(!wrap)return;
      let host=document.getElementById('dispatchConsolidated');
      if(!host){host=document.createElement('div');host.id='dispatchConsolidated';wrap.parentNode.insertBefore(host,wrap);}
      wrap.style.display='none';
      const groups=readGroups();
      const lots=[...new Set([...groups.values()].map(g=>g.lot))].sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}));
      if(!lots.length){host.innerHTML='<div class="fg-muted" style="padding:12px">Koi Ready Box nahi hai.</div>';return;}
      host.innerHTML=lots.map(lot=>lotTable(lot,groups)).join('');
      host.querySelectorAll('[data-dc-send]').forEach(inp=>inp.addEventListener('input',()=>applySelections(host)));
      renderBalances(host,groups);
    }finally{rendering=false;}
  }
  function init(){
    const body=document.getElementById('dispatchBoxRows');if(!body)return;
    render();
    new MutationObserver(()=>render()).observe(body,{childList:true,subtree:false});
    document.getElementById('loadReadyBoxes')?.addEventListener('click',()=>setTimeout(render,250));
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();