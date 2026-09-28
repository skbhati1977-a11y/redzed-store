(()=>{
const $=id=>document.getElementById(id);
const FALLBACK_UNITS=["PCS","KG","MTR","ROLL","BOX","PACKET","PKT","GADDI","SET","CONE"];
const UNIT_SELECT_IDS=["purchaseUnit","stockUnit","consumptionUnit","newPurchaseUnit","newStockUnit","newConsumptionUnit","newTypePU","newTypeCU"];
const EDITABLE_UNIT_SELECT_IDS=new Set(["newPurchaseUnit","newStockUnit","newConsumptionUnit","newTypePU","newTypeCU"]);
let client,state={material_types:[],materials:[],ledgers:[],units:FALLBACK_UNITS.map(unit_code=>({unit_code,unit_name:unit_code})),canManageUnits:false},selected=null,timer=null,supplierTimer=null,activeUnitSelect=null;
const esc=s=>String(s??"").replace(/[&<>\"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const money=n=>new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:2}).format(Number(n||0));
const num=(n,d=3)=>Number(n||0).toLocaleString("en-IN",{maximumFractionDigits:d});
const unitOptions=(v,editable=false)=>state.units.map(u=>`<option value="${esc(u.unit_code)}" ${u.unit_code===v?"selected":""}>${esc(u.unit_code)}${u.unit_name&&u.unit_name!==u.unit_code?` · ${esc(u.unit_name)}`:""}</option>`).join("")+(editable&&state.canManageUnits?'<option value="__NEW_UNIT__">+ NEW UNIT</option>':"");
function refreshUnitSelects(preferred={}){for(const id of UNIT_SELECT_IDS){const el=$(id);if(!el)continue;const value=preferred[id]||el.value||"PCS";el.innerHTML=unitOptions(value,EDITABLE_UNIT_SELECT_IDS.has(id));if([...el.options].some(o=>o.value===value))el.value=value;else el.value="PCS"}}
refreshUnitSelects();

function ledgerOptions(rows){return `<option value="">Select…</option>`+rows.map(x=>`<option value="${esc(x.id)}">${esc(x.ledger_name)}</option>`).join("")}
function supplierRows(){return (state.ledgers||[]).filter(x=>["SUPPLIER","PARTY","GENERAL"].includes(String(x.ledger_kind||"").toUpperCase()))}
function purchaseLedgerForType(t){
 const code=t==="REGULAR_CLOTH"?"REGULAR_CLOTH_PURCHASE":t==="MATCHING_CLOTH"?"MATCHING_CLOTH_PURCHASE":t==="STICKER"?"STICKER_PURCHASE":t==="METAL_ID"?"METAL_ID_PURCHASE":"OTHER_MATERIAL_PURCHASE";
 return state.ledgers.find(x=>String(x.category_code||"").toUpperCase()===code)||null
}
function setSupplier(id,name){
 $("supplier").value=id||"";
 $("supplierSearch").value=name||((state.ledgers||[]).find(x=>x.id===id)?.ledger_name||"");
 $("supplierSuggestions").classList.add("hidden");
}
function renderSupplierSuggestions(){
 const q=$("supplierSearch").value.trim().toLowerCase();
 if(!q){$("supplierSuggestions").classList.add("hidden");return}
 const rows=supplierRows().filter(x=>String(x.ledger_name||"").toLowerCase().includes(q)).slice(0,12);
 $("supplierSuggestions").innerHTML=rows.length?rows.map((r,i)=>`<button type="button" class="combo-item" data-sup="${i}"><strong>${esc(r.ledger_name)}</strong><small>${esc(r.ledger_kind||"SUPPLIER")}</small></button>`).join(""):`<div style="padding:10px;color:#9aa4af">No mapped supplier. Use + New.</div>`;
 $("supplierSuggestions").classList.remove("hidden");
 $("supplierSuggestions").querySelectorAll("[data-sup]").forEach(b=>b.onclick=()=>setSupplier(rows[Number(b.dataset.sup)].id,rows[Number(b.dataset.sup)].ledger_name));
}
async function loadPreferredSupplier(){
 if(!selected)return;
 try{
   if(selected.existing_material_id){
     const {data,error}=await client.from("rr_material_master_v805").select("preferred_supplier_ledger_id").eq("id",selected.existing_material_id).maybeSingle();
     if(!error&&data?.preferred_supplier_ledger_id){const l=state.ledgers.find(x=>x.id===data.preferred_supplier_ledger_id);if(l)setSupplier(l.id,l.ledger_name);return}
   }
   const {data,error}=await client.rpc("rr_material_source_supplier_get_v805_31",{p_source_type:selected.source_type,p_source_id:selected.source_id});
   if(!error&&data){const l=state.ledgers.find(x=>x.id===data);if(l)setSupplier(l.id,l.ledger_name)}
 }catch(e){console.warn("Preferred supplier mapping unavailable",e)}
}
async function load(){
 client=client||(window.RR?.getClient?RR.getClient():window.supabaseClient);
 if(!client)throw Error("Supabase client not available.");
 if(!window.RR?.requireRoles)throw Error("Authorization guard unavailable.");
 const auth=await RR.requireRoles(["owner","admin","super_admin"]);
 $("who").textContent=(auth.profile?.full_name||auth.user?.email||"User")+" · "+(String(auth.profile?.role_code||"").toLowerCase()==="owner"?"Super Admin":String(auth.profile?.role_code||""));
 const [boot,unitMaster,identity]=await Promise.all([
  client.rpc("rr_material_purchase_bootstrap_v805_1",{p_data_mode:$("dataMode").value}),
  client.rpc("rr_unit_master_list_v606"),
  client.rpc("rr_upm_effective_identity_v200")
 ]);
 if(boot.error)throw boot.error;if(unitMaster.error)throw unitMaster.error;if(identity.error)throw identity.error;
 const role=String(identity.data?.role_code||identity.data?.resolved_role||"").toUpperCase();
 state={...(boot.data||state),units:Array.isArray(unitMaster.data)&&unitMaster.data.length?unitMaster.data:state.units,canManageUnits:["OWNER","SUPER_ADMIN"].includes(role)};
 refreshUnitSelects();
 const types=(state.material_types||[]).filter(t=>String(t.type_code||"").toUpperCase()!=="REGULAR_CLOTH");
 $("type").innerHTML=`<option value="">Select…</option>`+types.map(t=>`<option value="${esc(t.type_code)}">${esc(t.type_name)}</option>`).join("");
 $("newMaterialType").innerHTML=`<option value="">Select…</option>`+types.filter(t=>!["MATCHING_CLOTH","STICKER","METAL_ID","REGULAR_CLOTH"].includes(String(t.type_code||"").toUpperCase())).map(t=>`<option value="${esc(t.type_code)}">${esc(t.type_name)}</option>`).join("");
 const suppliers=supplierRows();
 $("supplier").innerHTML=ledgerOptions(suppliers);
 $("newPreferredSupplier").innerHTML=ledgerOptions(suppliers);
 $("cashBank").innerHTML=ledgerOptions((state.ledgers||[]).filter(x=>["CASH","BANK"].includes(String(x.ledger_kind||"").toUpperCase())));
 $("purchaseLedger").innerHTML=ledgerOptions(state.ledgers||[]);
}

function clearSelection(){
 selected=null;$("no").value="";$("balanceStrip").classList.remove("show");$("sourceNotice").classList.add("hidden");$("savePost").disabled=false;
 $("stockQty").value=0;$("consumptionQty").value=0;calc();
}
async function searchMapped(){
 const type=$("type").value,q=$("name").value.trim();
 if(!type||!q){$("suggestions").classList.add("hidden");return}
 const {data,error}=await client.rpc("rr_material_source_search_v805_1",{p_type_code:type,p_search:q,p_data_mode:$("dataMode").value,p_limit:20});
 if(error)throw error;
 const rows=data||[];
 $("suggestions").innerHTML=rows.length?rows.map((r,i)=>`<button class="suggestion" data-i="${i}" type="button"><span><strong>${esc(r.material_name)}</strong><small>${esc(r.material_no||r.source_type)}</small></span><small>${r.current_balance_qty==null?"Mapped":`Bal ${num(r.current_balance_qty)} ${esc(r.stock_unit)}`}</small></button>`).join(""):`<div style="padding:10px;color:#9aa4af">No mapped match. Use + New for a generic material.</div>`;
 $("suggestions").classList.remove("hidden");
 $("suggestions").querySelectorAll("[data-i]").forEach(b=>b.onclick=()=>selectMapped(rows[Number(b.dataset.i)]));
}
async function selectMapped(r){
 selected=r;$("name").value=r.material_name||"";$("editMaterialName").disabled=false;$("no").value=r.material_no||"";
 $("purchaseUnit").value=r.purchase_unit||"PCS";$("stockUnit").value=r.stock_unit||"PCS";$("consumptionUnit").value=r.consumption_unit||"PCS";
 $("suggestions").classList.add("hidden");
 $("floatMaterial").textContent=[r.material_no,r.material_name].filter(Boolean).join(" · ");
 $("balanceStrip").classList.add("show");
 $("floatBefore").textContent=r.current_balance_qty==null?"Mapped":`${num(r.current_balance_qty)} ${r.stock_unit||""}`;
 $("beforeMetric").textContent=$("floatBefore").textContent;
 $("floatRunning").textContent=r.current_weighted_cost==null?"—":`${money(r.current_weighted_cost)} / ${r.consumption_unit||r.stock_unit||""}`;
 $("runningCost").textContent=$("floatRunning").textContent;
 const t=$("type").value;
 if(r.source_managed){
   $("floatAfter").textContent="Source-managed";
   $("sourceNotice").classList.remove("hidden");
   $("savePost").disabled=true;
   $("sourceNotice").textContent=t==="MATCHING_CLOTH"?
     "Matching Cloth mapping is locked to the existing Matching Stock source. Canonical purchase posting is intentionally not duplicated here until the Accounts + Matching ledger bridge is verified together.":
     `${t.replaceAll("_"," ")} is mapped from its existing verified master/inventory. Its canonical purchase module remains the posting source.`;
 }else{
   $("sourceNotice").classList.add("hidden");$("savePost").disabled=false;
 }
 await loadPreferredSupplier();updatePurchaseConversionUi();calc();
}
function updatePurchaseConversionUi(){const pu=String($("purchaseUnit").value||"").toUpperCase(),cu=String(selected?.consumption_unit||$("consumptionUnit").value||"").toUpperCase(),same=pu&&cu&&pu===cu;$("purchaseConversionWrap").classList.toggle("hidden",!pu||!cu||same);if(same)$("purchaseConversion").value="1";else if(pu&&cu){$("purchaseConversionLabel").textContent=pu+" → "+cu+" Conversion";$("purchaseConversionHint").textContent="Enter how many "+cu+" are received from 1 "+pu+".";if($("purchaseConversion").value==="1")$("purchaseConversion").value=""}}
function calc(){
 const q=Number($("purchaseQty").value||0),r=Number($("rate").value||0),val=q*r;
 $("currentValue").textContent=money(val);
 if(selected&&!selected.source_managed){$("floatAfter").textContent=q>0?"Backend calc on post":$("floatBefore").textContent}
}
function modal(id,show){$(id).classList.toggle("hidden",!show)}
function openNewUnit(selectId){
 if(!state.canManageUnits){$("msg").className="err";$("msg").textContent="Super Admin Unit Master authority required.";return}
 activeUnitSelect=selectId;$("newUnitName").value="";$("newUnitCode").value="";delete $("newUnitCode").dataset.edited;$("newUnitMsg").textContent="";modal("unitModal",true);setTimeout(()=>$("newUnitName").focus(),30)
}
async function saveNewUnit(){
 const name=$("newUnitName").value.trim(),code=$("newUnitCode").value.trim();
 if(!name)throw Error("Unit Name required.");if(!code)throw Error("Unit Code required.");
 const {data,error}=await client.rpc("rr_unit_master_create_v606",{p_unit_name:name,p_unit_code:code});if(error)throw error;
 const unit=data?.unit;if(!unit?.unit_code)throw Error("Unit Master did not return a canonical Unit.");
 const list=await client.rpc("rr_unit_master_list_v606");if(list.error)throw list.error;state.units=list.data||state.units;
 const target=activeUnitSelect;refreshUnitSelects(target?{[target]:unit.unit_code}:{});if(target&&$(target))$(target).value=unit.unit_code;
 $("newUnitMsg").className="ok";$("newUnitMsg").textContent=data.message||"Unit ready.";
 setTimeout(()=>modal("unitModal",false),250)
}
function newMaterialMethodUi(){const overhead=$("newConsumptionMethod").value==="OVERHEAD";$("newConsumptionUnitWrap").classList.toggle("hidden",overhead);$("newConversionWrap").classList.toggle("hidden",overhead);$("newOverheadInfo").classList.toggle("hidden",!overhead);if(overhead){const pu=$("newPurchaseUnit").value||"PCS";$("newStockUnit").value=pu;$("newConsumptionUnit").value=pu;$("newPurchaseToStock").value="1";$("newConsumptionToStock").value="1"}}
function updateNewMaterialConversion(){const pu=$("newPurchaseUnit").value||"PCS",cu=$("newConsumptionUnit").value||"PCS",same=pu===cu;$("newStockUnit").value=cu;$("newConsumptionToStock").value="1";$("newConversionLeft").textContent="1 "+pu+" =";$("newConversionRight").textContent=cu;if(same)$("newPurchaseToStock").value="1";else if($("newPurchaseToStock").value==="1")$("newPurchaseToStock").value="";$("newConversionHint").textContent=same?"1 "+pu+" = 1 "+cu:"Enter how many "+cu+" equal 1 "+pu;}
function currentTypeRow(){return (state.material_types||[]).find(x=>x.type_code===$("type").value)||null}
let newMaterialImageQueued=null;
function queueNewMaterialImage(e){const file=e.target.files?.[0];if(!file)return;if(newMaterialImageQueued?.url)URL.revokeObjectURL(newMaterialImageQueued.url);newMaterialImageQueued={file,url:URL.createObjectURL(file)};$("newMaterialImagePreview").innerHTML='<img src="'+newMaterialImageQueued.url+'" style="width:100%;max-height:180px;object-fit:contain;border-radius:9px">'}
function clearNewMaterialImage(){if(newMaterialImageQueued?.url)URL.revokeObjectURL(newMaterialImageQueued.url);newMaterialImageQueued=null;$("newMaterialImagePreview").textContent="NO IMAGE";$("newMaterialImageFile").value="";$("newMaterialCameraFile").value=""}
function openNewMaterial(){
 clearNewMaterialImage();
 const t=$("type").value;
 if(!t){$("msg").className="err";$("msg").textContent="Select Material Type first.";return}
 if(["MATCHING_CLOTH","STICKER","METAL_ID","REGULAR_CLOTH"].includes(t)){
   $("msg").className="err";$("msg").textContent="This type is source-managed. Create it in its canonical master, not as a duplicate generic material.";return
 }
 $("newMaterialType").value=t;$("newMaterialName").value=$("name").value.trim();$("newMaterialNo").value=$("no").value.trim();
 const tr=currentTypeRow();$("newPurchaseUnit").value=tr?.default_purchase_unit||"PCS";$("newStockUnit").value=tr?.default_consumption_unit||tr?.default_purchase_unit||"PCS";$("newConsumptionUnit").value=tr?.default_consumption_unit||"PCS";
 $("newPreferredSupplier").value=$("supplier").value||"";$("newReorderBelow").value="";$("newReorderUnit").textContent=$("newPurchaseUnit").value||"—";$("newConsumptionMethod").value="BOM_AUTO";newMaterialMethodUi();updateNewMaterialConversion();$("newMaterialMsg").textContent="";modal("materialModal",true)
}
async function saveNewMaterial(){if(!(await validateNewMaterialDuplicate(true)))return;
 $("newMaterialMsg").textContent="";
 const materialNo=$("newMaterialNo").value.trim();if(materialNo){const {data:existingNo,error:noError}=await client.rpc("rr_material_no_existing_v667",{p_material_no:materialNo});if(noError)throw noError;if(existingNo?.exists)throw Error("Material No. "+materialNo+" already exists as "+existingNo.material_name+". Select existing material or edit its name.");}
 const payload={
   p_type_code:$("newMaterialType").value,p_material_name:$("newMaterialName").value.trim(),p_material_no:$("newMaterialNo").value.trim()||null,
   p_purchase_unit:$("newPurchaseUnit").value,p_stock_unit:$("newStockUnit").value,p_purchase_to_stock:Number($("newPurchaseToStock").value||0),
   p_consumption_unit:$("newConsumptionUnit").value,p_consumption_to_stock:Number($("newConsumptionToStock").value||0),
   p_consumption_basis:$("newBasis").value,p_consumption_per_good_piece:Number($("newConsumptionPerGood").value||0),
   p_auto_consumption_event:$("newAutoEvent").value.trim()||null,p_preferred_supplier_ledger_id:$("newPreferredSupplier").value||null,
   p_applicable_to:{tags:$("newApplicableTo").value.split(",").map(x=>x.trim()).filter(Boolean)}
 };
 const {data:materialId,error}=await client.rpc("rr_material_create_v805_31",payload);if(error)throw error;if(newMaterialImageQueued?.file){if(!window.RR?.uploadMedia)throw Error("Canonical media uploader unavailable.");const media=await RR.uploadMedia({file:newMaterialImageQueued.file,entityType:"material_master_v805",entityId:String(materialId),mediaCategory:"reference",sourceType:"gallery",visibilityScope:"factory",caption:payload.p_material_name+" reference image"});const {error:coverError}=await client.from("rr_media").update({is_cover:true}).eq("id",media.id);if(coverError)throw coverError;clearNewMaterialImage()}const threshold=Number($("newReorderBelow").value||0);if(threshold>0){const {error:thresholdError}=await client.rpc("rr_material_reorder_purchase_threshold_set_v697",{p_material_id:materialId,p_reorder_below_purchase_qty:threshold,p_data_mode:$("dataMode").value});if(thresholdError)throw thresholdError}const method=$("newConsumptionMethod").value;if(method==="OVERHEAD"){const {error:mapError}=await client.rpc("rr_material_mapping_save_v660",{p_material_id:materialId,p_method:"OVERHEAD",p_category_code:null,p_department_code:null,p_execution_decision:false,p_qty_per_piece:null,p_effective_from:new Date().toISOString().slice(0,10),p_consumption_unit:null});if(mapError)throw mapError}
 modal("materialModal",false);await load();$("type").value=payload.p_type_code;$("name").value=payload.p_material_name;
 $("msg").className="ok";$("msg").textContent=method==="OVERHEAD"?"New material saved and mapped to global OVERHEAD · WEIGHTED COST / PCS.":"New material saved. Complete its "+method+" mapping in BOM Mapping.";
}
async function saveNewSupplier(){
 const name=$("newSupplierName").value.trim();if(!name)throw Error("Supplier name required.");
 const {data,error}=await client.rpc("rr_material_supplier_create_v805_31",{p_supplier_name:name});if(error)throw error;
 await load();const l=state.ledgers.find(x=>x.id===data);setSupplier(data,l?.ledger_name||name);modal("supplierModal",false);
 $("msg").className="ok";$("msg").textContent="Supplier ledger created and mapped.";
}
async function saveNewType(){
 const name=$("newTypeName").value.trim();if(!name)throw Error("Type name required.");
 const {data,error}=await client.rpc("rr_material_type_create_v805_31",{p_type_name:name,p_type_code:$("newTypeCode").value.trim()||null,p_default_purchase_unit:$("newTypePU").value,p_default_consumption_unit:$("newTypeCU").value});if(error)throw error;
 modal("typeModal",false);await load();$("type").value=data;$("msg").className="ok";$("msg").textContent="Material Type created.";
}
async function savePost(){
 $("msg").textContent="";const t=$("type").value;if(!t)throw Error("Select Material Type.");if(!selected)throw Error("Select mapped Material.");
 const pq=Number($("purchaseQty").value||0),rate=Number($("rate").value||0),purchaseUnit=$("purchaseUnit").value,consumptionUnit=selected?.consumption_unit||$("consumptionUnit").value,conversion=purchaseUnit===consumptionUnit?1:Number($("purchaseConversion").value||0);if(pq<=0)throw Error("Purchase Qty required.");if(purchaseUnit!==consumptionUnit&&conversion<=0)throw Error("Purchase to Consumption conversion required when units differ.");
 if(!$("supplier").value)throw Error("Select Supplier / Party.");
 if(selected.source_managed)throw Error("Source-managed Material must be purchased in its canonical module. Mapping remains locked here.");
 const {data,error}=await client.rpc("rr_material_post_purchase_txn_v661",{
   p_supplier_ledger_id:$("supplier").value||null,p_material_id:selected.existing_material_id,p_purchase_ledger_id:$("purchaseLedger").value||null,
   p_purchase_qty:pq,p_purchase_unit:purchaseUnit,p_purchase_to_consumption:conversion,p_rate:rate,p_bill_no:$("billNo").value||null,p_bill_date:$("billDate").value||null,p_gst_amount:Number($("gst").value||0),
   p_payment_status:$("paymentStatus").value,p_paid_amount:Number($("paidAmount").value||0),p_cash_bank_ledger_id:$("cashBank").value||null,p_data_mode:$("dataMode").value
 });
 if(error)throw error;
 $("msg").className="ok";$("msg").textContent=`Posted · Stock/Consumption calculated in backend · Before ${num(data.balance_before_purchase||data.balance_before)} · After ${num(data.balance_after_purchase||data.balance_after)}`;
 await client.rpc("rr_material_source_supplier_set_v805_31",{p_source_type:selected.source_type,p_source_id:selected.source_id,p_supplier_ledger_id:$("supplier").value});
 await load();
}
$("type").onchange=()=>{clearSelection();$("name").value="";$("supplierSearch").value="";$("supplier").value="";const t=currentTypeRow();if(t)$("purchaseUnit").value=t.default_purchase_unit||"PCS";$("purchaseConversion").value="";updatePurchaseConversionUi();const pl=purchaseLedgerForType($("type").value);if(pl)$("purchaseLedger").value=pl.id;$("suggestions").classList.add("hidden")};
$("name").oninput=()=>{clearTimeout(timer);clearSelection();timer=setTimeout(()=>searchMapped().catch(e=>{$("msg").className="err";$("msg").textContent=e.message}),160)};
$("supplierSearch").oninput=()=>{clearTimeout(supplierTimer);$("supplier").value="";supplierTimer=setTimeout(renderSupplierSuggestions,100)};
document.addEventListener("click",e=>{if(!e.target.closest(".mapped"))$("suggestions").classList.add("hidden");if(!e.target.closest(".combo"))$("supplierSuggestions").classList.add("hidden");const c=e.target.closest("[data-close]");if(c)modal(c.dataset.close,false)});
$("purchaseQty").addEventListener("input",calc);$("rate").addEventListener("input",calc);$("purchaseUnit").addEventListener("change",updatePurchaseConversionUi);
$("paymentStatus").onchange=()=>{const s=$("paymentStatus").value!=="CREDIT";$("paidWrap").classList.toggle("hidden",!s);$("cashWrap").classList.toggle("hidden",!s)};
let bomImageMedia=null,bomImageQueued=null;
async function loadBomMaterialImage(){const id=$("bomMaterial")?.value;if(!id){bomImageMedia=null;bomImageQueued=null;renderBomMaterialImage();return}const {data,error}=await client.from("rr_media").select("id,file_url,storage_path,is_cover,created_at").eq("entity_type","material_master_v805").eq("entity_id",id).eq("media_category","reference").order("is_cover",{ascending:false}).order("created_at",{ascending:false}).limit(1);if(error)throw error;bomImageMedia=data?.[0]||null;bomImageQueued=null;renderBomMaterialImage()}
function renderBomMaterialImage(){const p=$("bomImagePreview");if(!p)return;const url=bomImageQueued?.url||bomImageMedia?.file_url||"";p.innerHTML=url?'<img src="'+esc(url)+'" style="width:88px;height:88px;object-fit:cover;border-radius:10px;border:1px solid #39434e"><div><strong>Reference Image</strong><br><small style="color:var(--muted)">'+(bomImageQueued?'Ready to save / replace':'Saved · thumbnails enabled')+'</small></div>':'<div style="color:var(--muted)">NO IMAGE</div>'}
async function saveBomMaterialImage(){const id=$("bomMaterial")?.value;if(!id)throw Error("Select Material.");if(!bomImageQueued?.file)throw Error("Choose or capture an image first.");if(!window.RR?.uploadMedia)throw Error("Canonical media uploader unavailable.");const material=(state.materials||[]).find(x=>String(x.id||x.existing_material_id)===String(id));const media=await RR.uploadMedia({file:bomImageQueued.file,entityType:"material_master_v805",entityId:id,mediaCategory:"reference",sourceType:"gallery",visibilityScope:"factory",caption:(material?.material_name||"Material")+" reference image"});await client.from("rr_media").update({is_cover:false}).eq("entity_type","material_master_v805").eq("entity_id",id).eq("media_category","reference");const {error}=await client.from("rr_media").update({is_cover:true}).eq("id",media.id);if(error)throw error;if(bomImageMedia&&bomImageMedia.id!==media.id){if(bomImageMedia.storage_path){const s=await client.storage.from("redzed-media").remove([bomImageMedia.storage_path]);if(s.error)console.warn(s.error)}await client.from("rr_media").delete().eq("id",bomImageMedia.id)}if(bomImageQueued?.url)URL.revokeObjectURL(bomImageQueued.url);bomImageQueued=null;await loadBomMaterialImage();$("bomMsg").className="ok";$("bomMsg").textContent="Material image saved. Mapped thumbnails will use this reference image."}
async function deleteBomMaterialImage(){const id=$("bomMaterial")?.value;if(!id)throw Error("Select Material.");if(!bomImageMedia&&!bomImageQueued)return;if(!confirm("Delete this Material reference image?"))return;if(bomImageQueued?.url)URL.revokeObjectURL(bomImageQueued.url);bomImageQueued=null;if(bomImageMedia){if(bomImageMedia.storage_path){const s=await client.storage.from("redzed-media").remove([bomImageMedia.storage_path]);if(s.error)throw s.error}const d=await client.from("rr_media").delete().eq("id",bomImageMedia.id);if(d.error)throw d.error;bomImageMedia=null}renderBomMaterialImage();$("bomMsg").className="ok";$("bomMsg").textContent="Material image deleted."}
async function openMaterialEdit(id,name){if(!id)throw Error("Canonical Material ID missing.");$("renameMaterialName").value=name||"";$("renameMaterialMsg").textContent="";delete $("saveMaterialRename").dataset.bomMaterialId;try{const {data,error}=await client.rpc("rr_material_reorder_purchase_config_v697",{p_material_id:id,p_data_mode:$("dataMode").value});if(error)throw error;const unit=String(data?.purchase_unit||"").trim().toUpperCase();$("renameReorderBelow").value=data?.reorder_below_qty??"";$("renameReorderUnit").textContent=unit||"UNIT";$("renameReorderUnit").dataset.resolvedUnit=unit}catch(e){$("renameReorderBelow").value="";$("renameReorderUnit").textContent="UNIT";$("renameReorderUnit").dataset.resolvedUnit="";$("renameMaterialMsg").className="err";$("renameMaterialMsg").textContent="Unit mapping could not load: "+(e?.message||e)}modal("renameMaterialModal",true)}
const queueBomImage=e=>{const file=e.target.files?.[0];if(!file)return;if(bomImageQueued?.url)URL.revokeObjectURL(bomImageQueued.url);bomImageQueued={file,url:URL.createObjectURL(file)};renderBomMaterialImage()};$("newMaterialImageFile").onchange=queueNewMaterialImage;$("newMaterialCameraFile").onchange=queueNewMaterialImage;$("newMaterialImageClear").onclick=clearNewMaterialImage;$("bomImageFile").onchange=queueBomImage;$("bomCameraFile").onchange=queueBomImage;$("bomDeleteImage").onclick=()=>deleteBomMaterialImage().catch(e=>{$("bomMsg").className="err";$("bomMsg").textContent=e.message});
$("addMaterial").onclick=openNewMaterial;$("editMaterialName").onclick=async()=>{if(!selected)return;let id=selected.existing_material_id||selected.material_id||selected.id;if(!id&&selected.material_name){const {data:resolved,error:resolveError}=await client.from("rr_material_master_v805").select("id").eq("material_name",selected.material_name).eq("is_active",true).limit(1).maybeSingle();if(resolveError)throw resolveError;id=resolved?.id||""}await openMaterialEdit(id,selected.material_name)};;$("saveMaterialRename").onclick=async()=>{try{const bomId=$("saveMaterialRename").dataset.bomMaterialId||"";const id=bomId||(selected&&(selected.existing_material_id||selected.material_id||selected.id));if(!id)throw Error("Select Material.");const {data,error}=await client.rpc("rr_material_rename_v667",{p_material_id:id,p_material_name:$("renameMaterialName").value.trim()});if(error)throw error;const {error:thresholdError}=await client.rpc("rr_material_reorder_purchase_threshold_set_v697",{p_material_id:id,p_reorder_below_purchase_qty:Number($("renameReorderBelow").value||0),p_data_mode:$("dataMode").value});if(thresholdError)throw thresholdError;if(selected&&(selected.existing_material_id||selected.material_id)===id){selected.material_name=data.material_name;$("name").value=data.material_name;$("floatMaterial").textContent=[selected.material_no,data.material_name].filter(Boolean).join(" · ")}modal("renameMaterialModal",false);delete $("saveMaterialRename").dataset.bomMaterialId;await load();if(bomId){await openBom();$("bomMaterial").value=id;const opt=[...$("bomMaterial").options].find(o=>o.value===id);if(opt)opt.textContent=data.material_name;await hydrateBomMaterial()}}catch(e){$("renameMaterialMsg").className="err";$("renameMaterialMsg").textContent=e.message}};$("addSupplier").onclick=()=>{$("newSupplierName").value=$("supplierSearch").value.trim();$("newSupplierMsg").textContent="";modal("supplierModal",true)};
$("addType").onclick=()=>{$("newTypeName").value="";$("newTypeCode").value="";$("newTypeMsg").textContent="";modal("typeModal",true)};
async function validateNewMaterialDuplicate(focusOnError=false){const name=$("newMaterialName").value.trim(),no=$("newMaterialNo").value.trim();if(!name&&!no)return true;const {data,error}=await client.rpc("rr_material_duplicate_check_v668",{p_type_code:$("newMaterialType").value,p_material_name:name,p_material_no:no||null,p_exclude_material_id:null});if(error)throw error;if(!data?.duplicate){$("newMaterialMsg").textContent="";return true}const byNo=data.material_no_duplicate,msg=(byNo?"Duplicate Material No.":"Duplicate Material Name.")+" Existing: "+[data.match?.material_no,data.match?.material_name].filter(Boolean).join(" · ");$("newMaterialMsg").className="err";$("newMaterialMsg").textContent=msg;const el=byNo?$("newMaterialNo"):$("newMaterialName");el.setCustomValidity(msg);el.scrollIntoView({behavior:"smooth",block:"center"});if(focusOnError)setTimeout(()=>el.focus(),250);return false}
$("newMaterialName").addEventListener("input",()=>$("newMaterialName").setCustomValidity(""));$("newMaterialNo").addEventListener("input",()=>$("newMaterialNo").setCustomValidity(""));$("newMaterialName").addEventListener("blur",()=>validateNewMaterialDuplicate(false).catch(()=>{}));$("newMaterialNo").addEventListener("blur",()=>validateNewMaterialDuplicate(false).catch(()=>{}));
$("newConsumptionMethod").onchange=()=>{newMaterialMethodUi();if($("newConsumptionMethod").value!=="OVERHEAD")updateNewMaterialConversion()};$("newPurchaseUnit").onchange=()=>{if($("newConsumptionMethod").value==="OVERHEAD")newMaterialMethodUi();else updateNewMaterialConversion()};$("newConsumptionUnit").onchange=updateNewMaterialConversion;
$("saveNewMaterial").onclick=()=>saveNewMaterial().catch(e=>{$("newMaterialMsg").className="err";$("newMaterialMsg").textContent=e.message});
$("saveNewSupplier").onclick=()=>saveNewSupplier().catch(e=>{$("newSupplierMsg").className="err";$("newSupplierMsg").textContent=e.message});
$("saveNewType").onclick=()=>saveNewType().catch(e=>{$("newTypeMsg").className="err";$("newTypeMsg").textContent=e.message});
$("saveNewUnit").onclick=()=>saveNewUnit().catch(e=>{$("newUnitMsg").className="err";$("newUnitMsg").textContent=e.message});
$("newUnitName").addEventListener("input",()=>{if(!$("newUnitCode").dataset.edited)$("newUnitCode").value=$("newUnitName").value.trim().toUpperCase().replace(/[^A-Z0-9]+/g,"_").replace(/^_+|_+$/g,"")});
$("newUnitCode").addEventListener("input",e=>{e.target.dataset.edited="1";e.target.value=e.target.value.toUpperCase().replace(/[^A-Z0-9_]+/g,"")});
for(const id of EDITABLE_UNIT_SELECT_IDS){const el=$(id);if(!el)continue;el.addEventListener("focus",()=>{el.dataset.previousUnit=el.value});el.addEventListener("change",()=>{if(el.value!=="__NEW_UNIT__")return;const previous=el.dataset.previousUnit||"PCS";el.value=previous;openNewUnit(id)})}
$("savePost").onclick=()=>savePost().catch(e=>{$("msg").className="err";$("msg").textContent=e.message});
$("refresh").onclick=()=>load().catch(e=>alert(e.message));$("dataMode").onchange=()=>{clearSelection();load().catch(e=>alert(e.message))};
const WORKER_CONSUMPTION_DEPARTMENTS=[
 ["PRINTING","Print"],["STICKER","Sticker"],["METAL_ID","Metal ID"],["STITCHING","Karigar / Stitching"],["OVERLOCK","Overlock"],["FOLDING","Folding"],["KAAJ_BTN","Kaaj / Button"],["TEAK_TANKI","Teak / Tanki"],["THREAD_CUT","Thread Cut"],["QC","QC"],["PRESS","Press"],["PACKING","Packing"],["DESPATCH","Despatch"]
];
function fillWorkerDepartmentSelect(){const el=$("bomDepartment");if(!el)return;const keep=el.value;el.innerHTML='<option value="">Select Department…</option>'+WORKER_CONSUMPTION_DEPARTMENTS.map(([v,n])=>'<option value="'+v+'">'+n+'</option>').join("");if(keep&&[...el.options].some(o=>o.value===keep))el.value=keep}
function bomMethodUi(){const m=$("bomMethod").value;$("bomCategoryWrap").classList.toggle("hidden",m!=="BOM_AUTO");$("bomQtyWrap").classList.toggle("hidden",m!=="BOM_AUTO");$("bomDeptWrap").classList.toggle("hidden",m!=="WORKER_ACTUAL");$("bomExecutionWrap").classList.toggle("hidden",m!=="DIRECT_ACTUAL");$("bomDirectDeptWrap").classList.toggle("hidden",m!=="DIRECT_ACTUAL"||$("bomExecution").value==="true");$("bomUnitWrap").classList.toggle("hidden",m==="OVERHEAD"||m==="WORKER_ACTUAL");$("bomOverheadWrap").classList.toggle("hidden",m!=="OVERHEAD")}
async function openBom(){fillWorkerDepartmentSelect();const {data,error}=await client.rpc("rr_material_purchase_bootstrap_v805_1",{p_data_mode:$("dataMode").value});if(error)throw error;const mats=(data?.materials||[]).filter(x=>x.material_id||x.existing_material_id),categories=data?.categories||[];$("bomMaterial").innerHTML='<option value="">Select…</option>'+mats.map(x=>'<option value="'+esc(x.material_id||x.existing_material_id)+'" data-unit="'+esc(x.consumption_unit||"")+'">'+esc(x.material_name)+'</option>').join("");$("bomCategoryMenu").innerHTML='<label style="display:block;padding:7px"><input type="checkbox" data-bom-cat="ALL" checked style="width:auto"> ALL</label>'+categories.filter(x=>x.category_code).map(x=>'<label style="display:block;padding:7px"><input type="checkbox" data-bom-cat="'+esc(x.category_code)+'" style="width:auto"> '+esc(x.category_name||x.category_code)+'</label>').join("");$("bomCategoryButton").textContent="ALL ▾";$("bomUnit").innerHTML=unitOptions("");$("bomDate").value=new Date().toISOString().slice(0,10);$("bomMsg").textContent="Select an existing Material to load its saved master units and canonical mapping.";$("bomMsg").className="";bomMethodUi();modal("bomModal",true)}
$("openBom").onclick=()=>openBom().catch(e=>{$("msg").className="err";$("msg").textContent=e.message});$("bomMethod").onchange=bomMethodUi;$("bomExecution").onchange=bomMethodUi;async function hydrateBomMaterial(){const material=$("bomMaterial").value,opt=$("bomMaterial").selectedOptions[0],defaultUnit=opt?.dataset.unit||"";$("bomUnit").innerHTML=unitOptions(defaultUnit);if(defaultUnit)$("bomUnit").value=defaultUnit;$("bomQty").value="";$("bomDepartment").value="";$("bomDirectDepartment").value="";$("bomExecution").value="true";[...$("bomCategoryMenu").querySelectorAll("[data-bom-cat]")].forEach(o=>o.checked=o.dataset.bomCat==="ALL");$("bomCategoryButton").textContent="ALL ▾";$("bomDate").value=new Date().toISOString().slice(0,10);$("bomMsg").className="";$("bomMsg").textContent=material?("Saved master Consumption Unit: "+(defaultUnit||"Not set")+" · Loading canonical mapping…"):"Select Material.";if(!material){bomMethodUi();return}const {data,error}=await client.rpc("rr_material_mapping_list_v656");if(error)throw error;const rows=(data?.rows||[]).filter(r=>String(r.material_id)===String(material)&&r.is_active!==false);if(!rows.length){$("bomMethod").value="";$("bomMsg").className="notice";$("bomMsg").textContent="Mapping not set · Saved master Consumption Unit: "+(defaultUnit||"Not set")+". Choose Consumption Method to create the first canonical mapping.";bomMethodUi();return;}const latestDate=rows.map(r=>r.effective_from||"").sort().reverse()[0],latest=rows.filter(r=>String(r.effective_from||"")===String(latestDate)),first=latest[0];$("bomMethod").value=first.consumption_method||"BOM_AUTO";if(first.unit){$("bomUnit").innerHTML=unitOptions(first.unit);$("bomUnit").value=first.unit}$("bomDate").value=first.effective_from||new Date().toISOString().slice(0,10);if(first.consumption_method==="BOM_AUTO"){const cats=new Set(latest.filter(r=>r.consumption_method==="BOM_AUTO").map(r=>String(r.category_code||"").toUpperCase()));[...$("bomCategoryMenu").querySelectorAll("[data-bom-cat]")].forEach(o=>o.checked=cats.has(String(o.dataset.bomCat).toUpperCase()));const checked=[...$("bomCategoryMenu").querySelectorAll("[data-bom-cat]:checked")];$("bomCategoryButton").textContent=(checked.some(x=>x.dataset.bomCat==="ALL")?"ALL":checked.length===1?checked[0].parentElement.textContent.trim():checked.length+" selected")+" ▾";$("bomQty").value=first.qty_per_piece??""}else if(first.consumption_method==="WORKER_ACTUAL"){fillWorkerDepartmentSelect();$("bomDepartment").value=first.consume_department_code||"";}else if(first.consumption_method==="DIRECT_ACTUAL"){$("bomExecution").value=first.execution_decision?"true":"false";$("bomDirectDepartment").value=first.consume_department_code||""}$("bomMsg").className="ok";$("bomMsg").textContent=(first.consumption_method==="WORKER_ACTUAL"?"Saved WORKER mapping loaded · Department engine is the quantity/unit authority":"Saved canonical mapping loaded · "+(first.consumption_method||""))+" · Effective "+(first.effective_from||"—");bomMethodUi()}
$("bomMaterial").onchange=async()=>{try{if(bomImageQueued?.url)URL.revokeObjectURL(bomImageQueued.url);bomImageQueued=null;bomImageMedia=null;renderBomMaterialImage();await hydrateBomMaterial();await loadBomMaterialImage()}catch(e){$("bomMsg").className="err";$("bomMsg").textContent=e.message}};$("bomEditMaterialName").onclick=async()=>{const id=$("bomMaterial").value;if(!id){$("bomMsg").className="err";$("bomMsg").textContent="Select Material first.";return}const opt=$("bomMaterial").selectedOptions[0];await openMaterialEdit(id,opt?.textContent?.trim()||"");$("saveMaterialRename").dataset.bomMaterialId=id};
$("bomAddUnit").onclick=()=>openNewUnit("bomUnit");$("bomAddMaterial").onclick=()=>{modal("bomModal",false);$("type").value="OTHER_MATERIAL";$("name").value="";$("no").value="";openNewMaterial();};$("bomCategoryButton").onclick=()=>$("bomCategoryMenu").classList.toggle("hidden");
$("bomCategoryMenu").onchange=e=>{if(!e.target.matches("[data-bom-cat]"))return;const boxes=[...$("bomCategoryMenu").querySelectorAll("[data-bom-cat]")],all=boxes.find(x=>x.dataset.bomCat==="ALL");if(e.target===all){if(all.checked)boxes.forEach(x=>{if(x!==all)x.checked=false});else if(!boxes.some(x=>x!==all&&x.checked))all.checked=true}else{all.checked=false}const selected=boxes.filter(x=>x.checked);if(!selected.length)all.checked=true;const now=boxes.filter(x=>x.checked);$("bomCategoryButton").textContent=(now.some(x=>x.dataset.bomCat==="ALL")?"ALL":now.length===1?now[0].parentElement.textContent.trim():now.length+" selected")+" ▾"};
document.addEventListener("click",e=>{if(!$("bomCategoryWrap").contains(e.target))$("bomCategoryMenu").classList.add("hidden")});
$("saveBom").onclick=async()=>{try{const method=$("bomMethod").value,material=$("bomMaterial").value;if(!material)throw Error("Select Material.");if(!method)throw Error("Select Consumption Method.");if(method==="WORKER_ACTUAL"&&!$("bomDepartment").value)throw Error("Select Consume At Department.");const categories=method==="BOM_AUTO"?[...$("bomCategoryMenu").querySelectorAll("[data-bom-cat]:checked")].map(o=>o.dataset.bomCat):[null];if(method==="BOM_AUTO"&&!categories.length)throw Error("Select ALL or at least one Category.");if(method==="BOM_AUTO"){const {error}=await client.rpc("rr_material_mapping_category_set_v696",{p_material_id:material,p_category_codes:categories,p_qty_per_piece:Number($("bomQty").value),p_effective_from:$("bomDate").value,p_consumption_unit:$("bomUnit").value||null});if(error)throw error}else{const {error}=await client.rpc("rr_material_mapping_save_v660",{p_material_id:material,p_method:method,p_category_code:null,p_department_code:method==="WORKER_ACTUAL"?$("bomDepartment").value:method==="DIRECT_ACTUAL"&&$("bomExecution").value==="false"?$("bomDirectDepartment").value:null,p_execution_decision:method==="DIRECT_ACTUAL"&&$("bomExecution").value==="true",p_qty_per_piece:null,p_effective_from:$("bomDate").value,p_consumption_unit:method==="OVERHEAD"||method==="WORKER_ACTUAL"?null:($("bomUnit").value||null)});if(error)throw error}if(bomImageQueued?.file)await saveBomMaterialImage();$("bomMsg").className="ok";$("bomMsg").textContent="Canonical mapping saved.";if(bomImageQueued?.url)URL.revokeObjectURL(bomImageQueued.url);bomImageQueued=null;$("bomImageFile").value="";$("bomCameraFile").value="";await load();$("bomMaterial").value=material;await hydrateBomMaterial();await loadBomMaterialImage();$("bomMsg").className="ok";$("bomMsg").textContent="Canonical mapping saved and reloaded.";}catch(e){$("bomMsg").className="err";$("bomMsg").textContent=e.message}};
$("billDate").value=new Date().toISOString().slice(0,10);
if(window.RR?.enableZeroClean)RR.enableZeroClean(document);
if(window.RR?.enableEnterNext)RR.enableEnterNext($("form"));
load().catch(e=>alert(e.message));
})();
