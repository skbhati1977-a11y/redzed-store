(()=>{
'use strict';
if(window.__RR_CUTTING_UI_9186__)return;window.__RR_CUTTING_UI_9186__=true;
if(!/\/real-cutting-master\.html$/i.test(location.pathname))return;

const css=document.createElement('style');
css.textContent=`
:root{--cm-ui-bg:#0b0d11;--cm-ui-card:#12161d;--cm-ui-card2:#171c25;--cm-ui-line:#2a313d;--cm-ui-text:#f7f8fb;--cm-ui-muted:#98a2b3;--cm-ui-accent:#d83f5d;--cm-ui-ok:#56efb2;--cm-ui-warn:#ffc857}
body{background:var(--cm-ui-bg)!important;color:var(--cm-ui-text)!important}
.cm-page{width:min(1100px,100%)!important;padding:0 12px calc(88px + env(safe-area-inset-bottom))!important}
.cm-topbar{min-height:76px!important;padding:16px 2px 12px!important;border-bottom:1px solid var(--cm-ui-line)!important;display:flex!important;align-items:center!important}
.cm-topbar>div:first-child{min-width:0;flex:1}.cm-kicker{display:none!important}.cm-topbar h1{font-size:clamp(28px,7vw,40px)!important;line-height:1.05!important;margin:0!important;letter-spacing:-.02em!important}.cm-links{display:none!important}
.cm-hero{display:none!important}
.cm-toolbar{margin:12px 0 10px!important;padding:12px!important;border-radius:18px!important;background:var(--cm-ui-card)!important;border:1px solid var(--cm-ui-line)!important;box-shadow:none!important}
.cm-toolbar label span{font-size:11px!important;color:var(--cm-ui-muted)!important;margin-bottom:7px!important}.cm-toolbar input{min-height:48px!important;border-radius:14px!important;background:#0d1117!important;border:1px solid #333b48!important;padding:0 14px!important;font-size:16px!important}
#cmUiActions{display:grid;grid-template-columns:1fr 1fr;gap:9px;margin-bottom:10px}.cm-ui-action{min-height:46px;border-radius:13px;border:1px solid #333b48;background:var(--cm-ui-card2);color:#fff;font-weight:850;padding:0 13px}.cm-ui-action.primary{background:#341b22;border-color:#71313e;color:#ffd7df}
.cm-filters{display:grid!important;grid-template-columns:repeat(5,minmax(max-content,1fr));gap:7px!important;overflow:auto!important;margin-top:10px!important;padding-bottom:2px!important;scrollbar-width:none}.cm-filters::-webkit-scrollbar{display:none}.cm-filters button{min-height:42px!important;padding:0 12px!important;border-radius:12px!important;background:#10141a!important;border:1px solid #2f3744!important;color:#c8d0dc!important;font-size:12px!important;white-space:nowrap}.cm-filters button.is-active{background:#d83f5d!important;color:#fff!important;border-color:#d83f5d!important;outline:0!important}
.cm-stats{grid-template-columns:repeat(5,minmax(0,1fr))!important;gap:8px!important;margin:10px 0 14px!important}.cm-stats article{padding:10px!important;border-radius:14px!important;background:var(--cm-ui-card)!important;border-color:var(--cm-ui-line)!important}.cm-stats small{font-size:10px!important;margin-bottom:4px!important}.cm-stats strong{font-size:19px!important}
.cm-section-head{margin:14px 2px 10px!important}.cm-section-head small{display:none!important}.cm-section-head h2{font-size:18px!important;margin:0!important}
.cm-gallery{grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:10px!important}.cm-card{border-radius:18px!important;background:var(--cm-ui-card)!important;border-color:var(--cm-ui-line)!important;padding:13px!important;box-shadow:none!important}.cm-card h3{font-size:22px!important;margin:7px 0 3px!important}.cm-card p{font-size:12px!important}.cm-actions{gap:8px!important}.cm-actions button{min-height:44px!important;border-radius:12px!important}
.cm-pm-decision,.cm-metrics{gap:7px!important}.cm-pm-decision span,.cm-metrics span,.cm-lot-box,.cm-summary,.cm-weight-summary span,.cm-total-line{border-color:#2c3440!important;background:#0e1218!important;border-radius:12px!important}
.cm-sheet{z-index:2147482000!important;align-items:flex-end!important;padding-top:calc(64px + env(safe-area-inset-top))!important}.cm-backdrop{background:#000b!important;backdrop-filter:blur(3px)}.cm-sheet-panel{width:min(760px,100%)!important;max-height:calc(100dvh - 64px - env(safe-area-inset-top))!important;border-radius:24px 24px 0 0!important;border:1px solid #303846!important;background:#10141a!important;padding:12px 12px calc(18px + env(safe-area-inset-bottom))!important;box-shadow:0 -18px 50px #000a!important}.cm-sheet-panel.cm-wide{width:min(900px,100%)!important}.cm-grab{width:44px!important;height:4px!important;background:#495363!important;margin-bottom:10px!important}.cm-sheet-head{position:sticky!important;top:-12px!important;z-index:4!important;background:#10141af2!important;backdrop-filter:blur(12px)!important;padding:10px 2px 12px!important;margin:0 0 10px!important;border-bottom:1px solid #2c3440!important;align-items:center!important}.cm-sheet-head small{display:none!important}.cm-sheet-head h2{font-size:21px!important;line-height:1.15!important;margin:0!important}.cm-sheet-head p{display:none!important}.cm-sheet-head>button{width:42px!important;height:42px!important;border-radius:12px!important;background:#202735!important;border:1px solid #343d4b!important;font-size:22px!important}
.cm-form{gap:10px!important}.cm-form-card,.cm-notes{padding:12px!important;border-radius:16px!important;background:#141922!important;border:1px solid #2e3744!important}.cm-form-card h3{font-size:15px!important;margin:0 0 11px!important}.cm-form-title{align-items:center!important;margin-top:10px!important}.cm-form-title p,.cm-rule-note{display:none!important}.cm-form-title h3{font-size:15px!important}.cm-form label span,.cm-notes>span{font-size:11px!important;color:#aeb8c7!important;margin-bottom:6px!important}.cm-form input,.cm-form select,.cm-form textarea,.cm-notes textarea{min-height:46px!important;border-radius:12px!important;background:#0c1016!important;border:1px solid #333c49!important;padding:10px 12px!important;font-size:16px!important}.cm-form textarea,.cm-notes textarea{min-height:88px!important;resize:vertical}.cm-grid-2,.cm-grid-3{gap:9px!important}.cm-child-row{border:1px solid #2b3340!important;background:#0d1117!important;border-radius:12px!important}.cm-size-grid{gap:7px!important}.cm-sticky{position:sticky!important;bottom:calc(-18px - env(safe-area-inset-bottom))!important;z-index:5!important;grid-template-columns:1fr 1.4fr!important;gap:9px!important;padding:14px 0 calc(10px + env(safe-area-inset-bottom))!important;background:linear-gradient(#10141a00,#10141a 20%)!important}.cm-sticky button{min-height:50px!important;border-radius:14px!important;font-weight:900!important}.cm-primary{background:#d83f5d!important}.cm-secondary{background:#222935!important;border:1px solid #343d4b!important}.cm-cost-breakup{grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:7px!important}.cm-cost-breakup span:last-child{grid-column:1/-1}.cm-weight-summary{grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:7px!important}
#cmMessage:not(:empty){border-radius:12px!important;font-size:13px!important;padding:10px 12px!important}
@media(max-width:720px){.cm-page{padding-inline:10px!important}.cm-topbar{padding-top:12px!important;min-height:66px!important}.cm-toolbar{padding:10px!important}.cm-filters{grid-template-columns:none!important;grid-auto-flow:column!important;grid-auto-columns:max-content!important}.cm-stats{grid-template-columns:repeat(2,minmax(0,1fr))!important}.cm-gallery{grid-template-columns:1fr!important}.cm-grid-2,.cm-grid-3,.cm-weight-summary,.cm-pm-decision{grid-template-columns:1fr!important}.cm-cost-breakup{grid-template-columns:1fr 1fr!important}.cm-sheet-panel{border-radius:20px 20px 0 0!important}.cm-sheet-head h2{font-size:19px!important}}
@media(max-width:380px){#cmUiActions{grid-template-columns:1fr}.cm-stats{grid-template-columns:1fr 1fr!important}.cm-sticky{grid-template-columns:1fr!important}}
`;
document.head.appendChild(css);

function polish(){
  const toolbar=document.querySelector('.cm-toolbar');
  if(toolbar&&!document.getElementById('cmUiActions')){
    const row=document.createElement('div');row.id='cmUiActions';
    const cost=document.getElementById('openCostSettings');
    const refresh=document.getElementById('refreshCutting');
    if(cost){cost.className='cm-ui-action';cost.textContent='Cost Settings';row.appendChild(cost)}
    if(refresh){refresh.className='cm-ui-action primary';refresh.textContent='Refresh';row.appendChild(refresh)}
    if(row.children.length)toolbar.prepend(row);
  }
  const h=document.querySelector('.cm-section-head h2');if(h)h.textContent='Lots';
  document.querySelectorAll('.cm-sheet-head p,.cm-form-title p,.cm-rule-note').forEach(el=>el.setAttribute('aria-hidden','true'));
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',polish,{once:true});else polish();
setTimeout(polish,250);
})();