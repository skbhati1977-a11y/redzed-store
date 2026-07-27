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
  SUPABASE_ANON_KEY
);

/* V720 compatibility — existing Masters पर असर नहीं पड़ेगा */
window.supabaseClient = supabaseClient;
window.supabaseDb = supabaseClient;
window.redzedSupabase = supabaseClient;
window.sb = supabaseClient;

window.dispatchEvent(
  new CustomEvent("redzed:supabase-ready")
);