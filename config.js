// REAL FACTORY · CANONICAL FRONTEND CONFIG V805
// Public client configuration only. Never put service_role/secret/database password here.

const SUPABASE_URL = "https://hruartsemierwhtzonei.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_uo3dcrFuRvGsvRzPcdTV0A_5ZVwgzga";
const SUPABASE_LEGACY_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhydWFydHNlbWllcndodHpvbmVpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI5Mjg5NzksImV4cCI6MjA5ODUwNDk3OX0.Cm_RW1ir7IDRmjH3Xqn9rMnDeel0DYpo3CWtQ32tE7o";

// Canonical client key used by frontend now:
const SUPABASE_ANON_KEY = SUPABASE_PUBLISHABLE_KEY;

window.SUPABASE_URL = SUPABASE_URL;
window.SUPABASE_PUBLISHABLE_KEY = SUPABASE_PUBLISHABLE_KEY;
window.SUPABASE_LEGACY_ANON_KEY = SUPABASE_LEGACY_ANON_KEY;
window.SUPABASE_ANON_KEY = SUPABASE_ANON_KEY;

window.RR_CONFIG = Object.freeze({
  supabaseUrl: SUPABASE_URL,
  supabaseAnonKey: SUPABASE_PUBLISHABLE_KEY,
  supabasePublishableKey: SUPABASE_PUBLISHABLE_KEY,
  supabaseLegacyAnonKey: SUPABASE_LEGACY_ANON_KEY,
  publicAppBaseUrl: "https://skbhati1977-a11y.github.io"
});

const supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY
);

// Compatibility aliases used by older REAL FACTORY modules.
window.supabaseClient = supabaseClient;
window.supabaseDb = supabaseClient;
window.redzedSupabase = supabaseClient;
window.sb = supabaseClient;

window.dispatchEvent(new CustomEvent("real-factory:supabase-ready"));
window.dispatchEvent(new CustomEvent("redzed:supabase-ready"));
