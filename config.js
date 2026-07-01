// Supabase Settings: Project Settings → API से URL और anon public key paste करें
const SUPABASE_URL = "PASTE_SUPABASE_PROJECT_URL_HERE";
const SUPABASE_ANON_KEY = "PASTE_SUPABASE_ANON_KEY_HERE";
const WHATSAPP_NUMBER = "9654401954";
const ADMIN_PIN = "9654"; // बाद में बदल दें
const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
