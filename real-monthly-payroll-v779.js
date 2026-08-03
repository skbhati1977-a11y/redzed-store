(() => {
"use strict";
window.REDZED_MONTHLY_PAYROLL_VERSION="779.7.1";
const REDZED_PAYROLL_DATA_MODE="TEST";
window.REDZED_PAYROLL_DATA_MODE=REDZED_PAYROLL_DATA_MODE;

function previousMonthStart(){
  const d=new Date();
  d.setDate(1);
  d.setMonth(d.getMonth()-1);
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-01`;
}
const state={client:null,user:null,profile:null,worker:null,role:"",tab:"my",history:[],management:null,month:previousMonthStart()};
const $=id=>document.getElementById(id);
const safe=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
const money=v=>`₹ ${Number(v||0).toLocaleString("en-IN",{minimumFractionDigits:2,maximumFractionDigits:2})}`;
const upper=v=>String(v||"").trim().toUpperCase();
const lower=v=>String(v||"").trim().toLowerCase();
const err=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(" — ")||"Unknown error";
const canManage=()=>["owner","admin","manager","production"].includes(state.role);
function say(text,type=""){const el=$("message");el.textContent=text||"";el.className=`message ${type}`.trim()}
function openSheet(id){$(id).classList.remove("hidden");document.body.style.overflow="hidden"}
function closeSheet(id){$(id).classList.add("hidden");if(!document.querySelector(".sheet:not(.hidden)"))document.body.style.overflow=""}
async function rpc(name,payload={}){
  const r=await state.client.rpc(name,payload);
  if(r.error){
    const wrapped=new Error(`${name}: ${r.error.message||"RPC failed"}`);
    wrapped.details=r.error.details;
    wrapped.hint=r.error.hint;
    wrapped.code=r.error.code;
    throw wrapped;
  }
  return r.data;
}
function badge(status){const s=upper(status||"—"),cls=["PAID","FINAL","APPROVED","CLOSED"].some(x=>s.includes(x))?"good":["UNDER_REVIEW","CALCULATED","POSTED"].some(x=>s.includes(x))?"warn":s.includes("REVERSED")||s.includes("CANCELLED")?"bad":"";return `<span class="badge ${cls}">${safe(s.replaceAll("_"," "))}</span>`}

function formatDhm(value){
  const text=String(value||"").trim();
  return text||"0 M";
}
function textOrDash(value){
  const text=String(value??"").trim();
  return text||"—";
}
function dateText(value){
  if(!value)return "—";
  const d=new Date(value);
  return Number.isNaN(d.getTime())?String(value):d.toLocaleDateString("en-IN",{day:"2-digit",month:"short",year:"numeric"});
}
function dateTimeText(value){
  if(!value)return "—";
  const d=new Date(value);
  return Number.isNaN(d.getTime())?String(value):d.toLocaleString("en-IN",{dateStyle:"medium",timeStyle:"short"});
}
function detailHero(label,amount,sub=""){
  return `<div class="detail-hero"><small>${safe(label)}</small><strong>${money(amount)}</strong>${sub?`<div class="muted" style="margin-top:5px">${safe(sub)}</div>`:""}</div>`;
}
function emptyDetails(message){
  return `<div class="detail-empty">${safe(message)}</div>`;
}
function workflowHtml(status){
  const s=upper(status);
  const steps=["DRAFT","POSTED","FINAL","PAID"];
  const current=steps.indexOf(s);
  return `<div class="workflow">${steps.map((step,i)=>`<span class="workflow-step ${i<current?"active":i===current?"current":""}">${step}</span>${i<steps.length-1?`<span class="muted">→</span>`:""}`).join("")}</div>`;
}

function showTab(tab){state.tab=tab;$("tab-my").classList.toggle("hidden",tab!=="my");$("tab-management").classList.toggle("hidden",tab!=="management");document.querySelectorAll("#tabs button").forEach(b=>b.classList.toggle("active",b.dataset.tab===tab));if(tab==="management")loadManagement()}
function payrollCard(p){return `<article class="item"><div class="item-head"><div><h4>${safe(p.salary_month)}</h4><p class="muted">${badge(p.payroll_status)} ${p.settlement_status?badge(p.settlement_status):""}</p></div><strong>${money(p.net_payable_salary)}</strong></div><div class="detail-grid"><div class="detail-box"><small>Monthly Salary</small><strong>${money(p.monthly_salary)}</strong></div><div class="detail-box"><small>Net Extra Work</small><strong>${money(p.net_extra_work?.amount)}</strong><span class="muted">${safe(p.net_extra_work?.time||"0 M")}</span></div><div class="detail-box"><small>Monthly Incentive</small><strong>${money(p.monthly_incentive)}</strong></div><div class="detail-box"><small>Claims / Recovery</small><strong>${money(p.claims_recovery)}</strong></div></div><div class="actions"><button class="btn" data-summary="${safe(p.payroll_id)}">Open Payroll</button>${p.pdf_available?`<button class="btn" data-pdf="${safe(p.payroll_id)}">PDF</button>`:""}${p.whatsapp_available?`<button class="btn" data-wa="${safe(p.payroll_id)}">WhatsApp</button>`:""}</div></article>`}
async function loadMy(){try{say("Loading payroll…");const data=await rpc("rr_get_my_payroll_history_v779_3",{p_limit:24,p_data_mode:REDZED_PAYROLL_DATA_MODE});state.history=data?.payroll_history||[];$("tab-my").innerHTML=`<div class="toolbar"><button id="refreshMy" class="btn">Refresh</button></div><div class="list">${state.history.map(payrollCard).join("")||'<div class="panel empty">Abhi koi Monthly Payroll record nahi hai.</div>'}</div>`;$("refreshMy").onclick=loadMy;bindPayrollButtons();say("")}catch(e){console.error(e);$("tab-my").innerHTML=`<div class="panel empty">${safe(err(e))}</div>`;say(err(e),"error")}}
async function openSummary(id){try{if(state.tab==="management")showTab("my");const d=await rpc("rr_get_payroll_summary_v779_3",{p_payroll_id:id});const heads=d.heads||[];$("tab-my").innerHTML=`<div class="toolbar"><button id="backHistory" class="btn">← Payroll History</button></div><article class="payroll-slip"><div class="slip-head"><div><p class="kicker">${safe(d.header?.title)}</p><h2>${safe(d.header?.salary_month)}</h2><p class="muted">${safe(d.header?.worker_name)} · ${safe(d.header?.worker_code)} · ${safe(d.header?.department_code)}</p></div><div>${badge(d.status?.payroll_status)} ${d.status?.settlement_status?badge(d.status.settlement_status):""}</div></div>${heads.map(h=>`<div class="slip-row"><div><b>${safe(h.label)}</b>${h.time?`<span class="sub">${safe(h.time)}</span>`:""}</div><span class="amount">${money(h.amount)}</span><button class="btn" data-detail-section="${safe(h.code)}" data-payroll="${safe(id)}">Details</button></div>`).join("")}<div class="slip-total"><span>${safe(d.net_payable?.label)}</span><strong>${money(d.net_payable?.amount)}</strong></div><div class="status-row"><span class="badge">Paid ${money(d.payment?.paid_amount)}</span><span class="badge">Balance ${money(d.payment?.closing_balance)}</span></div>${workflowHtml(d.status?.payroll_status)}<div class="actions"><button class="btn" data-detail-section="PAYMENT" data-payroll="${safe(id)}">Payment Details</button>${d.actions?.raise_dispute?`<button class="btn warn" data-dispute="${safe(id)}">Raise Dispute</button>`:""}${d.actions?.download_pdf?`<button class="btn" data-pdf="${safe(id)}">PDF</button>`:""}${d.actions?.share_whatsapp?`<button class="btn" data-wa="${safe(id)}">WhatsApp</button>`:""}</div></article>`;$("backHistory").onclick=loadMy;bindPayrollButtons();say("")}catch(e){say(err(e),"error")}}

function renderDetails(title,html){
  $("detailsTitle").textContent=title;
  $("detailsBody").innerHTML=html;
  openSheet("detailsSheet");
}
function renderMonthlySalaryDetails(d){
  const deduction=d.net_deduction||{};
  return `
    ${detailHero("Monthly Salary",d.monthly_salary_amount)}
    <div class="sheet-summary">
      <div class="detail-box"><small>Contract Monthly Salary</small><strong>${money(d.contract_monthly_salary)}</strong></div>
      <div class="detail-box"><small>Per Minute Rate</small><strong>₹ ${Number(d.per_minute_rate||0).toLocaleString("en-IN",{minimumFractionDigits:6,maximumFractionDigits:8})}</strong></div>
      <div class="detail-box"><small>Salary Basis</small><strong>${Number(d.basis_days||30)} Days</strong></div>
      <div class="detail-box"><small>Monthly Base</small><strong>${Number(d.monthly_base_minutes||18000).toLocaleString("en-IN")} Minutes</strong></div>
    </div>
    <div class="detail-section">
      <h3>Net Deduction</h3>
      <div class="detail-line">
        <div><b>${formatDhm(deduction.time)}</b><div class="meta">${Number(deduction.minutes||0)} minutes</div></div>
        <div class="value">${money(deduction.amount)}</div>
      </div>
    </div>`;
}

function renderExtraWorkDetails(d,full={}){
  const rows=Array.isArray(d.date_wise)?d.date_wise:[];
  const salary=full.monthly_salary_details||{};
  const extra=full.net_extra_work_details||{};
  const snapshot=full.calculation_snapshot||{};
  const attendance=snapshot.attendance||{};

  const deductionMinutes=Number(
    salary.net_deduction_minutes
    ?? attendance.net_deduction_minutes
    ?? 0
  );

  const extraMinutes=Number(
    extra.minutes
    ?? d.total_minutes
    ?? attendance.net_extra_work_minutes
    ?? 0
  );

  const netWorkingMinutes=Number(
    attendance.net_working_minutes
    ?? snapshot.net_working_minutes
    ?? 0
  );

  const deductionTime=
    salary.net_deduction_dhm
    || attendance.net_deduction_dhm
    || formatDhm(
      deductionMinutes
        ? `${Math.floor(deductionMinutes/60)} H ${deductionMinutes%60} M`
        : "0 M"
    );

  const extraTime=
    extra.time
    || d.total_time
    || attendance.net_extra_work_dhm
    || formatDhm(
      extraMinutes
        ? `${Math.floor(extraMinutes/60)} H ${extraMinutes%60} M`
        : "0 M"
    );

  const netWorkingTime=
    attendance.net_working_dhm
    || formatDhm(
      netWorkingMinutes
        ? `${Math.floor(netWorkingMinutes/600)} D ${Math.floor((netWorkingMinutes%600)/60)} H ${netWorkingMinutes%60} M`
        : "0 M"
    );

  return `
    ${detailHero("Net Extra Work",d.amount,extraTime)}

    <div class="sheet-summary">
      <div class="detail-box">
        <small>Total Deduction Time</small>
        <strong>${safe(deductionTime)}</strong>
        <span class="muted">${deductionMinutes.toLocaleString("en-IN")} minutes</span>
      </div>

      <div class="detail-box">
        <small>Total Extra Work Time</small>
        <strong>${safe(extraTime)}</strong>
        <span class="muted">${extraMinutes.toLocaleString("en-IN")} minutes</span>
      </div>

      <div class="detail-box">
        <small>Net Working Time</small>
        <strong>${safe(netWorkingTime)}</strong>
        <span class="muted">${netWorkingMinutes.toLocaleString("en-IN")} minutes</span>
      </div>

      <div class="detail-box">
        <small>Net Extra Work Amount</small>
        <strong>${money(d.amount)}</strong>
      </div>
    </div>

    <div class="detail-section">
      <h3>Date-wise Extra Work Record</h3>
      ${rows.length
        ?`<div class="detail-table-wrap">
            <table class="detail-table">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Time</th>
                  <th>Minutes</th>
                </tr>
              </thead>
              <tbody>
                ${rows.map(r=>`
                  <tr>
                    <td>${safe(dateText(r.date))}</td>
                    <td>${safe(formatDhm(r.time))}</td>
                    <td>${Number(r.minutes||0)}</td>
                  </tr>
                `).join("")}
              </tbody>
            </table>
          </div>`
        :emptyDetails("Is payroll month me Net Extra Work record nahi hai.")
      }
    </div>`;
}

function renderIncentiveDetails(d){
  const rows=Array.isArray(d.items)?d.items:[];
  return `
    ${detailHero("Monthly Incentive",d.total_amount)}
    <div class="detail-section">
      <h3>Approved Incentive Items</h3>
      ${rows.length?`<div class="detail-list">${rows.map(r=>`<div class="detail-line"><div><b>${safe(String(r.type||"Incentive").replaceAll("_"," "))}</b><div class="meta">${safe(r.description||"No description")} · ${safe(r.status||"")}</div></div><div class="value">${money(r.amount)}</div></div>`).join("")}</div>`:emptyDetails("Is payroll month me approved incentive nahi hai.")}
    </div>`;
}
function renderClaimsDetails(d){
  const rows=Array.isArray(d.items)?d.items:[];
  return `
    ${detailHero("Claims / Recovery",d.total_amount)}
    <div class="sheet-summary">
      <div class="detail-box"><small>Approved Claims</small><strong>${money(d.approved_claims)}</strong></div>
      <div class="detail-box"><small>Advance Recovery</small><strong>${money(d.advance_recovery)}</strong></div>
    </div>
    <div class="detail-section">
      <h3>Applied Recovery Items</h3>
      ${rows.length?`<div class="detail-table-wrap"><table class="detail-table"><thead><tr><th>Type</th><th>Applied Date</th><th>Amount</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${safe(String(r.source_type||"").replaceAll("_"," "))}</td><td>${safe(dateTimeText(r.applied_at))}</td><td>${money(r.amount)}</td></tr>`).join("")}</tbody></table></div>`:emptyDetails("Is payroll me Claim ya Advance Recovery apply nahi hui.")}
    </div>`;
}
function renderPaymentDetails(d){
  const rows=Array.isArray(d.items)?d.items:[];
  return `
    <div class="detail-section">
      <h3>Payment History</h3>
      ${rows.length?`<div class="detail-table-wrap"><table class="detail-table"><thead><tr><th>Date</th><th>Payment Added</th><th>Total Paid</th><th>Closing Balance</th></tr></thead><tbody>${rows.map(r=>{const x=r.details||{};return `<tr><td>${safe(dateTimeText(r.date))}</td><td>${money(x.payment_added)}</td><td>${money(x.total_payment)}</td><td>${money(x.closing_balance)}</td></tr>`}).join("")}</tbody></table></div>`:emptyDetails("Abhi koi salary payment record nahi hai.")}
    </div>`;
}
async function openSection(id,section){
  try{
    const key=upper(section);

    if(key==="NET_EXTRA_WORK"){
      const [d,full]=await Promise.all([
        rpc("rr_get_payroll_section_details_v779_3",{
          p_payroll_id:id,
          p_section:section
        }),
        rpc("rr_get_payroll_details_v779_1",{
          p_payroll_id:id
        })
      ]);
      renderDetails(
        "Work Time Summary",
        renderExtraWorkDetails(d,full)
      );
      return;
    }

    const d=await rpc("rr_get_payroll_section_details_v779_3",{
      p_payroll_id:id,
      p_section:section
    });

    if(key==="MONTHLY_SALARY")
      renderDetails("Monthly Salary Details",renderMonthlySalaryDetails(d));
    else if(key==="MONTHLY_INCENTIVE")
      renderDetails("Monthly Incentive Details",renderIncentiveDetails(d));
    else if(key==="CLAIMS_RECOVERY")
      renderDetails("Claims / Recovery Details",renderClaimsDetails(d));
    else if(key==="PAYMENT")
      renderDetails("Payment History",renderPaymentDetails(d));
    else
      renderDetails(d.title||section,emptyDetails("Details available nahi hain."));
  }catch(e){say(err(e),"error")}
}

async function getPdf(id){try{const d=await rpc("rr_get_payslip_payload_v779_3",{p_payroll_id:id});renderDetails("PDF Payslip",`${detailHero("PDF Payslip",d.payload?.net_payable?.amount||0)}<div class="detail-empty">PDF payload ready hai. Final renderer se payslip PDF generate hogi.</div>`);say("PDF payload ready. Frontend/server renderer isse PDF banayega.","success")}catch(e){say(err(e),"error")}}
async function getWhatsapp(id){try{const d=await rpc("rr_get_whatsapp_payslip_payload_v779_3",{p_payroll_id:id});renderDetails("WhatsApp Payslip",`<div class="detail-section"><div class="detail-box"><small>Status</small><strong>${safe(d.send_status||"READY")}</strong></div><div class="detail-box" style="margin-top:9px"><small>Message Preview</small><strong class="details">${safe(d.message_text||"")}</strong></div></div>`);say("WhatsApp payload ready. Raw URL visible nahi hai.","success")}catch(e){say(err(e),"error")}}
function openAction(type,id){$("actionType").value=type;$("actionPayrollId").value=id;const title={DISPUTE:"Raise Payroll Dispute",REVIEW:"Open Review",FINALIZE:"Finalize Payroll",PAYMENT:"Record Salary Payment",POST:"Post Payroll"}[type]||type;$("actionTitle").textContent=title;let fields=`<label><span>Reason / Note *</span><textarea id="actionReason" rows="4" required></textarea></label>`;if(type==="DISPUTE")fields=`<label><span>Section</span><select id="actionSection"><option>MONTHLY_SALARY</option><option>NET_EXTRA_WORK</option><option>MONTHLY_INCENTIVE</option><option>CLAIMS_RECOVERY</option><option>PAYMENT</option><option>OTHER</option></select></label>`+fields;if(type==="PAYMENT")fields=`<label><span>Payment Amount *</span><input id="actionAmount" type="number" min="0.01" step="0.01" required></label>`+fields;$("actionFields").innerHTML=fields;$("actionMessage").textContent="";openSheet("actionSheet")}
async function submitAction(e){e.preventDefault();const type=$("actionType").value,id=$("actionPayrollId").value,reason=$("actionReason")?.value.trim()||"";try{let d;if(type==="DISPUTE")d=await rpc("rr_raise_payroll_dispute_v779_3",{p_payroll_id:id,p_section:$("actionSection").value,p_dispute_text:reason,p_evidence:{}});if(type==="POST")d=await rpc("rr_post_monthly_payroll_v779_2",{p_payroll_id:id,p_reason:reason});if(type==="REVIEW")d=await rpc("rr_open_payroll_review_v779_2",{p_payroll_id:id,p_reason:reason});if(type==="FINALIZE")d=await rpc("rr_finalize_monthly_payroll_v779_2",{p_payroll_id:id,p_reason:reason});if(type==="PAYMENT")d=await rpc("rr_record_monthly_salary_payment_v779_2",{p_payroll_id:id,p_payment_amount:Number($("actionAmount").value),p_reason:reason});closeSheet("actionSheet");say(`${type} completed.`,"success");if(state.tab==="management")loadManagement();else openSummary(id)}catch(ex){$("actionMessage").textContent=err(ex);$("actionMessage").className="message error"}}
function bindPayrollButtons(){document.querySelectorAll("[data-summary]").forEach(b=>b.onclick=()=>openSummary(b.dataset.summary));document.querySelectorAll("[data-detail-section]").forEach(b=>b.onclick=()=>openSection(b.dataset.payroll,b.dataset.detailSection));document.querySelectorAll("[data-pdf]").forEach(b=>b.onclick=()=>getPdf(b.dataset.pdf));document.querySelectorAll("[data-wa]").forEach(b=>b.onclick=()=>getWhatsapp(b.dataset.wa));document.querySelectorAll("[data-dispute]").forEach(b=>b.onclick=()=>openAction("DISPUTE",b.dataset.dispute));document.querySelectorAll("[data-action]").forEach(b=>b.onclick=()=>openAction(b.dataset.action,b.dataset.payroll))}
async function generateAllPayroll(){
  const btn=$("generateAllPayroll");
  if(!btn)return;
  const old=btn.textContent;
  btn.disabled=true;
  btn.textContent="Generating…";
  try{
    const d=await rpc("rr_generate_monthly_payroll_batch_v779_5",{
      p_payroll_month:state.month,
      p_data_mode:REDZED_PAYROLL_DATA_MODE,
      p_reason:"Owner generated completed monthly payroll"
    });
    say(`Generated ${d.generated||0}; existing ${d.already_existing||0}; attendance pending ${d.skipped_no_attendance||0}; failed ${d.failed||0}.`,d.failed?"error":"success");
    await loadManagement();
  }catch(e){say(err(e),"error")}
  finally{btn.disabled=false;btn.textContent=old}
}
async function generateOnePayroll(workerId){
  try{
    await rpc("rr_generate_worker_monthly_payroll_safe_v779_5",{
      p_worker_id:workerId,
      p_payroll_month:state.month,
      p_data_mode:REDZED_PAYROLL_DATA_MODE,
      p_reason:"Owner generated worker monthly payroll"
    });
    say("Worker payroll generated.","success");
    await loadManagement();
  }catch(e){say(err(e),"error")}
}
async function generateLegacyPayroll(workerId){
  const reason=prompt("Legacy Payroll reason mandatory","Worker Attendance module se pehle salaried tha");
  if(!reason?.trim())return;
  try{
    await rpc("rr_generate_worker_monthly_payroll_legacy_v779_5",{
      p_worker_id:workerId,p_payroll_month:state.month,
      p_reason:reason.trim(),p_data_mode:REDZED_PAYROLL_DATA_MODE
    });
    say("Legacy monthly payroll generated.","success");
    await loadManagement();
  }catch(e){say(err(e),"error")}
}
async function generateAllLegacyPayroll(){
  const reason=prompt("Sab legacy workers ke liye reason mandatory","Attendance go-live se pehle ka historical monthly payroll");
  if(!reason?.trim())return;
  const btn=$("generateAllLegacyPayroll"),old=btn?.textContent||"Generate All Legacy";
  if(btn){btn.disabled=true;btn.textContent="Generating Legacy…"}
  try{
    const d=await rpc("rr_generate_monthly_payroll_legacy_batch_v779_5",{
      p_payroll_month:state.month,p_reason:reason.trim(),p_data_mode:REDZED_PAYROLL_DATA_MODE
    });
    say(`Legacy generated ${d.legacy_generated||0}; existing ${d.already_existing||0}; attendance available ${d.skipped_attendance_available||0}; failed ${d.failed||0}.`,d.failed?"error":"success");
    await loadManagement();
  }catch(e){say(err(e),"error")}
  finally{if(btn){btn.disabled=false;btn.textContent=old}}
}

function normalizeManagementBoard(data){
  const d=data&&typeof data==="object"?data:{};
  const summary=d.summary&&typeof d.summary==="object"?d.summary:{};
  const workers=Array.isArray(d.workers)?d.workers:[];
  return {
    ...d,
    summary:{
      eligible_workers:Number(summary.eligible_workers||0),
      generated_workers:Number(summary.generated_workers||0),
      legacy_generated_workers:Number(summary.legacy_generated_workers||0),
      attendance_generated_workers:Number(summary.attendance_generated_workers||0),
      not_generated_workers:Number(summary.not_generated_workers||0),
      monthly_salary_total:Number(summary.monthly_salary_total||0),
      net_extra_work_total:Number(summary.net_extra_work_total||0),
      incentive_total:Number(summary.incentive_total||0),
      claims_recovery_total:Number(summary.claims_recovery_total||0),
      net_payable_total:Number(summary.net_payable_total||0),
      paid_total:Number(summary.paid_total||0),
      closing_balance_total:Number(summary.closing_balance_total||0)
    },
    workers
  };
}

async function loadManagement(){
  if(!canManage())return;
  try{
    say("Loading management payroll…");
    const d=normalizeManagementBoard(await rpc("rr_get_payroll_management_board_v779_5",{p_payroll_month:state.month,p_data_mode:REDZED_PAYROLL_DATA_MODE}));
    state.management=d;
    const s=d.summary||{},completed=d.month_completed!==false,ownerAdmin=["owner","admin"].includes(state.role);
    $("tab-management").innerHTML=`<div class="toolbar"><label><span>Payroll Month</span><input id="managementMonth" type="month" value="${safe(state.month.slice(0,7))}"></label><button id="refreshManagement" class="btn">Refresh</button><button id="generateAllPayroll" class="btn primary" ${completed?"":"disabled"}>Generate Attendance Payroll</button>${ownerAdmin?`<button id="generateAllLegacyPayroll" class="btn warn" ${completed?"":"disabled"}>Generate All Legacy</button>`:""}${completed?"":'<span class="muted">Current/future month generate nahi hoga.</span>'}</div><div class="summary-grid">
<div class="summary-card"><small>Eligible Workers</small><strong>${s.eligible_workers}</strong></div>
<div class="summary-card"><small>Generated</small><strong>${s.generated_workers}</strong></div>
<div class="summary-card"><small>Legacy Generated</small><strong>${s.legacy_generated_workers}</strong></div>
<div class="summary-card"><small>Monthly Salary</small><strong>${money(s.monthly_salary_total)}</strong></div>
<div class="summary-card"><small>Extra + Incentive</small><strong>${money(s.net_extra_work_total+s.incentive_total)}</strong></div>
<div class="summary-card"><small>Claims / Recovery</small><strong>${money(s.claims_recovery_total)}</strong></div>
<div class="summary-card"><small>Net Payable</small><strong>${money(s.net_payable_total)}</strong></div>
</div><div class="list">${(d.workers||[]).map(w=>`<article class="item"><div class="item-head"><div><h4>${safe(w.worker_name)} · ${safe(w.worker_code||"")}</h4><p class="muted">${safe(w.department_code||"")} · SALARIED · Attendance ${Number(w.approved_attendance_days||0)} day(s)</p><p>${badge(w.payroll_status)} ${w.settlement_status?badge(w.settlement_status):""} <span class="badge">${safe(w.generation_status||"")}</span></p>${w.generation_mode==="LEGACY"&&w.legacy_reason?`<p class="muted">Legacy: ${safe(w.legacy_reason)}</p>`:""}</div><strong>${money(w.net_payable_salary)}</strong></div><div class="detail-grid"><div class="detail-box"><small>Contract Salary</small><strong>${money(w.contract_monthly_salary)}</strong></div><div class="detail-box"><small>Monthly Salary</small><strong>${money(w.monthly_salary)}</strong></div><div class="detail-box"><small>Net Extra Work</small><strong>${money(w.net_extra_work_amount)}</strong><span class="muted">${safe(w.net_extra_work_time||"0 M")}</span></div><div class="detail-box"><small>Incentive</small><strong>${money(w.monthly_incentive)}</strong></div><div class="detail-box"><small>Claims / Recovery</small><strong>${money(w.claims_recovery)}</strong></div><div class="detail-box"><small>Paid / Remaining</small><strong>${money(w.payment_amount)} / ${money(w.closing_balance)}</strong></div></div><div class="actions">${w.payroll_id?`<button class="btn" data-summary="${safe(w.payroll_id)}">Details</button>`:""}${!w.payroll_id&&w.generation_status==="READY_TO_GENERATE"?`<button class="btn primary" data-generate-worker="${safe(w.worker_id)}">Generate</button>`:""}${!w.payroll_id&&w.generation_status==="READY_FOR_LEGACY_GENERATION"&&ownerAdmin?`<button class="btn warn" data-generate-legacy="${safe(w.worker_id)}">Generate Legacy</button>`:""}${w.payroll_status==="DRAFT"?`<button class="btn primary" data-action="POST" data-payroll="${safe(w.payroll_id)}">Post</button>`:""}${w.payroll_status==="POSTED"?`<button class="btn warn" data-action="REVIEW" data-payroll="${safe(w.payroll_id)}">Review</button>`:""}${["POSTED","UNDER_REVIEW"].includes(w.payroll_status)?`<button class="btn success" data-action="FINALIZE" data-payroll="${safe(w.payroll_id)}">Finalize</button>`:""}${["FINAL","PAID"].includes(w.payroll_status)?`<button class="btn primary" data-action="PAYMENT" data-payroll="${safe(w.payroll_id)}">Payment</button>`:""}</div></article>`).join("")||`<div class="panel empty">
      TEST mode me active salaried worker profile nahi mila.
      <br><small>RPC: rr_get_payroll_management_board_v779_5 · Month: ${safe(state.month)}</small>
    </div>`}</div>`;
    $("managementMonth").onchange=e=>{state.month=e.target.value+"-01";loadManagement()};
    $("refreshManagement").onclick=loadManagement;
    $("generateAllPayroll").onclick=generateAllPayroll;
    if($("generateAllLegacyPayroll"))$("generateAllLegacyPayroll").onclick=generateAllLegacyPayroll;
    document.querySelectorAll("[data-generate-worker]").forEach(b=>b.onclick=()=>generateOnePayroll(b.dataset.generateWorker));
    document.querySelectorAll("[data-generate-legacy]").forEach(b=>b.onclick=()=>generateLegacyPayroll(b.dataset.generateLegacy));
    bindPayrollButtons();say("");
  }catch(e){console.error(e);$("tab-management").innerHTML=`<div class="panel empty">${safe(err(e))}</div>`;say(err(e),"error")}
}
async function boot(){try{state.client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;if(!state.client)throw new Error("Supabase client unavailable.");const u=await state.client.auth.getUser();if(u.error||!u.data?.user)throw new Error("Login required.");state.user=u.data.user;const p=await state.client.from("rr_user_profiles").select("*").eq("auth_user_id",state.user.id).eq("is_active",true).limit(1).maybeSingle();if(p.error)throw p.error;state.profile=p.data||{};state.role=lower(state.profile.role_code);if(canManage())$("managementTabButton").classList.remove("hidden");document.querySelectorAll("#tabs button").forEach(b=>b.onclick=()=>showTab(b.dataset.tab));document.querySelectorAll("[data-close]").forEach(b=>b.onclick=()=>closeSheet(b.dataset.close));$("actionForm").onsubmit=submitAction;document.addEventListener("keydown",e=>{if(e.key==="Escape"){const s=document.querySelector(".sheet:not(.hidden)");if(s)closeSheet(s.id)}});await loadMy();
if(canManage()){
  showTab("management");
}else{
  showTab("my");
}
window.RR?.startAccessGuard?.()}catch(e){console.error(e);say(err(e),"error");$("tab-my").innerHTML=`<div class="panel empty">${safe(err(e))}</div>`}}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",boot);else boot();
})();