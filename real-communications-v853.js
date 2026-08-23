(() => {
  const ownerName = document.getElementById("ownerName");
  const logoutBtn = document.getElementById("logoutBtn");
  const refreshBtn = document.getElementById("refreshBtn");
  const statusFilter = document.getElementById("statusFilter");
  const messageList = document.getElementById("messageList");
  const rowCount = document.getElementById("rowCount");
  const pageMessage = document.getElementById("pageMessage");

  const OUTBOX_TABLE = "rr_comm_outbox_v853";
  const MARK_OPENED_RPC = "rr_comm_mark_whatsapp_opened_v853";

  function setMessage(text, type = "") {
    pageMessage.textContent = text || "";
    pageMessage.className = `rr-message ${type}`.trim();
  }

  function safeText(value) {
    return String(value ?? "").replace(/[&<>"']/g, (char) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;"
    }[char]));
  }

  function firstValue(row, keys, fallback = "") {
    for (const key of keys) {
      const value = row?.[key];
      if (value !== null && value !== undefined && String(value).trim() !== "") return value;
    }
    return fallback;
  }

  function normalizePhone(value) {
    const digits = String(value || "").replace(/\D/g, "");
    if (!digits) return "";
    if (digits.length === 10) return `91${digits}`;
    return digits;
  }

  function buildWhatsappUrl(row) {
    const existingUrl = firstValue(row, ["whatsapp_url", "wa_url", "link_url"]);
    if (existingUrl && /^https:\/\/wa\.me\//i.test(existingUrl)) return existingUrl;
    const phone = normalizePhone(firstValue(row, [
      "recipient_mobile", "mobile", "phone", "phone_no", "recipient_phone", "receiver_phone", "customer_phone", "whatsapp_number"
    ]));
    const text = firstValue(row, ["message", "message_text", "message_body", "body", "content", "whatsapp_message"]);
    if (!phone || !text) return "";
    return `https://wa.me/${phone}?text=${encodeURIComponent(text)}`;
  }

  function messageBody(row) {
    return firstValue(row, ["message", "message_text", "message_body", "body", "content", "whatsapp_message"], "No message text found.");
  }

  function recipientLabel(row) {
    return firstValue(row, ["customer_name", "party_name", "receiver_name", "recipient_name", "name", "recipient_mobile", "mobile", "phone", "recipient_phone"], "Recipient");
  }

  async function requireOwner() {
    const { data, error } = await supabaseClient.auth.getSession();
    if (error || !data.session) {
      window.location.replace("real-login.html");
      throw new Error("Login required.");
    }
    const { data: profile, error: profileError } = await supabaseClient
      .from("rr_user_profiles").select("role_code, is_active")
      .eq("auth_user_id", data.session.user.id).single();
    if (profileError || !profile?.is_active || !["owner", "admin"].includes(profile.role_code)) {
      await supabaseClient.auth.signOut();
      window.location.replace("real-login.html");
      throw new Error("Owner/Admin access required.");
    }
    ownerName.textContent = "SUPER ADMIN";
  }

  async function markOpened(messageId) {
    const { error } = await supabaseClient.rpc(MARK_OPENED_RPC, { p_message_id: messageId });
    if (error) throw error;
  }

  async function openWhatsapp(row) {
    const id = firstValue(row, ["id", "message_id", "outbox_id"]);
    const url = buildWhatsappUrl(row);
    if (!id) throw new Error("Message ID missing in outbox row.");
    if (!url) throw new Error("WhatsApp number/message missing in outbox row.");
    const popup = window.open(url, "_blank", "noopener,noreferrer");
    if (!popup) window.location.href = url;
    try { await markOpened(id); } catch (error) { console.warn(error); }
    setMessage("WhatsApp opened. Send button manually press karna hoga.", "success");
    await loadMessages();
  }

  function renderMessages(rows) {
    rowCount.textContent = `${rows.length} rows`;
    if (!rows.length) {
      messageList.innerHTML = '<p class="rr-muted">No outbox messages found.</p>';
      return;
    }
    messageList.innerHTML = rows.map((row, index) => {
      const id = safeText(firstValue(row, ["id", "message_id", "outbox_id"], `row-${index}`));
      const status = safeText(firstValue(row, ["send_status", "status", "delivery_status"], "READY"));
      const phone = safeText(firstValue(row, ["recipient_mobile", "mobile", "phone", "recipient_phone", "customer_phone"], ""));
      const created = safeText(firstValue(row, ["created_at", "inserted_at", "queued_at"], ""));
      return `<article class="rf-comm-card" data-message-index="${index}">
        <div class="rf-comm-head"><div class="rf-comm-title"><strong>${safeText(recipientLabel(row))}</strong><span>${phone}${phone && created ? " - " : ""}${created}</span></div><span class="rf-comm-status">${status}</span></div>
        <p class="rf-comm-text">${safeText(messageBody(row))}</p>
        <div class="rf-comm-card-actions"><button class="rr-btn rr-btn-primary" type="button" data-open-message="${id}">Open WhatsApp</button></div>
      </article>`;
    }).join("");

    messageList.querySelectorAll("[data-open-message]").forEach((button) => {
      button.addEventListener("click", async () => {
        const card = button.closest("[data-message-index]");
        const row = rows[Number(card.dataset.messageIndex)];
        button.disabled = true; button.textContent = "Opening..."; setMessage("");
        try { await openWhatsapp(row); }
        catch (error) { console.error(error); setMessage(error.message || "WhatsApp open failed.", "error"); }
        finally { button.disabled = false; button.textContent = "Open WhatsApp"; }
      });
    });
  }

  async function loadMessages() {
    setMessage(""); refreshBtn.disabled = true; refreshBtn.textContent = "Loading...";
    try {
      const selectedStatus = statusFilter.value;
      let query = supabaseClient.from(OUTBOX_TABLE).select("*").order("created_at", { ascending: false }).limit(50);
      if (selectedStatus) query = query.eq("send_status", selectedStatus);
      const { data, error } = await query;
      if (error) throw error;
      renderMessages(data || []);
    } catch (error) {
      console.error(error); rowCount.textContent = "Error";
      messageList.innerHTML = '<p class="rr-muted">Outbox data could not load.</p>';
      setMessage(error.message || "Outbox load failed.", "error");
    } finally { refreshBtn.disabled = false; refreshBtn.textContent = "Refresh"; }
  }

  logoutBtn.addEventListener("click", async () => { await supabaseClient.auth.signOut(); window.location.replace("real-login.html"); });
  refreshBtn.addEventListener("click", loadMessages);
  statusFilter.addEventListener("change", loadMessages);

  (async () => {
    try { await requireOwner(); await loadMessages(); }
    catch (error) { console.error(error); setMessage(error.message || "Access failed.", "error"); }
  })();
})();