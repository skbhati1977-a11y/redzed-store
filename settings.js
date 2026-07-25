/******************************************************************
 * REDZED Dealer Catalog
 * File        : settings.js
 * Recovery ID : RR-005
 * Status      : RECOVERED
 ******************************************************************/

async function loadSettings() {

    const { data, error } = await supabaseClient
        .from("settings")
        .select("*")
        .eq("is_active", true);

    if (error) {
        console.error("Settings Load Error :", error);
        return;
    }

    CFG.SETTINGS = {};

    data.forEach(item => {

        CFG.SETTINGS[item.setting_key] = item.setting_value;

    });

}


async function loadWhatsAppNumbers() {

    const { data, error } = await supabaseClient
        .from("whatsapp_numbers")
        .select("*")
        .eq("is_active", true);

    if (error) {
        console.error("WhatsApp Load Error :", error);
        return;
    }

    CFG.WHATSAPP = data;

    const defaultNumber = data.find(item => item.is_default);

    if (defaultNumber) {

        CFG.DEFAULT_WHATSAPP = defaultNumber;

    }

}

}