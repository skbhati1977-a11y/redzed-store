(() => {
  "use strict";
  const query = new URLSearchParams(location.search);
  if (String(query.get("rr_partner_mode") || "").toUpperCase() !== "CUSTOMER")
    return;
  if (window.__RR_PARTNER_SENDER_WINDOW_V82__) return;
  window.__RR_PARTNER_SENDER_WINDOW_V82__ = true;

  const customerId = query.get("customer") || query.get("customer_id") || "";
  const rawRpc = RF853.rpc.bind(RF853);
  const SESSION_KEY = "rr_customer_secure_session_v9592";
  const DEVICE_KEY = "rr_customer_device_v9592";
  const RETURN_KEY = "rr_partner_chat_return_v82";
  let workspace = null;
  let core = null;
  let latestCollection = null;

  function setText(node, value) {
    if (node && node.textContent !== value) node.textContent = value;
  }

  function setHtml(node, value) {
    if (node && node.innerHTML !== value) node.innerHTML = value;
  }

  function device() {
    let value = localStorage.getItem(DEVICE_KEY);
    if (!value) {
      const bytes = new Uint8Array(24);
      crypto.getRandomValues(bytes);
      value = [...bytes]
        .map((item) => item.toString(16).padStart(2, "0"))
        .join("");
      localStorage.setItem(DEVICE_KEY, value);
    }
    return value;
  }

  function auth() {
    let saved = null;
    try {
      saved = JSON.parse(localStorage.getItem(SESSION_KEY) || "null");
    } catch (_) {}
    if (!saved?.session_token)
      throw Error("Valid distributor login से collection भेजें.");
    return {
      p_session_token: saved.session_token,
      p_device_id: device(),
    };
  }

  async function context() {
    if (!workspace)
      workspace = await rawRpc("rr_market_partner_workspace_v67", auth());
    if (!core)
      core = await rawRpc("rr_market_partner_sender_core_views_v81", {
        ...auth(),
        p_partner_customer_id: customerId,
      });
    const customer = (workspace.customers || []).find(
      (item) => String(item.id) === String(customerId),
    );
    if (!customer || customer.status !== "ACTIVE")
      throw Error("Distributor customer relation is unavailable.");
    return { customer, workspace, core };
  }

  function sentLots() {
    const sent = new Set();
    (core?.views || []).forEach((item) =>
      (item.view?.rows || []).forEach((line) => {
        const lot = String(line.lot_no || "").trim().toUpperCase();
        if (lot) sent.add(lot);
      }),
    );
    return sent;
  }

  function numeric(id, fallback = 0) {
    return Math.max(
      0,
      Number(document.getElementById(id)?.value ?? fallback ?? 0) || 0,
    );
  }

  async function requirementDetail(requirementId) {
    const { customer, workspace: data } = await context();
    const order = (data.orders || []).find(
      (item) => String(item.id) === String(requirementId),
    );
    if (!order) throw Error("Requirement is unavailable.");
    return {
      id: order.id,
      customer_name: customer.name,
      lines: (order.lines || []).map((line) => ({
        id: line.id,
        lot_no: line.lot_no,
        requested_qty: Number(line.requested_qty || 0),
        accepted_qty: Number(line.requested_qty || 0),
        card: {
          category: line.category,
          size_text: line.size_text,
          primary_image_url: line.image_url,
          media: line.image_url ? [{ image_url: line.image_url }] : [],
        },
      })),
    };
  }

  async function mappedRpc(name, args = {}) {
    if (name === "rr_web_window_cards_v9329") {
      await context();
      const rows = await rawRpc("rr_market_partner_cards_v67", {
        ...auth(),
        p_search: args.p_search || null,
      });
      const used = sentLots();
      return (Array.isArray(rows) ? rows : []).filter(
        (row) => !used.has(String(row.lot_no || "").trim().toUpperCase()),
      );
    }

    if (name === "rr_market_create_share_v9420") {
      const { customer } = await context();
      const margin = numeric("rrPartnerMargin82", customer.margin);
      const discount = numeric("rrPartnerDiscount82", customer.discount);
      latestCollection = await rawRpc(
        "rr_market_partner_collection_priced_create_v67",
        {
          ...auth(),
          p_partner_customer_id: customerId,
          p_lines: (args.p_lots || []).map((lot) => ({
            lot_no: lot,
            margin_amount: margin,
            discount_amount: discount,
          })),
        },
      );
      core = null;
      return latestCollection;
    }

    if (
      name === "rr_chat_send_staff_v9433" ||
      name === "rr_chat_staff_upload_v9434"
    ) {
      if (!latestCollection?.collection_id)
        throw Error("Collection context missing. Select samples again.");
      const { workspace: data } = await context();
      const owner = String(data.owner_name || "Distributor")
        .replace(/\s+DISTRIBUTOR$/i, "")
        .trim();
      const privateBody = String(
        args.p_body ||
          `${latestCollection.collection_display_no || "COLLECTION"} · Open collection`,
      ).replace(/REDZED(?:\s+COLLECTION)?/gi, `${owner} DISTRIBUTOR COLLECTION`);
      const result = await rawRpc(
        "rr_market_partner_collection_chat_upsert_v82",
        {
          ...auth(),
          p_partner_customer_id: customerId,
          p_collection_id: latestCollection.collection_id,
          p_body: privateBody,
        },
      );
      sessionStorage.setItem(
        RETURN_KEY,
        JSON.stringify({ mode: "CUSTOMER", customer: customerId, at: Date.now() }),
      );
      return result;
    }

    if (name === "rr_chat_staff_inbox_v9434") {
      const { customer, workspace: data } = await context();
      return [
        {
          chat_id: `t67-customer-${customerId}`,
          customer_id: customerId,
          customer_name: `${data.owner_name || "Distributor"} DISTRIBUTOR ↔ ${customer.group_name || `${customer.name} GROUP`}`,
          mobile: customer.mobile || "",
        },
      ];
    }

    if (name === "rr_chat_requirement_detail_v9508")
      return requirementDetail(args.p_requirement_id);

    return rawRpc(name, args);
  }

  RF853.rpc = mappedRpc;

  function injectPricing() {
    if (document.getElementById("rrPartnerPricing82")) return;
    const host = document.querySelector(".rf-shell .card .ww-top");
    if (!host) return;
    const box = document.createElement("div");
    box.id = "rrPartnerPricing82";
    box.innerHTML =
      '<label>Margin ₹<input id="rrPartnerMargin82" type="number" min="0" value="0"></label><label>Customer Discount ₹<input id="rrPartnerDiscount82" type="number" min="0" value="0"></label>';
    host.after(box);
    const style = document.createElement("style");
    style.id = "rrPartnerPricingCss82";
    style.textContent = `
      #rrPartnerPricing82{display:grid;grid-template-columns:1fr 1fr;gap:8px;padding:9px;margin-top:8px;border:1px solid #40516a;border-radius:12px;background:#101923;position:sticky;top:0;z-index:20}
      #rrPartnerPricing82 label{display:grid;gap:4px;font-size:12px;font-weight:900;color:#aeb9c7}
      #rrPartnerPricing82 input{width:100%;padding:10px;border:1px solid #43536b;border-radius:9px;background:#0c141e;color:#fff;font-size:16px}
      @media(max-width:760px){.ww-grid{grid-template-columns:repeat(2,minmax(0,1fr))!important}.ww-grid .ww-card{min-width:0}}
    `;
    document.head.appendChild(style);
    context()
      .then(({ customer }) => {
        document.getElementById("rrPartnerMargin82").value = Number(
          customer.margin || 0,
        );
        document.getElementById("rrPartnerDiscount82").value = Number(
          customer.discount || 0,
        );
      })
      .catch(() => {});
    const view = document.getElementById("viewCols");
    if (view) {
      view.value = "2";
      view.dispatchEvent(new Event("change", { bubbles: true }));
    }
  }

  function lockPartnerWindow() {
    const dataMode = document.getElementById("dataMode");
    if (dataMode) {
      dataMode.value = "TEST";
      dataMode.disabled = true;
      dataMode.closest(".rf-actions")?.classList.add("rrPartnerActions82");
    }
    const dashboard = document.querySelector('.rf-actions a[href*="real-dashboard"]');
    if (dashboard) {
      setText(dashboard, "← CHAT");
      dashboard.href = `real-sales-live-chat-v9434.html?rr_partner_mode=CUSTOMER&customer=${encodeURIComponent(customerId)}&from=distributor`;
    }
    const title = document.querySelector(".rf-brand h1");
    setText(title, "Distributor Collection");
    const subtitle = document.querySelector(".rf-brand .muted");
    setText(
      subtitle,
      "Fresh samples only · thumbnail, category, size and photos",
    );
    document.querySelector(".ww-bucket")?.classList.add("rrPartnerHidden82");
    const bucket = document.getElementById("bucketBtn");
    if (bucket) bucket.style.display = "none";
    if (!document.getElementById("rrPartnerWindowCss82")) {
      const style = document.createElement("style");
      style.id = "rrPartnerWindowCss82";
      style.textContent =
        ".rrPartnerHidden82{display:none!important}.rrPartnerActions82 select{display:none!important}.ww-actions{display:none!important}.sharebar.chat-mode{padding-bottom:calc(8px + env(safe-area-inset-bottom))}";
      document.head.appendChild(style);
    }
  }

  function tuneCards() {
    document.querySelectorAll(".ww-card .cap div").forEach((line) => {
      if (!/^📦\s*AVL/i.test(line.textContent || "")) return;
      const card = line.closest(".ww-card");
      const lot = card?.dataset.card;
      const row = window.__rrPartnerRows82?.find(
        (item) => String(item.lot_no) === String(lot),
      );
      const available = Number(row?.available_qty || 0);
      setHtml(
        line,
        available <= 0
          ? "📦 OUT OF STOCK"
          : String(row?.stock_status || "").toUpperCase() === "LOW_STOCK"
            ? "📦 LOW STOCK"
            : "📦 STOCK-IN",
      );
    });
  }

  const original = RF853.rpc;
  RF853.rpc = async (name, args = {}) => {
    const result = await original(name, args);
    if (name === "rr_web_window_cards_v9329")
      window.__rrPartnerRows82 = Array.isArray(result) ? result : [];
    return result;
  };

  sessionStorage.setItem(
    RETURN_KEY,
    JSON.stringify({ mode: "CUSTOMER", customer: customerId, at: Date.now() }),
  );
  lockPartnerWindow();
  injectPricing();
  new MutationObserver(() => {
    lockPartnerWindow();
    injectPricing();
    tuneCards();
  }).observe(document.documentElement, { childList: true, subtree: true });
})();
