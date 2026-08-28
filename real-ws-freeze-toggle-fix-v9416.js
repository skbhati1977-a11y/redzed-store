(()=>{
'use strict';
if(window.__RR_WS_FREEZE_TOGGLE_FIX_V9419__)return;window.__RR_WS_FREEZE_TOGGLE_FIX_V9419__=true;
if(!/\/real-finished-goods-v787\.html$/i.test(location.pathname))return;
let last=0;
function isTarget(t){const g=document.getElementById('rr9419grid');if(!g||!t?.closest)return false;if(g.classList.contains('frozen'))return !!t.closest('[data-freeze-toggle],.rr9419-left-row,.rr9419-left-head');const h=t.closest('.rr9419-main-head-cell');if(h)return [...h.parentElement.children].indexOf(h)<2;const c=t.closest('.rr9419-row .rr9419-cell');return c?[...c.parentElement.children].indexOf(c)<2:false}
document.addEventListener('click',e=>{if(!isTarget(e.target))return;const n=Date.now();if(n-last<430){last=0;e.preventDefault();e.stopImmediatePropagation();window.__rr9419ToggleFreeze?.()}else last=n},true);
document.addEventListener('dblclick',e=>{if(isTarget(e.target)){e.preventDefault();e.stopImmediatePropagation()}},true);
})();