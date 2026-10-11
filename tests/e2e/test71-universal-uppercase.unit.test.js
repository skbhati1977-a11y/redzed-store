'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.resolve(__dirname,'../../real-common.js'),'utf8');
test('universal business uppercase authority is installed and protected',()=>{assert.match(source,/installBusinessUppercaseInputs/);assert.match(source,/toLocaleUpperCase/);assert.match(source,/password.*email.*url.*search/);assert.match(source,/remark\|remarks\|note\|notes\|description/);assert.match(source,/addEventListener\('submit'/);assert.match(source,/dataset\.rrUppercase==='off'/)});

test('number assist must normalize before matching',()=>{const accessory=fs.readFileSync(path.resolve(__dirname,'../../real-accessory-master-v804.js'),'utf8');assert.match(accessory,/uppercaseBusinessValue\?\.\(input\).*const rows=matches\(\)/s);});

test('active TEST71 business feeding surfaces are covered by common uppercase authority or exempt-only',()=>{const active=['real-cutting-master.html','real-finished-goods-v787.html','real-metal-id-master-v804.html','real-print-master.html','real-product-master-v720.html','real-sticker-master-v804.html','real-art-master.html','real-department-lite-v9127.html'];for(const file of active){const html=fs.readFileSync(path.resolve(__dirname,'../../'+file),'utf8');assert.match(html,/real-common\.js/,file+' must load real-common.js')}const exemptOnly=['real-accounts-suite-v857.html','test70-cb-purchase-real-chat-pilot.html'];for(const file of exemptOnly){const html=fs.readFileSync(path.resolve(__dirname,'../../'+file),'utf8');const fields=[...html.matchAll(/<(?:input|textarea)\b[^>]*>/gi)].map(m=>m[0]);assert.ok(fields.every(x=>/type=[\"']search[\"']/i.test(x)),file+' may omit common only while all manual fields are search-only')}});

test('accessory image stays before number and name',()=>{for(const file of ['real-sticker-master-v804.html','real-metal-id-master-v804.html']){const html=fs.readFileSync(path.resolve(__dirname,'../../'+file),'utf8'),image=html.indexOf('id="currentImageBox"'),no=html.indexOf('id="itemNo"'),name=html.indexOf('id="itemName"');assert.ok(image>=0&&image<no&&no<name,file+' must keep image -> number -> name DOM order')}});

test('CB edit keeps compact four-column S child Art thumbnail row before remarks',()=>{const html=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');const sets=html.indexOf('id="setDecisionCard"'),materials=html.indexOf('id="extraMaterialCard"');assert.ok(sets>=0&&materials>sets);assert.ok(html.includes('class="set-art-preview"'));assert.ok(html.includes('class="canonicalSetArt"'));assert.ok(html.includes("entity_type','art'"));});

test('legacy CB material without canonical Art category mapping is exception-compatible',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/legacyUnmapped/);assert.match(cb,/if\(legacyUnmapped\)continue/)});


test('saved and new Additional Material rows use one canonical shape without silent first-material selection',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.doesNotMatch(cb,/firstExtra=!reg\?materialCategories\(\)\[0\]/);assert.match(cb,/categoryId:cat\?\.id\|\|''/);assert.match(cb,/canonicalEntryById/);assert.match(cb,/material_category_id/);assert.match(cb,/vendor_bill_no/);assert.match(cb,/requirement_state/);assert.match(cb,/allocationAllowed\.length\?allocationAllowed/)});


test('live roll edits change Physical Stock-In only and never overwrite Party Bill Qty',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/regular\.rolls\[ci\]\[ri\]\.qty=e\.target\.value;markReconciliationDirty\(\);renderMaterials\(\);updateSummary\(\)/);assert.doesNotMatch(cb,/regular\.qty=String\(rollTotal\(regular\)/);assert.match(cb,/liveKey=bill\.toFixed\(3\).*physical\.toFixed\(3\)/);assert.match(cb,/stale\?'RECHECK_REQUIRED'/);assert.match(cb,/friendlySaveError/)});


test('CB reconciliation has one working REPORT SHORT EXCESS action and no stale Damage action',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/REPORT SHORT \/ EXCESS/);assert.match(cb,/class="secondary reportVariance"/);assert.match(cb,/reportVariance'\)\?\.addEventListener\('click',reportReconciliationVariance\)/);assert.doesNotMatch(cb,/>REPORT DAMAGE<\/button>/);assert.doesNotMatch(cb,/class="secondary reportShortage"/)});


test('TEST71 Real Chat has universal friendly error guard without changing business validation',()=>{const shell=fs.readFileSync(path.resolve(__dirname,'../../test70-cb-purchase-real-chat-pilot.html'),'utf8'),guard=fs.readFileSync(path.resolve(__dirname,'../../test71-user-friendly-errors.js'),'utf8');assert.match(shell,/test71-user-friendly-errors\.js/);assert.match(guard,/RRUserFriendlyError/);assert.match(guard,/null value in column/);assert.match(guard,/unhandledrejection/);assert.match(guard,/actionFrame/);assert.match(guard,/if\(!TECH\.test\(s\)\)return s/)});


test('WhatsApp handoff preserves current CB editor context for Android back return',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/RR_CB_WHATSAPP_RETURN_V1/);assert.match(cb,/href:location\.href,scrollY:window\.scrollY,cbId/);assert.match(cb,/pageshow.*restoreCbAfterWhatsApp/);assert.match(cb,/visibilitychange/);assert.match(cb,/window\.scrollTo/)});


test('CB GSM and Cutting exact roll yield foundation are wired without changing quantity reconciliation',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8'),cut=fs.readFileSync(path.resolve(__dirname,'../../redzed-cutting-cb-actions-v72035.js'),'utf8'),pm=fs.readFileSync(path.resolve(__dirname,'../../real-cutting-master-pm.V719.3.js'),'utf8');assert.match(cb,/class="colourGsm"/);assert.match(cb,/rr_cb_colour_gsm_save_v1/);assert.match(cb,/rr_cb_colour_gsm_v1/);assert.match(cb,/function reconciliationLocal/);assert.match(cut,/rr_cutting_regular_purchase_sources_v2/);assert.match(cut,/Physical Rolls · Lot Binding/);assert.match(cut,/RR_SELECTED_CUTTING_ROLL_IDS/);assert.match(pm,/rr_cutting_bind_rolls_v1/);assert.match(pm,/rr_cutting_capture_yield_v1/);assert.match(pm,/valid\.lotMode!=='multi'/)});


test('Multi Cutting uses per-lot roll selections and prevents one physical roll being selected twice',()=>{const cut=fs.readFileSync(path.resolve(__dirname,'../../redzed-cutting-cb-actions-v72035.js'),'utf8'),pm=fs.readFileSync(path.resolve(__dirname,'../../real-cutting-master-pm.V719.3.js'),'utf8');assert.match(cut,/selectedRollIdsByDev/);assert.match(cut,/RR_SELECTED_CUTTING_ROLLS_BY_DEV/);assert.match(cut,/data-roll-scope/);assert.match(pm,/selectedRollsByDev/);assert.match(pm,/for\(const lot of valid\.lots\)/);assert.match(pm,/rr_cutting_capture_yield_v1/)});


test('CB editor mobile workspace keeps header and save actions in normal document flow',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('.head{position:relative'));assert.ok(cb.includes('.actions{position:static'));assert.ok(!cb.includes('.head{position:sticky'));assert.ok(!cb.includes('.actions{position:fixed'))});


test('Additional Material renders three explicit layers with PO between mapping and purchase',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');const a=cb.indexOf('A · MATERIAL SELECTION'),b=cb.indexOf('B · MATERIAL → SET LINK'),cc=cb.indexOf('C · REQUIREMENT ESTIMATE · PO BASIS'),d=cb.indexOf('D · PURCHASE DETAILS');assert.ok(a>=0&&b>a&&cc>b&&d>cc);assert.ok(cb.includes('QUALITY / VARIETY'));assert.ok(cb.includes('ITEM / MATERIAL *'));});

test('CB embedded editor header keeps active CB number visible',()=>{const js=fs.readFileSync(path.resolve(__dirname,'../../test70-real-chat-live-v70.js'),'utf8');assert.ok(js.includes("EDIT / CONTINUE · CB "));assert.ok(js.includes("EDIT / CONTINUE · NEW CB"));assert.ok(js.includes("actionUrl.searchParams.get('cb_no')"))});


test('Every Additional Material selects category before decided-Art thumbnail and estimate',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');const b=cb.indexOf('B · MATERIAL → SET LINK'),cc=cb.indexOf('C · REQUIREMENT ESTIMATE · PO BASIS'),slice=cb.slice(b,cc);assert.ok(slice.includes('For which Set? *'));assert.ok(slice.includes('Material rule'));assert.ok(!slice.includes('ART DECISION'));assert.ok(!slice.includes('SLEEVE FINISH'));assert.ok(!slice.includes('SIZE FAMILY'));});

test('Additional Material uses progressive first-next chain and retires global add control',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('+ ADD FIRST MATERIAL'));assert.ok(cb.includes('+ ADD NEXT MATERIAL'));assert.ok(cb.includes('function addNextMaterial()'));assert.ok(cb.includes("querySelector('.addNextMaterial')"));assert.ok(!cb.includes('id="addMaterial"'));assert.ok(!cb.includes('+ ADD ANOTHER MATERIAL'));assert.ok(cb.includes('Current material selection complete करें, फिर अगला material add करें.'))});


test('Additional Material numbering excludes Regular Cloth and follows progressive sequence',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("materialNo=materials.slice(1,mi+1).filter(x=>x.type!=='regular').length"));assert.ok(cb.includes('MATERIAL ${materialNo}'));assert.ok(!cb.includes('<h4>Additional Material</h4>'))});


test('Material card uses alphabetic internal steps separate from material numbering',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('A · MATERIAL SELECTION'));assert.ok(cb.includes('B · MATERIAL → SET LINK'));assert.ok(cb.includes('C · REQUIREMENT ESTIMATE · PO BASIS'));assert.ok(cb.includes('D · PURCHASE DETAILS'));assert.ok(cb.includes('MATERIAL ${materialNo}'));});

