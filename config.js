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

const CFG = Object.seal({
  SETTINGS: {},
  WHATSAPP: [],
  DEFAULT_WHATSAPP: null
});

const supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true
    }
  }
);

/* V720 compatibility — existing Masters पर असर नहीं पड़ेगा */
window.supabaseClient = supabaseClient;
window.supabaseDb = supabaseClient;
window.redzedSupabase = supabaseClient;
window.sb = supabaseClient;

/* V9148 MC search: typed fabric/vendor search syncs to original save fields. */
if (/real-product-master-v720\.html$/i.test(window.location.pathname)) {
  const rrMcSearchableMapping = document.createElement("script");
  rrMcSearchableMapping.src = "real-mc-searchable-mapping-v9140.js?v=9148";
  rrMcSearchableMapping.async = false;
  document.head.appendChild(rrMcSearchableMapping);

  document.addEventListener("submit", event => {
    if (event.target?.id !== "mcForm") return;
    const search = document.getElementById("mcFabricSearch");
    const select = document.getElementById("mcFabricSelect");
    const newInput = document.getElementById("mcNewFabric");
    const wrap = document.getElementById("mcNewFabricWrap");
    const typed = String(search?.value || "").trim();
    if (!typed || !select || !newInput) return;
    if (!select.value) {
      select.value = "__new__";
      newInput.value = typed;
      wrap?.classList.remove("hidden");
      select.dispatchEvent(new Event("change", { bubbles: true }));
    }
  }, true);
}

/* V9144 GLOBAL MOBILE FILL UX: hide descriptions, mode badge, and active form headers. */
const rrGlobalMobileFill = document.createElement("script");
rrGlobalMobileFill.src = "real-global-mobile-fill-v9144.js?v=9144";
rrGlobalMobileFill.async = false;
document.head.appendChild(rrGlobalMobileFill);

/* V9096 MOBILE SESSION RECOVERY
 * Mobile browsers throttle background timers. When the app resumes after
 * the access token expired, proactively refresh the persisted session before
 * production RPCs fire. This avoids transient 401 "JWT expired" screens.
 */
let rrAuthRefreshPromise = null;
window.RRRefreshSupabaseSession = async function RRRefreshSupabaseSession(force = false) {
  if (rrAuthRefreshPromise) return rrAuthRefreshPromise;
  rrAuthRefreshPromise = (async () => {
    try {
      const { data, error } = await supabaseClient.auth.getSession();
      if (error) throw error;
      const session = data?.session || null;
      if (!session) return null;
      const expiresAt = Number(session.expires_at || 0) * 1000;
      const nearExpiry = !expiresAt || expiresAt <= Date.now() + 90_000;
      if (force || nearExpiry) {
        const refreshed = await supabaseClient.auth.refreshSession();
        if (refreshed.error) throw refreshed.error;
        return refreshed.data?.session || session;
      }
      return session;
    } catch (error) {
      console.warn("REAL FACTORY auth refresh", error);
      return null;
    } finally {
      rrAuthRefreshPromise = null;
    }
  })();
  return rrAuthRefreshPromise;
};

const rrRecoverAuth = () => window.RRRefreshSupabaseSession?.(false);
window.addEventListener("focus", rrRecoverAuth, { passive: true });
window.addEventListener("online", rrRecoverAuth, { passive: true });
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") rrRecoverAuth();
});
setTimeout(rrRecoverAuth, 0);

window.dispatchEvent(
  new CustomEvent("redzed:supabase-ready")
);
