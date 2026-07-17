(() => {
"use strict";

console.info("REDZED Patch Engine v1 Loaded.");

const app = window.RRCuttingMaster;

if (!app) {
    console.error("RRCuttingMaster Bridge not found.");
    return;
}

window.REDZED = window.REDZED || {};

REDZED.version = "1.0";

REDZED.cutting = app;

REDZED.plugins = {};

REDZED.use = function(name, plugin) {

    console.info("Loading Plugin :", name);

    REDZED.plugins[name] = plugin;

    if (typeof plugin.init === "function") {
        plugin.init(app);
    }

};

console.info("Patch Engine Ready.");

})();
