(()=>{
  'use strict';
  if(window.__RR_PACKING_WORKER_MAP_V9356__)return;
  window.__RR_PACKING_WORKER_MAP_V9356__=true;
  let lastCard=null,manualValue='';
  const $=id=>document.getElementById(id);
  const txt=n=>String(n?.textContent||'').replace(/\s+/g,' ').trim();
  function norm(v){return String(v||'').toLowerCase().replace(/\s+/g,' ').trim();}
  function selectedLot(){return txt($('selectedPackLot')).replace(/^Lot\s+/i,'').trim();}
  function cardPacker(card){
    const rows=[...(card?.querySelectorAll?.('.fg-card-line')||[])];
    for(const row of rows){
      const parts=[...row.children].map(txt);
      if(/^packer$/i.test(parts[0]||''))return parts.slice(1).join(' ').trim();
    }
    const raw=txt(card),m=raw.match(/Packer\s+(.+)$/i);
    return m?m[1].trim():'';
  }
  function metaPacker(){
    const meta=$('selectedPackMeta');
    const chips=[...(meta?.querySelectorAll?.('.fg-chip')||[])];
    for(const chip of chips){
      const t=txt(chip),m=t.match(/^Packer\s+(.+)$/i);
      if(m)return m[1].trim();
    }
    const raw=txt(meta),m=raw.match(/Packer\s+([^A-Z]+?)(?:Admin\/Manager|Algorithm|$)/i);
    return m?m[1].trim():'';
  }
  function findOptionByName(sel,name){
    const n=norm(name);
    if(!sel||!n||/not assigned/i.test(name))return null;
    return [...sel.options].find(o=>norm(o.textContent).startsWith(n)||norm(o.textContent).includes(n));
  }
  function sync(){
    const sel=$('packWorker'),block=$('assignPackBlock'),btn=$('assignPack');
    if(!sel||!block)return;
    const lot=selectedLot();
    const mappedName=metaPacker()||((lastCard&&String(lastCard.lot||'')===lot)?lastCard.packer:'');
    const opt=findOptionByName(sel,mappedName);
    if(opt){
      if(sel.value!==opt.value){sel.value=opt.value;sel.dispatchEvent(new Event('change',{bubbles:true}));}
      block.hidden=false;
      sel.disabled=true;
      sel.dataset.rrMappedWorker='1';
      if(btn)btn.hidden=true;
      return;
    }
    if(sel.dataset.rrMappedWorker==='1'){
      sel.disabled=false;
      delete sel.dataset.rrMappedWorker;
      if(btn)btn.hidden=false;
    }
    if(!block.hidden&&manualValue&&sel.value!==manualValue&&[...sel.options].some(o=>o.value===manualValue)){
      sel.value=manualValue;
    }
  }
  document.addEventListener('click',e=>{
    const card=e.target?.closest?.('[data-pack-lot]');
    if(card)lastCard={lot:String(card.dataset.packLot||''),packer:cardPacker(card)};
    setTimeout(sync,80);setTimeout(sync,350);setTimeout(sync,900);
  },true);
  document.addEventListener('change',e=>{
    if(e.target?.id==='packWorker'&&!e.target.disabled)manualValue=e.target.value||manualValue;
  },true);
  new MutationObserver(()=>setTimeout(sync,0)).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden','disabled']});
  [100,300,700,1200,2000].forEach(ms=>setTimeout(sync,ms));
})();