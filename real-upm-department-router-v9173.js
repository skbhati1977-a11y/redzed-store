(()=>{
'use strict';
const KAAJ_KEYS=['KAAJ','KAJ','KASJ','BUTTON','BTN','BT','BATTAN','BATAN','KAAJBUTTON','KAJBUTTON','KASJBUTTON','KAAJBTN','KAJBTN','KASJBTN','KAAJBATTAN','KAJBATTAN','KASJBATTAN','BUTTONKAAJ','BUTTONKAJ','BUTTONKASJ','BTNKAAJ','BTNKAJ','BTNKASJ'];
const ALIAS={KR:'STITCHING',KARIGAR:'STITCHING',STITCH:'STITCHING',STITCHING:'STITCHING',OV:'OVERLOCK',OVERLOCK:'OVERLOCK',FLD:'FOLDING',FLATLOCK:'FOLDING',FOLDING:'FOLDING',TEAK:'TEAK_TANKI',TANKI:'TEAK_TANKI',TEAK_TANKI:'TEAK_TANKI',KAAJ:'KAAJ_BUTTON',KAJ:'KAAJ_BUTTON',KASJ:'KAAJ_BUTTON',BUTTON:'KAAJ_BUTTON',BTN:'KAAJ_BUTTON',BT:'KAAJ_BUTTON',BATTAN:'KAAJ_BUTTON',BATAN:'KAAJ_BUTTON',THREAD_CUT:'THREAD_CUT',THREAD_CUTTING:'THREAD_CUT',TH_CUT:'THREAD_CUT',QC:'QC',CHECKING:'QC',PRESS:'PRESS',FINISHING:'PRESS',PRINT:'PRINTING',PRINTING:'PRINTING',STICKER:'STICKER',ID:'METAL_ID',ID_WORK:'METAL_ID',METAL_ID:'METAL_ID',PACK:'PACKING',PACKING:'PACKING',DISPATCH:'DESPATCH',DESPATCH:'DESPATCH'};
const ACTIVE=new Set(['PRINTING','STICKER','METAL_ID','STITCHING','OVERLOCK','FOLDING','TEAK_TANKI','KAAJ_BUTTON','THREAD_CUT','QC','PRESS','PACKING','DESPATCH']);
const NAMES={PRINTING:'Print',STICKER:'Sticker',METAL_ID:'Metal ID',STITCHING:'Karigar / Stitching',TEAK_TANKI:'Teak / Tanki',KAAJ_BUTTON:'Kaaj / Btn',DESPATCH:'Despatch',OVERLOCK:'Overlock',FOLDING:'Folding',THREAD_CUT:'Thread Cutting',QC:'QC',PRESS:'Press',PACKING:'Packing'};
const canonical=v=>{const raw=String(v||'').trim().toUpperCase(),key=raw.replace(/[^A-Z0-9]+/g,'');return KAAJ_KEYS.includes(key)?'KAAJ_BUTTON':(ALIAS[raw]||ALIAS[key]||raw)};
const isActive=v=>ACTIVE.has(canonical(v));
function routeDepartment(raw,label,opts={}){
 const dept=canonical(raw);if(!ACTIVE.has(dept))return false;
 const q=new URLSearchParams(location.search),mode=String(opts.mode||q.get('mode')||'TEST').trim().toUpperCase()==='REAL'?'REAL':'TEST';
 const resolvedLabel=NAMES[dept]||String(label||dept).trim();
 location.href=`real-department-lite-v9127.html?dept=${encodeURIComponent(dept)}&label=${encodeURIComponent(resolvedLabel)}&mode=${encodeURIComponent(mode)}&from=${encodeURIComponent(opts.from||'UPM')}&v=9175`;
 return true;
}
window.RRCanonicalDepartment=canonical;
window.RRCanonicalDepartmentName=v=>NAMES[canonical(v)]||canonical(v);
window.RRIsActiveDepartment=isActive;
window.RRRouteDepartment=routeDepartment;
const select=document.getElementById('homeDept');
if(!select)return;
select.addEventListener('change',e=>{
 if(!select.value)return;
 const dept=canonical(select.value);
 if(routeDepartment(dept,NAMES[dept]||dept)){e.preventDefault();e.stopImmediatePropagation();}
},true);
})();
