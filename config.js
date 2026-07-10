const SUPABASE_URL = "https://hruartsemierwhtzonei.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_uo3dcrFuRvGsvRzPcdTV0A_5ZVwgzga";

const WHATSAPP_NUMBER = "9654401954";
const ADMIN_PIN = "9654";

const CFG = {
  ADMIN_PIN: ADMIN_PIN
};

const supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY
);
