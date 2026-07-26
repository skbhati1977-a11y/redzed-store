/******************************************************************
 * REDZED Dealer Catalog
 * File        : settings.js
 * Recovery ID : RR-005
 * Status      : PRODUCTION
 * Purpose     : Load Website Settings & WhatsApp Numbers
 ******************************************************************/


/* ==========================================================
   Load Website Settings
========================================================== */

async function loadSettings() {

    const { data, error } = await supabaseClient
        .from("settings")
        .select("*")
        .eq("is_active", true);

    if (error) {

        console.error("Settings Load Error :", error);
        return;

    }

    // Reset Settings Object
    CFG.SETTINGS = {};

    // Convert rows into key => value object
    (data || []).forEach(item => {

        CFG.SETTINGS[item.setting_key] = item.setting_value;

    });

}


/* ==========================================================
   Load WhatsApp Numbers
========================================================== */

async function loadWhatsAppNumbers() {

    const { data, error } = await supabaseClient
        .from("whatsapp_numbers")
        .select("*")
        .eq("is_active", true);

    if (error) {

        console.error("WhatsApp Load Error :", error);
        return;

    }

    // Store all active WhatsApp numbers
    CFG.WHATSAPP = data || [];

    // Default Number Priority
    // 1. is_default = true
    // 2. First Active Number
    // 3. null

    CFG.DEFAULT_WHATSAPP =
        CFG.WHATSAPP.find(item => item.is_default)
        || CFG.WHATSAPP[0]
        || null;

    console.log("WhatsApp Numbers :", CFG.WHATSAPP);

    console.log("Default WhatsApp :", CFG.DEFAULT_WHATSAPP);

}