test('CB supplier Add New persists canonical details and auto-selects saved supplier',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('CANONICAL SUPPLIER MASTER'));assert.ok(cb.includes('cbNewSupplierMobile'));assert.ok(cb.includes('cbNewSupplierAddress'));assert.ok(cb.includes('cbNewSupplierGstin'));assert.ok(cb.includes('rr_supplier_upsert_v1'));assert.ok(cb.includes('materials[supplierModalMaterialIndex].vendor=saved.supplier_name'));assert.ok(cb.includes('secondary compact-new addVendor'));assert.ok(!cb.includes("prompt('New Supplier Name'"))});


test('Set-wise Material Art constraint remains authoritative and decided Art cannot rewrite allowed categories',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('allowed_art_category_ids:allowed'));assert.ok(!cb.includes('effective=decided?'));assert.ok(cb.includes("existing decided Art does not match this Material's allowed categories"));assert.ok(cb.includes("decided Art category is outside this Material's Allowed Art Categories"))});


test('Canonical CB invokeSave exists and uses v600 idempotent save authority',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('async function invokeSave('));assert.ok(cb.includes("rr_cb_department_save_v601"));assert.ok(cb.includes('p_action_id:pa.actionId'));assert.ok(cb.includes('p_payload:body'))});


test('Technical errors never render raw through CB friendly error boundary',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('function isTechnicalError(raw)'));assert.ok(cb.includes('ReferenceError|TypeError|SyntaxError|is not defined'));assert.ok(cb.includes('Save पूरा नहीं हो सका. कृपया required details check करके दोबारा Save करें.'));assert.ok(!cb.includes('Canonical CB save service rejected the request'))});


