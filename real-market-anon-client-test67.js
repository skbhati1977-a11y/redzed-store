(() => {
  "use strict";
  // REDZED staff invoice must retain the authenticated Supabase client/JWT.\n  // The isolated anonymous client is only for distributor/customer share flows.\n  if (String(new URLSearchParams(location.search).get("role") || "").toUpperCase() === "REDZED") return;\n  if (window.__RR_MARKET_ANON_CLIENT_TEST67__) return;
  window.__RR_MARKET_ANON_CLIENT_TEST67__ = true;
  const current = window.supabaseClient;
  const url = current?.supabaseUrl || (typeof SUPABASE_URL !== "undefined" ? SUPABASE_URL : "");
  const key = current?.supabaseKey || (typeof SUPABASE_ANON_KEY !== "undefined" ? SUPABASE_ANON_KEY : "");
  if (!window.supabase?.createClient || !url || !key) return;
  const anonymous = window.supabase.createClient(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
  window.supabaseClient = anonymous;
  window.supabaseDb = anonymous;
  window.redzedSupabase = anonymous;
  window.sb = anonymous;
})();
