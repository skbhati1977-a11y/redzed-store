#!/usr/bin/env node
"use strict";

/*
  REDZED V720.37.5 — Individual Multi Lot Cards
  Usage:
    node patch-individual-multi-lot-cards.js real-cutting-master-pm.V719.3.js

  This patch changes only the released-lot display section.
  Database records are already individual in rr_production_lots.
*/

const fs = require("fs");
const path = require("path");

const input = process.argv[2] || "real-cutting-master-pm.V719.3.js";

if (!fs.existsSync(input)) {
  console.error(`File not found: ${input}`);
  process.exit(1);
}

const original = fs.readFileSync(input, "utf8");
const backup = `${input}.backup-v720375`;
fs.writeFileSync(backup, original, "utf8");

const oldBlock = String.raw`          ${
            lots.length
              ? \`
                <div class="cm-lot-identity ${isNewLot ? "is-new" : ""}">
                  <small>RELEASED LOT NO · PRIMARY IDENTITY</small>
                  <strong>${safe(lotNos.join(" · "))}</strong>
                  <span>${safe(childCode)} · ${totalPcs} pcs · ${safe(lotStatusLabel(lot))}</span>
                </div>

                <div class="cm-lot-box">
                  <h4 class="${isNewLot ? "cm-lot-title-new" : ""}">
                    ${lots.length > 1 ? "MULTI LOT" : "LOT"}
                    <span class="cm-lot-number ${isNewLot ? "cm-lot-number-highlight" : ""}">
                      ${safe(lotNos.join(" · "))}
                    </span>
                  </h4>
                  <p>${safe(lot?.style_name || decision.styleName || "")}</p>
                  <p>
                    ${totalPcs} pcs ·
                    <strong>${safe(lotStatusLabel(lot))}</strong>
                  </p>
                  <div class="cm-lot-cost">
                    <span>
                      Final / Pc:
                      <strong>${money(finalPerPiece)}</strong>
                    </span>
                    <span>
                      Total:
                      <strong>${money(totalCost)}</strong>
                    </span>
                  </div>
                </div>
              \`
              : \`
                <div class="cm-lot-box">
                  <h4>Permanent Lot No Due</h4>
                  <p>
                    पहले Single या Multi Lot चुनें, फिर Manual Lot No भरें.
                  </p>
                </div>
              \`
          }`;

const newBlock = String.raw`          ${
            lots.length
              ? \`
                <div class="cm-lot-release-summary ${isNewLot ? "is-new" : ""}">
                  <small>${lots.length > 1 ? "MULTI RELEASED · INDIVIDUAL LOTS" : "RELEASED LOT NO · PRIMARY IDENTITY"}</small>
                  <strong>${lots.length} Lot${lots.length > 1 ? "s" : ""} · ${totalPcs} pcs</strong>
                  <span>हर Lot No स्वतंत्र production identity है</span>
                </div>

                <div class="cm-individual-lot-grid">
                  ${lots.map((individualLot, lotIndex) => {
                    const individualLotNo = String(individualLot.lot_no || "").trim().toUpperCase();
                    const individualPcs = Number(individualLot.planned_pcs || individualLot.cutting_pcs || 0);
                    const individualTotal = Number(effectiveLotTotalCost(individualLot) || 0);
                    const individualPerPiece = individualPcs > 0
                      ? individualTotal / individualPcs
                      : Number(individualLot.final_cost_per_piece || 0);

                    const individualDevCode = canonicalDevelopmentCode(
                      individualLot.variant_code ||
                      individualLot.dev_code ||
                      individualLot.development_code ||
                      individualLot.child_code ||
                      (lots.length > 1 ? subDevelopmentCode(childCode, lotIndex) : childCode)
                    );

                    return \`
                      <article
                        class="cm-lot-box cm-independent-lot-card ${isNewLot ? "is-new" : ""}"
                        data-production-lot-id="${safe(individualLot.id || individualLot.production_lot_id || "")}"
                        data-lot-no="${safe(individualLotNo)}"
                        data-dev-code="${safe(individualDevCode)}"
                      >
                        <header class="cm-independent-lot-head">
                          <div>
                            <small>INDIVIDUAL RELEASED LOT</small>
                            <h4 class="${isNewLot ? "cm-lot-title-new" : ""}">
                              <span class="cm-lot-number ${isNewLot ? "cm-lot-number-highlight" : ""}">
                                ${safe(individualLotNo)}
                              </span>
                            </h4>
                          </div>
                          <span class="cm-dev-code-badge">${safe(individualDevCode)}</span>
                        </header>

                        <p>${safe(individualLot.style_name || decision.styleName || "")}</p>
                        <p>
                          <strong>${individualPcs} pcs</strong> ·
                          ${safe(lotStatusLabel(individualLot))}
                        </p>

                        <div class="cm-lot-cost">
                          <span>
                            Final / Pc:
                            <strong>${money(individualPerPiece)}</strong>
                          </span>
                          <span>
                            Total:
                            <strong>${money(individualTotal)}</strong>
                          </span>
                        </div>

                        <div class="cm-independent-note">
                          Printing, KR, OV, Folding, QC, Press और Packing में यह Lot अलग चलेगा।
                        </div>
                      </article>
                    \`;
                  }).join("")}
                </div>
              \`
              : \`
                <div class="cm-lot-box">
                  <h4>Permanent Lot No Due</h4>
                  <p>
                    पहले Single या Multi Lot चुनें, फिर Manual Lot No भरें.
                  </p>
                </div>
              \`
          }`;

