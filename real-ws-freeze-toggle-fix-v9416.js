(()=>{
'use strict';
if(window.__RR_WS_FREEZE_TOGGLE_FIX_V9416__)return;
window.__RR_WS_FREEZE_TOGGLE_FIX_V9416__=true;
if(!/\/real-finished-goods-v787\.html$/i.test(location.pathname))return;
let lastTap=0;
function isTarget(t){const g=document.getElementById('rr9415grid');if(!g||!t?.closest)return false;if(t.closest('[data-freeze-toggle]'))return true;if(!g.classList.contains('frozen')){const h=t.closest('.rr9415-main-head-cell');if(h&&[...h.parentElement.children].indexOf(h)<2)return true;const c=t.closest('.rr9415-row .rr9415-cell');if(c&&[...c.parentElement.children].indexOf(c)<2)return true}return false}
document.addEventListener('click',e=>{if(!isTarget(e.target))return;const n=Date.now();if(n-lastTap<430){lastTap=0;e.preventDefault();e.stopImmediatePropagation();window.__rr9415ToggleFreeze?.()}else lastTap=n},true);
document.addEventListener('dblclick',e=>{if(isTarget(e.target)){e.preventDefault();e.stopImmediatePropagation()}},true);
})();