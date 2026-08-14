(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const templates = [
    { id: "production_due", title: "Production Due", hint: "Print/Sticker/Metal ID explicit due", table: "rr_print_due_activation_v839", question: "Production due summary batao: print, sticker, metal id me kya pending hai?" },
    { id: "upm_flow", title: "UPM Open Queue", hint: "Assign due / submit due / running jobs", table: "rr_upm_dynamic_submit_history_v741", question: "UPM open queue aur submit due status summarize karo." },
    { id: "packing", title: "Packing Ready", hint: "Press ready and packing cards", rpc: "rr_fg_ready_packing_cards_v788", question: "Packing ready lots aur pending assignment summary batao." },
    { id: "webstore", title: "Webstore Stock", hint: "Saleable stock and low stock", table: "rr_universal_sale_lot_v849", question: "Webstore saleable stock aur low stock lots batao." },
    { id: "sales_return", title: "Sales / Return", hint: "CPI and returnable lines", table: "rr_fg_final_cpi_v787", question: "Sales CPI aur returns ka latest summary batao." },
    { id: "accounts", title: "Accounts / Costing", hint: "Voucher and costing result", table: "rr_costing_effective_result_v850", question: "Accounts costing aur voucher impact summary batao." },
    { id: "attendance", title: "Attendance / Workers", hint: "Worker salary and attendance", table: "rr_monthly_payroll_management_v779_5", question: "Attendance salary workers ka pending/payable summary batao." }
  ];
  let active = templates[0];

  const safe = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  const msg = (text, type = "") => { $("pageMessage").textContent = text || ""; $("pageMessage").className = `rr-message ${type}`.trim(); };

  async function requireAccess() {
    const { data, error } = await supabaseClient.auth.getSession();
    if (error || !data.session) {
      window.location.replace("real-login.html");
      throw new Error("Login required.");
    }
    const { data: profile, error: profileError } = await supabaseClient.from("rr_user_profiles").select("role_code,is_active").eq("auth_user_id", data.session.user.id).single();
    if (profileError || !profile?.is_active) throw new Error("Active user profile required.");
    $("ownerName").textContent = ["owner", "admin"].includes(profile.role_code) ? "SUPER ADMIN" : String(profile.role_code || "USER").toUpperCase();
  }

  function renderTemplates() {
    const q = $("reportSearch").value.trim().toLowerCase();
    const list = templates.filter((item) => !q || `${item.title} ${item.hint} ${item.question}`.toLowerCase().includes(q));
    $("templateList").innerHTML = list.map((item) => `<button class="rf-report-item" data-template="${safe(item.id)}">${safe(item.title)}<small>${safe(item.hint)}</small></button>`).join("") || '<p class="rr-muted">No matching report.</p>';
    document.querySelectorAll("[data-template]").forEach((button) => button.onclick = () => selectTemplate(button.dataset.template));
    $("suggestions").innerHTML = list.slice(0, 5).map((item) => `<button class="rf-chip" type="button" data-suggest="${safe(item.id)}">${safe(item.title)}</button>`).join("");
    document.querySelectorAll("[data-suggest]").forEach((button) => button.onclick = () => selectTemplate(button.dataset.suggest));
  }

  function selectTemplate(id) {
    active = templates.find((item) => item.id === id) || active;
    $("activeTitle").textContent = active.title;
    $("questionBox").value = active.question;
    loadTemplateRows();
  }

  function renderRows(rows) {
    if (!rows.length) {
      $("tableResult").innerHTML = '<p class="rr-muted">No rows found for this report.</p>';
      return;
    }
    const keys = [...new Set(rows.slice(0, 10).flatMap((row) => Object.keys(row || {})))].slice(0, 9);
    $("tableResult").innerHTML = `<div class="rf-table-wrap"><table class="rf-table"><thead><tr>${keys.map((key) => `<th>${safe(key.replaceAll("_", " ").toUpperCase())}</th>`).join("")}</tr></thead><tbody>${rows.map((row) => `<tr>${keys.map((key) => `<td>${safe(row[key] ?? "-")}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`;
  }

  async function loadTemplateRows() {
    msg("");
    try {
      let rows = [];
      if (active.rpc) {
        const { data, error } = await supabaseClient.rpc(active.rpc, { p_data_mode: "TEST" });
        if (error) throw error;
        rows = data || [];
      } else {
        const { data, error } = await supabaseClient.from(active.table).select("*").limit(50);
        if (error) throw error;
        rows = data || [];
      }
      renderRows(rows);
      msg(`${active.title} loaded.`, "success");
    } catch (error) {
      console.warn(error);
      $("tableResult").innerHTML = '<p class="rr-muted">Report backend source unavailable or permission blocked.</p>';
      msg(error.message || "Report load failed.", "error");
    }
  }

  async function askAi() {
    const question = $("questionBox").value.trim();
    if (!question) {
      msg("Question type karein.", "error");
      return;
    }
    $("askAiBtn").disabled = true;
    $("askAiBtn").textContent = "Generating...";
    $("reportResult").textContent = "";
    try {
      const { data, error } = await supabaseClient.functions.invoke("real-factory-ai", {
        body: { question, report_type: active.id, data_mode: "TEST", source: "REPORTS_V857" }
      });
      if (error) throw error;
      const answer = data?.answer || data?.text || data?.message || JSON.stringify(data, null, 2);
      $("reportResult").textContent = answer;
      msg("AI report generated.", "success");
    } catch (error) {
      console.warn(error);
      $("reportResult").textContent = "AI backend call failed. Template report data neeche loaded rahega.\n\n" + (error.message || String(error));
      msg("AI function unavailable or permission blocked.", "error");
    } finally {
      $("askAiBtn").disabled = false;
      $("askAiBtn").textContent = "Ask AI / Generate Report";
    }
  }

  $("reportSearch").addEventListener("input", renderTemplates);
  $("refreshBtn").addEventListener("click", loadTemplateRows);
  $("askAiBtn").addEventListener("click", askAi);
  $("logoutBtn").addEventListener("click", async () => {
    await supabaseClient.auth.signOut();
    window.location.replace("real-login.html");
  });

  document.addEventListener("DOMContentLoaded", async () => {
    try {
      await requireAccess();
      renderTemplates();
      selectTemplate(active.id);
    } catch (error) {
      console.error(error);
      msg(error.message || "Reports page failed.", "error");
    }
  });
})();
