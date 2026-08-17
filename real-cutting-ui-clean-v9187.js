(()=>{
'use strict';
if(window.__RR_CUTTING_CLEAN_9187__)return;window.__RR_CUTTING_CLEAN_9187__=true;
if(!/\/real-cutting-master\.html$/i.test(location.pathname))return;
const st=document.createElement('style');st.id='rrCuttingClean9187';st.textContent=`
/* V9187 — UI only. Preserve data/status/errors; remove explanatory verbosity. */
.cm-hero,.cm-section-head{display:none!important}
.cm-kicker,.cm-links{display:none!important}
.cm-topbar{min-height:62px!important;padding:12px 2px 10px!important;margin:0!important}
.cm-topbar h1{font-size:clamp(26px,7vw,36px)!important;line-height:1.08!important;margin:0!important}
.cm-toolbar{margin-top:8px!important}
.cm-toolbar>label>span{display:none!important}
#cmSearch{min-height:46px!important}
.cm-card>p,.cm-card .cm-rule-note{display:none!important}
.cm-sheet-head small,.cm-sheet-head p,.cm-form-title p,.cm-rule-note{display:none!important}
.rr-cba-head p,.rr-cba-panel>p,.rr-cba-item>p{display:none!important}
.cm-form-card>p:not(.rr-message),.cm-form-card>.cm-rule-note{display:none!important}
.cm-empty p{display:none!important}
.cm-sheet-head{min-height:58px!important}
.cm-sheet-head h2{margin:0!important}
.cm-form-card h3{margin-bottom:10px!important}
.cm-actions{margin-top:10px!important;padding-top:10px!important}
@media(max-width:720px){.cm-page{padding-inline:10px!important}.cm-topbar{min-height:58px!important}.cm-toolbar{margin-top:6px!important}.cm-card{padding:12px!important}}
`;document.head.appendChild(st);
function clean(){
 const h=document.querySelector('.cm-topbar h1');if(h)h.textContent='Cutting Master';
 const map={ready:'Ready Lot',released:'Released Lot',all:'All',child:'D Cards',completed:'Completed'};
 document.querySelectorAll('#cmFilters button[data-filter]').forEach(b=>{const k=b.dataset.filter;if(map[k])b.textContent=map[k]});
 document.querySelectorAll('.cm-sheet-head p,.cm-form-title p,.cm-rule-note,.rr-cba-head p').forEach(n=>n.setAttribute('aria-hidden','true'));
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',clean,{once:true});else clean();
setTimeout(clean,200);setTimeout(clean,800);
})();