(()=>{
'use strict';
const select=document.getElementById('homeDept');
if(!select)return;
const ALIAS={KR:'STITCHING',KARIGAR:'STITCHING',STITCH:'STITCHING',STITCHING:'STITCHING',OV:'OVERLOCK',OVERLOCK:'OVERLOCK',FLD:'FOLDING',FLATLOCK:'FOLDING',FOLDING:'FOLDING',KAAJ:'KAAJ',KAJ:'KAAJ',BUTTON:'BUTTON',BTN:'BUTTON',KAAJ_BUTTON:'KAAJ_BUTTON',TEAK:'TEAK_TANKI',TANKI:'TEAK_TANKI',TEAK_TANKI:'TEAK_TANKI',THREAD_CUT:'THREAD_CUT',THREAD_CUTTING:'THREAD_CUT',TH_CUT:'THREAD_CUT',QC:'QC',CHECKING:'QC',PRESS:'PRESS',FINISHING:'PRESS',PRINT:'PRINTING',PRINTING:'PRINTING',STICKER:'STICKER',ID:'METAL_ID',ID_WORK:'METAL_ID',METAL_ID:'METAL_ID',PACK:'PACKING',PACKING:'PACKING',DISPATCH:'DESPATCH',DESPATCH:'DESPATCH',CUT:'CUTTING',CUTTING:'CUTTING'};
function canonical(v){v=String(v||'').trim().toUpperCase();return ALIAS[v]||v}
function route(){const dept=canonical(select.value);if(!dept)return;const option=select.options[select.selectedIndex],label=String(option?.textContent||dept).replace(/^[^A-Z0-9]+/i,'').trim();location.href=`real-department-lite-v9127.html?dept=${encodeURIComponent(dept)}&label=${encodeURIComponent(label)}&mode=TEST&from=UPM&v=9173`;}
select.addEventListener('change',e=>{if(!select.value)return;e.stopImmediatePropagation();route();},true);
})();