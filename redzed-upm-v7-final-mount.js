(() => {
  'use strict';
  const VERSION = '720810';
  const CUTTING_URL = `real-cutting-master.html?v=${VERSION}`;

  const create = (tag, attrs = {}, html = '') => {
    const el = document.createElement(tag);
    Object.entries(attrs).forEach(([k,v]) => {
      if (k === 'class') el.className = v;
      else if (k === 'text') el.textContent = v;
      else el.setAttribute(k,v);
    });
    if (html) el.innerHTML = html;
    return el;
  };

  function installStyles(){
    if(document.getElementById('rrUpmUnifiedV7Style')) return;
    const s=create('style',{id:'rrUpmUnifiedV7Style'});
    s.textContent=`
      body.rr-upm-unified-v7{overflow-x:hidden}
      .rr-v7-shell{position:sticky;top:0;z-index:8500;display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap;padding:10px 14px;border-bottom:1px solid #383842;background:rgba(15,15,19,.97);backdrop-filter:blur(10px)}
      .rr-v7-title small{display:block;color:#d9a93d;font-weight:900}.rr-v7-title strong{font-size:16px}
      .rr-v7-tabs{display:flex;gap:8px;flex-wrap:wrap}.rr-v7-tabs button{border:1px solid #383842;background:#202027;color:#fff;border-radius:10px;padding:9px 12px;font-weight:850;cursor:pointer}
      .rr-v7-tabs button.is-active{background:linear-gradient(#d24a59,#9b2d39);border-color:#e25a68}
      .rr-v7-panel[hidden]{display:none!important}.rr-v7-cutting-panel{height:calc(100vh - 72px);min-height:650px}
      .rr-v7-cutting-frame{display:block;width:100%;height:100%;border:0;background:#0b0b0e}
      .rr-v7-note{padding:7px 14px;color:#aaaab4;background:#111116;border-bottom:1px solid #2e2e36;font-size:12px}
      @media(max-width:720px){.rr-v7-shell{align-items:flex-start}.rr-v7-title{width:100%}.rr-v7-cutting-panel{height:calc(100vh - 110px);min-height:560px}}
    `;
    document.head.appendChild(s);
  }

  function init(){
    if(document.getElementById('rrUpmUnifiedV7Shell')) return;
    installStyles();
    document.body.classList.add('rr-upm-unified-v7');

    /* Keep global fixed overlays outside the production panel. */
    const fixedOverlayIds = new Set(['rrAssignModalV8','imageViewer']);
    const overlays = [...document.body.children].filter(el => fixedOverlayIds.has(el.id));
    const existingNodes = [...document.body.childNodes].filter(node => !overlays.includes(node));

    const shell=create('header',{id:'rrUpmUnifiedV7Shell',class:'rr-v7-shell'});
    const title=create('div',{class:'rr-v7-title'},'<small>REDZED REAL · UPM V8</small><strong>Cutting → Same Lot No → All Departments</strong>');
    const tabs=create('nav',{class:'rr-v7-tabs','aria-label':'Universal Production modules'});
    const cuttingButton=create('button',{type:'button',text:'Cutting Module'});
    const productionButton=create('button',{type:'button',text:'Department Production'});
    const refreshButton=create('button',{type:'button',text:'Refresh Active'});
    const dashboard=create('button',{type:'button',text:'Dashboard'});
    dashboard.onclick=()=>location.href='real-dashboard-v720372.html';
    tabs.append(cuttingButton,productionButton,refreshButton,dashboard);
    shell.append(title,tabs);

    const note=create('div',{class:'rr-v7-note'});
    note.textContent='Cutting Module unchanged. Released Lot automatically continues in Department Production. Manual Register Lot UI removed.';

    const cuttingPanel=create('section',{id:'rrV7CuttingPanel',class:'rr-v7-panel rr-v7-cutting-panel'});
    const frame=create('iframe',{id:'rrV7CuttingFrame',class:'rr-v7-cutting-frame',src:CUTTING_URL,title:'Existing Cutting Module',loading:'eager'});
    cuttingPanel.appendChild(frame);

    const productionPanel=create('section',{id:'rrV7ProductionPanel',class:'rr-v7-panel'});
    existingNodes.forEach(n=>productionPanel.appendChild(n));

    document.body.append(shell,note,cuttingPanel,productionPanel);
    overlays.forEach(el=>document.body.appendChild(el));

    let active='production';
    try{active=sessionStorage.getItem('rr_upm_v8_active')||'production'}catch(_){}

    function show(name){
      active=name==='cutting'?'cutting':'production';
      const cut=active==='cutting';
      cuttingPanel.hidden=!cut; productionPanel.hidden=cut;
      cuttingButton.classList.toggle('is-active',cut);
      productionButton.classList.toggle('is-active',!cut);
      if(!cut) document.getElementById('refresh')?.click();
      try{sessionStorage.setItem('rr_upm_v8_active',active)}catch(_){}
    }

    cuttingButton.onclick=()=>show('cutting');
    productionButton.onclick=()=>show('production');
    refreshButton.onclick=()=>{
      if(active==='cutting'){
        try{
          const inner=frame.contentDocument?.getElementById('refreshCutting')||frame.contentDocument?.getElementById('refresh');
          inner?inner.click():frame.contentWindow.location.reload();
        }catch(_){frame.src=frame.src}
      }else document.getElementById('refresh')?.click();
    };
    show(active);
  }

  document.readyState==='loading'
    ? document.addEventListener('DOMContentLoaded',init,{once:true})
    : init();
})();