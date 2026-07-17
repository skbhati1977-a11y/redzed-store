(() => {
"use strict";

const REDZED = window.REDZED;
const Core = window.RRCuttingMaster;

if (!REDZED || !Core) {
    console.error("REDZED Patch Engine or Cutting Master Core missing.");
    return;
}

const CuttingPlugin = {

    name: "cutting",
    version: "1.0.0",

    decision: {},
    lots: {},
    bundles: {},
    validation: {},
    events: {},
    api: {},

    init(app) {
        this.app = app;
        console.info("REDZED Cutting Plugin Ready");
    }

};

REDZED.use("cutting", CuttingPlugin);

})();
