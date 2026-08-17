(()=>{
'use strict';
const ALIAS={KR:'STITCHING',KARIGAR:'STITCHING',STITCH:'STITCHING',STITCHING:'STITCHING',OV:'OVERLOCK',OVERLOCK:'OVERLOCK',FLD:'FOLDING',FLATLOCK:'FOLDING',FOLDING:'FOLDING',KAAJ:'KAAJ',KAJ:'KAAJ',BUTTON:'BUTTON',BTN:'BUTTON',THREAD_CUT:'THREAD_CUT',THREAD_CUTTING:'THREAD_CUT',TH_CUT:'THREAD_CUT',QC:'QC',CHECKING:'QC',PRESS:'PRESS',FINISHING:'PRESS',PRINT:'PRINTING',PRINTING:'PRINTING',STICKER:'STICKER',ID:'METAL_ID',ID_WORK:'METAL_ID',METAL_ID:'METAL_ID',PACK:'PACKING',PACKING:'PACKING'};
const ACTIVE=new Set(['PRINTING','STICKER','METAL_ID','STITCHING','KAAJ','BUTTON','OVERLOCK','FOLDING','THREAD_CUT','QC','PRESS','PACKING']);
const canonical=v=>ALIAS[String(v||'').trim().toUpperCase()]||String(v||'').trim().toUpperCase();
function routeDepartment(raw,label,opts={}){
 const dept=canonical(raw);if(!ACTIVE.has(dept))return false;
 const q=new URLSearchParams(location.search),mode=String(opts.mode||q.get('mode')||'TEST').trim().toUpperCase()==='REAL'?'REAL':'TEST';
 location.href=`real-department-lite-v9127.html?dept=${encodeURIComponent(dept)}&label=${encodeURIComponent(String(label||dept).trim())}&mode=${encodeURIComponent(mode)}&from=${encodeURIComponent(opts.from||'UPM')}&v=9157`;
 return true;
}
window.RRCanonicalDepartment=canonical;
window.RRRouteDepartment=routeDepartment;
const select=document.getElementById('homeDept');
if(!select)return;
select.addEventListener('change',e=>{
 if(!select.value)return;
 const option=select.options[select.selectedIndex],label=String(option?.textContent||select.value).replace(/^[^A-Z0-9]+/i,'').trim();
 if(routeDepartment(select.value,label)){e.preventDefault();e.stopImmediatePropagation();}
},true);
})();