(() => {
"use strict";

window.REAL FACTORY_PRODUCT_CB_LEDGER_VERSION = "720.36.2-PERMISSION-LEDGER";

const state = {client:null,role:"",ledger:[],actions:[],effects:[],lastCb:"",busy:false};
const $ = id => document.getElementById(id);
const safe = value => String(value ?? "").replace(/[&<>"']/g,c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
const kg = value => `${Number(value || 0).toFixed(3)} kg`;
const money = value => new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:2}).format(Number(value || 0));
const dateTime = value => value ? new Intl.DateTimeFormat("en-IN",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value)) : "—";
const statusText = value => String(value || "").replaceAll("_"," ");
const errorText = error => [error?.message,error?.details,error?.hint,error?.code].filter(Boolean).join(" — ") || "Unknown error";

function getClient(){
  let client=null;
  try{if(typeof supabaseClient!=="undefined"&&supabaseClient?.from)client=supabaseClient}catch{}
  return client || [window.supabaseClient,window.supabaseDb,window.redzedSupabase,window.sb].find(x=>x?.from) || null;
}
function isOwner(){return state.role==="owner"}
function canViewFinancials(){return ["owner","admin","account","accounts"].includes(String(state.role||"").toLowerCase())}
function normalizePhone(value){let x=String(value||"").replace(/\D/g,"");if(x.length===10)x=`91${x}`;return x}
function openWhatsapp(phone,message){const n=normalizePhone(phone);if(!n)throw new Error("Vendor WhatsApp number required.");const w=window.open(`https://wa.me/${n}?text=${encodeURIComponent(message)}`,"_blank","noopener,noreferrer");if(!w)throw new Error("Browser ने WhatsApp popup block किया।")}
function proofLinks(action){return Array.isArray(action.media)?action.media.map(x=>x.file_url).filter(Boolean):[]}
function messageWithProof(action){const links=proofLinks(action);return `${action.vendor_message||""}${links.length?`\n\nDamage / GR proof:\n${links.join("\n")}`:""}`}
function say(text,type="info"){const box=$("message");if(!box)return;box.textContent=text;box.className=`message ${type}`}

async function loadRole(){const r=await state.client.rpc("rr_current_role");if(!r.error&&r.data)state.role=String(r.data).toLowerCase()}
async function loadData(){
  if(state.busy||!state.client||!canViewFinancials())return;
  state.busy=true;
  try{
    const [l,a,e]=await Promise.all([
      state.client.from("rr_product_cb_purchase_ledger_v72035").select("*").order("bill_date",{ascending:false}),
      state.client.from("rr_cutting_cb_action_details_v1").select("*").order("created_at",{ascending:false}),
      state.client.from("rr_cutting_cb_action_effect_details_v1").select("*").order("created_at",{ascending:false})
    ]);
    if(l.error)console.warn(l.error);else state.ledger=l.data||[];
    if(a.error)console.warn(a.error);else state.actions=a.data||[];
    if(e.error)console.warn(e.error);else state.effects=e.data||[];
  }finally{state.busy=false}
}

function injectStyles(){
  if($("rrPmLedgerStyles"))return;
  const style=document.createElement("style");style.id="rrPmLedgerStyles";style.textContent=`
    .rr-pm-ledger-note{padding:12px;border:1px solid #65502c;border-radius:12px;background:#241f13;color:#ead79b;line-height:1.45;margin-bottom:12px}
    .rr-pm-ledger{margin-top:12px}.rr-pm-ledger h3{margin:0 0 10px}.rr-pm-ledger table{min-width:1120px}
    .rr-pm-rolls{display:flex;gap:6px;flex-wrap:wrap}.rr-pm-roll{padding:5px 7px;border:1px solid #3b3b45;border-radius:9px;background:#101014;white-space:nowrap}
    .rr-pm-action{padding:11px;border:1px solid #3a3a44;border-radius:12px;background:#101014;margin-top:8px}.rr-pm-action-head{display:flex;justify-content:space-between;gap:8px;align-items:flex-start}
    .rr-pm-action p{margin:4px 0}.rr-pm-proof{display:flex;gap:7px;overflow:auto;margin-top:8px}.rr-pm-proof img,.rr-pm-proof video{width:90px;height:90px;object-fit:cover;border-radius:9px;background:#08080a}
    .rr-pm-owner-btn{margin-top:9px;border:1px solid #896a25;background:#4c3b15;color:#ffe49d;border-radius:9px;padding:7px 10px;font-weight:900}
    .rr-pm-pending{border-color:#7c5b2c;background:#221b12}.rr-pm-approved{border-color:#286c48;background:#10261a}
  `;document.head.appendChild(style);
}

function rollsHtml(rows){
  const rolls=Array.isArray(rows)?rows:[];
  if(!rolls.length)return "—";
  return `<div class="rr-pm-rolls">${rolls.map(r=>`<span class="rr-pm-roll"><b>${safe(r.division_code||"D")} · ${safe(r.colour_name||"Colour")} · Roll ${safe(r.roll_no)}</b><br><small>${kg(r.original_qty)} → ${kg(r.current_qty)}</small></span>`).join("")}</div>`;
}

function purchaseLedgerHtml(cbNo){
  const rows=state.ledger.filter(x=>String(x.cb_no)===String(cbNo));
  if(!rows.length)return `<p class="muted">Purchase ledger view अभी उपलब्ध नहीं है। V720.35 SQL check करें।</p>`;
  return `<div class="table-wrap"><table><thead><tr><th>Date</th><th>Bill No.</th><th>Vendor</th><th>Fabric</th><th>Roll / Colour / D</th><th>Original Qty</th><th>Rate</th><th>Original Value</th><th>GR Qty</th><th>Damage Qty</th><th>Exchange IN</th><th>Current Qty</th><th>Current Value</th><th>Status</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${safe(r.bill_date||"—")}</td><td><strong>${safe(r.bill_no||"—")}</strong></td><td>${safe(r.vendor_name||"—")}</td><td>${safe(r.fabric_name||r.category_name||"—")}</td><td>${rollsHtml(r.rolls)}</td><td>${kg(r.original_quantity)}</td><td>${money(r.rate)}</td><td>${money(r.original_amount)}</td><td class="negative">${kg(r.total_gr_qty)}</td><td class="negative">${kg(r.total_damage_qty)}</td><td class="positive">${kg(r.total_exchange_qty)}</td><td><strong>${kg(r.current_quantity)}</strong></td><td><strong>${money(r.current_value)}</strong></td><td><span class="status-chip">${safe(statusText(r.operation_status))}</span></td></tr>`).join("")}</tbody></table></div>`;
}

function mediaHtml(action){const rows=Array.isArray(action.media)?action.media:[];if(!rows.length)return"";return `<div class="rr-pm-proof">${rows.map(m=>String(m.media_type).toUpperCase()==="IMAGE"?`<a href="${safe(m.file_url)}" target="_blank"><img src="${safe(m.file_url)}" alt="Proof"></a>`:`<video controls preload="metadata" src="${safe(m.file_url)}"></video>`).join("")}</div>`}

function actionHtml(action){
  const pending=!action.effect_posted&&!["REJECTED"].includes(action.status);
  const approved=Boolean(action.effect_posted);
  const source=[action.bill_no,action.vendor_name,action.fabric_name,action.colour_name,action.roll_no?`Roll ${action.roll_no}`:""].filter(Boolean).join(" · ")||`${action.full_gr_scope||""} Full GR`;
  return `<article class="rr-pm-action ${pending?"rr-pm-pending":approved?"rr-pm-approved":""}"><div class="rr-pm-action-head"><div><strong>Action-${safe(action.action_no)} · ${safe(statusText(action.action_type))}</strong><p>${safe(action.division_code)} · Lot ${safe(action.source_lot_no||"—")} · ${kg(action.qty)} · ${money(action.value_snapshot)}</p><small>${safe(source)}</small></div><span class="status-chip">${safe(statusText(action.status))}</span></div><p><small>${safe(action.reason)}</small></p>${mediaHtml(action)}${approved?`<p><small>Owner approved: ${dateTime(action.owner_approved_at)} · Product Master stock/cost effect posted.</small></p>`:""}${isOwner()&&approved&&["OWNER_APPROVED","VENDOR_MESSAGE_SENT"].includes(action.status)?`<button class="rr-pm-owner-btn" type="button" data-pm-vendor="${safe(action.id)}">Owner → Vendor WhatsApp</button>`:""}</article>`;
}

function actionsHtml(cbNo){
  const rows=state.actions.filter(x=>String(x.cb_no)===String(cbNo));
  if(!rows.length)return `<p class="muted">इस CB में अभी Cutting Damage / GR report नहीं है।</p>`;
  const pending=rows.filter(x=>!x.effect_posted&&x.status!=="REJECTED");
  const final=rows.filter(x=>x.effect_posted||x.status==="REJECTED");
  return `${pending.length?`<h4>Pending Cutting Reports</h4>${pending.map(actionHtml).join("")}`:""}<h4 style="margin-top:14px">Approved / Final Action Ledger</h4>${final.length?final.map(actionHtml).join(""):`<p class="muted">No approved action yet.</p>`}`;
}

function effectsHtml(cbNo){
  const rows=state.effects.filter(x=>String(x.cb_no)===String(cbNo));
  if(!rows.length)return `<p class="muted">Approved effect entries अभी नहीं हैं।</p>`;
  return `<div class="table-wrap"><table><thead><tr><th>Owner Approval</th><th>Lot No.</th><th>D</th><th>Type</th><th>Bill No.</th><th>Vendor</th><th>Qty</th><th>Rate</th><th>Value</th><th>Reason</th><th>Vendor Message</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${dateTime(r.owner_approved_at)}</td><td><strong>${safe(r.source_lot_no||"—")}</strong></td><td>${safe(r.division_code||"—")}</td><td>${safe(statusText(r.action_type))}</td><td>${safe(r.bill_no||"—")}</td><td>${safe(r.vendor_name||"—")}</td><td>${kg(r.qty)}</td><td>${money(r.rate)}</td><td>${money(r.value)}</td><td>${safe(r.reason||"—")}</td><td>${r.vendor_message_sent_at?`Sent ${dateTime(r.vendor_message_sent_at)}`:"Pending / Owner decision"}</td></tr>`).join("")}</tbody></table></div>`;
}

