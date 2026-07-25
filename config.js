 /******************************************************************
 * REDZED Dealer Catalog
 * File        : config.js
 * Recovery ID : RR-005
 * Status      : RECOVERED
 ******************************************************************/

const SUPABASE_URL = "https://hruartsemierwhtzonei.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_uo3dcrFuRvGsvRzPcdTV0A_5ZVwgzga";

const CFG = {
    SETTINGS: {},
    WHATSAPP: {}
};

const supabaseClient = window.supabase.createClient(
    SUPABASE_URL,
    SUPABASE_ANON_KEY
);