test('Save failures guide to exact relevant field or section with friendly message',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('function guideSaveError(ex)'));assert.ok(cb.includes("err.guide={selector:'.reconcile-box'}"));assert.ok(cb.includes("base+' .vendor'"));assert.ok(cb.includes("base+' .bill'"));assert.ok(cb.includes("base+' .date'"));assert.ok(cb.includes("base+' .rate'"));assert.ok(cb.includes("base+' .materialQty'"));assert.ok(cb.includes('const guided=guideSaveError(ex);setMessage(guided.message);focusGuidedIssue(guided)'))});


test('Save stage errors identify failing CB subsystem without raw technical text',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("e.saveStage='CB_SAVE'"));assert.ok(cb.includes("e.saveStage='MATERIAL_MAPPING'"));assert.ok(cb.includes("e.saveStage='GSM_SAVE'"));assert.ok(cb.includes('Material की Set / Art mapping save नहीं हो सकी.'));assert.ok(cb.includes('Colour GSM save नहीं हो सका.'));assert.ok(cb.includes("err.guide={selector:'.material-layer:nth-of-type(2)'}"))});


test('Statement timeout reports exact friendly reason instead of blaming required details',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('server save process timeout हुआ है'));assert.ok(cb.includes('/statement timeout|canceling statement|query canceled/i.test(raw)'))});


