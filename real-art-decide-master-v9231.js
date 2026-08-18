(()=>{
"use strict";
if(window.__RR_ART_DECIDE_MASTER_9231__)return;
window.__RR_ART_DECIDE_MASTER_9231__=true;

const $=id=>document.getElementById(id);
const state={client:null,role:null,due:[],units:[],purchases:[],arts:[],prints:[],stickers:[],metals:[],active:null,step:"art",artId:null,printMode:"NA",printIds:[],stickerMode:"NA",stickerIds:[],metalMode:"NA",metalIds:[]};
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
const textError=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(" — ")||"Unknown error";
const kg=v=>`${Number(v||0).toFixed(3)} kg`;
function say(text="",type=""){const el=$("message");el.textContent=text;el.className=`message ${type}`.trim();}
function decisionSay(text="",type=""){const el=$("decisionMessage");el.textContent=text;el.className=`message ${type}`.trim();}
function setBusy(button,busy,label){if(!button)return;if(busy){button.dataset.old=button.textContent;button.disabled=true;button.textContent=label}else{button.disabled=false;button.textContent=button.dataset.old||button.textContent}}

function getClient(){
  try{if(window.supabaseClient?.from)return window.supabaseClient}catch(_e){}
  try{if(typeof supabaseClient!=="undefined"&&supabaseClient?.from)return supabaseClient}catch(_e){}
  return [window.supabaseDb,window.redzedSupabase,window.sb].find(x=>x?.from)||null;
}
async function waitForClient(){const started=Date.now();while(Date.now()-started<12000){const c=getClient();if(c)return c;await new Promise(r=>setTimeout(r,100))}return null}
async function loadRole(){const r=await state.client.rpc("rr_current_role");if(!r.error&&r.data){state.role=String(r.data).toLowerCase();return}if(window.RR?.requireOwner){await RR.requireOwner();state.role="owner";return}throw new Error(`User role could not be verified: ${textError(r.error)}`)}
async function currentDataMode(){try{const r=await state.client.rpc("rr_app_data_mode_state_v786");if(!r.error&&r.data?.default_mode)return String(r.data.default_mode).toUpperCase()}catch(_e){}return "TEST"}
async function rows(table){const r=await state.client.from(table).select("*");if(r.error)throw new Error(`${table}: ${textError(r.error)}`);return r.data||[]}
async function printRows(){let r=await state.client.from("rr_print_library_view").select("*");if(!r.error)return r.data||[];r=await state.client.from("rr_print_master").select("*");if(r.error)throw new Error(`Print Master: ${textError(r.error)}`);return r.data||[]}

function unitFor(id){return state.units.find(x=>String(x.id)===String(id))||null}
function purchaseFor(unit){return state.purchases.find(x=>String(x.id)===String(unit?.purchase_id))||null}
function dNo(unit){return `D${Number(unit?.division_index||1)}`}
function cbNo(unit){return purchaseFor(unit)?.cb_no||unit?.cb_base_no||String(unit?.cb_code||"CB").replace(/[-\s]S\d+.*$/i,"")||"CB"}
function dueFor(id){return state.due.find(x=>String(x.cb_unit_id)===String(id))||null}

async function loadData(){
  const refresh=$("refresh");setBusy(refresh,true,"Loading…");$("gallery").setAttribute("aria-busy","true");
  try{
    const [dueR,countR,arts,prints,stickers,metals]=await Promise.all([
      state.client.rpc("rr_pm_decision_filter_v802",{p_filter:"ART_DUE"}),
      state.client.rpc("rr_pm_decision_tab_counts_v802"),
      rows("rr_art_master"),printRows(),rows("rr_sticker_master_library_v803"),rows("rr_metal_id_master_library_v803")
    ]);
    if(dueR.error)throw new Error(`Art Due list: ${textError(dueR.error)}`);
    if(countR.error)throw new Error(`Art Due count: ${textError(countR.error)}`);
    state.due=Array.isArray(dueR.data)?dueR.data:[];
    const ids=state.due.map(x=>x.cb_unit_id).filter(Boolean);
    let units=[];if(ids.length){const u=await state.client.from("rr_cb_units").select("*").in("id",ids);if(u.error)throw new Error(`CB children: ${textError(u.error)}`);units=u.data||[]}
    const purchaseIds=[...new Set(units.map(x=>x.purchase_id).filter(Boolean))];
    let purchases=[];if(purchaseIds.length){const p=await state.client.from("rr_fabric_purchases").select("*").in("id",purchaseIds);if(p.error)throw new Error(`CB purchases: ${textError(p.error)}`);purchases=p.data||[]}
    Object.assign(state,{units,purchases,arts:arts.filter(x=>x.is_active!==false),prints:prints.filter(x=>x.is_active!==false),stickers:stickers.filter(x=>x.is_active!==false),metals:metals.filter(x=>x.is_active!==false)});
    $("dueCount").textContent=String(Number(countR.data?.art_due??state.due.length));
    renderGallery();say(state.due.length?"Art Due CB children loaded.":"No Art Due CB child right now.",state.due.length?"success":"");
  }catch(e){console.error(e);$("gallery").innerHTML=`<article class="empty"><h3>Art Decide Master could not load</h3><p>${esc(textError(e))}</p></article>`;say(textError(e),"error")}
  finally{$("gallery").setAttribute("aria-busy","false");setBusy(refresh,false)}
}

function renderGallery(){
  const q=$("search").value.trim().toLowerCase();
  const cards=state.due.map(d=>{const u=unitFor(d.cb_unit_id);if(!u)return"";const cb=cbNo(u),dn=dNo(u);const search=`${cb} ${dn} ${u.cb_code||""}`.toLowerCase();if(q&&!search.includes(q))return"";return `<article class="card" data-unit="${esc(u.id)}"><div class="card-body"><div class="card-head"><div><span class="chip">ART DUE</span><h3>${esc(cb)}</h3></div><span class="dno">${esc(dn)}</span></div><div class="metrics"><div class="metric"><small>Child</small><strong>${esc(dn)}</strong></div><div class="metric"><small>Weight</small><strong>${esc(kg(u.divided_weight??u.allocated_qty))}</strong></div><div class="metric"><small>Print</small><strong>${esc(String(d.print_status||"PENDING").replaceAll("_"," "))}</strong></div><div class="metric"><small>Sticker / Metal</small><strong>${esc(`${String(d.sticker_status||"PENDING").replaceAll("_"," ")} · ${String(d.metal_id_status||"PENDING").replaceAll("_"," ")}`)}</strong></div></div><button class="btn primary" type="button" data-decide="${esc(u.id)}" style="width:100%">Decide Art / Crafting</button></div></article>`}).join("");
  $("gallery").innerHTML=cards||`<article class="empty"><h3>${q?"No matching Art Due child":"No Art Due CB child"}</h3><p>${q?"Search badal kar dekhein.":"Jab kisi CB child ka Art Due hoga, card yahan automatically aayega."}</p></article>`;
  $("gallery").querySelectorAll("[data-decide]").forEach(b=>b.onclick=()=>openDecision(b.dataset.decide));
}

function openDecision(unitId){
  const u=unitFor(unitId);if(!u)return;
  state.active=u;state.step="art";state.artId=null;state.printMode="NA";state.printIds=[];state.stickerMode="NA";state.stickerIds=[];state.metalMode="NA";state.metalIds=[];
  $("decisionTitle").textContent=`${cbNo(u)} · ${dNo(u)}`;$("decisionContext").textContent="Cutting se pehle complete crafting decision";$("pickerSearch").value="";decisionSay("");showStep("art");
  const sheet=$("decisionSheet");sheet.classList.remove("hidden");sheet.setAttribute("aria-hidden","false");document.body.style.overflow="hidden";
}
function closeDecision(){const sheet=$("decisionSheet");sheet.classList.add("hidden");sheet.setAttribute("aria-hidden","true");document.body.style.overflow=""}

function currentMode(){return state.step==="print"?state.printMode:state.step==="sticker"?state.stickerMode:state.step==="metal"?state.metalMode:null}
function setMode(mode){if(state.step==="print"){state.printMode=mode;if(mode!=="SELECTED")state.printIds=[]}else if(state.step==="sticker"){state.stickerMode=mode;if(mode!=="SELECTED")state.stickerIds=[]}else if(state.step==="metal"){state.metalMode=mode;if(mode!=="SELECTED")state.metalIds=[]}renderPicker()}
function itemMeta(step,row){
  if(step==="art")return {id:row.id,no:row.art_no||row.art_code||"ART",name:row.product_name||row.item_name||row.description||"Art"};
  if(step==="print")return {id:row.id,no:row.print_no||row.print_code||"PRINT",name:row.print_name||row.short_note||"Print"};
  if(step==="sticker")return {id:row.id,no:row.sticker_no||"STICKER",name:[row.sticker_name,row.sticker_quality].filter(Boolean).join(" · ")||"Sticker"};
  return {id:row.id,no:row.metal_id_no||"METAL ID",name:[row.metal_id_name,row.id_size].filter(Boolean).join(" · ")||"Metal ID"};
}
function sourceForStep(){return state.step==="art"?state.arts:state.step==="print"?state.prints:state.step==="sticker"?state.stickers:state.metals}
function selectedIds(){return state.step==="print"?state.printIds:state.step==="sticker"?state.stickerIds:state.metalIds}
function renderPicker(){
  const step=state.step,q=$("pickerSearch").value.trim().toLowerCase(),mode=$("modeRow");
  if(step==="art"){mode.classList.add("hidden");mode.innerHTML=""}else{mode.classList.remove("hidden");const m=currentMode();mode.innerHTML=[["NA","N.A."],["DUE","DUE"],["SELECTED","SELECT MASTER"]].map(([v,l])=>`<button class="mode ${m===v?"selected":""}" type="button" data-mode="${v}"><strong>${l}</strong></button>`).join("");mode.querySelectorAll("[data-mode]").forEach(b=>b.onclick=()=>setMode(b.dataset.mode))}
  let list=sourceForStep();if(step!=="art"&&currentMode()!=="SELECTED")list=[];
  list=list.filter(row=>{const m=itemMeta(step,row);return !q||`${m.no} ${m.name}`.toLowerCase().includes(q)});
  const selected=selectedIds();
  $("picker").innerHTML=list.map(row=>{const m=itemMeta(step,row),on=step==="art"?String(state.artId)===String(m.id):selected.includes(String(m.id));return `<button class="pick ${on?"selected":""}" type="button" data-pick="${esc(m.id)}"><strong>${esc(m.no)}</strong><small>${esc(m.name)}</small></button>`}).join("")||`<article class="empty" style="padding:22px"><p>${step!=="art"&&currentMode()!=="SELECTED"?"N.A. / DUE selected. Continue karein.":"No matching master found."}</p></article>`;
  $("picker").querySelectorAll("[data-pick]").forEach(b=>b.onclick=()=>togglePick(b.dataset.pick));
}
function togglePick(id){id=String(id);if(state.step==="art")state.artId=id;else if(state.step==="print"){state.printMode="SELECTED";state.printIds=state.printIds.includes(id)?state.printIds.filter(x=>x!==id):[...state.printIds,id]}else if(state.step==="sticker"){state.stickerMode="SELECTED";state.stickerIds=state.stickerIds.includes(id)?state.stickerIds.filter(x=>x!==id):[...state.stickerIds,id]}else{state.metalMode="SELECTED";state.metalIds=state.metalIds.includes(id)?state.metalIds.filter(x=>x!==id):[...state.metalIds,id]}renderPicker()}

function showStep(step){state.step=step;$("decisionTabs").querySelectorAll("[data-step]").forEach(b=>b.classList.toggle("active",b.dataset.step===step));const cfg={art:["Art select kijiye. SUBMIT & CONTINUE se Print khulega.","SUBMIT & CONTINUE"],print:["Print select karein; nahi hai to N.A., baad me decide karna ho to DUE.","SUBMIT & CONTINUE"],sticker:["Sticker select karein; nahi hai to N.A., baad me decide karna ho to DUE.","SUBMIT & CONTINUE"],metal:["Metal ID select karein; phir SAVE & EXIT final crafting decision save karega.","SAVE & EXIT"]}[step];$("decisionNote").textContent=cfg[0];$("decisionNext").textContent=cfg[1];$("pickerSearch").value="";decisionSay("");renderPicker()}
function stepError(step){if(step==="art"&&!state.artId)return"Art select karna zaroori hai.";if(step==="print"&&state.printMode==="SELECTED"&&!state.printIds.length)return"Print select karein, ya N.A./DUE choose karein.";if(step==="sticker"&&state.stickerMode==="SELECTED"&&!state.stickerIds.length)return"Sticker select karein, ya N.A./DUE choose karein.";if(step==="metal"&&state.metalMode==="SELECTED"&&!state.metalIds.length)return"Metal ID select karein, ya N.A./DUE choose karein.";return""}
function allError(){return stepError("art")||stepError("print")||stepError("sticker")||stepError("metal")}
async function advance(){const err=stepError(state.step);if(err){decisionSay(err,"error");return}if(state.step==="art")return showStep("print");if(state.step==="print")return showStep("sticker");if(state.step==="sticker")return showStep("metal");return saveDecision()}
async function saveDecision(){const err=allError();if(err){decisionSay(err,"error");return}const btn=$("decisionNext");setBusy(btn,true,"Saving…");try{const mode=await currentDataMode();const r=await state.client.rpc("rr_pm_save_decision_bundle_v804",{p_cb_unit_id:state.active.id,p_art_id:state.artId,p_print_mode:state.printMode,p_print_ids:state.printIds,p_sticker_mode:state.stickerMode,p_sticker_master_ids:state.stickerIds,p_metal_id_mode:state.metalMode,p_metal_id_master_ids:state.metalIds,p_data_mode:mode});if(r.error)throw r.error;closeDecision();await loadData();say(`${cbNo(state.active)} · ${dNo(state.active)} Art / Crafting decision saved.`,"success")}catch(e){console.error(e);decisionSay(textError(e),"error")}finally{setBusy(btn,false)}}

function bind(){$("refresh").onclick=loadData;$("search").oninput=renderGallery;$("pickerSearch").oninput=renderPicker;$("decisionNext").onclick=advance;$("decisionTabs").querySelectorAll("[data-step]").forEach(b=>b.onclick=()=>showStep(b.dataset.step));document.querySelectorAll("[data-close]").forEach(b=>b.onclick=closeDecision);document.addEventListener("keydown",e=>{if(e.key==="Escape"&&!$("decisionSheet").classList.contains("hidden"))closeDecision()})}
async function boot(){try{state.client=await waitForClient();if(!state.client)throw new Error("Supabase client unavailable.");await loadRole();if(!["owner","admin"].includes(state.role))throw new Error("Art Decide Master requires Owner/Admin role.");bind();await loadData()}catch(e){console.error(e);$("gallery").innerHTML=`<article class="empty"><h3>Art Decide Master start failed</h3><p>${esc(textError(e))}</p></article>`;say(textError(e),"error")}}
boot();
})();