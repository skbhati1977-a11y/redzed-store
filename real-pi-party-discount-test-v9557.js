(()=>{
'use strict';
if(window.__RR_PI_PARTY_DISCOUNT_V9557__)return;
window.__RR_PI_PARTY_DISCOUNT_V9557__=true;
const $=id=>document.getElementById(id),num=v=>Math.max(0,Number(v||0));
let pendingDiscount=null,actor=null,baseRpc=null,mounted=false;

function syncRows(v){
  document.querySelectorAll('#rows input.disc').forEach(el=>{
    el.readOnly=true;
    el.value=String(v);
    el.dispatchEvent(new Event('change',{bubbles:true}));
    el.readOnly=true;
  });
}
function currentFromRows(){const e=document.querySelector('#rows input.disc');return e?Number(e.value||0):0;}
function updateRowLocks(){document.querySelectorAll('#rows input.disc').forEach(el=>el.readOnly=true);}

async function mount(){
  if(mounted)return;
  const customer=$('customer'),dispatch=$('dispatch');
  if(!customer||!dispatch||!window.RF853?.rpc)return;
  mounted=true;
  try{actor=await baseRpc('rr_pi_actor_context_v9526',{});}catch(_){actor={superadmin:false};}
  const card=customer.closest('.card');if(!card)return;
  const addBox=card.querySelector('.addBox');
  const box=document.createElement('div');box.id='partyDiscountBox';box.className='partyDiscountBox';
  box.innerHTML=`<div><b>PARTY DISCOUNT · INTERNAL</b></div><div class="partyDiscountField"><label>Party Discount / PCS</label><input id="partyDiscount" type="number" min="0" max="10" step="0.01"></div>`;
  if(addBox)card.insertBefore(box,addBox);else card.appendChild(box);
  const inp=$('partyDiscount');
  const setInitial=()=>{
    const v=currentFromRows();
    if(document.querySelector('#rows input.disc')){
      inp.value=String(v);pendingDiscount=v;inp.readOnly=!actor?.superadmin;
      syncRows(v);updateRowLocks();return true;
    }return false;
  };
  if(!setInitial()){
    let n=0;const t=setInterval(()=>{if(setInitial()||++n>40)clearInterval(t)},100);
  }
  inp.addEventListener('input',()=>{
    if(!actor?.superadmin)return;
    let v=Number(inp.value);if(!Number.isFinite(v))v=0;
    if(v<0)v=0;if(v>10)v=10;pendingDiscount=v;syncRows(v);
  });
  new MutationObserver(()=>{updateRowLocks();if(pendingDiscount!=null)document.querySelectorAll('#rows input.disc').forEach(el=>{if(Number(el.value||0)!==pendingDiscount){el.value=String(pendingDiscount);el.dispatchEvent(new Event('change',{bubbles:true}));el.readOnly=true;}})}).observe($('rows'),{childList:true,subtree:true});
}

function installRpcShim(){
  if(!window.RF853?.rpc||window.RF853.__partyDiscount9557)return false;
  baseRpc=window.RF853.rpc.bind(window.RF853);
  window.RF853.rpc=async function(name,args={}){
    if(name==='rr_pi_set_customer_discount_v9525'){
      pendingDiscount=num(args.p_discount);
      const inp=$('partyDiscount');if(inp)inp.value=String(pendingDiscount);
      return {ok:true,deferred:true,discount_per_piece:pendingDiscount};
    }
    if(name==='rr_fg_save_pi_v816'){
      const d=pendingDiscount==null?currentFromRows():pendingDiscount;
      return baseRpc('rr_fg_save_pi_party_discount_v9557',{
        p_pi_id:args.p_pi_id??null,
        p_customer_name:args.p_customer_name,
        p_dispatch_details:args.p_dispatch_details,
        p_lines:args.p_lines,
        p_party_discount:d,
        p_freight_amount:args.p_freight_amount??0,
        p_packing_other:args.p_packing_other??0,
        p_gst_pct:args.p_gst_pct??0,
        p_finalize:args.p_finalize??false,
        p_data_mode:args.p_data_mode||'TEST'
      });
    }
    return baseRpc(name,args);
  };
  window.RF853.__partyDiscount9557=true;
  return true;
}

const style=document.createElement('style');
style.textContent='.partyDiscountBox{display:grid;grid-template-columns:1fr minmax(220px,320px);gap:12px;align-items:end;margin-top:12px;padding:12px;border:1px solid #5c4c24;background:#17150d;border-radius:10px}.partyDiscountField label{display:block;color:#d6c58e;font-size:12px;margin-bottom:4px}.partyDiscountField input{width:100%;box-sizing:border-box;background:#0b1119;border:1px solid #806c31;color:#fff;border-radius:7px;padding:10px;font-weight:800}.partyDiscountField input[readonly]{opacity:.8}@media(max-width:650px){.partyDiscountBox{grid-template-columns:1fr}}';
document.head.appendChild(style);

let tries=0;const timer=setInterval(()=>{if(installRpcShim()){clearInterval(timer);mount();}else if(++tries>100)clearInterval(timer)},20);
addEventListener('DOMContentLoaded',()=>{installRpcShim();mount()});
})();