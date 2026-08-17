(()=>{
'use strict';
const C=window.ACCESSORY_MASTER_CONFIG||{},item=String(C.itemType||'').toUpperCase();
if(!['STICKER','METAL_ID'].includes(item))return;
const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const mode=()=>String(new URLSearchParams(location.search).get('mode')||document.getElementById('dataMode')?.value||'TEST').toUpperCase();
const idField=item==='STICKER'?'sticker_master_id':'metal_id_master_id';
async function refresh(){const c=db();if(!c)return;const r=await c.from('rr_accessory_stock_balance_v804').select(`${idField},physical_stock_qty,open_requirement_qty,free_stock_qty`).eq('data_mode',mode()).eq('item_type',item);if(r.error){console.warn('available stock',r.error);return}const map=new Map((r.data||[]).map(x=>[String(x[idField]||''),x]));document.querySelectorAll('#cards .rr-accessory-library-card[data-master-id]').forEach(card=>{const x=map.get(String(card.dataset.masterId||''));if(!x)return;let box=card.querySelector('.rr-accessory-closing');if(!box)return;const s=box.querySelector('small'),v=box.querySelector('strong');if(s)s.textContent='AVAILABLE STOCK';if(v)v.textContent=String(Number(x.free_stock_qty||0).toLocaleString('en-IN',{maximumFractionDigits:2}));box.title=`Physical ${Number(x.physical_stock_qty||0)} · Active Reserved ${Number(x.open_requirement_qty||0)} · Available ${Number(x.free_stock_qty||0)}`;});}
let n=0;const t=setInterval(()=>{if(document.querySelector('#cards .rr-accessory-library-card')){clearInterval(t);refresh();new MutationObserver(()=>setTimeout(refresh,50)).observe(document.getElementById('cards'),{childList:true,subtree:true});document.getElementById('dataMode')?.addEventListener('change',refresh)}else if(++n>80)clearInterval(t)},100);
})();