async function sendVendor(id){
  const action=state.actions.find(x=>String(x.id)===String(id));if(!action)return;
  const phone=action.vendor_phone||prompt("Vendor WhatsApp number")||"";if(!phone)return;
  const message=prompt("Vendor message",messageWithProof(action))||"";if(!message)return;
  try{
    openWhatsapp(phone,message);
    const r=await state.client.rpc("rr_cutting_mark_cb_action_vendor_sent_v1",{p_action_id:id,p_vendor_phone:phone,p_vendor_message:message});
    if(r.error)throw r.error;
    await loadData();renderCurrent();say("Vendor WhatsApp opened and ledger marked.","success");
  }catch(e){say(errorText(e),"error")}
}

function removeDirectCbActions(){
  const body=$("detailBody");if(!body)return;
  body.querySelectorAll("[data-cb-gr],[data-damage]").forEach(x=>x.remove());
  body.querySelectorAll(".purchase-ops .card-actions").forEach(holder=>{if(!holder.children.length)holder.remove()});
}

function renderCurrent(){
  const body=$("detailBody");
  const kicker=String($("detailKicker")?.textContent||"").toUpperCase();
  const cbNo=String($("detailTitle")?.textContent||"").trim();
  if(!body||!cbNo||kicker!=="CB DETAILS"||!canViewFinancials())return;
  removeDirectCbActions();
  const ledgerRows = state.ledger.filter(x=>String(x.cb_no)===String(cbNo));
  const actionRows = state.actions.filter(x=>String(x.cb_no)===String(cbNo));
  const effectRows = state.effects.filter(x=>String(x.cb_no)===String(cbNo));
  const signature = JSON.stringify({
    cbNo,role:state.role,
    ledger:ledgerRows.map(x=>[x.purchase_entry_id,x.current_quantity,x.current_value,x.total_gr_qty,x.total_damage_qty,x.total_exchange_qty]),
    actions:actionRows.map(x=>[x.id,x.status,x.effect_posted,x.qty,x.value_snapshot,(x.media||[]).length]),
    effects:effectRows.map(x=>[x.id,x.qty,x.value,x.action_status,x.vendor_message_sent_at])
  });
  const existing=body.querySelector("#rrPmCuttingLedgerV72035");
  if(existing?.dataset.signature===signature) return;
  existing?.remove();
  const section=document.createElement("section");
  section.dataset.signature=signature;
  section.id="rrPmCuttingLedgerV72035";
  section.className="form-card spaced rr-pm-ledger";
  section.innerHTML=`<div class="rr-pm-ledger-note"><strong>Final source rule:</strong> CB Damage / Partial GR / Full GR की entry Cutting Master करेगा। Owner approval के बाद यही Product Master CB card permanent purchase ledger, quantity और costing effect दिखाएगा। यहाँ duplicate GR entry नहीं होगी।</div><h3>Permanent CB Purchase Ledger</h3>${purchaseLedgerHtml(cbNo)}<h3 style="margin-top:16px">Cutting Damage / GR Reports</h3>${actionsHtml(cbNo)}<h3 style="margin-top:16px">Approved Quantity & Cost Effects</h3>${effectsHtml(cbNo)}`;
  body.appendChild(section);
  section.querySelectorAll("[data-pm-vendor]").forEach(b=>b.onclick=()=>sendVendor(b.dataset.pmVendor));
}

let timer=null;
function scheduleRender(){clearTimeout(timer);timer=setTimeout(async()=>{const kicker=String($("detailKicker")?.textContent||"").toUpperCase();const cbNo=String($("detailTitle")?.textContent||"").trim();if(kicker!=="CB DETAILS"||!cbNo)return;if(state.lastCb!==cbNo){state.lastCb=cbNo;await loadData()}renderCurrent()},80)}

async function boot(){
  injectStyles();state.client=getClient();if(!state.client){console.warn("V720.35 Product CB ledger: Supabase client unavailable");return}
  await loadRole();await loadData();
  const observer=new MutationObserver(scheduleRender);observer.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:["class","aria-hidden"]});
  $("refresh")?.addEventListener("click",()=>setTimeout(async()=>{await loadData();renderCurrent()},800));
  scheduleRender();
  window.REAL FACTORY_PRODUCT_CB_LEDGER={refresh:async()=>{await loadData();renderCurrent()},state:()=>({...state})};
}

if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",boot);else boot();
})();