test('CB save uses bounded v601 wrapper while preserving canonical save authority',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("rr_cb_department_save_v601"));assert.ok(!cb.includes("sb().rpc('rr_cb_department_save_v600'"))});


test('CB save batches repeated Real Chat reconciliation through v601 authority',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("rr_cb_department_save_v601"))});


test('Normal Accounts Book uses reversal-pair filtered projections',()=>{const js=fs.readFileSync(path.resolve(__dirname,'../../real-accounts-v805.js'),'utf8');assert.ok(js.includes('rr_day_book_v807'));assert.ok(js.includes('rr_ledger_statement_v807'));assert.ok(!js.includes('rr_day_book_v806'));assert.ok(!js.includes('rr_ledger_statement_v806'))});


test('Current detail remains above previous-current projection',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');const detail=cb.indexOf('Decision: <b>${esc(x.decision)}</b> · Financial Qty'),projection=cb.indexOf('${esc(h.view_role)} · ${esc(h.decision_date)}');assert.ok(detail>=0&&projection>detail)});


test('Reconciliation canonical load embeds decision projection in same backend snapshot',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_cb_quantity_reconciliation_get_v2'));assert.ok(cb.includes('r.data?.decision_projection'));assert.ok(cb.includes('await loadReconciliation();renderMaterials();'))});


test('CB reconciliation decisions remain view-only until final confirm then post current decision',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_cb_quantity_reconcile_draft_v5'));assert.ok(cb.includes('rr_cb_reconciliation_post_on_confirm_v1'));assert.ok(cb.includes('if(confirming&&cbId)'));assert.ok(cb.includes('Accounts posting will happen only on SAVE & CONFIRM.'))});


test('CB reconciliation render state is declared before use',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');const decl=cb.indexOf('reconciliation=null,reconciliationHistory=[]'),render=cb.indexOf('function reconciliationPanel()');assert.ok(decl>=0&&render>decl);assert.ok(!cb.includes("cbLoadStage"));assert.ok(!cb.includes("loadStage='RENDER'"))});


test('Used material category is hidden from later Additional Material cards',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("const used=new Set(materials.filter(x=>x.type!=='regular'&&x!==m&&x.categoryId)"))});


test('Collar Cuff aliases expose one canonical material while legacy history remains immutable',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("c.is_active!==false"));assert.ok(cb.includes("!=='cuff-collar'"))});


test('Add New Material requires canonical duplicate guard before create',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_material_canonical_guard_v1'));assert.ok(cb.includes("g.status==='EXACT'"));assert.ok(cb.includes("g.status==='SIMILAR'"));assert.ok(cb.includes('Press Save again only if this is genuinely a different material.'))});


test('Collar and Cuff material uses independent Collar neck and Cuff sleeve switches',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("role:'COLLAR'},{zone:'SLEEVE',role:'CUFF'"));assert.ok(cb.includes('>WITH CUFF</option>'));assert.ok(!cb.includes('>WITH CUFF / TAPE</option>'));assert.ok(cb.includes("['N_A','N/A · NOT APPLICABLE'],['CUFF','CUFF']"))});


test('Cutting and CB identity hints stay distinct',()=>{const fs=require('fs'),path=require('path');const cutting=fs.readFileSync(path.resolve(__dirname,'../../real-cutting-master.html'),'utf8'),cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cutting.includes('<span>Lot No. *</span><input id="lotNo" type="text" placeholder="Lot No.">'));assert.ok(!cutting.includes('placeholder="CB No."'));assert.ok(cb.includes('<span>CB No. *</span><input id="cbNo" autocomplete="off" placeholder="CB No.">'));assert.ok(!cb.includes('id="cbNo" autocomplete="off" placeholder="Lot No."'))});


test('Cuff and Tape resolve to one canonical WITH_CUFF mode',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("['WITH_CUFF','CUFF_TAPE','TAPE','CUFF']"));assert.ok(cb.includes('WITH CUFF'));assert.ok(!cb.includes('>WITH TAPE<'));});
