(()=>{"use strict";
const safe=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const mapped=new Map();
let busy=false;
function decorate(){
  document.querySelectorAll("[data-person]").forEach(row=>{
    const item=mapped.get(String(row.dataset.person));
    if(!item||row.dataset.salaryMapped78)return;
    row.dataset.salaryMapped78="1";
    const text=row.querySelector("small");
    if(text)text.insertAdjacentHTML("beforeend",` · <b class="salary-map-v78">Salary Ledger mapped</b>`);
  });
}
function ledgerRow(workerId){
  const item=mapped.get(String(workerId)),box=document.getElementById("messages");
  if(!item||!box||box.querySelector("[data-salary-ledger-v78]"))return;
  const row=document.createElement("a");
  row.dataset.salaryLedgerV78=item.salary_ledger_id;
  row.className="salary-ledger-v78";
  row.href=`real-accounts-v805.html?v=9787&scope=SALARY&ledger_id=${encodeURIComponent(item.salary_ledger_id)}`;
  row.innerHTML=`<span>₹</span><b>Salary &amp; Wages Ledger</b><small>${safe(item.worker_name)} · ${safe(item.department_code||"Department")} · ${safe(item.payroll_category||"Salary")}</small><em>OPEN ›</em>`;
  box.prepend(row);
}
async function load(){
  if(busy||!window.supabaseClient)return;busy=true;
  try{
    const session=await supabaseClient.auth.getSession();
    if(!session.data?.session)return;
    const r=await supabaseClient.rpc("rr_test70_worker_accounts_map_v78");
    if(r.error)throw r.error;
    (Array.isArray(r.data)?r.data:[]).forEach(x=>mapped.set(String(x.worker_id),x));
    decorate();
  }catch(e){console.error("TEST70 worker accounts mapping:",e)}finally{busy=false}
}
document.addEventListener("click",e=>{
  const row=e.target.closest?.("[data-person]");
  if(row)setTimeout(()=>ledgerRow(row.dataset.person),80);
},true);
const style=document.createElement("style");
style.textContent=".salary-map-v78{color:#8ce5b5}.salary-ledger-v78{display:grid;grid-template-columns:38px 1fr auto;gap:3px 9px;align-items:center;margin:0 0 8px;padding:10px;border:1px solid #39725d;border-radius:12px;background:#102d26;color:#fff;text-decoration:none}.salary-ledger-v78>span{grid-row:1/3;width:36px;height:36px;display:grid;place-items:center;border-radius:50%;background:#1d624c;font-size:20px;font-weight:900}.salary-ledger-v78>b{font-size:13px}.salary-ledger-v78>small{color:#a9caba;font-size:10px}.salary-ledger-v78>em{grid-column:3;grid-row:1/3;color:#8ce5b5;font-size:11px;font-style:normal;font-weight:900}";
document.head.appendChild(style);
new MutationObserver(decorate).observe(document.documentElement,{childList:true,subtree:true});
document.readyState==="loading"?document.addEventListener("DOMContentLoaded",()=>{setTimeout(load,400)},{once:true}):setTimeout(load,400);
window.__TEST70_WORKER_ACCOUNTS_V78__={mapped,refresh:load};
})();