let patched = original;

if (!patched.includes(oldBlock)) {
  console.error("Expected combined-lot display block not found.");
  console.error("No changes made. Backup was created at:", backup);
  process.exit(2);
}

patched = patched.replace(oldBlock, newBlock);

const marker = "// ===== REDZED CUTTING MASTER PM CORE V719 START =====";
const cssInjector = String.raw`
/* V720.37.5 individual multi-lot cards */
(function installIndividualLotCardStyles() {
  if (document.getElementById("rrIndividualLotCardsV720375")) return;
  const style = document.createElement("style");
  style.id = "rrIndividualLotCardsV720375";
  style.textContent = \`
    .cm-lot-release-summary{
      margin-top:14px;padding:14px;border:1px solid #d9a91a;border-radius:14px;
      display:grid;gap:4px;background:rgba(217,169,26,.08)
    }
    .cm-lot-release-summary small{font-weight:800;letter-spacing:.08em}
    .cm-lot-release-summary strong{font-size:1.15rem}
    .cm-individual-lot-grid{display:grid;gap:12px;margin-top:12px}
    .cm-independent-lot-card{
      border:2px solid rgba(217,169,26,.75)!important;
      border-radius:16px!important;padding:14px!important
    }
    .cm-independent-lot-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px}
    .cm-independent-lot-head small{font-size:.72rem;font-weight:800;letter-spacing:.08em}
    .cm-independent-lot-head h4{margin:4px 0 0}
    .cm-dev-code-badge{
      display:inline-flex;align-items:center;justify-content:center;min-width:52px;
      padding:7px 10px;border-radius:999px;background:#f2c62d;color:#111;font-weight:900
    }
    .cm-independent-note{
      margin-top:10px;padding-top:10px;border-top:1px dashed rgba(255,255,255,.18);
      font-size:.82rem;opacity:.82
    }
    @media (min-width:900px){
      .cm-individual-lot-grid{grid-template-columns:repeat(2,minmax(0,1fr))}
    }
  \`;
  document.head.appendChild(style);
})();
`;

patched = patched.replace(marker, `${marker}\n${cssInjector}`);

fs.writeFileSync(input, patched, "utf8");

console.log("PATCHED_OK");
console.log("Updated:", path.resolve(input));
console.log("Backup :", path.resolve(backup));
console.log("Deploy the updated JS and hard refresh with a new cache version, e.g. ?v=720375");
