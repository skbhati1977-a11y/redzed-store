(()=>{
'use strict';
const C=window.ACCESSORY_MASTER_CONFIG||{};
if(!['STICKER','METAL_ID'].includes(String(C.itemType||'').toUpperCase()))return;
const style=document.createElement('style');
style.textContent=`
#cards>.tablewrap{display:none!important}
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
#cards .rr-accessory-closing{margin-top:9px;padding:9px 10px;border:1px solid var(--line);border-radius:10px;background:#0d0d12;display:flex;align-items:center;justify-content:space-between;gap:8px}
#cards .rr-accessory-closing small{color:var(--muted);font-size:10px;font-weight:800;letter-spacing:.04em}
#cards .rr-accessory-closing strong{font-size:15px}
#cards .rr-accessory-library-actions{display:grid;grid-template-columns:1fr 1fr;gap:7px;margin-top:11px}
#cards .rr-accessory-library-actions button{padding:8px 9px;min-width:0}
#cards .rr-accessory-library-actions .rr-archive-btn{grid-column:1/-1}
@media(max-width:600px){#cards.cards{grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:9px!important}#cards .rr-accessory-library-caption{padding:9px}#cards .rr-accessory-library-no{font-size:15px}#cards .rr-accessory-library-actions{gap:5px}#cards .rr-accessory-library-actions button{padding:7px 5px;font-size:12px}}
`;
document.head.appendChild(style);
const cleanHead=v=>String(v||'').replace(/[▲▼↕⇅]/g,'').replace(/\s+/g,' ').trim().toLowerCase();
function transform(){
 const root=document.getElementById('cards'); if(!root)return;
 const table=root.querySelector('table'); if(!table)return;
 const heads=[...table.querySelectorAll('thead th')].map(x=>cleanHead(x.textContent));
 const exact=(...names)=>heads.findIndex(h=>names.some(n=>h===cleanHead(n)));
 const iImg=exact('Image'),iNo=exact('No.','No'),iName=exact('Name'),iAttr=heads.findIndex(h=>/quality|size|type/.test(h)),iPhysical=exact('Physical'),iActive=exact('Active'),iActions=exact('Actions');
 const frag=document.createDocumentFragment();
 [...table.querySelectorAll('tbody tr')].forEach(tr=>{
  const td=[...tr.children]; if(td.length<3)return;
  const no=(iNo>=0?td[iNo]?.textContent:'')?.trim()||'—';
  const name=(iName>=0?td[iName]?.textContent:'')?.trim()||'—';
  const attr=iAttr>=0?(td[iAttr]?.textContent.trim()||'—'):'—';
  const closing=iPhysical>=0?(td[iPhysical]?.textContent.trim()||'0'):'0';
  const active=iActive>=0?(td[iActive]?.textContent.trim()||''):'';
  if(/no items found/i.test(no+' '+name))return;
  const oldImage=iImg>=0?td[iImg]?.querySelector('[data-image]'):null;
  const img=iImg>=0?td[iImg]?.querySelector('img'):null;
  const oldEdit=iActions>=0?td[iActions]?.querySelector('[data-edit]'):null;
  const oldView=iActions>=0?td[iActions]?.querySelector('[data-image]'):null;
  const oldArchive=iActions>=0?td[iActions]?.querySelector('.rr-archive-btn[data-archive-id]'):null;
  const id=String(oldEdit?.dataset.edit||oldView?.dataset.image||oldArchive?.dataset.archiveId||'').trim();
  const article=document.createElement('article');article.className='rr-accessory-library-card';article.dataset.masterId=id;
  let media;
  if(img){media=oldImage||document.createElement('button');media.classList.add('rr-accessory-library-image');media.title='View image';media.style.cssText='';if(!media.querySelector('img'))media.appendChild(img);}
  else{media=document.createElement('div');media.className='rr-accessory-library-image';media.innerHTML='<span class="rr-accessory-library-placeholder">NO IMAGE</span>';}
  const cap=document.createElement('div');cap.className='rr-accessory-library-caption';
  const h=document.createElement('h3');h.className='rr-accessory-library-no';h.textContent=no;
  const p=document.createElement('p');p.className='rr-accessory-library-name';p.textContent=name;
  const meta=document.createElement('div');meta.className='rr-accessory-library-meta';
  const tag=document.createElement('span');tag.className='rr-accessory-library-tag';tag.textContent=attr;
  const status=document.createElement('span');status.className=/yes/i.test(active)?'status-ok':'status-off';status.textContent=active;
  const bal=document.createElement('div');bal.className='rr-accessory-closing';bal.innerHTML='<small>CLOSING STOCK</small><strong></strong>';bal.querySelector('strong').textContent=closing;
  meta.append(tag,status);cap.append(h,p,meta,bal);
  const actions=document.createElement('div');actions.className='rr-accessory-library-actions';
  if(oldEdit){oldEdit.style.cssText='';actions.appendChild(oldEdit)}
  if(oldView&&oldView!==oldImage){oldView.style.cssText='';oldView.textContent='View';actions.appendChild(oldView)}
  let archive=oldArchive;
  if(!archive&&id){archive=document.createElement('button');archive.type='button';archive.className='rr-archive-btn';archive.dataset.archiveId=id;archive.textContent='Archive'}
  if(archive){archive.style.cssText='';actions.appendChild(archive)}
  if(actions.children.length)cap.appendChild(actions);
  article.append(media,cap);frag.appendChild(article);
 });
 root.replaceChildren(frag);root.dataset.rrLibraryCards='1';
}
const root=document.getElementById('cards'); if(!root)return;
let busy=false;new MutationObserver(()=>{if(busy)return;if(!root.querySelector('table'))return;busy=true;requestAnimationFrame(()=>{transform();busy=false})}).observe(root,{childList:true,subtree:true});
setTimeout(transform,0);
})();