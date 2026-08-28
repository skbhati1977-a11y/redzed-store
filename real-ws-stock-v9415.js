(()=>{
'use strict';
if(window.__RR_WS_STOCK_V9419__)return;window.__RR_WS_STOCK_V9419__=true;
if(!/\/real-finished-goods-v787\.html$/i.test(location.pathname))return;
const qs=new URLSearchParams(location.search),mode=qs.get('mode')==='REAL'?'REAL':'TEST',BATCH=50;
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const state={rows:[],search:'',multi:'',sort:'LOT_ASC',offset:0,hasMore:true,loading:false,frozen:true,timer:0};
const COLS=[
{k:'thumb',h:'Pic',w:54,cell:x=>x.thumbnail?`<img class="rr9419-thumb" src="${esc(x.thumbnail)}" loading="lazy">`:'<span class="rr9419-thumb"></span>'},
{k:'lot',h:'Lot No.',w:116,cell:x=>`<b>${esc(x.lot_no)}</b>`},
{k:'category',h:'Category',w:190,cell:x=>esc(x.category||'—')},
{k:'sizes',h:'Sizes',w:105,cell:x=>esc(x.sizes||'—')},
{k:'cb',h:'CB No.',w:120,cell:x=>esc(x.cb_no||'—')},
{k:'avail',h:'Available',w:92,cell:x=>`<b>${Number(x.available_qty||0)}</b>`},
{k:'sales',h:'TTL Sales PCS',w:110,cell:x=>`<b>${Number(x.sales_qty||0)}</b>`},
{k:'rec',h:'TTL Rec PCS',w:105,cell:x=>`<b>${Number(x.received_qty||0)}</b>`},
{k:'stock',h:'Stock',w:72,cell:x=>`<b>${esc(x.stock_status||'')}</b>`}
];
function css(){if(document.getElementById('rr9419css'))return;const s=document.createElement('style');s.id='rr9419css';s.textContent=`
[data-view="stock"] .rr9419-grid{display:grid;grid-template-columns:auto minmax(0,1fr);overflow:hidden;border:1px solid #30343d;border-radius:12px;background:#17191f}
[data-view="stock"] .rr9419-left{display:none;border-right:2px solid #3b4250}.rr9419-grid.frozen .rr9419-left{display:block;width:170px}
[data-view="stock"] .rr9419-left-head{display:grid;grid-template-columns:54px 116px;height:48px;background:#20232b;font-weight:900}
[data-view="stock"] .rr9419-main{min-width:0;overflow:hidden}.rr9419-main-head-wrap{overflow:hidden}.rr9419-main-head{display:flex;width:max-content;height:48px;background:#20232b;font-weight:900}
[data-view="stock"] .rr9419-main-head-cell,[data-view="stock"] .rr9419-cell{display:flex;align-items:center;padding:7px 8px;box-sizing:border-box;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
[data-view="stock"] .rr9419-left-body,[data-view="stock"] .rr9419-main-body{height:60vh;overflow-y:auto}.rr9419-main-body{overflow:auto;-webkit-overflow-scrolling:touch}
[data-view="stock"] .rr9419-left-row{display:grid;grid-template-columns:54px 116px;min-height:60px;border-bottom:1px solid #30343d}.rr9419-row{display:flex;width:max-content;min-height:60px;border-bottom:1px solid #30343d}
[data-view="stock"] .rr9419-thumb{width:34px;height:44px;object-fit:cover;border-radius:7px;background:#111;display:block}
[data-view="stock"] .rr9419-headbar{display:flex;gap:8px;margin:8px 0}.rr9419-search{flex:1;min-width:0;padding:10px;background:#111;color:#fff;border:1px solid #30343d;border-radius:10px}.rr9419-icon{width:46px;border-radius:10px;background:#20232b;color:#fff;border:1px solid #30343d}
[data-view="stock"] .rr9419-loader{padding:12px;text-align:center;color:#aab0ba;font-size:12px}
`;document.head.appendChild(s)}
async function rpcPage(offset){const {data,error}=await supabaseClient.rpc('rr_ws_stock_search_page_v9419',{p_search:state.search,p_multi_lots:state.multi,p_sort:state.sort,p_data_mode:mode,p_limit:BATCH,p_offset:offset});if(error)throw error;return data||{rows:[],has_more:false,next_offset:offset}}
function mount(){const p=document.querySelector('[data-view="stock"] .fg-panel');if(!p)return;p.dataset.ws9419='1';p.innerHTML=`<h2>WS · Webstore / Store Stock</h2><div class="rr9419-headbar"><input id="rr9419search" class="rr9419-search" placeholder="Search lot / category / size / CB…"><button class="rr9419-icon" id="rr9419sort">↕</button><button class="rr9419-icon" id="rr9419multi">☷</button></div><div id="rr9419grid" class="rr9419-grid frozen"><div class="rr9419-left"><div class="rr9419-left-head"><div data-freeze-toggle>Pic</div><div data-freeze-toggle>Lot No.</div></div><div id="rr9419left" class="rr9419-left-body"></div></div><div class="rr9419-main"><div class="rr9419-main-head-wrap"><div id="rr9419head" class="rr9419-main-head"></div></div><div id="rr9419body" class="rr9419-main-body"></div></div></div>`;
const inp=p.querySelector('#rr9419search');inp?.addEventListener('input',e=>{state.search=e.target.value;clearTimeout(state.timer);state.timer=setTimeout(()=>resetAndLoad(),250)});bindScroll();resetAndLoad()}
function mainCols(){return state.frozen?COLS.slice(2):COLS}
function render(){const l=document.getElementById('rr9419left'),h=document.getElementById('rr9419head'),b=document.getElementById('rr9419body'),g=document.getElementById('rr9419grid');if(!l||!h||!b||!g)return;g.classList.toggle('frozen',state.frozen);const cs=mainCols();h.innerHTML=cs.map(c=>`<div class="rr9419-main-head-cell" style="width:${c.w}px;min-width:${c.w}px">${c.h}</div>`).join('');b.innerHTML=state.rows.map(x=>`<div class="rr9419-row">${cs.map(c=>`<div class="rr9419-cell" style="width:${c.w}px;min-width:${c.w}px">${c.cell(x)}</div>`).join('')}</div>`).join('')+(state.loading?'<div class="rr9419-loader">Loading…</div>':state.hasMore?'<div class="rr9419-loader">Scroll for more</div>':'');l.innerHTML=state.rows.map(x=>`<div class="rr9419-left-row"><div class="rr9419-cell" data-freeze-toggle>${COLS[0].cell(x)}</div><div class="rr9419-cell" data-freeze-toggle>${COLS[1].cell(x)}</div></div>`).join('')}
async function resetAndLoad(){state.rows=[];state.offset=0;state.hasMore=true;const b=document.getElementById('rr9419body'),l=document.getElementById('rr9419left');if(b){b.scrollTop=0;b.scrollLeft=0}if(l)l.scrollTop=0;await loadMore()}
async function loadMore(){if(state.loading||!state.hasMore)return;state.loading=true;render();try{const page=await rpcPage(state.offset);const rows=Array.isArray(page.rows)?page.rows:[];state.rows.push(...rows);state.offset=Number(page.next_offset??state.offset+rows.length);state.hasMore=Boolean(page.has_more);state.loading=false;render()}catch(e){state.loading=false;state.hasMore=false;render();const b=document.getElementById('rr9419body');if(b)b.insertAdjacentHTML('beforeend',`<div class="rr9419-loader" style="color:#ff7d88">${esc(e.message)}</div>`)}}
function bindScroll(){const l=document.getElementById('rr9419left'),b=document.getElementById('rr9419body'),h=document.getElementById('rr9419head');if(!l||!b)return;b.addEventListener('scroll',()=>{l.scrollTop=b.scrollTop;if(h)h.style.transform=`translateX(${-b.scrollLeft}px)`;if(b.scrollTop+b.clientHeight>=b.scrollHeight-240)loadMore()},{passive:true});l.addEventListener('scroll',()=>{b.scrollTop=l.scrollTop;if(l.scrollTop+l.clientHeight>=l.scrollHeight-240)loadMore()},{passive:true})}
window.__rr9419ToggleFreeze=()=>{state.frozen=!state.frozen;render()};
css();if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(mount,120));else setTimeout(mount,120);new MutationObserver(()=>{const p=document.querySelector('[data-view="stock"] .fg-panel');if(p&&!p.dataset.ws9419)mount()}).observe(document.documentElement,{childList:true,subtree:true});
})();