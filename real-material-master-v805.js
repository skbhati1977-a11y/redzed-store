(()=>{
const $=id=>document.getElementById(id);
const UNITS=["PCS","KG","MTR","ROLL","BOX","PACKET","PKT","GADDI","SET","CONE"];
let client,state={material_types:[],materials:[],ledgers:[]},selected=null,timer=null,supplierTimer=null;
const esc=s=>String(s??"").replace(/[&<>\"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const money=n=>new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:2}).format(Number(n||0));
const num=(n,d=3)=>Number(n||0).toLocaleString("en-IN",{maximumFractionDigits:d});
const unitOptions=v=>UNITS.map(u=>`<option value="${u}" ${u===v?"selected":""}>${u}</option>`).join("");
for(const id of ["purchaseUnit","stockUnit","consumptionUnit","newPurchaseUnit","newStockUnit","newConsumptionUnit","newTypePU","newTypeCU"]) if($(id)) $(id).innerHTML=unitOptions();

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
 const {data,error}=await client.rpc("rr_material_purchase_bootstrap_v805_1",{p_data_mode:$("dataMode").value});
 if(error)throw error;
 state=data||state;
 const types=(state.material_types||[]).filter(t=>String(t.type_code||"").toUpperCase()!=="REGULAR_CLOTH");
 $("type").innerHTML=`<option value="">Select…</option>`+types.map(t=>`<option value="${esc(t.type_code)}">${esc(t.type_name)}</option>`).join("");
 $("newMaterialType").innerHTML=`<option value="">Select…</option>`+types.filter(t=>!["MATCHING_CLOTH","STICKER","METAL_ID","REGULAR_CLOTH"].includes(String(t.type_code||"").toUpperCase())).map(t=>`<option value="${esc(t.type_code)}">${esc(t.type_name)}</option>`).join("");
 const suppliers=supplierRows();
 $("supplier").innerHTML=ledgerOptions(suppliers);
 $("newPreferredSupplier").innerHTML=ledgerOptions(suppliers);
 $("cashBank").innerHTML=ledgerOptions((state.ledgers||[]).filter(x=>["CASH","BANK"].includes(String(x.ledger_kind||"").toUpperCase())));
 $("purchaseLedger").innerHTML=ledgerOptions(state.ledgers||[]);
 try{
  const {data:{user}}=await client.auth.getUser();
  if(user){const {data:p}=await client.from("rr_user_profiles").select("full_name,role_code").eq("auth_user_id",user.id).maybeSingle();$("who").textContent=p?`${p.full_name||"User"} · ${String(p.role_code||"").toLowerCase()==="owner"?"Super Admin":p.role_code}`:(user.email||"User")}
 }catch{}
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
 selected=r;$("name").value=r.material_name||"";$("no").value=r.material_no||"";
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
 await loadPreferredSupplier();calc();
}
function calc(){
 const q=Number($("purchaseQty").value||0),r=Number($("rate").value||0),val=q*r;
 $("currentValue").textContent=money(val);
 if(selected&&!selected.source_managed){$("floatAfter").textContent=q>0?"Backend calc on post":$("floatBefore").textContent}
}
function modal(id,show){$(id).classList.toggle("hidden",!show)}
function currentTypeRow(){return (state.material_types||[]).find(x=>x.type_code===$("type").value)||null}
function openNewMaterial(){
 const t=$("type").value;
 if(!t){$("msg").className="err";$("msg").textContent="Select Material Type first.";return}
 if(["MATCHING_CLOTH","STICKER","METAL_ID","REGULAR_CLOTH"].includes(t)){
   $("msg").className="err";$("msg").textContent="This type is source-managed. Create it in its canonical master, not as a duplicate generic material.";return
 }
 $("newMaterialType").value=t;$("newMaterialName").value=$("name").value.trim();$("newMaterialNo").value=$("no").value.trim();
 const tr=currentTypeRow();$("newPurchaseUnit").value=tr?.default_purchase_unit||"PCS";$("newStockUnit").value=tr?.default_consumption_unit||tr?.default_purchase_unit||"PCS";$("newConsumptionUnit").value=tr?.default_consumption_unit||"PCS";
 $("newPreferredSupplier").value=$("supplier").value||"";$("newMaterialMsg").textContent="";modal("materialModal",true)
}
async function saveNewMaterial(){
 $("newMaterialMsg").textContent="";
 const payload={
   p_type_code:$("newMaterialType").value,p_material_name:$("newMaterialName").value.trim(),p_material_no:$("newMaterialNo").value.trim()||null,
   p_purchase_unit:$("newPurchaseUnit").value,p_stock_unit:$("newStockUnit").value,p_purchase_to_stock:Number($("newPurchaseToStock").value||0),
   p_consumption_unit:$("newConsumptionUnit").value,p_consumption_to_stock:Number($("newConsumptionToStock").value||0),
   p_consumption_basis:$("newBasis").value,p_consumption_per_good_piece:Number($("newConsumptionPerGood").value||0),
   p_auto_consumption_event:$("newAutoEvent").value.trim()||null,p_preferred_supplier_ledger_id:$("newPreferredSupplier").value||null,
   p_applicable_to:{tags:$("newApplicableTo").value.split(",").map(x=>x.trim()).filter(Boolean)}
 };
 const {error}=await client.rpc("rr_material_create_v805_31",payload);if(error)throw error;
 modal("materialModal",false);await load();$("type").value=payload.p_type_code;$("name").value=payload.p_material_name;
 $("msg").className="ok";$("msg").textContent="New material saved in backend. Type its name and select the mapped result.";
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
 const pq=Number($("purchaseQty").value||0),rate=Number($("rate").value||0);if(pq<=0)throw Error("Purchase Qty required.");
 if(!$("supplier").value)throw Error("Select Supplier / Party.");
 if(selected.source_managed)throw Error("Source-managed Material must be purchased in its canonical module. Mapping remains locked here.");
 const {data,error}=await client.rpc("rr_material_post_purchase_auto_v805_31",{
   p_supplier_ledger_id:$("supplier").value||null,p_material_id:selected.existing_material_id,p_purchase_ledger_id:$("purchaseLedger").value||null,
   p_purchase_qty:pq,p_rate:rate,p_bill_no:$("billNo").value||null,p_bill_date:$("billDate").value||null,p_gst_amount:Number($("gst").value||0),
   p_payment_status:$("paymentStatus").value,p_paid_amount:Number($("paidAmount").value||0),p_cash_bank_ledger_id:$("cashBank").value||null,p_data_mode:$("dataMode").value
 });
 if(error)throw error;
 $("msg").className="ok";$("msg").textContent=`Posted · Stock/Consumption calculated in backend · Before ${num(data.balance_before_purchase||data.balance_before)} · After ${num(data.balance_after_purchase||data.balance_after)}`;
 await client.rpc("rr_material_source_supplier_set_v805_31",{p_source_type:selected.source_type,p_source_id:selected.source_id,p_supplier_ledger_id:$("supplier").value});
 await load();
}
$("type").onchange=()=>{clearSelection();$("name").value="";$("supplierSearch").value="";$("supplier").value="";const t=currentTypeRow();if(t)$("purchaseUnit").value=t.default_purchase_unit||"PCS";const pl=purchaseLedgerForType($("type").value);if(pl)$("purchaseLedger").value=pl.id;$("suggestions").classList.add("hidden")};
$("name").oninput=()=>{clearTimeout(timer);clearSelection();timer=setTimeout(()=>searchMapped().catch(e=>{$("msg").className="err";$("msg").textContent=e.message}),160)};
$("supplierSearch").oninput=()=>{clearTimeout(supplierTimer);$("supplier").value="";supplierTimer=setTimeout(renderSupplierSuggestions,100)};
document.addEventListener("click",e=>{if(!e.target.closest(".mapped"))$("suggestions").classList.add("hidden");if(!e.target.closest(".combo"))$("supplierSuggestions").classList.add("hidden");const c=e.target.closest("[data-close]");if(c)modal(c.dataset.close,false)});
$("purchaseQty").addEventListener("input",calc);$("rate").addEventListener("input",calc);
$("paymentStatus").onchange=()=>{const s=$("paymentStatus").value!=="CREDIT";$("paidWrap").classList.toggle("hidden",!s);$("cashWrap").classList.toggle("hidden",!s)};
$("addMaterial").onclick=openNewMaterial;$("addSupplier").onclick=()=>{$("newSupplierName").value=$("supplierSearch").value.trim();$("newSupplierMsg").textContent="";modal("supplierModal",true)};
$("addType").onclick=()=>{$("newTypeName").value="";$("newTypeCode").value="";$("newTypeMsg").textContent="";modal("typeModal",true)};
$("saveNewMaterial").onclick=()=>saveNewMaterial().catch(e=>{$("newMaterialMsg").className="err";$("newMaterialMsg").textContent=e.message});
$("saveNewSupplier").onclick=()=>saveNewSupplier().catch(e=>{$("newSupplierMsg").className="err";$("newSupplierMsg").textContent=e.message});
$("saveNewType").onclick=()=>saveNewType().catch(e=>{$("newTypeMsg").className="err";$("newTypeMsg").textContent=e.message});
$("savePost").onclick=()=>savePost().catch(e=>{$("msg").className="err";$("msg").textContent=e.message});
$("refresh").onclick=()=>load().catch(e=>alert(e.message));$("dataMode").onchange=()=>{clearSelection();load().catch(e=>alert(e.message))};
$("billDate").value=new Date().toISOString().slice(0,10);
if(window.RR?.enableZeroClean)RR.enableZeroClean(document);
if(window.RR?.enableEnterNext)RR.enableEnterNext($("form"));
load().catch(e=>alert(e.message));
})();