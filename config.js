/******************************************************************
 * REDZED Dealer Catalog
 * File        : config.js
 * Recovery ID : RR-005
 * Status      : RECOVERED · V9309 PACKING MANAGER BEHALF
 ******************************************************************/
const SUPABASE_URL="https://hruartsemierwhtzonei.supabase.co";
const SUPABASE_ANON_KEY="sb_publishable_uo3dcrFuRvGsvRzPcdTV0A_5ZVwgzga";
const CFG=Object.seal({SETTINGS:{},WHATSAPP:[],DEFAULT_WHATSAPP:null});
const supabaseClient=window.supabase.createClient(SUPABASE_URL,SUPABASE_ANON_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});window.supabaseClient=supabaseClient;window.supabaseDb=supabaseClient;window.redzedSupabase=supabaseClient;window.sb=supabaseClient;
const RR_REPO_BASE="/redzed-store/";
const RR_TRAVEL_VERSION="9309";
const RR_LATEST_DASHBOARD_URL=`${RR_REPO_BASE}real-dashboard-v9182.html?v=${RR_TRAVEL_VERSION}`;
const rrIsDashboardPath=path=>/\/real-dashboard(?:-v9182)?\.html$/i.test(path||"");
if(!rrIsDashboardPath(window.location.pathname)){
 const pinDashboardReturn=()=>{
  document.querySelectorAll('a[href]').forEach(a=>{
   try{const u=new URL(a.getAttribute('href'),window.location.href);if(/\/real-dashboard(?:-v\d+)?\.html$/i.test(u.pathname))a.href=RR_LATEST_DASHBOARD_URL}catch(_e){}
  });
 };
 document.addEventListener('DOMContentLoaded',pinDashboardReturn,{once:true});
 setTimeout(pinDashboardReturn,0);
 if(/\/real-cb-new-v9130-fix2\.html$/i.test(window.location.pathname)){
  document.addEventListener('click',e=>{const btn=e.target.closest('button');const inline=String(btn?.getAttribute('onclick')||'');if(btn&&/history\.back\s*\(/i.test(inline)){e.preventDefault();e.stopImmediatePropagation();window.location.href=RR_LATEST_DASHBOARD_URL}},true);
 }
}
if(/\/art-v9148\/?$/i.test(window.location.pathname)){
 const style=document.createElement("style");style.textContent=`#iconStatus{display:none!important}#designNotes{display:none!important}#artCraftMapCard{display:none!important}`;document.head.appendChild(style);
 const hide=()=>{const icon=document.getElementById("iconStatus");if(icon){icon.hidden=true;icon.style.setProperty("display","none","important")}const notes=document.getElementById("designNotes");if(notes){notes.hidden=true;const card=notes.closest(".art-field-card")||notes.parentElement;if(card){card.hidden=true;card.style.setProperty("display","none","important")}}const old=document.getElementById("artCraftMapCard");if(old){old.hidden=true;old.style.setProperty("display","none","important")}};document.addEventListener("DOMContentLoaded",hide,{once:true});setTimeout(hide,0);setTimeout(hide,500);
 const craftLayout=document.createElement("script");craftLayout.src="factory-craft-layout.js?v=9155";craftLayout.async=false;document.head.appendChild(craftLayout);
 const categoryCraft=document.createElement("script");categoryCraft.src="category-craft-library.js?v=9155";categoryCraft.async=false;document.head.appendChild(categoryCraft);
}
if(rrIsDashboardPath(window.location.pathname)){
 const pinLatestDashboardRoutes=()=>{
  document.querySelectorAll('a[href]').forEach(a=>{
   const text=String(a.textContent||'').replace(/\s+/g,' ').trim().toLowerCase();
   if(text==='cb new'||text.startsWith('cb new · regular cloth'))a.href=`${RR_REPO_BASE}real-cb-new-v9130-loader.html?v=${RR_TRAVEL_VERSION}&fix=20260817`;
   else if(text==='matching cloth')a.href=`${RR_REPO_BASE}real-product-master-v720.html?view=matching-cloth&v=${RR_TRAVEL_VERSION}`;
   else if(text==='art master')a.href=`${RR_REPO_BASE}art-v9148/?v=${RR_TRAVEL_VERSION}`;
   else if(text==='print master')a.href=`${RR_REPO_BASE}real-print-master.html?v=${RR_TRAVEL_VERSION}`;
   else if(text==='sticker master')a.href=`${RR_REPO_BASE}real-sticker-master-v804.html?v=${RR_TRAVEL_VERSION}`;
   else if(text==='metal id master')a.href=`${RR_REPO_BASE}real-metal-id-master-v804.html?v=${RR_TRAVEL_VERSION}`;
   else if(text==='cutting master')a.href=`${RR_REPO_BASE}real-cutting-master.html?v=${RR_TRAVEL_VERSION}`;
   else if(text==='upm costing'||text==='actual costing')a.href=`${RR_REPO_BASE}real-upm-costing-v9300.html?v=${RR_TRAVEL_VERSION}`;
   else if(text==='packing / rrq'||text==='packing'||text==='rrq')a.href=`${RR_REPO_BASE}real-finished-goods-v787.html?view=packing&v=${RR_TRAVEL_VERSION}`;
   else if(text.includes('pi / cpi'))a.href=`${RR_REPO_BASE}real-finished-goods-v787.html?view=sale&v=${RR_TRAVEL_VERSION}`;
   else{try{const u=new URL(a.getAttribute('href'),window.location.href),raw=String(u.searchParams.get('dept')||'').toUpperCase(),k=raw.replace(/[^A-Z0-9]+/g,''),d=['KAAJ','KAJ','KASJ','BUTTON','BTN','BT','BATTAN','BATAN','KAAJBUTTON','KAJBUTTON','KASJBUTTON','KAAJBTN','KAJBTN','KASJBTN','KAAJBATTAN','KAJBATTAN','KASJBATTAN','BUTTONKAAJ','BUTTONKAJ','BUTTONKASJ','BTNKAAJ','BTNKAJ','BTNKASJ'].includes(k)?'KAAJ_BUTTON':raw;if((/\/real-department-lite-v9127\.html$/i.test(u.pathname)||/\/real-universal-production-v770-v9059\.html$/i.test(u.pathname))&&['PRINTING','STICKER','METAL_ID','STITCHING','OVERLOCK','FOLDING','KAAJ','KAJ','KASJ','KAAJ_BUTTON','BUTTON','BTN','BT','BATTAN','BATAN','TEAK_TANKI','THREAD_CUT','QC','PRESS','PACKING','DESPATCH'].includes(d)){a.href=`${RR_REPO_BASE}real-universal-production-v770-v9059.html?dept=${encodeURIComponent(d)}&mode=TEST&from=DASHBOARD&v=${RR_TRAVEL_VERSION}`}}catch(_e){}}
  });
 };
 document.addEventListener('DOMContentLoaded',pinLatestDashboardRoutes,{once:true});setTimeout(pinLatestDashboardRoutes,0);
}
if(/\/real-cutting-master\.html$/i.test(window.location.pathname)){
 window.__RR_CUTTING_UI_LOADER_9190__=true;
 window.__RR_CUTTING_LOAD_GUARD_9191__=true;
 window.__RR_CUTTING_LOADING_GUARD_9191__=true;
 const rrApplyCuttingView=()=>{
  const view=String(new URLSearchParams(window.location.search).get('view')||'all').toLowerCase();
  const filter=view==='ready-lot'?'ready':view==='release-lot'?'released':'all';
  const btn=document.querySelector(`#cmFilters button[data-filter="${filter}"]`);
  if(btn&&!btn.classList.contains('is-active'))btn.click();
 };
 document.addEventListener('DOMContentLoaded',()=>{setTimeout(rrApplyCuttingView,0);setTimeout(rrApplyCuttingView,350);setTimeout(rrApplyCuttingView,900)},{once:true});
}
if(/\/real-universal-production-v729\.html$/i.test(window.location.pathname)){const s=document.createElement("script");s.src="real-upm-lot-mapped-details-v9151.js?v=9151";s.async=false;document.head.appendChild(s)}
if(/real-product-master-v720\.html$/i.test(window.location.pathname)){const s=document.createElement("script");s.src="real-mc-searchable-mapping-v9140.js?v=9148";s.async=false;document.head.appendChild(s);document.addEventListener("submit",event=>{if(event.target?.id!=="mcForm")return;const search=document.getElementById("mcFabricSearch"),select=document.getElementById("mcFabricSelect"),newInput=document.getElementById("mcNewFabric"),wrap=document.getElementById("mcNewFabricWrap"),typed=String(search?.value||"").trim();if(!typed||!select||!newInput)return;if(!select.value){select.value="__new__";newInput.value=typed;wrap?.classList.remove("hidden");select.dispatchEvent(new Event("change",{bubbles:true}))}},true)}
if(/\/art-v9148\/?$/i.test(window.location.pathname)||/\/real-print-master\.html$/i.test(window.location.pathname)||/\/real-sticker-master-v804\.html$/i.test(window.location.pathname)||/\/real-metal-id-master-v804\.html$/i.test(window.location.pathname)){const a=document.createElement("script");a.src=`${RR_REPO_BASE}real-master-archive-v9159.js?v=9166`;a.async=false;document.head.appendChild(a)}
if(/\/real-department-lite-v9127\.html$/i.test(window.location.pathname)||/\/real-sticker-master-v804\.html$/i.test(window.location.pathname)||/\/real-metal-id-master-v804\.html$/i.test(window.location.pathname)){const g=document.createElement("script");g.src=`${RR_REPO_BASE}real-sticker-metal-print-guard-v9160.js?v=9160`;g.async=false;document.head.appendChild(g)}
if(/\/real-finished-goods-v787\.html$/i.test(window.location.pathname)){const p=document.createElement("script");p.src=`${RR_REPO_BASE}real-packing-manager-behalf-v9309.js?v=${RR_TRAVEL_VERSION}`;p.async=false;document.head.appendChild(p)}
if(!/\/real-cutting-master\.html$/i.test(window.location.pathname)){const mobile=document.createElement("script");mobile.src="real-global-mobile-fill-v9144.js?v=9144";mobile.async=false;document.head.appendChild(mobile)}
if(!window.__RR_GLOBAL_CARET_END_LOADER_9310__){window.__RR_GLOBAL_CARET_END_LOADER_9310__=true;const caret=document.createElement("script");caret.src=`${RR_REPO_BASE}real-global-caret-end-v9310.js?v=9310`;caret.async=false;(document.head||document.documentElement).appendChild(caret)}
if(!rrIsDashboardPath(window.location.pathname)&&!window.__RR_SLICE_MENU_LOADER_9309__){window.__RR_SLICE_MENU_LOADER_9309__=true;const nav=document.createElement('script');nav.src=`${RR_REPO_BASE}real-global-slice-menu-v9190.js?v=${RR_TRAVEL_VERSION}`;nav.async=false;(document.head||document.documentElement).appendChild(nav)}
let rrAuthRefreshPromise=null;window.RRRefreshSupabaseSession=async function(force=false){if(rrAuthRefreshPromise)return rrAuthRefreshPromise;rrAuthRefreshPromise=(async()=>{try{const{data,error}=await supabaseClient.auth.getSession();if(error)throw error;const session=data?.session||null;if(!session)return null;const expiresAt=Number(session.expires_at||0)*1000,nearExpiry=!expiresAt||expiresAt<=Date.now()+90000;if(force||nearExpiry){const refreshed=await supabaseClient.auth.refreshSession();if(refreshed.error)throw refreshed.error;return refreshed.data?.session||session}return session}catch(error){console.warn("REAL FACTORY auth refresh",error);return null}finally{rrAuthRefreshPromise=null}})();return rrAuthRefreshPromise};const recover=()=>window.RRRefreshSupabaseSession?.(false);window.addEventListener("focus",recover,{passive:true});window.addEventListener("online",recover,{passive:true});document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible")recover()});setTimeout(recover,0);window.dispatchEvent(new CustomEvent("redzed:supabase-ready"));
