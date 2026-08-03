(() => {
"use strict";
window.REDZED_ROLE_PERMISSION_VERSION="777.4.2";

const state={client:null,auth:null,data:null,tab:"matrix",module:"all",search:"",departmentView:"main",editingField:null,editingDepartment:null,editingWorker:null,editingIdentityWorker:null,impactMode:"NON_IMPACT",routes:[],selectedUser:"",workerSearch:"",departmentSearch:"",busy:false};
const $=id=>document.getElementById(id);
const safe=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
const err=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(" — ")||"Unknown error";
const upper=v=>String(v||"").trim().toUpperCase();
const lower=v=>String(v||"").trim().toLowerCase();
const bool=v=>Boolean(v);
const actorRole=()=>lower(
  state.auth?.role_code
  || state.auth?.profile?.role_code
  || state.auth?.user?.role_code
  || ""
);
const isOwner=()=>actorRole()==="owner";
const isAdmin=()=>actorRole()==="admin";
const userRole=u=>lower(u?.role_code);
const isOwnerUser=u=>userRole(u)==="owner";
const isAdminUser=u=>userRole(u)==="admin";
function identityFor(workerId){
  return (state.data?.worker_identities||[])
    .find(x=>String(x.worker_id)===String(workerId))||null;
}
function testPhoneFor(workerId){
  return (state.data?.worker_test_phone_modes||[])
    .find(x=>String(x.worker_id)===String(workerId))||null;
}
function witnessPolicyForDepartment(departmentCode){
  return (state.data?.department_witness_policies||[])
    .find(x=>lower(x.department_code)===lower(departmentCode))||null;
}
function leadershipFor(workerId){
  return (state.data?.worker_leadership||[])
    .find(x=>String(x.worker_id)===String(workerId))||null;
}
function payrollFor(workerId,mode="TEST"){
  return (state.data?.worker_payroll||[])
    .find(x=>
      String(x.worker_id)===String(workerId)
      && upper(x.data_mode||"TEST")===upper(mode)
    )||null;
}
function shiftOptionsV777(selected=""){
  const rows=state.data?.payroll_shifts||[];
  return rows.map(s=>`
    <option value="${safe(s.shift_id)}"
      ${String(s.shift_id)===String(selected)?"selected":""}>
      ${safe(s.shift_name)} ·
      ${safe(String(s.duty_start||"").slice(0,5))}–${safe(String(s.duty_end||"").slice(0,5))}
      · ${safe(s.normal_payable_minutes)} min
    </option>
  `).join("");
}
function activeLoginUsers(){
  return (state.data?.users||[]).filter(u=>
    u.auth_user_id
    && u.is_active!==false
    && upper(u.access_status||"ACTIVE")==="ACTIVE"
  );
}
function witnessCandidates(physicalWorkerId){
  const activeAuthIds=new Set(
    activeLoginUsers().map(u=>String(u.auth_user_id))
  );

  return (state.data?.workers||[]).filter(w=>{
    if(String(w.worker_id)===String(physicalWorkerId))return false;

    const identity=identityFor(w.worker_id);
    const linkedAuthId=
      identity?.linked_auth_user_id
      || w.linked_auth_user_id
      || null;

    return w.is_active!==false
      && upper(w.access_status||"ACTIVE")==="ACTIVE"
      && linkedAuthId
      && activeAuthIds.has(String(linkedAuthId));
  });
}
function say(text,type="info",target="message"){const el=$(target);if(!el)return;el.textContent=text||"";el.className=`message ${type}`}
function busy(button,on,text="Working…"){if(!button)return;if(on){button.dataset.old=button.textContent;button.disabled=true;button.textContent=text}else{button.disabled=false;button.textContent=button.dataset.old||button.textContent}}
function openSheet(id){const el=$(id);el.classList.remove("hidden");el.setAttribute("aria-hidden","false");document.body.style.overflow="hidden"}
function closeSheet(id){const el=$(id);el.classList.add("hidden");el.setAttribute("aria-hidden","true");if(!document.querySelector(".sheet:not(.hidden)"))document.body.style.overflow=""}
function statusBadge(status){const s=upper(status||"ACTIVE"),cls=s==="ACTIVE"?"good":s.includes("BLOCK")||s.includes("INACTIVE")||s.includes("REVOK")||s.includes("ARCHIVE")?"bad":"warn";return `<span class="badge ${cls}">${safe(s.replaceAll("_"," "))}</span>`}
function moduleOptions(selected="",includeAll=false){const modules=[...new Set((state.data?.fields||[]).map(f=>f.module_code).concat((state.data?.departments||[]).map(d=>d.department_code)))].filter(Boolean).sort();return `${includeAll?`<option value="all">All Modules</option>`:""}${modules.map(m=>`<option value="${safe(m)}" ${m===selected?"selected":""}>${safe(m.replaceAll("_"," ").toUpperCase())}</option>`).join("")}`}
function departmentLabel(code){return state.data?.departments?.find(d=>d.department_code===code)?.department_name||code}
function topDepartments(){const rows=(state.data?.departments||[]).filter(d=>!d.parent_department_code&&d.is_active!==false);return rows.sort((a,b)=>a.display_order-b.display_order)}
function allDepartments(){return [...(state.data?.departments||[])].filter(d=>d.is_active!==false).sort((a,b)=>a.display_order-b.display_order)}
function everyDepartment(){return [...(state.data?.departments||[])].sort((a,b)=>Number(a.display_order||100)-Number(b.display_order||100)||String(a.department_name||"").localeCompare(String(b.department_name||"")))}
function workerSkills(workerId){return (state.data?.worker_skills||[]).filter(x=>String(x.worker_id)===String(workerId)&&x.is_active!==false).sort((a,b)=>Number(b.is_primary)-Number(a.is_primary)||String(a.department_name||a.department_code).localeCompare(String(b.department_name||b.department_code)))}
function roleOptions(selected=""){const roles=(state.data?.roles||[]).filter(r=>r.is_active!==false);const fallback=["admin","account","cutting_master","printing","manager","karigar","overlock","kaaj","button","folding","thread_cut","qc","press","packing","sales","sales_manager","dispatch","distributor","distributor_staff"].map(role_code=>({role_code,role_name:role_code.replaceAll("_"," ")}));const list=roles.length?roles:fallback;return list.map(r=>`<option value="${safe(r.role_code)}" ${String(r.role_code)===String(selected)?"selected":""}>${safe(r.role_name||r.role_code)} · ${safe(r.role_code)}</option>`).join("")}

function matrixDepartments(){const all=allDepartments();if(state.departmentView==="fabrication")return all.filter(d=>d.department_code==="fabrication"||d.parent_department_code==="fabrication");if(state.departmentView==="all")return all;return topDepartments()}
function departmentViewOptions(){return `<option value="main" ${state.departmentView==="main"?"selected":""}>Main Departments</option><option value="fabrication" ${state.departmentView==="fabrication"?"selected":""}>Fabrication Breakdown</option><option value="all" ${state.departmentView==="all"?"selected":""}>All Departments</option>`}
function fieldPermission(fieldId,department){return state.data?.field_permissions?.find(p=>p.field_id===fieldId&&p.department_code===department)?.access_mode||"HIDE"}
function userOverride(profileId,fieldId){return state.data?.user_field_overrides?.find(p=>p.profile_id===profileId&&p.field_id===fieldId)||null}
function actionPermission(actionKey,department){return Boolean(state.data?.action_permissions?.find(p=>p.action_key===actionKey&&p.department_code===department)?.is_allowed)}
function userActionOverride(profileId,actionKey){return state.data?.user_action_overrides?.find(p=>p.profile_id===profileId&&p.action_key===actionKey)||null}
function setAccessClass(select){select.classList.remove("access-hide","access-view","access-edit");select.classList.add(`access-${lower(select.value)}`)}

async function rpc(name,payload={}){const r=await state.client.rpc(name,payload);if(r.error)throw r.error;return r.data}
async function loadConsole({quiet=false}={}){
  if(state.busy)return;state.busy=true;
  try{
    state.data=await rpc("rr_owner_permission_console_v1",{p_module_code:null});
    try{
      const authData=await invokeUserAdmin({action:"list_users"});
      const authUsers=authData?.users||[];
      const byAuthId=new Map(authUsers.map(u=>[String(u.auth_user_id||u.id),u]));
      state.data.users=(state.data.users||[]).map(profile=>({
        ...profile,
        ...(byAuthId.get(String(profile.auth_user_id))||{})
      }));
    }catch(edgeError){
      console.warn("Auth user list unavailable; profile list shown.",edgeError);
    }
    try{
      state.data.workers=await rpc("rr_owner_worker_directory_v8_4",{p_department_code:null,p_include_inactive:true});
    }catch(workerError){
      console.warn("Unified worker directory unavailable.",workerError);
      state.data.workers=[];
    }
    try{
      const departmentData=await rpc("rr_owner_department_console_v2",{});
      state.data.departments=departmentData.departments||state.data.departments||[];
      state.data.roles=departmentData.roles||[];
      state.data.worker_skills=departmentData.worker_skills||[];
    }catch(departmentError){
      console.warn("Dynamic Department Master unavailable.",departmentError);
      state.data.roles=state.data.roles||[];
      state.data.worker_skills=state.data.worker_skills||[];
    }
    try{
      const identityResult=await state.client
        .from("rr_worker_identity_board_v770")
        .select("*")
        .order("worker_name",{ascending:true});
      if(identityResult.error)throw identityResult.error;
      state.data.worker_identities=identityResult.data||[];
    }catch(identityError){
      console.warn("Worker Identity Board unavailable.",identityError);
      state.data.worker_identities=[];
    }
    try{
      const testPhoneResult=await state.client
        .from("rr_worker_test_phone_board_v773_2")
        .select("*")
        .order("worker_name",{ascending:true});
      if(testPhoneResult.error)throw testPhoneResult.error;
      state.data.worker_test_phone_modes=testPhoneResult.data||[];
    }catch(testPhoneError){
      console.warn("Worker Test Phone Board unavailable.",testPhoneError);
      state.data.worker_test_phone_modes=[];
    }
    try{
      const witnessPolicyResult=await state.client
        .from("rr_department_witness_policy_board_v774")
        .select("*")
        .order("department_name",{ascending:true});
      if(witnessPolicyResult.error)throw witnessPolicyResult.error;
      state.data.department_witness_policies=witnessPolicyResult.data||[];
    }catch(witnessPolicyError){
      console.warn("Department Witness Policy unavailable.",witnessPolicyError);
      state.data.department_witness_policies=[];
    }
    try{
      const leadershipResult=await state.client
        .from("rr_worker_leadership_board_v777_4")
        .select("*")
        .order("worker_name",{ascending:true});
      if(leadershipResult.error)throw leadershipResult.error;
      state.data.worker_leadership=leadershipResult.data||[];
    }catch(leadershipError){
      console.warn("Worker Leadership Master unavailable.",leadershipError);
      state.data.worker_leadership=[];
    }
    try{
      const payrollResult=await state.client
        .from("rr_worker_payroll_board_v777_3")
        .select("*")
        .order("worker_name",{ascending:true});
      if(payrollResult.error)throw payrollResult.error;
      state.data.worker_payroll=payrollResult.data||[];
    }catch(payrollError){
      console.warn("Worker Payroll Board unavailable.",payrollError);
      state.data.worker_payroll=[];
    }
    try{
      const shiftResult=await state.client
        .from("rr_shift_options_v777_3")
        .select("*")
        .order("shift_name",{ascending:true});
      if(shiftResult.error)throw shiftResult.error;
      state.data.payroll_shifts=shiftResult.data||[];
    }catch(shiftError){
      console.warn("Payroll Shift options unavailable.",shiftError);
      state.data.payroll_shifts=[];
    }
    renderAll();
    if(!quiet)say("Permission console loaded.","success");
  }catch(e){console.error(e);say(err(e),"error")}
  finally{state.busy=false}
}
function renderStats(){const d=state.data||{};const active=(d.users||[]).filter(u=>u.is_active).length;$("stats").innerHTML=[["Fields",(d.fields||[]).length],["Departments",(d.departments||[]).length],["Login Users",(d.users||[]).length],["Unified Workers",(d.workers||[]).length],["Active Users",active],["Impact Fields",(d.fields||[]).filter(f=>f.impact_mode==="IMPACT").length]].map(([a,b])=>`<div class="stat"><small>${a}</small><strong>${b}</strong></div>`).join("")}
function filteredFields(){let rows=[...(state.data?.fields||[])];if(state.module!=="all")rows=rows.filter(f=>f.module_code===state.module);const q=lower(state.search);if(q)rows=rows.filter(f=>JSON.stringify([f.field_key,f.display_name,f.module_code,f.section_code]).toLowerCase().includes(q));return rows}
function groupRows(fields,departments,cellMaker){let html="",last="";for(const f of fields){const group=`${f.module_code} · ${f.section_code}`;if(group!==last){html+=`<tr class="group"><td colspan="${departments.length+1}">${safe(group.toUpperCase())}</td></tr>`;last=group}html+=`<tr><td class="field-cell"><strong>${safe(f.display_name)}</strong><small>${safe(f.field_key)} · ${safe(f.data_type)}${f.unit_code?` · ${safe(f.unit_code)}`:""} · ${safe(f.status)}</small></td>${departments.map(d=>cellMaker(f,d)).join("")}</tr>`}return html||`<tr><td colspan="${departments.length+1}">No fields.</td></tr>`}

function renderMatrix(){const deps=matrixDepartments(),fields=filteredFields();$("tab-matrix").innerHTML=`<div class="toolbar"><label class="grow"><span>Search field</span><input id="matrixSearch" value="${safe(state.search)}" placeholder="Lot No, Actual Rate, Packing..."></label><label><span>Module</span><select id="matrixModule">${moduleOptions(state.module,true)}</select></label><label><span>Department Columns</span><select id="matrixDepartmentView">${departmentViewOptions()}</select></label><button id="matrixRefresh" class="secondary">Refresh</button></div><div class="panel"><p class="note">First horizontal row departments की है और first vertical column fields की—दोनों permanently sticky हैं। हर cell में HIDE / VIEW / EDIT चुनें।</p><div class="matrix-wrap"><table class="matrix"><thead><tr><th class="field-head">Field / Entry</th>${deps.map(d=>`<th>${safe(d.department_name)}</th>`).join("")}</tr></thead><tbody>${groupRows(fields,deps,(f,d)=>{const mode=fieldPermission(f.id,d.department_code);return `<td><select class="matrix-access access-${lower(mode)}" data-field="${f.id}" data-dept="${d.department_code}"><option ${mode==="HIDE"?"selected":""}>HIDE</option><option ${mode==="VIEW"?"selected":""}>VIEW</option><option ${mode==="EDIT"?"selected":""}>EDIT</option></select></td>`})}</tbody></table></div></div>`;
  $("matrixSearch").oninput=e=>{state.search=e.target.value;clearTimeout(renderMatrix.t);renderMatrix.t=setTimeout(renderMatrix,180)};$("matrixModule").onchange=e=>{state.module=e.target.value;renderMatrix()};$("matrixDepartmentView").onchange=e=>{state.departmentView=e.target.value;renderMatrix()};$("matrixRefresh").onclick=()=>loadConsole();document.querySelectorAll(".matrix-access").forEach(select=>select.onchange=async()=>{setAccessClass(select);select.disabled=true;try{const row=await rpc("rr_owner_set_field_permission_v1",{p_field_id:select.dataset.field,p_department_code:select.dataset.dept,p_access_mode:select.value});const old=state.data.field_permissions.find(p=>p.field_id===row.field_id&&p.department_code===row.department_code);if(old)Object.assign(old,row);else state.data.field_permissions.push(row);say(`${departmentLabel(select.dataset.dept)} · permission saved.`,"success")}catch(e){say(err(e),"error");await loadConsole({quiet:true})}finally{select.disabled=false}})}

function renderActions(){const deps=matrixDepartments(),actions=state.data?.actions||[];$("tab-actions").innerHTML=`<div class="toolbar"><label><span>Department Columns</span><select id="actionDepartmentView">${departmentViewOptions()}</select></label></div><div class="panel"><p class="note">WhatsApp, Verify, Approve, Export, Print, Field Create और User Block जैसी actions यहाँ department-wise Allow/Deny होंगी। Owner master override हमेशा रहेगा।</p><div class="matrix-wrap"><table class="matrix"><thead><tr><th class="field-head">Action</th>${deps.map(d=>`<th>${safe(d.department_name)}</th>`).join("")}</tr></thead><tbody>${actions.map(a=>`<tr><td class="field-cell"><strong>${safe(a.display_name)}</strong><small>${safe(a.action_key)} · ${safe(a.module_code)}${a.is_sensitive?" · Sensitive":""}</small></td>${deps.map(d=>{const allow=actionPermission(a.action_key,d.department_code);return `<td><select class="action-access ${allow?"access-edit":"access-hide"}" data-action="${safe(a.action_key)}" data-dept="${safe(d.department_code)}"><option value="false" ${!allow?"selected":""}>DENY</option><option value="true" ${allow?"selected":""}>ALLOW</option></select></td>`}).join("")}</tr>`).join("")}</tbody></table></div></div>`;$("actionDepartmentView")?.addEventListener("change",e=>{state.departmentView=e.target.value;renderActions()});document.querySelectorAll(".action-access").forEach(select=>select.onchange=async()=>{select.className=`action-access ${select.value==="true"?"access-edit":"access-hide"}`;select.disabled=true;try{const row=await rpc("rr_owner_set_action_permission_v1",{p_action_key:select.dataset.action,p_department_code:select.dataset.dept,p_is_allowed:select.value==="true"});const old=state.data.action_permissions.find(p=>p.action_key===row.action_key&&p.department_code===row.department_code);if(old)Object.assign(old,row);else state.data.action_permissions.push(row);say("Action permission saved.","success")}catch(e){say(err(e),"error");await loadConsole({quiet:true})}finally{select.disabled=false}})}

function renderOverrides(){const users=state.data?.users||[],selected=state.selectedUser||users[0]?.id||"";state.selectedUser=selected;const user=users.find(u=>u.id===selected),deps=user?.department_code||"";const fields=filteredFields();const actions=state.data?.actions||[];$("tab-overrides").innerHTML=`<div class="toolbar"><label class="grow"><span>Particular User</span><select id="overrideUser">${users.map(u=>`<option value="${u.id}" ${u.id===selected?"selected":""}>${safe(u.full_name||u.role_code||u.id)} · ${safe(u.role_code)} · ${safe(u.access_status)}</option>`).join("")}</select></label><label><span>Module</span><select id="overrideModule">${moduleOptions(state.module,true)}</select></label><label class="grow"><span>Search</span><input id="overrideSearch" value="${safe(state.search)}"></label></div>${user?`<div class="panel"><div class="row between"><div><h3>${safe(user.full_name||"User")}</h3><p class="muted">Role ${safe(user.role_code)} · Department ${safe(departmentLabel(deps))} · blank/Inherit = department default</p></div>${statusBadge(user.access_status)}</div><div class="matrix-wrap"><table class="matrix"><thead><tr><th class="field-head">Field / Entry</th><th>Department Default</th><th>User Override</th></tr></thead><tbody>${fields.map(f=>{const def=fieldPermission(f.id,deps),ov=userOverride(user.id,f.id);return `<tr><td class="field-cell"><strong>${safe(f.display_name)}</strong><small>${safe(f.field_key)} · ${safe(f.module_code)}</small></td><td><span class="badge">${safe(def)}</span></td><td><select class="user-field-override" data-field="${f.id}"><option value="" ${!ov?"selected":""}>INHERIT</option><option value="HIDE" ${ov?.access_mode==="HIDE"?"selected":""}>HIDE</option><option value="VIEW" ${ov?.access_mode==="VIEW"?"selected":""}>VIEW</option><option value="EDIT" ${ov?.access_mode==="EDIT"?"selected":""}>EDIT</option></select></td></tr>`}).join("")}</tbody></table></div></div><div class="panel" style="margin-top:10px"><h3>User Action Overrides</h3><div class="matrix-wrap"><table class="matrix"><thead><tr><th class="field-head">Action</th><th>Department Default</th><th>User Override</th></tr></thead><tbody>${actions.map(a=>{const def=actionPermission(a.action_key,deps),ov=userActionOverride(user.id,a.action_key);return `<tr><td class="field-cell"><strong>${safe(a.display_name)}</strong><small>${safe(a.action_key)}</small></td><td>${def?"ALLOW":"DENY"}</td><td><select class="user-action-override" data-action="${safe(a.action_key)}"><option value="" ${!ov?"selected":""}>INHERIT</option><option value="false" ${ov&&ov.is_allowed===false?"selected":""}>DENY</option><option value="true" ${ov?.is_allowed===true?"selected":""}>ALLOW</option></select></td></tr>`}).join("")}</tbody></table></div><div class="toolbar"><label><span>Record Scope Module</span><select id="scopeModule">${moduleOptions("cutting")}</select></label><label><span>Row Scope</span><select id="scopeType"><option>OWN_ENTRIES</option><option>ASSIGNED</option><option>OWN_DEPARTMENT</option><option>ASSIGNED_BUILDING</option><option>ALL_FABRICATION</option><option>ALL_PRODUCTION</option><option>ALL_RECORDS</option><option>TERRITORY</option><option>DISTRIBUTOR_SELF</option></select></label><button id="saveScope" class="primary">Save Scope</button></div></div>`:`<div class="panel">No users.</div>`}`;
  $("overrideUser")?.addEventListener("change",e=>{state.selectedUser=e.target.value;renderOverrides()});$("overrideModule")?.addEventListener("change",e=>{state.module=e.target.value;renderOverrides()});$("overrideSearch")?.addEventListener("input",e=>{state.search=e.target.value;clearTimeout(renderOverrides.t);renderOverrides.t=setTimeout(renderOverrides,180)});
  document.querySelectorAll(".user-field-override").forEach(sel=>sel.onchange=async()=>{sel.disabled=true;try{await rpc("rr_owner_set_user_field_override_v1",{p_profile_id:selected,p_field_id:sel.dataset.field,p_access_mode:sel.value||null,p_valid_until:null,p_reason:"Owner permission matrix"});await loadConsole({quiet:true});state.selectedUser=selected;renderOverrides();say("User field override saved.","success")}catch(e){say(err(e),"error")}finally{sel.disabled=false}});
  document.querySelectorAll(".user-action-override").forEach(sel=>sel.onchange=async()=>{sel.disabled=true;try{await rpc("rr_owner_set_user_action_override_v1",{p_profile_id:selected,p_action_key:sel.dataset.action,p_is_allowed:sel.value===""?null:sel.value==="true",p_valid_until:null,p_reason:"Owner action override"});await loadConsole({quiet:true});state.selectedUser=selected;renderOverrides();say("User action override saved.","success")}catch(e){say(err(e),"error")}finally{sel.disabled=false}});
  $("saveScope")?.addEventListener("click",async()=>{try{await rpc("rr_owner_set_user_record_scope_v1",{p_profile_id:selected,p_module_code:$("scopeModule").value,p_scope_type:$("scopeType").value,p_scope_values:{}});say("Record scope saved.","success")}catch(e){say(err(e),"error")}})
}

function fieldCard(f){const rule=state.data?.impact_rules?.find(r=>r.field_id===f.id&&r.version_no===f.latest_version),life=f.draft_status&&f.draft_status!=="NONE"?`${f.status} · ${f.draft_status}`:f.status;return `<article class="card"><div class="row between"><div><h4>${safe(f.display_name)}</h4><p class="muted">${safe(f.field_key)}</p></div>${statusBadge(life)}</div><p><span class="badge ${f.impact_mode==="IMPACT"?"warn":""}">${f.impact_mode==="IMPACT"?"✓ IMPACT":"✕ NON-IMPACT"}</span> <span class="badge">${safe(f.module_code)}</span></p><small class="muted">${safe(f.data_type)} · ${safe(f.input_type)}${f.unit_code?` · ${safe(f.unit_code)}`:""}${rule?` · ${safe(rule.adapter_code)}`:""}</small><div class="button-row"><button class="secondary tiny" data-edit-field="${f.id}">Open / Edit / Demo</button></div></article>`}
function renderFields(){const fields=filteredFields();$("tab-fields").innerHTML=`<div class="toolbar"><label class="grow"><span>Search Field Master</span><input id="fieldSearch" value="${safe(state.search)}"></label><label><span>Module</span><select id="fieldModule">${moduleOptions(state.module,true)}</select></label><button id="newField" class="primary">+ Owner Create Field</button></div><div class="card-list">${fields.map(fieldCard).join("")||`<div class="panel">No fields.</div>`}</div>`;$("fieldSearch").oninput=e=>{state.search=e.target.value;clearTimeout(renderFields.t);renderFields.t=setTimeout(renderFields,180)};$("fieldModule").onchange=e=>{state.module=e.target.value;renderFields()};$("newField").onclick=()=>openFieldEditor();document.querySelectorAll("[data-edit-field]").forEach(b=>b.onclick=()=>openFieldEditor(b.dataset.editField))}

function formatDate(value){if(!value)return "—";const d=new Date(value);return Number.isNaN(d.getTime())?"—":d.toLocaleString("en-IN",{dateStyle:"medium",timeStyle:"short"})}
function renderUsers(){
  const users=state.data?.users||[];
  $("tab-users").innerHTML=`
    <div class="toolbar">
      <label class="grow"><span>Search users</span><input id="userSearch" placeholder="Name, email, role, user ID"></label>
      <button id="refreshUsers" class="secondary">Refresh</button>
      ${isOwner()?`<button id="createUser" class="primary">+ Create User Login</button>`:""}
    </div>
    <div class="panel">
      <p class="note">
        OWNER सबसे ऊपर और database-protected है. ADMIN Owner को block, deactivate,
        archive, reset या override नहीं कर सकता. Sirf OWNER Admin security control करेगा.
      </p>
    </div>
    <div id="userCards" class="card-list">${userCards(users)}</div>`;

  if($("createUser"))$("createUser").onclick=()=>openUserCreate();
  $("refreshUsers").onclick=()=>loadConsole();
  $("userSearch").oninput=e=>{
    const q=lower(e.target.value);
    const rows=!q?users:users.filter(u=>
      JSON.stringify([
        u.full_name,u.email,u.role_code,u.department_code,
        u.auth_user_id,u.id,u.access_status
      ]).toLowerCase().includes(q)
    );
    $("userCards").innerHTML=userCards(rows);
    bindUserButtons();
  };
  bindUserButtons();
}

function userActionButtonsV773(u){
  if(isOwnerUser(u)){
    return `
      <span class="owner-lock-note">
        OWNER PROTECTED · Delete / Block / Deactivate / Downgrade / Password Override बंद
      </span>
    `;
  }

  if(isAdminUser(u)){
    if(!isOwner()){
      return `
        <span class="owner-lock-note">
          ADMIN security control सिर्फ OWNER के पास है
        </span>
      `;
    }

    return `
      <button class="warning tiny"
        data-owner-admin-action="BLOCKED"
        data-user="${safe(u.id)}">Block Admin</button>
      <button class="primary tiny"
        data-owner-admin-action="ACTIVE"
        data-user="${safe(u.id)}">Activate Admin</button>
      <button class="danger tiny"
        data-owner-admin-action="INACTIVE"
        data-user="${safe(u.id)}">Deactivate Admin</button>
      <button class="secondary tiny"
        data-reset-user="${safe(u.id)}">Reset Admin Password</button>
    `;
  }

  return `
    <button class="warning tiny" data-user-action="TEMP_BLOCK" data-user="${safe(u.id)}">Block Access Now</button>
    <button class="secondary tiny" data-reset-user="${safe(u.id)}">Reset Password</button>
    <button class="primary tiny" data-user-action="ACTIVATE" data-user="${safe(u.id)}">Activate</button>
    <button class="danger tiny" data-user-action="DEACTIVATE" data-user="${safe(u.id)}">Deactivate</button>
    <button class="danger tiny" data-user-action="ARCHIVE" data-user="${safe(u.id)}">Archive</button>
  `;
}

function userCards(users){
  return users.map(u=>`
    <article class="card ${isOwnerUser(u)?"owner-card":""}">
      <div class="row between">
        <div>
          <h4>${safe(u.full_name||"Unnamed User")}</h4>
          <p class="muted">
            ${safe(u.email||"Email unavailable")} ·
            ${safe(upper(u.role_code))} ·
            ${safe(departmentLabel(u.department_code))}
          </p>
        </div>
        ${isOwnerUser(u)
          ?'<span class="badge owner-badge">OWNER · HIGHEST</span>'
          :statusBadge(u.access_status)}
      </div>
      <small class="muted">Auth User ID: ${safe(u.auth_user_id||"not linked")}</small><br>
      <small class="muted">Profile ID: ${safe(u.id||"—")}</small>
      <p class="note">
        Last login: ${safe(formatDate(u.last_sign_in_at))}<br>
        Created: ${safe(formatDate(u.auth_created_at||u.created_at))}
      </p>
      ${u.access_reason?`<p class="note">${safe(u.access_reason)}</p>`:""}
      <div class="button-row">${userActionButtonsV773(u)}</div>
    </article>
  `).join("")||`<div class="panel">No users found.</div>`;
}

function bindUserButtons(){
  document.querySelectorAll("[data-user-action]")
    .forEach(b=>b.onclick=()=>changeUserAccess(
      b.dataset.user,b.dataset.userAction,b
    ));

  document.querySelectorAll("[data-owner-admin-action]")
    .forEach(b=>b.onclick=()=>ownerSetAdminStatusV773(
      b.dataset.user,b.dataset.ownerAdminAction,b
    ));

  document.querySelectorAll("[data-reset-user]")
    .forEach(b=>b.onclick=()=>resetUserPassword(
      b.dataset.resetUser,b
    ));
}


function workerIdentityBadgesV773(w){
  const i=identityFor(w.worker_id);

  if(!i){
    return `<span class="badge warn">IDENTITY NOT LOADED</span>`;
  }

  const status=i.identity_status||"DEVICE_NOT_SET";
  const ready=i.receive_identity_ready===true;

  const testPhone=testPhoneFor(w.worker_id);
  return `
    <span class="badge ${ready?"good":status.includes("REQUIRED")||status.includes("PENDING")?"warn":"bad"}">
      ${safe(i.identity_status_hinglish||status.replaceAll("_"," "))}
    </span>
    ${i.device_mode?`<span class="badge">${safe(i.device_mode.replaceAll("_"," "))}</span>`:""}
    ${i.receive_auth_mode?`<span class="badge">${safe(i.receive_auth_mode.replaceAll("_"," "))}</span>`:""}
    ${testPhone?.test_mode_enabled?`
      <span class="badge warn">
        ${safe((testPhone.test_device_mode||"TEST PHONE").replaceAll("_"," "))}
        · ${safe(testPhone.test_mobile||"8368849128")}
      </span>
    `:""}
  `;
}

function workerCards(rows){
  return rows.map(w=>{
    const skills=workerSkills(w.worker_id);
    const identity=identityFor(w.worker_id);

    return `
      <article class="card">
        <div class="row between">
          <div>
            <h4>${safe(w.worker_name||"Unnamed Worker")}</h4>
            <p class="muted">
              ${safe(w.worker_code||"—")} ·
              ${safe(w.role_code||"worker")} ·
              Primary ${safe(departmentLabel(w.department_code))}
            </p>
          </div>
          ${statusBadge(w.access_status)}
        </div>

        <p>
          <span class="badge ${w.worker_source==="ROLE_DIRECTORY"?"good":"warn"}">
            ${safe((w.worker_source||"MANUAL").replaceAll("_"," "))}
          </span>
          ${w.linked_auth_user_id
            ?` <span class="badge good">LOGIN LINKED</span>`
            :` <span class="badge">NO LOGIN</span>`}
        </p>

        <div class="identity-badges">
          ${workerIdentityBadgesV773(w)}
          ${(()=>{
            const l=leadershipFor(w.worker_id);
            if(!l||l.leadership_role==="NONE")return "";
            return `
              <span class="badge good">
                ${safe(l.leadership_role.replaceAll("_"," "))}
              </span>
              <span class="badge">
                ${safe(l.compensation_mode.replaceAll("_"," "))}
              </span>
            `;
          })()}
        </div>

        ${identity?.witness_worker_name?`
          <p class="witness-line">
            Witness: <b>${safe(identity.witness_worker_name)}</b> ·
            ${safe(identity.witness_mapping_status||"ACTIVE")}
          </p>
        `:""}

        <div class="skill-list">
          ${skills.length
            ?skills.map(x=>`
              <span class="skill-chip ${x.is_primary?"primary":""}">
                ${x.is_primary?"PRIMARY · ":""}
                ${safe(x.department_name||departmentLabel(x.department_code))}
              </span>
            `).join("")
            :`<span class="muted">
              No skill map yet; primary department fallback is active.
            </span>`}
        </div>

        <small class="muted">Worker ID: ${safe(w.worker_id||"—")}</small>
        ${w.mobile?`<br><small class="muted">Mobile: ${safe(w.mobile)}</small>`:""}

        <div class="button-row">
          ${w.worker_source!=="ROLE_DIRECTORY"
            ?`<button class="secondary tiny" data-edit-worker="${w.worker_id}">Edit Worker</button>`
            :""}
          <button class="secondary tiny" data-worker-skills="${w.worker_id}">
            Departments / Skills
          </button>
          <button class="primary tiny" data-worker-identity="${w.worker_id}">
            Device / Login / Witness
          </button>

          ${w.worker_source!=="ROLE_DIRECTORY"?`
            <button class="primary tiny" data-worker-action="ACTIVATE" data-worker="${w.worker_id}">Activate</button>
            <button class="warning tiny" data-worker-action="BLOCK" data-worker="${w.worker_id}">Block</button>
            <button class="danger tiny" data-worker-action="DEACTIVATE" data-worker="${w.worker_id}">Deactivate</button>
          `:`<span class="muted">Login-user access Users & Access se control hoga.</span>`}
        </div>
      </article>
    `;
  }).join("")||`<div class="panel">No workers found.</div>`;
}

function renderWorkers(){
  const rows=state.data?.workers||[];

  $("tab-workers").innerHTML=`
    <div class="toolbar">
      <label class="grow">
        <span>Search unified workers</span>
        <input id="workerSearch" value="${safe(state.workerSearch)}"
          placeholder="Worker name, code, department, device, identity">
      </label>
      <button id="refreshWorkers" class="secondary">Refresh</button>
      <button id="addManualWorker" class="primary">+ Add Worker</button>
      ${isOwner()?`
        <select id="bulkTestPhoneMode" style="max-width:220px">
          <option value="TEST_KEYPAD_PHONE">TEST KEYPAD PHONE</option>
          <option value="TEST_SMARTPHONE">TEST SMARTPHONE</option>
        </select>
        <button id="applyAllTestPhone" class="warning">
          Apply Test Phone to All Workers
        </button>
      `:""}
    </div>

    <div class="panel">
      <p class="note">
        Primary और additional skills के साथ Device Mode, Self Login और Witness
        mapping यहीं control होगी. Mobile से login auto-link नहीं होगा.
      </p>
    </div>

    <div id="workerCards" class="card-list">${workerCards(rows)}</div>
  `;

  $("refreshWorkers").onclick=()=>loadConsole();
  $("addManualWorker").onclick=openWorkerCreate;
  if($("applyAllTestPhone"))$("applyAllTestPhone").onclick=applyAllTestPhoneV7732;

  $("workerSearch").oninput=e=>{
    state.workerSearch=e.target.value;
    const q=lower(e.target.value);

    const filtered=!q?rows:rows.filter(w=>
      JSON.stringify([
        w.worker_name,w.worker_code,w.department_code,w.role_code,
        w.worker_source,w.access_status,workerSkills(w.worker_id),
        identityFor(w.worker_id)
      ]).toLowerCase().includes(q)
    );

    $("workerCards").innerHTML=workerCards(filtered);
    bindWorkerButtons();
  };

  bindWorkerButtons();
}

function bindWorkerButtons(){
  document.querySelectorAll("[data-edit-worker]")
    .forEach(b=>b.onclick=()=>openWorkerEditor(b.dataset.editWorker));

  document.querySelectorAll("[data-worker-action]")
    .forEach(b=>b.onclick=()=>changeWorkerAccess(
      b.dataset.worker,b.dataset.workerAction,b
    ));

  document.querySelectorAll("[data-worker-skills]")
    .forEach(b=>b.onclick=()=>openWorkerSkills(b.dataset.workerSkills));

  document.querySelectorAll("[data-worker-identity]")
    .forEach(b=>b.onclick=()=>openWorkerIdentityV773(
      b.dataset.workerIdentity
    ));
}

function workerDepartmentOptions(selected=""){return allDepartments().filter(d=>d.worker_assignment_enabled!==false||d.department_code===selected).map(d=>`<option value="${safe(d.department_code)}" ${d.department_code===selected?"selected":""}>${safe(d.department_name)}</option>`).join("")}
function openWorkerCreate(){state.editingWorker=null;$("workerForm").reset();$("workerSheetTitle").textContent="Add Shop-Floor Worker";$("saveWorker").textContent="Add Worker";$("wDepartment").innerHTML=workerDepartmentOptions();$("wRole").value="worker";$("workerModeNote").textContent="यह manual worker है; login access automatically create नहीं होगा. Worker का नाम, primary department, role और mobile बाद में modify किए जा सकते हैं.";say("","info","workerMessage");openSheet("workerSheet")}
function openWorkerEditor(workerId){const worker=(state.data?.workers||[]).find(x=>String(x.worker_id)===String(workerId));if(!worker)return;state.editingWorker=worker;$("workerSheetTitle").textContent=`Edit ${worker.worker_name||"Worker"}`;$("saveWorker").textContent="Save Worker Changes";$("wName").value=worker.worker_name||"";$("wDepartment").innerHTML=workerDepartmentOptions(worker.department_code);$("wDepartment").value=worker.department_code||"";$("wRole").value=worker.role_code||"worker";$("wMobile").value=worker.mobile||"";$("workerModeNote").textContent=`Worker ID ${worker.worker_id} permanent रहेगा. Details बदलने पर UPM और Worker Directory refresh होंगी; additional skills अलग Departments / Skills screen से बदलें.`;say("","info","workerMessage");openSheet("workerSheet")}
async function createManualWorker(event){event.preventDefault();const btn=event.submitter;const editing=state.editingWorker;busy(btn,true,editing?"Saving…":"Adding…");try{let saved;if(editing){saved=await rpc("rr_owner_update_worker_v8_4",{p_worker_id:editing.worker_id,p_worker_name:$("wName").value.trim(),p_department_code:$("wDepartment").value,p_role_code:$("wRole").value.trim()||"worker",p_mobile:$("wMobile").value.trim()||null});}else{saved=await rpc("rr_owner_add_worker_v8_4",{p_worker_name:$("wName").value.trim(),p_department_code:$("wDepartment").value,p_role_code:$("wRole").value.trim()||"worker",p_mobile:$("wMobile").value.trim()||null});}closeSheet("workerSheet");state.editingWorker=null;await loadConsole({quiet:true});showTab("workers");const worker=Array.isArray(saved)?saved[0]:saved;if(!editing&&worker?.worker_id)openWorkerSkills(worker.worker_id);say(editing?"Worker details modified. UPM mapping refresh हो गई.":"Worker added. Primary department save हुआ; additional skills चुन सकते हैं.","success")}catch(e){const extra=editing&&String(e?.message||"").includes("rr_owner_update_worker_v8_4")?" · Worker edit के लिए backend RPC rr_owner_update_worker_v8_4 deploy करें।":"";say(err(e)+extra,"error","workerMessage")}finally{busy(btn,false)}}
async function changeWorkerAccess(workerId,action,button){const w=(state.data?.workers||[]).find(x=>String(x.worker_id)===String(workerId));if(!w)return;const reason=prompt(`${action} reason`,"Owner worker directory update")||"";if(!reason)return;busy(button,true,"Applying…");try{await rpc("rr_owner_set_worker_access_v8_4",{p_worker_id:workerId,p_action:action,p_reason:reason});await loadConsole({quiet:true});showTab("workers");say(`${w.worker_name}: ${action} applied.`,"success")}catch(e){say(err(e),"error")}finally{busy(button,false)}}

function renderLeadershipDepartmentRowsV776(selectedDepartments=[]){
  const selected=new Set((selectedDepartments||[]).map(lower));

  return allDepartments()
    .filter(d=>d.worker_assignment_enabled!==false)
    .map(d=>`
      <label class="leadership-dept-option">
        <input
          class="leadership-managed-dept"
          type="checkbox"
          value="${safe(d.department_code)}"
          ${selected.has(lower(d.department_code))?"checked":""}>
        <span>
          <b>${safe(d.department_name)}</b><br>
          <small>${safe(d.department_code)}</small>
        </span>
      </label>
    `).join("");
}

function updatePayrollFieldsV777(){
  const category=$("payrollWorkerCategory").value;
  const salaried=category==="SALARIED";
  updateLeadershipCompensationFieldsV776();

  $("payrollSalariedFields").classList.toggle("hidden",!salaried);
  $("payrollMonthlySalary").required=salaried;
  $("payrollShiftId").required=salaried;
  $("payrollAdvanceLimitType").required=salaried;
  $("payrollAdvanceLimitValue").required=salaried;

  if(!salaried){
    $("payrollMonthlySalary").value="0";
    $("payrollShiftId").value="";
    $("payrollAdvanceLimitType").value="";
    $("payrollAdvanceLimitValue").value="";
  }

  $("payrollPolicySummary").textContent=salaried
    ?"Attendance required · Day 20 advance · salary due by next month day 7."
    :"Attendance excluded · presence UPM Job Activity se · weekly advance · 15-day settlement.";
}

function updateLeadershipCompensationFieldsV776(){
  const role=$("leadershipRole").value;
  const payroll=$("payrollWorkerCategory").value||"PIECE_RATE";
  const select=$("leadershipCompensationMode");
  const previous=select.value;

  $("leadershipPayrollCategory").value=payroll;
  $("leadershipPayrollCategoryLabel").textContent=
    payroll==="SALARIED"?"SALARIED":"PIECE RATE";

  $("leadershipManagedBlock").classList.toggle("hidden",role==="NONE");

  const salariedOptions=[
    ["SALARY_ONLY","SALARY ONLY"],
    ["SALARY_PLUS_FLAT","SALARY + MONTHLY INCENTIVE"],
    ["SALARY_PLUS_SALE_PCS","SALARY + PER-PCS SALE INCENTIVE"],
    ["SALARY_PLUS_FLAT_SALE_PCS","SALARY + MONTHLY + PER-PCS SALE INCENTIVE"]
  ];

  const pieceOptions=[
    ["PCS_ONLY","PCS ONLY"],
    ["PCS_PLUS_FLAT","PCS + MONTHLY INCENTIVE"],
    ["PCS_PLUS_RATE","PCS + RATE ENHANCEMENT"],
    ["PCS_PLUS_FLAT_RATE","PCS + MONTHLY INCENTIVE + RATE ENHANCEMENT"]
  ];

  const options=payroll==="SALARIED"?salariedOptions:pieceOptions;
  select.innerHTML=options.map(([value,label])=>
    `<option value="${value}">${label}</option>`
  ).join("");

  const valid=new Set(options.map(([value])=>value));
  select.value=valid.has(previous)
    ?previous
    :(payroll==="SALARIED"?"SALARY_ONLY":"PCS_ONLY");

  const mode=select.value;
  const needsFlat=[
    "SALARY_PLUS_FLAT","SALARY_PLUS_FLAT_SALE_PCS",
    "PCS_PLUS_FLAT","PCS_PLUS_FLAT_RATE"
  ].includes(mode);
  const needsRate=["PCS_PLUS_RATE","PCS_PLUS_FLAT_RATE"].includes(mode);
  const needsSale=[
    "SALARY_PLUS_SALE_PCS","SALARY_PLUS_FLAT_SALE_PCS"
  ].includes(mode);

  $("leadershipFlatBlock").classList.toggle("hidden",!needsFlat);
  $("leadershipRateBlock").classList.toggle("hidden",!needsRate);
  $("leadershipSaleBlock").classList.toggle("hidden",!needsSale);

  $("leadershipMonthlyFlat").disabled=!needsFlat;
  $("leadershipRateType").disabled=!needsRate;
  $("leadershipRateValue").disabled=!needsRate;
  $("leadershipSaleBasis").disabled=!needsSale;
  $("leadershipSaleRate").disabled=!needsSale;

  if(!needsFlat)$("leadershipMonthlyFlat").value="0";
  if(!needsRate){
    $("leadershipRateType").value="NONE";
    $("leadershipRateValue").value="0";
  }
  if(!needsSale){
    $("leadershipSaleBasis").value="NONE";
    $("leadershipSaleRate").value="0";
  }
}

function openWorkerSkills(workerId){
  const worker=(state.data?.workers||[])
    .find(x=>String(x.worker_id)===String(workerId));
  if(!worker)return;

  $("skillWorkerId").value=workerId;
  $("workerSkillsTitle").textContent=
    `${worker.worker_name} · Job / Skills / Leadership`;

  const current=workerSkills(workerId);
  const primary=current.find(x=>x.is_primary)?.department_code
    || worker.department_code;

  $("workerSkillRows").innerHTML=allDepartments()
    .filter(d=>d.worker_assignment_enabled!==false)
    .map(d=>{
      const selected=current.some(x=>x.department_code===d.department_code)
        || d.department_code===worker.department_code;

      return `<article class="card">
        <div class="row between">
          <label class="check">
            <input class="skill-enabled"
              data-dept="${safe(d.department_code)}"
              type="checkbox" ${selected?"checked":""}>
            ${safe(d.department_name)}
          </label>
          <label class="check">
            <input class="skill-primary"
              name="skillPrimary"
              data-dept="${safe(d.department_code)}"
              type="radio" ${d.department_code===primary?"checked":""}>
            Primary
          </label>
        </div>
        <small class="muted">
          ${safe(d.department_code)} · ${safe(d.department_type||"PRODUCTION")}
        </small>
      </article>`;
    }).join("");

  document.querySelectorAll(".skill-primary").forEach(r=>{
    r.onchange=()=>{
      if(r.checked){
        const check=document.querySelector(
          `.skill-enabled[data-dept="${CSS.escape(r.dataset.dept)}"]`
        );
        if(check)check.checked=true;
      }
    };
  });

  const leadership=leadershipFor(workerId)||{
    leadership_role:"NONE",
    base_payroll_category:"PIECE_RATE",
    compensation_mode:"PCS_ONLY",
    monthly_flat_incentive:0,
    rate_enhancement_type:"NONE",
    rate_enhancement_value:0,
    managed_departments:[],
    leadership_status:"ACTIVE"
  };

  $("leadershipRole").value=leadership.leadership_role||"NONE";
  $("leadershipPayrollCategory").value=
    leadership.base_payroll_category||"PIECE_RATE";
  $("leadershipCompensationMode").value=
    leadership.compensation_mode||"PCS_ONLY";
  $("leadershipMonthlyFlat").value=
    Number(leadership.monthly_flat_incentive||0);
  $("leadershipRateType").value=
    leadership.rate_enhancement_type||"NONE";
  $("leadershipRateValue").value=
    Number(leadership.rate_enhancement_value||0);
  $("leadershipSaleBasis").value=
    leadership.sale_incentive_basis||"NONE";
  $("leadershipSaleRate").value=
    Number(leadership.sale_incentive_rate||0);
  $("leadershipEffectiveFrom").value=
    leadership.effective_from||new Date().toISOString().slice(0,10);
  $("leadershipEffectiveTo").value=leadership.effective_to||"";
  $("leadershipStatus").value=leadership.leadership_status||"ACTIVE";

  $("leadershipDepartmentRows").innerHTML=
    renderLeadershipDepartmentRowsV776(
      leadership.managed_departments||[]
    );

  updateLeadershipCompensationFieldsV776();

  const today=new Date().toISOString().slice(0,10);
  const existingMode=payrollFor(workerId,"REAL")?"REAL":"TEST";
  const payroll=payrollFor(workerId,existingMode)||{
    worker_category:"PIECE_RATE",
    monthly_salary:0,
    shift_id:null,
    late_deduction_applicable:true,
    overtime_applicable:true,
    holiday_extra_applicable:true,
    grace_offset_against_ot:true,
    exception_reason:"",
    salaried_advance_limit_type:null,
    salaried_advance_limit_value:null,
    effective_from:today,
    effective_to:null,
    data_mode:"TEST"
  };

  $("payrollDataMode").value=payroll.data_mode||"TEST";
  $("payrollWorkerCategory").value=payroll.worker_category||"PIECE_RATE";
  $("payrollMonthlySalary").value=Number(payroll.monthly_salary||0);
  $("payrollShiftId").innerHTML=
    `<option value="">Select active Shift</option>${shiftOptionsV777(payroll.shift_id||"")}`;
  $("payrollShiftId").value=payroll.shift_id||"";
  $("payrollLateApplicable").checked=payroll.late_deduction_applicable!==false;
  $("payrollOtApplicable").checked=payroll.overtime_applicable!==false;
  $("payrollHolidayApplicable").checked=payroll.holiday_extra_applicable!==false;
  $("payrollGraceOffset").checked=payroll.grace_offset_against_ot!==false;
  $("payrollExceptionReason").value=payroll.exception_reason||"";
  $("payrollAdvanceLimitType").value=payroll.salaried_advance_limit_type||"";
  $("payrollAdvanceLimitValue").value=
    payroll.salaried_advance_limit_value??"";
  $("payrollEffectiveFrom").value=payroll.effective_from||today;
  $("payrollEffectiveTo").value=payroll.effective_to||"";

  updatePayrollFieldsV777();
  say("","info","workerSkillsMessage");
  openSheet("workerSkillsSheet");
}

async function saveWorkerSkills(event){
  event.preventDefault();
  const button=event.submitter;
  busy(button,true,"Saving…");

  try{
    const workerId=$("skillWorkerId").value;

    const rows=[...document.querySelectorAll(".skill-enabled")]
      .filter(x=>x.checked)
      .map(x=>({
        department_code:x.dataset.dept,
        is_primary:Boolean(
          document.querySelector(
            `.skill-primary[data-dept="${CSS.escape(x.dataset.dept)}"]`
          )?.checked
        ),
        is_active:true
      }));

    if(!rows.length){
      throw new Error("Select at least one Job Department.");
    }

    if(rows.filter(x=>x.is_primary).length!==1){
      throw new Error("Exactly one Primary Job Department required.");
    }

    const leadershipRole=$("leadershipRole").value;
    const managedDepartments=[
      ...document.querySelectorAll(".leadership-managed-dept:checked")
    ].map(x=>x.value);

    if(leadershipRole!=="NONE" && !managedDepartments.length){
      throw new Error(
        "Department Head/Production Manager ke liye Managed Department select karein."
      );
    }

    await rpc("rr_owner_set_worker_departments_v1",{
      p_worker_id:workerId,
      p_rows:rows
    });

    await rpc("rr_set_worker_leadership_v777_4_final",{
      p_worker_id:workerId,
      p_leadership_role:leadershipRole,
      p_managed_departments:managedDepartments,
      p_base_payroll_category:$("leadershipPayrollCategory").value,
      p_compensation_mode:$("leadershipCompensationMode").value,
      p_monthly_flat_incentive:
        Number($("leadershipMonthlyFlat").value||0),
      p_rate_enhancement_type:$("leadershipRateType").value,
      p_rate_enhancement_value:
        Number($("leadershipRateValue").value||0),
      p_sale_incentive_basis:$("leadershipSaleBasis").value,
      p_sale_incentive_rate:
        Number($("leadershipSaleRate").value||0),
      p_effective_from:$("leadershipEffectiveFrom").value,
      p_effective_to:$("leadershipEffectiveTo").value||null,
      p_status:$("leadershipStatus").value,
      p_reason:"Role & Permission V777.4 Final Leadership configuration"
    });

    const payrollCategory=$("payrollWorkerCategory").value;
    const salaried=payrollCategory==="SALARIED";

    if(salaried && !$("payrollShiftId").value){
      throw new Error("SALARIED Worker ke liye active Shift select karein.");
    }
    if(salaried && Number($("payrollMonthlySalary").value||0)<=0){
      throw new Error("SALARIED Worker ke liye Monthly Salary required hai.");
    }
    if(salaried && !$("payrollAdvanceLimitType").value){
      throw new Error("Salaried Advance Limit Type select karein.");
    }
    if(salaried && Number($("payrollAdvanceLimitValue").value||0)<=0){
      throw new Error("Salaried Advance Limit Value required hai.");
    }

    await rpc("rr_set_worker_payroll_profile_v777_3",{
      p_worker_id:workerId,
      p_worker_category:payrollCategory,
      p_monthly_salary:salaried
        ?Number($("payrollMonthlySalary").value||0)
        :0,
      p_shift_id:salaried?$("payrollShiftId").value:null,
      p_late_deduction_applicable:$("payrollLateApplicable").checked,
      p_overtime_applicable:$("payrollOtApplicable").checked,
      p_holiday_extra_applicable:$("payrollHolidayApplicable").checked,
      p_grace_offset_against_ot:$("payrollGraceOffset").checked,
      p_exception_reason:$("payrollExceptionReason").value.trim()||null,
      p_salaried_advance_limit_type:salaried
        ?$("payrollAdvanceLimitType").value
        :null,
      p_salaried_advance_limit_value:salaried
        ?Number($("payrollAdvanceLimitValue").value||0)
        :null,
      p_effective_from:$("payrollEffectiveFrom").value,
      p_effective_to:$("payrollEffectiveTo").value||null,
      p_data_mode:$("payrollDataMode").value,
      p_reason:"Role & Permission V777.3 Payroll Profile"
    });

    closeSheet("workerSkillsSheet");
    await loadConsole({quiet:true});
    showTab("workers");
    say(
      "Job, skills, leadership aur payroll profile saved.",
      "success"
    );
  }catch(e){
    say(err(e),"error","workerSkillsMessage");
  }finally{
    busy(button,false);
  }
}


function availableLoginUsersV7743(workerId,selectedAuthUserId=""){
  const occupiedByOtherWorker=new Set();

  (state.data?.workers||[]).forEach(w=>{
    if(String(w.worker_id)===String(workerId))return;

    const identity=identityFor(w.worker_id);
    const linkedAuthId=
      identity?.linked_auth_user_id
      || w.linked_auth_user_id
      || null;

    if(linkedAuthId){
      occupiedByOtherWorker.add(String(linkedAuthId));
    }
  });

  return activeLoginUsers().filter(u=>{
    const authId=String(u.auth_user_id||"");
    if(!authId)return false;

    // Current Worker's existing login remains visible.
    if(authId===String(selectedAuthUserId||""))return true;

    // Login already attached to any other Worker is hidden.
    return !occupiedByOtherWorker.has(authId);
  });
}

function loginOptionsV773(workerId,selected=""){
  const users=availableLoginUsersV7743(workerId,selected);

  if(!users.length){
    return `
      <option value="">
        No unlinked active Login User available · Create User first
      </option>
    `;
  }

  return `
    <option value="">Select unlinked active Login User</option>
    ${users.map(u=>`
      <option value="${safe(u.auth_user_id)}"
        ${String(u.auth_user_id)===String(selected)?"selected":""}>
        ${safe(u.full_name||u.email||u.auth_user_id)} ·
        ${safe(upper(u.role_code))}
      </option>
    `).join("")}
  `;
}

function witnessOptionsV773(workerId,selected=""){
  const worker=(state.data?.workers||[])
    .find(x=>String(x.worker_id)===String(workerId));
  const policy=witnessPolicyForDepartment(worker?.department_code);

  if(!policy){
    return `<option value="">Department Witness Policy configure karein</option>`;
  }

  const rows=[];

  if(policy.primary_witness_worker_id){
    rows.push(`
      <option value="${safe(policy.primary_witness_worker_id)}">
        PRIMARY HEAD · ${safe(policy.primary_witness_name||"—")}
      </option>
    `);
  }

  if(policy.secondary_witness_worker_id){
    rows.push(`
      <option value="${safe(policy.secondary_witness_worker_id)}">
        SECONDARY RANDOM · ${safe(policy.secondary_witness_name||"—")}
      </option>
    `);
  }

  return rows.length
    ?rows.join("")
    :`<option value="">Witness Policy incomplete</option>`;
}

function updateIdentityModeFieldsV773(){
  const mode=$("identityDeviceMode").value;
  const smartphone=mode==="SMARTPHONE";

  $("identityLoginBlock").classList.toggle("hidden",!smartphone);
  $("identityWitnessBlock").classList.toggle(
    "hidden",
    smartphone||!mode
  );

  $("identityLoginUser").disabled=!smartphone;
  $("identityWitnessWorker").disabled=smartphone||!mode;

  if(smartphone){
    const hasAvailableLogin=[...$("identityLoginUser").options]
      .some(option=>Boolean(option.value));

    if(!hasAvailableLogin){
      $("identityLoginUser").title=$("identityTestPhoneEnabled").checked
        ?"Test Phone enabled hai: test-only save allowed; Real Login LINK PENDING rahega."
        :"SMARTPHONE Worker ke liye pehle Users & Access me alag Login User create karein.";
    }else{
      $("identityLoginUser").title="";
    }
  }
}

function openWorkerIdentityV773(workerId){
  const worker=(state.data?.workers||[])
    .find(x=>String(x.worker_id)===String(workerId));
  if(!worker)return;

  const identity=identityFor(workerId)||{};
  state.editingIdentityWorker=worker;

  $("workerIdentityTitle").textContent=
    `${worker.worker_name} · Device / Login / Witness`;

  $("identityWorkerId").value=workerId;
  $("identityWorkerSummary").innerHTML=`
    <b>${safe(worker.worker_name)}</b><br>
    ${safe(worker.worker_code||"—")} ·
    ${safe(departmentLabel(worker.department_code))}<br>
    Mobile: ${safe(worker.mobile||"Not saved")}<br>
    Current Identity: ${safe(
      identity.identity_status_hinglish
      || identity.identity_status
      || "DEVICE MODE SET KAREIN"
    )}
  `;

  $("identityDeviceMode").value=identity.device_mode||"";
  $("identityLoginUser").innerHTML=loginOptionsV773(
    workerId,
    identity.linked_auth_user_id||""
  );
  $("identityWitnessWorker").innerHTML=witnessOptionsV773(
    workerId,
    identity.witness_worker_id||""
  );
  $("identityWitnessWorker").disabled=true;

  const witnessPolicy=witnessPolicyForDepartment(worker.department_code);
  $("identityWitnessPolicySummary").innerHTML=witnessPolicy
    ?`
      <b>Primary Head:</b> ${safe(witnessPolicy.primary_witness_name||"Not set")}<br>
      <b>Secondary Same Department:</b> ${safe(witnessPolicy.secondary_witness_name||"Not selected")}<br>
      <b>Policy Status:</b> ${safe(witnessPolicy.policy_status||"INCOMPLETE")}
    `
    :"Department Witness Policy configured nahi hai.";

  $("identityCurrentLink").textContent=identity.linked_login_name
    ?`Linked Login: ${identity.linked_login_name}`
    :"Linked Login: None";

  $("identityCurrentWitness").textContent=identity.witness_worker_name
    ?`Active Witness: ${identity.witness_worker_name}`
    :"Active Witness: None";

  const testPhone=testPhoneFor(workerId)||{};
  $("identityTestPhoneEnabled").checked=Boolean(testPhone.test_mode_enabled);
  $("identityTestPhoneMode").value=testPhone.test_device_mode||"TEST_KEYPAD_PHONE";
  $("identityTestMobile").value=testPhone.test_mobile||"8368849128";

  updateIdentityModeFieldsV773();
  say("","info","workerIdentityMessage");
  openSheet("workerIdentitySheet");
}

async function saveWorkerIdentityV773(event){
  event.preventDefault();

  const btn=event.submitter;
  const workerId=$("identityWorkerId").value;
  const deviceMode=$("identityDeviceMode").value;
  const identity=identityFor(workerId)||{};

  if(!deviceMode){
    say("Device Mode select karein.","error","workerIdentityMessage");
    return;
  }

  busy(btn,true,"Saving Identity…");

  try{
    await rpc("rr_set_worker_device_mode_v770",{
      p_worker_id:workerId,
      p_device_mode:deviceMode,
      p_reason:"Role & Permission V773 explicit Device Mode"
    });

    let testOnlyIdentityPending=false;

    if(deviceMode==="SMARTPHONE"){
      const authUserId=$("identityLoginUser").value;
      const testPhoneEnabled=$("identityTestPhoneEnabled").checked;

      if(!authUserId){
        if(!testPhoneEnabled){
          throw new Error(
            "SMARTPHONE worker ke liye active Login User select karein."
          );
        }

        /*
          Development-only allowance:
          Device Mode is saved, Login remains pending, and V775 Test Mode
          may route the test message to the configured shared test mobile.
          Real/production communication still requires linked Self Login.
        */
        testOnlyIdentityPending=true;
      }else{
        if(
          identity.linked_auth_user_id
          && String(identity.linked_auth_user_id)!==String(authUserId)
        ){
          await rpc("rr_unlink_worker_login_v770",{
            p_worker_id:workerId,
            p_reason:"V774.4 Login replacement before explicit link"
          });
        }

        await rpc("rr_link_worker_login_v770",{
          p_worker_id:workerId,
          p_auth_user_id:authUserId,
          p_reason:"Role & Permission V774.4 Owner/Admin verified Login Link"
        });
      }
    }else{
      await rpc("rr_apply_department_witness_to_worker_v774",{
        p_physical_worker_id:workerId,
        p_reason:"Role & Permission V774 Department Witness Policy"
      });
    }

    if($("identityTestPhoneEnabled").checked){
      await rpc("rr_set_worker_test_phone_mode_v773_2",{
        p_worker_id:workerId,
        p_test_device_mode:$("identityTestPhoneMode").value,
        p_test_mobile:$("identityTestMobile").value.trim()||"8368849128",
        p_reason:"Role & Permission V773.2 development test phone"
      });
    }else{
      await rpc("rr_disable_worker_test_phone_mode_v773_2",{
        p_worker_id:workerId,
        p_reason:"Role & Permission V773.2 test phone disabled"
      });
    }

    closeSheet("workerIdentitySheet");
    state.editingIdentityWorker=null;
    await loadConsole({quiet:true});
    showTab("workers");
    say(
      testOnlyIdentityPending
        ?"Test identity saved. Real SMARTPHONE Login abhi LINK PENDING hai; Test routing configured mobile par chalegi."
        :"Worker Device / Login / Witness identity saved.",
      testOnlyIdentityPending?"info":"success"
    );
  }catch(e){
    say(err(e),"error","workerIdentityMessage");
  }finally{
    busy(btn,false);
  }
}

async function unlinkWorkerLoginV773(){
  const workerId=$("identityWorkerId").value;
  const worker=state.editingIdentityWorker;
  const identity=identityFor(workerId);

  if(!identity?.linked_auth_user_id){
    say("Is Worker ka Login linked nahi hai.","error","workerIdentityMessage");
    return;
  }

  const reason=prompt(
    `${worker?.worker_name||"Worker"} Login unlink reason`,
    "Owner verified unlink"
  )||"";

  if(!reason)return;

  try{
    await rpc("rr_unlink_worker_login_v770",{
      p_worker_id:workerId,
      p_reason:reason
    });

    await loadConsole({quiet:true});
    openWorkerIdentityV773(workerId);
    say("Worker Login unlink ho gaya.","success","workerIdentityMessage");
  }catch(e){
    say(err(e),"error","workerIdentityMessage");
  }
}

async function applyAllTestPhoneV7732(){
  if(!isOwner()){
    say("Sirf OWNER sab Workers par Test Phone apply kar sakta hai.","error");
    return;
  }

  const mode=$("bulkTestPhoneMode").value;
  const label=mode==="TEST_SMARTPHONE"?"TEST SMARTPHONE":"TEST KEYPAD PHONE";

  if(!confirm(
    `${label} · 8368849128 sab active non-Owner/Admin Workers par apply karein?`
  ))return;

  const button=$("applyAllTestPhone");
  busy(button,true,"Applying…");

  try{
    const result=await rpc("rr_set_all_workers_test_phone_mode_v773_2",{
      p_test_device_mode:mode,
      p_test_mobile:"8368849128",
      p_reason:"V773.2 bulk development test phone"
    });

    await loadConsole({quiet:true});
    showTab("workers");
    say(
      `${result.workers_updated||0} Workers par ${label} · 8368849128 applied.`,
      "success"
    );
  }catch(e){
    say(err(e),"error");
  }finally{
    busy(button,false);
  }
}

async function ownerSetAdminStatusV773(profileId,status,button){
  if(!isOwner()){
    say("Sirf OWNER Admin security control kar sakta hai.","error");
    return;
  }

  const user=(state.data?.users||[]).find(u=>String(u.id)===String(profileId));
  if(!user||!isAdminUser(user))return;

  const active=status==="ACTIVE";
  const reason=prompt(
    `${user.full_name||"Admin"} · ${status} reason`,
    "Owner Admin control"
  )||"";

  if(!reason)return;

  if(!confirm(
    `${user.full_name||"Admin"} ka status ${status} karein?`
  ))return;

  busy(button,true,"Applying…");

  try{
    await rpc("rr_owner_set_admin_status_v772",{
      p_target_auth_user_id:user.auth_user_id,
      p_is_active:active,
      p_access_status:status,
      p_keep_admin_role:true,
      p_reason:reason
    });

    /*
      Edge Function call is attempted only for auth-level session access.
      Database V772 guard remains final authority.
    */
    try{
      const action=status==="ACTIVE"
        ?"ACTIVATE"
        :status==="BLOCKED"
          ?"TEMP_BLOCK"
          :"DEACTIVATE";

      await invokeUserAdmin({
        action:"set_access",
        profile_id:profileId,
        auth_user_id:user.auth_user_id,
        access_action:action,
        reason
      });
    }catch(edgeError){
      console.warn(
        "Admin auth-session sync unavailable; database status saved.",
        edgeError
      );
    }

    await loadConsole({quiet:true});
    showTab("users");
    say(`${user.full_name}: Admin status ${status}.`,"success");
  }catch(e){
    say(err(e),"error");
  }finally{
    busy(button,false);
  }
}


function sameDepartmentLoginWorkersV774(departmentCode){
  return (state.data?.workers||[]).filter(w=>{
    const i=identityFor(w.worker_id);
    return lower(w.department_code)===lower(departmentCode)
      && w.is_active!==false
      && upper(w.access_status||"ACTIVE")==="ACTIVE"
      && i?.identity_status==="LINKED_SELF_LOGIN";
  });
}

function openDepartmentWitnessPolicyV774(departmentCode){
  const department=everyDepartment()
    .find(x=>x.department_code===departmentCode);
  if(!department)return;

  const policy=witnessPolicyForDepartment(departmentCode)||{};
  const candidates=sameDepartmentLoginWorkersV774(departmentCode);

  $("departmentWitnessCode").value=departmentCode;
  $("departmentWitnessTitle").textContent=
    `${department.department_name} · Witness Policy`;

  $("departmentPrimaryWitness").innerHTML=`
    <option value="">Select Department Head</option>
    ${candidates.map(w=>`
      <option value="${safe(w.worker_id)}"
        ${String(w.worker_id)===String(policy.primary_witness_worker_id)?"selected":""}>
        ${safe(w.worker_name)} · ${safe(w.worker_code||"")}
      </option>
    `).join("")}
  `;

  $("departmentWitnessSummary").innerHTML=`
    <b>Primary Head:</b> ${safe(policy.primary_witness_name||"Not set")}<br>
    <b>Secondary Same Department:</b> ${safe(policy.secondary_witness_name||"Not selected")}<br>
    <b>Status:</b> ${safe(policy.policy_status||"INCOMPLETE")}
  `;

  say("","info","departmentWitnessMessage");
  openSheet("departmentWitnessSheet");
}

async function saveDepartmentPrimaryWitnessV774(event){
  event.preventDefault();
  const button=event.submitter;
  const departmentCode=$("departmentWitnessCode").value;
  const primaryWorkerId=$("departmentPrimaryWitness").value;

  if(!primaryWorkerId){
    say("Department Head select karein.","error","departmentWitnessMessage");
    return;
  }

  busy(button,true,"Saving Head…");

  try{
    await rpc("rr_set_department_primary_witness_v774",{
      p_department_code:departmentCode,
      p_primary_worker_id:primaryWorkerId,
      p_reason:"Role & Permission V774 Department Head"
    });

    await rpc("rr_randomize_department_secondary_witness_v774",{
      p_department_code:departmentCode,
      p_reason:"Role & Permission V774 random same-department secondary"
    });

    closeSheet("departmentWitnessSheet");
    await loadConsole({quiet:true});
    showTab("departments");
    say("Primary Head aur random same-department Secondary Witness saved.","success");
  }catch(e){
    say(err(e),"error","departmentWitnessMessage");
  }finally{
    busy(button,false);
  }
}

async function rerollDepartmentSecondaryV774(){
  const departmentCode=$("departmentWitnessCode").value;
  const button=$("rerollDepartmentSecondary");
  busy(button,true,"Selecting…");

  try{
    const result=await rpc("rr_randomize_department_secondary_witness_v774",{
      p_department_code:departmentCode,
      p_reason:"Owner/Admin requested secondary re-selection"
    });

    await loadConsole({quiet:true});
    openDepartmentWitnessPolicyV774(departmentCode);
    say(
      `Secondary Witness: ${result.secondary_witness_name||"selected"}`,
      "success",
      "departmentWitnessMessage"
    );
  }catch(e){
    say(err(e),"error","departmentWitnessMessage");
  }finally{
    busy(button,false);
  }
}

function departmentCards(rows){return rows.map(d=>`<article class="department-card ${d.is_active===false?"archive":""}"><div class="row between"><div><h4>${safe(d.department_name)}</h4><p class="muted">${safe(d.department_code)} · ${safe(d.department_type||"PRODUCTION")}</p></div>${statusBadge(d.is_active===false?"INACTIVE":"ACTIVE")}</div><div class="department-meta"><span class="badge">Parent ${safe(d.parent_department_code||"ROOT")}</span><span class="badge">Order ${Number(d.display_order||100)}</span>${d.production_enabled?'<span class="badge good">PRODUCTION</span>':''}${d.worker_assignment_enabled?'<span class="badge good">WORKERS</span>':''}${d.rate_enabled?'<span class="badge">RATE</span>':''}${d.colour_assignment_enabled?'<span class="badge">COLOUR</span>':''}${d.allow_alter?'<span class="badge warn">ALTER</span>':''}</div><div class="button-row"><button class="secondary tiny" data-edit-department="${safe(d.department_code)}">Modify Department</button><button class="primary tiny" data-department-witness="${safe(d.department_code)}">Witness Policy</button>${d.is_active===false?`<button class="primary tiny" data-department-status="ACTIVATE" data-department="${safe(d.department_code)}">Activate</button>`:`<button class="warning tiny" data-department-status="ARCHIVE" data-department="${safe(d.department_code)}">Archive</button>`}</div></article>`).join("")||'<div class="panel">No departments.</div>'}
function renderDepartments(){const all=everyDepartment(),q=lower(state.departmentSearch);const rows=!q?all:all.filter(d=>JSON.stringify(d).toLowerCase().includes(q));$("tab-departments").innerHTML=`<div class="toolbar"><label class="grow"><span>Search departments</span><input id="departmentSearch" value="${safe(state.departmentSearch)}" placeholder="Kaaj, Button, Eyelet"></label><button id="refreshDepartments" class="secondary">Refresh</button><button id="newDepartment" class="primary">+ Create Department</button></div><div class="panel"><p class="note">Department code permanent identity है. Display name edit हो सकता है. Hard delete नहीं होगा. New department Role, Permission Matrix, Worker Skills और UPM में map होता है.</p></div><div id="departmentCards" class="department-grid">${departmentCards(rows)}</div>`;$("departmentSearch").oninput=e=>{state.departmentSearch=e.target.value;clearTimeout(renderDepartments.t);renderDepartments.t=setTimeout(renderDepartments,160)};$("refreshDepartments").onclick=()=>loadConsole();$("newDepartment").onclick=()=>openDepartmentEditor();bindDepartmentButtons()}
function bindDepartmentButtons(){document.querySelectorAll("[data-edit-department]").forEach(b=>b.onclick=()=>openDepartmentEditor(b.dataset.editDepartment));document.querySelectorAll("[data-department-status]").forEach(b=>b.onclick=()=>changeDepartmentStatus(b.dataset.department,b.dataset.departmentStatus,b));document.querySelectorAll("[data-department-witness]").forEach(b=>b.onclick=()=>openDepartmentWitnessPolicyV774(b.dataset.departmentWitness))}
function openDepartmentEditor(code=null){const d=code?everyDepartment().find(x=>x.department_code===code):null;state.editingDepartment=d||null;$("departmentSheetTitle").textContent=d?`Edit ${d.department_name}`:"Create Department";$("dName").value=d?.department_name||"";$("dCode").value=d?.department_code||"";$("dCode").readOnly=Boolean(d);$("departmentCodeNote").textContent=d?`Permanent code: ${d.department_code}. यह code rename नहीं होगा.`:"Department code creation के बाद permanent रहेगा. Display name बाद में बदला जा सकता है.";const parentOptions='<option value="">Root / No Parent</option>'+everyDepartment().filter(x=>x.is_active!==false&&x.department_code!==code).map(x=>`<option value="${safe(x.department_code)}">${safe(x.department_name)}</option>`).join("");$("dParent").innerHTML=parentOptions;$("dParent").value=d?.parent_department_code||"";$("dType").value=d?.department_type||"PRODUCTION";$("dOrder").value=Number(d?.display_order||100);$("dCopyFrom").innerHTML='<option value="">No template</option>'+everyDepartment().filter(x=>x.is_active!==false&&x.department_code!==code).map(x=>`<option value="${safe(x.department_code)}">${safe(x.department_name)}</option>`).join("");$("dActive").checked=d?.is_active!==false;$("dProduction").checked=d?.production_enabled??true;$("dWorkerAssign").checked=d?.worker_assignment_enabled??true;$("dRateEnabled").checked=d?.rate_enabled??true;$("dColour").checked=d?.colour_assignment_enabled??true;$("dAlter").checked=d?.allow_alter??true;$("dCreateRole").checked=true;$("dCopyNow").checked=false;say("","info","departmentMessage");openSheet("departmentSheet")}
async function saveDepartment(event){event.preventDefault();const button=event.submitter;busy(button,true,"Saving…");try{await rpc("rr_owner_save_department_v2",{p_department_code:$("dCode").value.trim(),p_department_name:$("dName").value.trim(),p_parent_department_code:$("dParent").value||null,p_department_type:$("dType").value,p_display_order:Number($("dOrder").value||100),p_is_active:$("dActive").checked,p_production_enabled:$("dProduction").checked,p_worker_assignment_enabled:$("dWorkerAssign").checked,p_rate_enabled:$("dRateEnabled").checked,p_colour_assignment_enabled:$("dColour").checked,p_allow_alter:$("dAlter").checked,p_copy_permissions_from:$("dCopyFrom").value||null,p_copy_permissions:$("dCopyNow").checked,p_create_role:$("dCreateRole").checked});closeSheet("departmentSheet");await loadConsole({quiet:true});showTab("departments");say(state.editingDepartment?"Department modified; permanent code और existing mappings सुरक्षित हैं.":"Department created and mapped to Role, Permission and UPM.","success");state.editingDepartment=null}catch(e){say(err(e),"error","departmentMessage")}finally{busy(button,false)}}
async function changeDepartmentStatus(code,action,button){const reason=prompt(`${action} reason`,"Owner department update")||"";if(!reason)return;busy(button,true,"Applying…");try{await rpc("rr_owner_set_department_status_v2",{p_department_code:code,p_action:action,p_reason:reason});await loadConsole({quiet:true});showTab("departments");say(`${code}: ${action} applied.`,"success")}catch(e){say(err(e),"error")}finally{busy(button,false)}}

function renderAll(){renderStats();renderMatrix();renderActions();renderOverrides();renderFields();renderUsers();renderWorkers();renderDepartments();showTab(state.tab);populateFieldSelects()}
function showTab(tab){state.tab=tab;document.querySelectorAll("[id^='tab-']").forEach(el=>el.classList.toggle("hidden",el.id!==`tab-${tab}`));document.querySelectorAll("#tabs button").forEach(b=>b.classList.toggle("active",b.dataset.tab===tab))}

function populateFieldSelects(){if(!$("fModule"))return;$("fModule").innerHTML=moduleOptions($("fModule").value||"cutting");$("iAdapter").innerHTML=(state.data?.adapters||[]).map(a=>`<option value="${a.adapter_code}">${safe(a.adapter_name)} · ${a.live_ready?"LIVE":"DEMO ONLY"}</option>`).join("");$("uDepartment").innerHTML=allDepartments().map(d=>`<option value="${d.department_code}">${safe(d.department_name)}</option>`).join("");$("uRole").innerHTML=roleOptions($("uRole").value)}
function setImpactMode(mode){state.impactMode=mode;$("impactNo").classList.toggle("selected",mode==="NON_IMPACT");$("impactYes").classList.toggle("selected",mode==="IMPACT");$("impactFields").classList.toggle("hidden",mode!=="IMPACT")}
function routeRow(route={},index){return `<div class="grid3 route-row" data-index="${index}" style="margin-top:8px"><label><span>Target Module</span><select data-route="module">${moduleOptions(route.target_module_code||"printing")}</select></label><label><span>Relation Mode</span><select data-route="mode"><option ${route.relation_mode==="HIDE"?"selected":""}>HIDE</option><option ${!route.relation_mode||route.relation_mode==="VIEW_REFERENCE"?"selected":""}>VIEW_REFERENCE</option><option ${route.relation_mode==="EDITABLE_COPY"?"selected":""}>EDITABLE_COPY</option><option ${route.relation_mode==="DERIVED"?"selected":""}>DERIVED</option><option ${route.relation_mode==="PROCESS_SPECIFIC"?"selected":""}>PROCESS_SPECIFIC</option><option ${route.relation_mode==="DO_NOT_FORWARD"?"selected":""}>DO_NOT_FORWARD</option></select></label><div class="row"><label class="grow"><span>Target Field Key</span><input data-route="target" value="${safe(route.target_field_key||"")}"></label><button class="danger tiny" type="button" data-remove-route="${index}">×</button></div></div>`}
function renderRoutes(){$("routeRows").innerHTML=state.routes.map(routeRow).join("")||`<p class="muted">No cross-module route.</p>`;document.querySelectorAll("[data-remove-route]").forEach(b=>b.onclick=()=>{state.routes.splice(Number(b.dataset.removeRoute),1);renderRoutes()})}
function collectRoutes(){return [...document.querySelectorAll(".route-row")].map(row=>({target_module_code:row.querySelector('[data-route="module"]').value,relation_mode:row.querySelector('[data-route="mode"]').value,target_field_key:row.querySelector('[data-route="target"]').value.trim()}))}
function currentRule(field){return state.data?.impact_rules?.find(r=>r.field_id===field?.id&&r.version_no===field?.latest_version)||state.data?.impact_rules?.find(r=>r.field_id===field?.id)||null}
function fillRule(rule){$("iInventory").checked=bool(rule?.inventory_impact);$("iCosting").checked=bool(rule?.costing_impact);$("iWorkflow").checked=bool(rule?.workflow_impact);$("iCross").checked=bool(rule?.cross_module_impact);$("iAdapter").value=rule?.adapter_code||"DYNAMIC_LEDGER_ONLY";$("iReference").value=rule?.reference_context||"";$("iTarget").value=rule?.target_context||"";$("iSource").value=rule?.source_field_key||"";$("iSecondary").value=rule?.secondary_field_key||"";$("iInvOp").value=rule?.inventory_operator||"";$("iCostOp").value=rule?.cost_operator||"";$("iRateBasis").value=rule?.rate_basis||"";$("iTrigger").value=rule?.trigger_event||"OWNER_APPROVE";$("iApproval").checked=rule?.approval_required??true;$("iReverse").checked=rule?.allow_reverse??true;$("iFreeze").checked=bool(rule?.block_on_pending)}
function openFieldEditor(id=null){const f=id?state.data.fields.find(x=>x.id===id):null;state.editingField=f||null;state.routes=f?(state.data.routes||[]).filter(r=>r.field_id===f.id).map(r=>({...r})):[];$("fieldSheetTitle").textContent=f?`${f.display_name} · ${f.status}${f.draft_status&&f.draft_status!=="NONE"?` · ${f.draft_status}`:""}`:"Create Field Draft";$("fKey").value=f?.field_key||"";$("fName").value=f?.display_name||"";populateFieldSelects();$("fModule").value=f?.module_code||"cutting";$("fSection").value=f?.section_code||"general";$("fDataType").value=f?.data_type||"TEXT";$("fInputType").value=f?.input_type||"MANUAL";$("fUnit").value=f?.unit_code||"";$("fOrder").value=f?.display_order||100;$("fRequired").checked=bool(f?.is_required);$("fSensitive").checked=bool(f?.is_sensitive);setImpactMode(f?.impact_mode||"NON_IMPACT");fillRule(currentRule(f));renderRoutes();$("demoResult").classList.add("hidden");say("","info","fieldMessage");$("activateField").classList.toggle("hidden",f?.draft_status!=="DEMO_READY");$("suspendField").classList.toggle("hidden",f?.status!=="ACTIVE");$("revokeField").classList.toggle("hidden",!["ACTIVE","SUSPENDED"].includes(f?.status));openSheet("fieldSheet")}
async function saveFieldDraft(event){event?.preventDefault();const btn=$("saveField");busy(btn,true,"Saving…");try{const field=await rpc("rr_owner_save_field_draft_v1",{p_field_id:state.editingField?.id||null,p_field_key:$("fKey").value,p_display_name:$("fName").value,p_module_code:$("fModule").value,p_section_code:$("fSection").value,p_data_type:$("fDataType").value,p_input_type:$("fInputType").value,p_unit_code:$("fUnit").value||null,p_is_required:$("fRequired").checked,p_is_sensitive:$("fSensitive").checked,p_display_order:Number($("fOrder").value||100),p_impact_mode:state.impactMode,p_validation_config:{},p_ui_config:{created_from:"owner_permission_console_v72037"}});state.editingField=field;
    if(state.impactMode==="IMPACT")await rpc("rr_owner_save_impact_rule_v1",{p_field_id:field.id,p_adapter_code:$("iAdapter").value,p_inventory_impact:$("iInventory").checked,p_costing_impact:$("iCosting").checked,p_workflow_impact:$("iWorkflow").checked,p_cross_module_impact:$("iCross").checked,p_reference_context:$("iReference").value||null,p_source_field_key:$("iSource").value||null,p_secondary_field_key:$("iSecondary").value||null,p_target_context:$("iTarget").value||null,p_inventory_operator:$("iInvOp").value||null,p_cost_operator:$("iCostOp").value||null,p_rate_basis:$("iRateBasis").value||null,p_trigger_event:$("iTrigger").value,p_approval_required:$("iApproval").checked,p_allow_reverse:$("iReverse").checked,p_block_on_pending:$("iFreeze").checked,p_allocation_rule:null,p_conditions:{},p_config:{}});
    for(const route of collectRoutes())await rpc("rr_owner_set_field_route_v1",{p_field_id:field.id,p_target_module_code:route.target_module_code,p_relation_mode:route.relation_mode,p_target_field_key:route.target_field_key||null,p_config:{}});
    await loadConsole({quiet:true});state.editingField=state.data.fields.find(x=>x.id===field.id);openFieldEditor(field.id);say("Field draft saved. अब Demo run करें।","success","fieldMessage");return true
  }catch(e){console.error(e);say(err(e),"error","fieldMessage");return false}finally{busy(btn,false)}}
async function runDemo(){if(!state.editingField?.id){say("पहले Save Draft करें।","error","fieldMessage");return}const btn=$("runDemo");busy(btn,true,"Simulating…");try{await saveFieldDraft();const out=await rpc("rr_owner_run_field_demo_v1",{p_field_id:state.editingField.id,p_sample:{current_stock:Number($("dStock").value||0),current_value:Number($("dValue").value||0),qty:Number($("dQty").value||0),rate:Number($("dRate").value||0),amount:Number($("dAmount").value||0),divisor:Number($("dDivisor").value||0),base:Number($("dBase").value||0),entity_type:"DEMO",entity_id:"DEMO-1"}});$("demoResult").classList.remove("hidden");$("demoResult").textContent=`DEMO MODE — NO LIVE IMPACT\n\n${JSON.stringify(out,null,2)}`;await loadConsole({quiet:true});state.editingField=state.data.fields.find(x=>x.id===state.editingField.id);$("activateField").classList.toggle("hidden",state.editingField?.draft_status!=="DEMO_READY");say(out.passed?"Demo passed. Owner अब activate कर सकता है।":"Demo failed; rules बदलें।",out.passed?"success":"error","fieldMessage")}catch(e){say(err(e),"error","fieldMessage")}finally{busy(btn,false)}}
async function activateField(){if(!state.editingField)return;const ok=confirm("Demo preview सही है? Field को LIVE activate करें?");if(!ok)return;try{await rpc("rr_owner_activate_field_v1",{p_field_id:state.editingField.id});await loadConsole({quiet:true});closeSheet("fieldSheet");renderFields();say("Field Owner approval से ACTIVE हुई।","success")}catch(e){say(err(e),"error","fieldMessage")}}
async function suspendField(){const reason=prompt("Suspend reason")||"";if(!reason)return;try{await rpc("rr_owner_suspend_field_v1",{p_field_id:state.editingField.id,p_reason:reason});await loadConsole({quiet:true});closeSheet("fieldSheet");say("Field suspended; नया impact रुक गया।","success")}catch(e){say(err(e),"error","fieldMessage")}}
async function revokeField(){const reason=prompt("Revoke & Restore reason — compensating reversals बनेंगी")||"";if(!reason)return;if(!confirm("Field के अपने reversible effects reverse करके field REVOKE करें? History delete नहीं होगी।"))return;try{const out=await rpc("rr_owner_revoke_field_v1",{p_field_id:state.editingField.id,p_reason:reason});await loadConsole({quiet:true});closeSheet("fieldSheet");say(`Field revoked & restored. Reversals: ${out.reversal_count||0}`,"success")}catch(e){say(err(e),"error","fieldMessage")}}

function openUserCreate(){populateFieldSelects();$("userForm").reset();say("","info","userMessage");openSheet("userSheet")}
async function invokeUserAdmin(payload){const r=await state.client.functions.invoke("rr-owner-user-admin",{body:payload});if(r.error)throw r.error;if(r.data?.error)throw new Error(r.data.error);return r.data}
async function createUser(event){event.preventDefault();const btn=event.submitter;busy(btn,true,"Creating…");try{await invokeUserAdmin({action:"create_user",email:$("uEmail").value.trim(),password:$("uPassword").value,full_name:$("uName").value.trim(),role_code:$("uRole").value,department_code:$("uDepartment").value});closeSheet("userSheet");await loadConsole({quiet:true});say("User ID created. Existing password readable form में save नहीं हुआ।","success")}catch(e){say(`${err(e)} · Edge Function deploy check करें।`,"error","userMessage")}finally{busy(btn,false)}}
async function changeUserAccess(profileId,action,button){
  const user=state.data.users.find(u=>u.id===profileId);
  if(!user)return;

  if(isOwnerUser(user)){
    say("OWNER protected hai. Koi security action allowed nahi.","error");
    return;
  }

  if(isAdminUser(user)&&!isOwner()){
    say("Sirf OWNER Admin security control kar sakta hai.","error");
    return;
  }

  const reason=prompt(
    `${action.replaceAll("_"," ")} reason`,
    action==="TEMP_BLOCK"?"Immediate access block":"Owner access change"
  )||"";

  if(!reason)return;
  if(!confirm(
    `${user.full_name||user.role_code}: ${action.replaceAll("_"," ")} confirm?`
  ))return;

  busy(button,true,"Applying…");

  try{
    let out;
    try{
      out=await invokeUserAdmin({
        action:"set_access",
        profile_id:profileId,
        auth_user_id:user.auth_user_id,
        access_action:action,
        reason
      });
    }catch(edgeError){
      console.warn("Edge Function fallback",edgeError);
      out=await rpc("rr_owner_set_user_access_v1",{
        p_profile_id:profileId,
        p_action:action,
        p_reason:reason
      });
    }

    await loadConsole({quiet:true});
    say(
      `${user.full_name||"User"}: ${out.status||action}. Database access guard active.`,
      "success"
    );
  }catch(e){
    say(err(e),"error");
  }finally{
    busy(button,false);
  }
}

async function resetUserPassword(profileId,button){const user=state.data.users.find(u=>u.id===profileId);if(!user?.auth_user_id){say("Auth User ID missing.","error");return}if(isOwnerUser(user)){say("OWNER password ko Role & Permission se override/reset nahi kar sakte.","error");return}if(isAdminUser(user)&&!isOwner()){say("Sirf OWNER Admin password reset kar sakta hai.","error");return}const password=prompt(`New temporary password for ${user.full_name||"user"}`)||"";if(password.length<8){say("Password minimum 8 characters.","error");return}busy(button,true,"Resetting…");try{await invokeUserAdmin({action:"reset_password",auth_user_id:user.auth_user_id,password});say("Temporary password reset हुआ। पुराना password display नहीं हुआ।","success")}catch(e){say(`${err(e)} · Edge Function deploy check करें।`,"error")}finally{busy(button,false)}}

function bind(){document.querySelectorAll("[data-close]").forEach(x=>x.onclick=()=>closeSheet(x.dataset.close));$("tabs").querySelectorAll("button").forEach(b=>b.onclick=()=>showTab(b.dataset.tab));$("impactNo").onclick=()=>setImpactMode("NON_IMPACT");$("impactYes").onclick=()=>setImpactMode("IMPACT");$("addRoute").onclick=()=>{state.routes=collectRoutes();state.routes.push({target_module_code:"printing",relation_mode:"VIEW_REFERENCE"});renderRoutes()};$("fieldForm").onsubmit=saveFieldDraft;$("runDemo").onclick=runDemo;$("activateField").onclick=activateField;$("suspendField").onclick=suspendField;$("revokeField").onclick=revokeField;$("userForm").onsubmit=createUser;$("workerForm").onsubmit=createManualWorker;$("departmentForm").onsubmit=saveDepartment;$("workerSkillsForm").onsubmit=saveWorkerSkills;
  $("leadershipRole").onchange=updateLeadershipCompensationFieldsV776;
  $("leadershipCompensationMode").onchange=updateLeadershipCompensationFieldsV776;
  $("payrollWorkerCategory").onchange=updatePayrollFieldsV777;
  $("payrollDataMode").onchange=()=>{
    const workerId=$("skillWorkerId").value;
    const mode=$("payrollDataMode").value;
    const p=payrollFor(workerId,mode);
    if(p){
      $("payrollWorkerCategory").value=p.worker_category||"PIECE_RATE";
      $("payrollMonthlySalary").value=Number(p.monthly_salary||0);
      $("payrollShiftId").value=p.shift_id||"";
      $("payrollLateApplicable").checked=p.late_deduction_applicable!==false;
      $("payrollOtApplicable").checked=p.overtime_applicable!==false;
      $("payrollHolidayApplicable").checked=p.holiday_extra_applicable!==false;
      $("payrollGraceOffset").checked=p.grace_offset_against_ot!==false;
      $("payrollExceptionReason").value=p.exception_reason||"";
      $("payrollAdvanceLimitType").value=p.salaried_advance_limit_type||"";
      $("payrollAdvanceLimitValue").value=p.salaried_advance_limit_value??"";
      $("payrollEffectiveFrom").value=p.effective_from||new Date().toISOString().slice(0,10);
      $("payrollEffectiveTo").value=p.effective_to||"";
    }
    updatePayrollFieldsV777();
  };$("workerIdentityForm").onsubmit=saveWorkerIdentityV773;$("departmentWitnessForm").onsubmit=saveDepartmentPrimaryWitnessV774;$("rerollDepartmentSecondary").onclick=rerollDepartmentSecondaryV774;$("identityDeviceMode").onchange=updateIdentityModeFieldsV773;$("unlinkWorkerLogin").onclick=unlinkWorkerLoginV773;document.addEventListener("keydown",e=>{if(e.key==="Escape"){const sheet=document.querySelector(".sheet:not(.hidden)");if(sheet)closeSheet(sheet.id)}})}
async function boot(){try{state.client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;if(!state.client)throw new Error("Supabase client unavailable.");state.auth=await RR.requireRoles(["owner","admin"]);bind();await loadConsole();RR.startAccessGuard?.()}catch(e){console.error(e);say(err(e),"error")}}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",boot);else boot();
})();