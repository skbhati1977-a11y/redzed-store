/******************************************************************
 * REDZED Dealer Catalog
 * File        : config.js
 * Recovery ID : RR-005
 * Status      : RECOVERED
 ******************************************************************/

const SUPABASE_URL =
  "https://hruartsemierwhtzonei.supabase.co";

const SUPABASE_ANON_KEY =
  "sb_publishable_uo3dcrFuRvGsvRzPcdTV0A_5ZVwgzga";

const CFG = Object.seal({ SETTINGS: {}, WHATSAPP: [], DEFAULT_WHATSAPP: null });
const supabaseClient = window.supabase.createClient(SUPABASE_URL,SUPABASE_ANON_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
window.supabaseClient=supabaseClient;window.supabaseDb=supabaseClient;window.redzedSupabase=supabaseClient;window.sb=supabaseClient;

if (/\/art-v9148\/?$/i.test(window.location.pathname)) {
  const rrArtUiHide=document.createElement("style");rrArtUiHide.textContent=`#iconStatus{display:none!important}#designNotes{display:none!important}`;document.head.appendChild(rrArtUiHide);
  const rrApplyArtUiHide=()=>{const iconStatus=document.getElementById("iconStatus");if(iconStatus){iconStatus.hidden=true;iconStatus.style.setProperty("display","none","important")}const designNotes=document.getElementById("designNotes");if(designNotes){designNotes.hidden=true;designNotes.style.setProperty("display","none","important");const card=designNotes.closest(".art-field-card")||designNotes.parentElement;if(card){card.hidden=true;card.style.setProperty("display","none","important")}}};
  document.addEventListener("DOMContentLoaded",rrApplyArtUiHide,{once:true});const rrArtHideObserver=new MutationObserver(rrApplyArtUiHide);rrArtHideObserver.observe(document.documentElement,{childList:true,subtree:true});setTimeout(rrApplyArtUiHide,0);setTimeout(rrApplyArtUiHide,500);setTimeout(rrApplyArtUiHide,1500);
  const rrArtFactoryCraft=document.createElement("script");rrArtFactoryCraft.src="factory-craft-layout.js?v=9152";rrArtFactoryCraft.async=false;document.head.appendChild(rrArtFactoryCraft);
  const rrCraftUpmUi=document.createElement("script");rrCraftUpmUi.src="craft-upm-ui.js?v=9152";rrCraftUpmUi.async=false;document.head.appendChild(rrCraftUpmUi);
}

if (/\/real-universal-production-v729\.html$/i.test(window.location.pathname)) {const s=document.createElement("script");s.src="real-upm-lot-mapped-details-v9151.js?v=9151";s.async=false;document.head.appendChild(s);}
if (/real-product-master-v720\.html$/i.test(window.location.pathname)) {const s=document.createElement("script");s.src="real-mc-searchable-mapping-v9140.js?v=9148";s.async=false;document.head.appendChild(s);document.addEventListener("submit",event=>{if(event.target?.id!=="mcForm")return;const search=document.getElementById("mcFabricSearch"),select=document.getElementById("mcFabricSelect"),newInput=document.getElementById("mcNewFabric"),wrap=document.getElementById("mcNewFabricWrap"),typed=String(search?.value||"").trim();if(!typed||!select||!newInput)return;if(!select.value){select.value="__new__";newInput.value=typed;wrap?.classList.remove("hidden");select.dispatchEvent(new Event("change",{bubbles:true}))}},true);}
const rrGlobalMobileFill=document.createElement("script");rrGlobalMobileFill.src="real-global-mobile-fill-v9144.js?v=9144";rrGlobalMobileFill.async=false;document.head.appendChild(rrGlobalMobileFill);
let rrAuthRefreshPromise=null;window.RRRefreshSupabaseSession=async function(force=false){if(rrAuthRefreshPromise)return rrAuthRefreshPromise;rrAuthRefreshPromise=(async()=>{try{const{data,error}=await supabaseClient.auth.getSession();if(error)throw error;const session=data?.session||null;if(!session)return null;const expiresAt=Number(session.expires_at||0)*1000,nearExpiry=!expiresAt||expiresAt<=Date.now()+90000;if(force||nearExpiry){const refreshed=await supabaseClient.auth.refreshSession();if(refreshed.error)throw refreshed.error;return refreshed.data?.session||session}return session}catch(error){console.warn("REAL FACTORY auth refresh",error);return null}finally{rrAuthRefreshPromise=null}})();return rrAuthRefreshPromise};
const rrRecoverAuth=()=>window.RRRefreshSupabaseSession?.(false);window.addEventListener("focus",rrRecoverAuth,{passive:true});window.addEventListener("online",rrRecoverAuth,{passive:true});document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible")rrRecoverAuth()});setTimeout(rrRecoverAuth,0);window.dispatchEvent(new CustomEvent("redzed:supabase-ready"));