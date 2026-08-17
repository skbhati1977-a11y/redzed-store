(()=>{
'use strict';
const qs=new URLSearchParams(location.search);
const dept=String(qs.get('dept')||'').trim().toUpperCase();
if(dept!=='PRINTING'&&dept!=='PRINT')return;
const apply=()=>{
  const input=document.getElementById('rr9160ChemicalCost');
  if(!input)return;
  input.placeholder='KG';
};
new MutationObserver(apply).observe(document.body,{childList:true,subtree:true});
apply();
})();
