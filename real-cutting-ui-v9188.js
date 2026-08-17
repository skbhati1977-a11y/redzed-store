(()=>{
'use strict';
if(window.__RR_CUTTING_UI_9188__)return;window.__RR_CUTTING_UI_9188__=true;
if(!/\/real-cutting-master\.html$/i.test(location.pathname))return;

const style=document.createElement('style');
style.id='rrCuttingUi9188';
style.textContent=`
/* Root-level Cutting Master cleanup: keep operational data, remove explanatory verbosity. */
.cm-hero{display:none!important}
.cm-kicker{display:none!important}
.cm-links{display:none!important}
.cm-section-head small{display:none!important}
.cm-sheet-head small,.cm-sheet-head p{display:none!important}
.cm-form-title p,.cm-rule-note{display:none!important}
.cm-topbar{min-height:64px!important;padding:12px 0 10px!important}
.cm-topbar h1{margin:0!important;font-size:clamp(28px,7vw,40px)!important;line-height:1.05!important}
.cm-section-head{margin:12px 0 8px!important}
.cm-section-head h2{font-size:19px!important;margin:0!important}
.cm-toolbar{margin-top:10px!important}
.cm-sheet-head{align-items:center!important}
.cm-sheet-head h2{margin:0!important;font-size:21px!important}
.cm-form-title{align-items:center!important}
.cm-form-title h3{margin:0!important}
`;
(document.head||document.documentElement).appendChild(style);

function cleanText(){
  const sectionTitle=document.querySelector('.cm-section-head h2');
  if(sectionTitle)sectionTitle.textContent='Lots';

  const map=new Map([
    ['all','All'],
    ['ready','Ready Lot'],
    ['art_due','D Cards'],
    ['released','Released Lot'],
    ['completed','Completed']
  ]);
  document.querySelectorAll('#cmFilters button[data-filter]').forEach(btn=>{
    const label=map.get(String(btn.dataset.filter||'').toLowerCase());
    if(label)btn.textContent=label;
  });

  document.querySelectorAll('.cm-sheet-head p,.cm-form-title p,.cm-rule-note').forEach(el=>{
    el.hidden=true;
    el.setAttribute('aria-hidden','true');
  });
}

function run(){cleanText();}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',run,{once:true});else run();
setTimeout(run,0);setTimeout(run,250);setTimeout(run,800);
new MutationObserver(run).observe(document.documentElement,{childList:true,subtree:true});
})();