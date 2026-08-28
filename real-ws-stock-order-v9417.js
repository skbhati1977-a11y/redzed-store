(()=>{
'use strict';
if(window.__RR_WS_STOCK_ORDER_V9417__)return;
window.__RR_WS_STOCK_ORDER_V9417__=true;
if(!/\/real-finished-goods-v787\.html$/i.test(location.pathname))return;

function reorder(){
  const head=document.getElementById('rr9415mainhead');
  const body=document.getElementById('rr9415mainbody');
  if(!head||!body)return;
  const headers=[...head.children];
  if(headers.length<3)return;
  const findIndex=txt=>headers.findIndex(h=>String(h.textContent||'').trim()===txt);
  const iAvail=findIndex('Available');
  const iSales=findIndex('TTL Sales PCS');
  const iRec=findIndex('TTL Rec PCS');
  if(iAvail<0||iSales<0||iRec<0)return;

  const desired=[];
  headers.forEach((h,i)=>{if(![iAvail,iSales,iRec].includes(i))desired.push(h)});
  const insertAt=Math.min(iAvail,iSales,iRec);
  desired.splice(insertAt,0,headers[iAvail],headers[iSales],headers[iRec]);
  desired.forEach(n=>head.appendChild(n));

  body.querySelectorAll('.rr9415-row').forEach(row=>{
    const cells=[...row.children];
    if(cells.length!==headers.length)return;
    const map=new Map(headers.map((h,i)=>[h,cells[i]]));
    desired.forEach(h=>{const c=map.get(h);if(c)row.appendChild(c)});
  });
}

new MutationObserver(reorder).observe(document.documentElement,{childList:true,subtree:true});
document.addEventListener('DOMContentLoaded',()=>setTimeout(reorder,250));
setTimeout(reorder,250);
})();