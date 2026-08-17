(()=>{
'use strict';
const C=window.ACCESSORY_MASTER_CONFIG||{};
if(!['STICKER','METAL_ID'].includes(String(C.itemType||'').toUpperCase()))return;
const style=document.createElement('style');
style.textContent=`
#cards.cards{display:grid!important;grid-template-columns:repeat(auto-fill,minmax(220px,1fr))!important;gap:14px!important}
#cards .rr-accessory-library-card{overflow:hidden;border:1px solid var(--line);background:var(--panel);border-radius:15px;padding:0;min-width:0}
#cards .rr-accessory-library-image{width:100%;aspect-ratio:4/3;background:#0d0d11;display:grid;place-items:center;overflow:hidden;border:0;border-radius:0;padding:0;cursor:pointer}
#cards .rr-accessory-library-image img{width:100%;height:100%;object-fit:cover;display:block}
#cards .rr-accessory-library-placeholder{color:var(--muted);font-size:12px;font-weight:800;letter-spacing:.04em}
#cards .rr-accessory-library-caption{padding:12px 13px 13px}
#cards .rr-accessory-library-no{font-size:18px;font-weight:900;line-height:1.15;margin:0 0 3px}
#cards .rr-accessory-library-name{font-size:14px;font-weight:750;margin:0;color:var(--text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#cards .rr-accessory-library-meta{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:8px;color:var(--muted);font-size:11px}
#cards .rr-accessory-library-tag{border:1px solid var(--line);border-radius:999px;padding:4px 7px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#cards .rr-accessory-library-actions{display:flex;gap:7px;margin-top:11px}
#cards .rr-accessory-library-actions button{flex:1;padding:8px 9px;min-width:0}
@media(max-width:600px){#cards.cards{grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:9px!important}#cards .rr-accessory-library-caption{padding:9px}#cards .rr-accessory-library-no{font-size:15px}#cards .rr-accessory-library-actions{gap:5px}#cards .rr-accessory-library-actions button{padding:7px 5px;font-size:12px}}
`;
document.head.appendChild(style);
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
function transform(){
 const root=document.getElementById('cards'); if(!root)return;
 const table=root.querySelector('table'); if(!table)return;
 const heads=[...table.querySelectorAll('thead th')].map(x=>x.textContent.trim());
 const idx=n=>heads.findIndex(h=>h.toLowerCase()===n.toLowerCase());
 const iImg=idx('Image'),iNo=idx('No.'),iName=idx('Name'),iAttr=heads.findIndex(h=>/quality|size|type/i.test(h)),iActive=idx('Active'),iActions=idx('Actions');
 const cards=[...table.querySelectorAll('tbody tr')].map(tr=>{
  const td=[...tr.children]; if(td.length<3)return'';
  const no=td[iNo]?.textContent.trim()||'',name=td[iName]?.textContent.trim()||'—',attr=iAttr>=0?(td[iAttr]?.textContent.trim()||'—'):'—',active=iActive>=0?(td[iActive]?.textContent.trim()||''):'',img=td[iImg]?.querySelector('img');
  const edit=td[iActions]?.querySelector('[data-edit]'),view=td[iActions]?.querySelector('[data-image]');
  const id=edit?.dataset.edit||view?.dataset.image||'';
  const media=img?`<button class="rr-accessory-library-image" data-image="${safe(id)}" title="View image"><img src="${safe(img.src)}" alt=""></button>`:`<div class="rr-accessory-library-image"><span class="rr-accessory-library-placeholder">NO IMAGE</span></div>`;
  return `<article class="rr-accessory-library-card">${media}<div class="rr-accessory-library-caption"><h3 class="rr-accessory-library-no">${safe(no)}</h3><p class="rr-accessory-library-name">${safe(name)}</p><div class="rr-accessory-library-meta"><span class="rr-accessory-library-tag">${safe(attr)}</span><span class="${/yes/i.test(active)?'status-ok':'status-off'}">${safe(active||'')}</span></div><div class="rr-accessory-library-actions"><button data-edit="${safe(id)}">Edit</button>${img?`<button data-image="${safe(id)}">View</button>`:''}</div></div></article>`;
 }).join('');
 if(cards)root.innerHTML=cards;
}
const root=document.getElementById('cards'); if(!root)return;
let busy=false;new MutationObserver(()=>{if(busy)return;busy=true;requestAnimationFrame(()=>{transform();busy=false})}).observe(root,{childList:true,subtree:true});
setTimeout(transform,0);
})();