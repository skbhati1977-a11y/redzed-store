(() => {
  "use strict";
  const sb = () => window.supabaseClient || window.supabaseDb || window.redzedSupabase || window.sb;
  const esc = v => String(v ?? "").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const num = v => Number(v || 0);
  let inbox = {role:"WORKER",can_assign:false,items:[]};
  let active = null;

  async function rpc(name,args={}) { const {data,error}=await sb().rpc(name,args); if(error) throw error; return data; }
  const rowsOf = item => Array.isArray(item.lm_count_rows) && item.lm_count_rows.length ? item.lm_count_rows : (item.colour_rows || []);
  const totals = item => `<div class="rf794-totals"><b>TTL ASSIGN ${num(item.assigned_total)} PCS</b><b>TTL READY ${num(item.worker_ready_total)} PCS</b>${item.lm_counted_total!=null?`<b>TTL LM COUNT ${num(item.lm_counted_total)} PCS</b><b class="${num(item.difference)===0?'ok':'bad'}">DIFF ${num(item.difference)>0?'+':''}${num(item.difference)} PCS</b>`:""}</div>`;
  function matrix(item,editable=false){
    return `<div class="rf794-matrix">${rowsOf(item).map(c=>`<section><h4>${esc(c.colour_name||c.colour_code)} · ${esc(c.colour_code)}</h4><div>${(c.sizes||[]).map(s=>`<label><span>${esc(s.size_code)}<small>Assign ${num(s.assigned_qty)}</small></span>${editable?`<input inputmode="numeric" type="number" min="0" step="1" data-colour="${esc(c.colour_code)}" data-size="${esc(s.size_code)}" placeholder="Qty">`:`<b>${num(s.qty??s.ready_qty??s.assigned_qty)}</b>`}</label>`).join("")}</div></section>`).join("")}</div>`;
  }
  function show(item){ active=item; const sheet=document.getElementById("rf794Sheet");
    let body="";
    if(item.kind==="LM_OFFER") body=`<h2>READY TO SUBMIT · ${esc(item.premise_code||"L1/L2")}</h2><p>Lot <b>${esc(item.lot_no)}</b> · ${esc(item.department_code)}<br>Worker: <b>${esc(item.worker_name)}</b></p>${totals(item)}${matrix(item)}<div class="rf794-actions"><button data-do="ACCEPT" class="success">ACCEPT & COUNT</button><button data-do="UNAVAILABLE" class="warning">TEMPORARILY UNAVAILABLE</button><button data-do="REFUSED" class="danger">REFUSE WITH REASON</button></div>`;
    if(item.kind==="LM_ACTIVE") body=`<h2>COUNT & SEND</h2><p>Lot <b>${esc(item.lot_no)}</b> · Worker <b>${esc(item.worker_name)}</b></p>${totals(item)}${matrix(item,true)}<div class="rf794-actions"><button data-do="SEND_COUNT" class="success">SEND FOR WORKER CONFIRMATION</button></div>`;
    if(item.kind==="WORKER_CONFIRM") body=`<h2>FINAL COUNT CONFIRMATION</h2><p>Lot <b>${esc(item.lot_no)}</b> · LM <b>${esc(item.accepted_lm_name||"—")}</b></p>${totals(item)}${matrix(item)}<label class="rf794-next">Next Department (view suggestion only)<select id="rf794Next"><option value="">OPEN RANDOM QUEUE</option>${departmentOptions(item.department_code)}</select></label><div class="rf794-actions"><button data-do="WORKER_ACCEPT" class="success">ACCEPT & FINAL SUBMIT</button><button data-do="DISPUTE" class="danger">LM SE CONFIRM · QTY MISMATCH</button></div><p class="rf794-lock">Confirmation complete होने तक नया assignment locked रहेगा.</p>`;
    sheet.innerHTML=`<button class="rf794-close" type="button">×</button>${body}<p id="rf794Msg"></p>`;
    document.getElementById("rf794Modal").classList.remove("hidden"); bindSheet();
  }
  function departmentOptions(current){
    const list=window.RealFactoryUPM?.snapshot?.().departments||[];
    return list.filter(d=>String(d.department_code).toUpperCase()!==String(current).toUpperCase()&&String(d.department_code).toUpperCase()!=="CUTTING").map(d=>`<option value="${esc(d.department_code)}">${esc(d.department_name||d.department_code)}</option>`).join("");
  }
  function reason(){
    const choice=prompt("Reason code लिखें:\nTEA_MEAL_BREAK\nCOMPANY_WORK\nOTHER_FACTORY_WORK\nOUTSIDE_FACTORY_DUTY\nHANDLING_PHYSICAL_WORK\nHEALTH_EMERGENCY\nWRONG_DEPARTMENT\nOTHER");
    return String(choice||"").trim().toUpperCase();
  }
  function message(t,bad=false){const x=document.getElementById("rf794Msg");if(x){x.textContent=t;x.className=bad?"bad":"ok";}}
  async function act(code){
    try{
      if(code==="ACCEPT") await rpc("rr_upm_accept_submit_v794",{p_request_id:active.request_id});
      if(code==="REFUSED"||code==="UNAVAILABLE"){const why=reason();if(!why)return;await rpc("rr_upm_refuse_submit_v794",{p_request_id:active.request_id,p_response:code,p_reason:why});}
      if(code==="SEND_COUNT"){
        const entries=[...document.querySelectorAll("#rf794Sheet [data-colour][data-size]")];
        if(entries.some(i=>i.value===""||num(i.value)<0))throw new Error("हर Colour और Size की counted Qty भरें.");
        await rpc("rr_upm_lm_count_submit_v794",{p_request_id:active.request_id,p_count_rows:entries.map(i=>({colour_code:i.dataset.colour,size_code:i.dataset.size,qty:num(i.value)}))});
      }
      if(code==="WORKER_ACCEPT") await rpc("rr_upm_worker_decide_submit_v794",{p_request_id:active.request_id,p_decision:"ACCEPT",p_note:null,p_next_department_code:document.getElementById("rf794Next")?.value||null});
      if(code==="DISPUTE") {const note=prompt("Qty mismatch साफ लिखें (कौन-सा Colour/Size और सही Qty):");if(!note)return;await rpc("rr_upm_worker_decide_submit_v794",{p_request_id:active.request_id,p_decision:"DISPUTE",p_note:note,p_next_department_code:null});}
      document.getElementById("rf794Modal").classList.add("hidden"); await refresh(); window.RealFactoryUPM?.refresh?.();
    }catch(e){message(e.message||String(e),true);}
  }
  function bindSheet(){
    document.querySelector("#rf794Sheet .rf794-close").onclick=()=>document.getElementById("rf794Modal").classList.add("hidden");
    document.querySelectorAll("#rf794Sheet [data-do]").forEach(b=>b.onclick=()=>act(b.dataset.do));
  }
  function renderBell(){
    const host=document.getElementById("rf794Inbox"); if(!host)return;
    host.innerHTML=`<button id="rf794Bell" class="${inbox.items.length?'live':''}" type="button">SUBMIT ALERTS <b>${inbox.items.length}</b></button><button id="rf796Attendance" type="button">TEST ATTENDANCE GPS</button>`;
    host.querySelector("#rf794Bell").onclick=()=>{if(inbox.items[0])show(inbox.items[0]);else alert("No pending Submit alert.");};
    host.querySelector("#rf796Attendance").onclick=testAttendance;
    document.body.classList.toggle("rf794-no-assign",!inbox.can_assign);
  }
  async function testAttendance(){
    try{
      const event=String(prompt("TEST attendance event चुनें:\n1 = CHECK IN\n2 = CHECK OUT","1")||"").trim()==="2"?"CHECK_OUT":"CHECK_IN";
      const raw=prompt("Mandatory geofence scenario:\n1 = INSIDE GEOFENCE\n2 = OUTSIDE GEOFENCE","1");
      const scenario=String(raw||"").trim()==="1"?"INSIDE_GEOFENCE":String(raw||"").trim()==="2"?"OUTSIDE_GEOFENCE":"";
      if(!scenario)throw new Error("Inside या Outside Geofence scenario चुनना जरूरी है.");
      if(!navigator.geolocation)throw new Error("GPS उपलब्ध नहीं है.");
      const gps=await new Promise((resolve,reject)=>navigator.geolocation.getCurrentPosition(p=>resolve(p.coords),()=>reject(new Error("Location permission Allow करें.")),{enableHighAccuracy:true,timeout:15000,maximumAge:0}));
      const dept=document.getElementById("dept")?.value||new URLSearchParams(location.search).get("dept")||"";
      const out=await rpc("rr_test_attendance_scenario_v796",{p_department_code:dept,p_event_code:event,p_latitude:gps.latitude,p_longitude:gps.longitude,p_accuracy_meters:gps.accuracy,p_test_scenario:scenario});
      alert(`TEST attendance recorded\n${out.premise_code} · ${scenario.replaceAll("_"," ")}\nPhysical location allowed for TEST only. Salary/REAL attendance प्रभावित नहीं है.`);
    }catch(e){alert(e.message||String(e));}
  }
  async function refresh(){try{inbox=await rpc("rr_upm_submit_inbox_v794")||inbox;renderBell();if(inbox.items.some(x=>x.kind==="WORKER_CONFIRM")&&!document.hidden)show(inbox.items.find(x=>x.kind==="WORKER_CONFIRM"));}catch(e){console.warn("V794 inbox",e);}}
  function install(){
    document.body.insertAdjacentHTML("beforeend",`<div id="rf794Inbox"></div><div id="rf794Modal" class="modal hidden"><section id="rf794Sheet" class="sheet"></section></div>`);
    const title=document.getElementById("submitBtn");if(title)title.textContent="READY TO SUBMIT · SELECTED COLOURS";
    refresh();setInterval(refresh,60000);document.addEventListener("visibilitychange",()=>{if(!document.hidden)refresh();});
  }
  document.readyState==="loading"?document.addEventListener("DOMContentLoaded",install):install();
  console.info("REAL FACTORY SUBMIT CONFIRM V796 TEST LOCATION ROUTING");
})();
