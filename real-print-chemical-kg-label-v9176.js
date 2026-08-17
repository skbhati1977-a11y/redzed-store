(()=>{
'use strict';
const qs=new URLSearchParams(location.search);
const dept=String(qs.get('dept')||'').trim().toUpperCase();
if(dept!=='PRINTING'&&dept!=='PRINT')return;
function apply(){
  const input=document.getElementById('rr9160ChemicalCost');
  if(!input)return false;
  input.placeholder='KG';
  input.setAttribute('aria-label','Actual Chemical Cost in KG');
  const field=input.closest('.rr9160-field');
  const label=field?.querySelector('label');
  if(label)label.textContent='Actual Chemical Cost * (consumption/weighing based)';
  return true;
}
new MutationObserver(apply).observe(document.body,{childList:true,subtree:true});
let n=0;const t=setInterval(()=>{if(apply()||++n>100)clearInterval(t)},100);
apply();
})();
