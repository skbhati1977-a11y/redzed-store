(() => {
  "use strict";

  const RETURN_KEY = "rr_partner_chat_return_v82";
  const query = new URLSearchParams(location.search);
  let mode = String(query.get("rr_partner_mode") || "").toUpperCase();
  const remembered = (() => {
    try {
      return JSON.parse(sessionStorage.getItem(RETURN_KEY) || "null");
    } catch (_) {
      return null;
    }
  })();

  if (!mode && remembered?.mode && Date.now() - Number(remembered.at || 0) < 900000) {
    sessionStorage.removeItem(RETURN_KEY);
    const target = new URL(location.href);
    target.searchParams.set("rr_partner_mode", remembered.mode);
    target.searchParams.set("from", "distributor");
    if (remembered.customer)
      target.searchParams.set("customer", remembered.customer);
    location.replace(target.href);
    return;
  }
  if (!['CUSTOMER', 'REDZED'].includes(mode)) return;
  if (window.__RR_PARTNER_STAFF_CHAT_ADAPTER_V82__) return;
  window.__RR_PARTNER_STAFF_CHAT_ADAPTER_V82__ = true;
  // The direct staff page installs its own exit-oriented history handler.
  // Partner mode owns Back so overlays close first and then returns to the
  // distributor directory without ever exiting the browser tab.
  window.__RR_SALES_CHAT_BACK_NAV_V9478__ = true;
  window.__RR_MOBILE_BACK_STEP_TEST67__ = true;

  const customerId = query.get("customer") || "";
  const rawRpc = RF853.rpc.bind(RF853);
  const rawFrom = supabaseClient.from.bind(supabaseClient);
  const SESSION_KEY = "rr_customer_secure_session_v9592";
  const DEVICE_KEY = "rr_customer_device_v9592";
  const attachmentCache = new Map();
  const collectionPreviewCache = new Map();
  const profile = {
    id: "test67-distributor",
    full_name: "DISTRIBUTOR",
    role_code: "DISTRIBUTOR",
    is_active: true,
    access_status: "ACTIVE",
  };
  let workspace = null;
  let workspaceAt = 0;
  let activeRequirementId = "";
  let didAutoOpen = false;

  const $ = (id) => document.getElementById(id);
  const setText = (node, value) => {
    if (node && node.textContent !== value) node.textContent = value;
  };
  const esc = (value) =>
    String(value ?? "").replace(
      /[&<>"']/g,
      (char) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#039;",
        })[char],
    );

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

  function authArgs() {
    let saved = null;
    try {
      saved = JSON.parse(localStorage.getItem(SESSION_KEY) || "null");
    } catch (_) {}
    if (!saved?.session_token)
      throw Error("Valid distributor login से यह chat खोलें.");
    return {
      p_session_token: saved.session_token,
      p_device_id: device(),
    };
  }

  async function state(force = false) {
    if (!force && workspace && Date.now() - workspaceAt < 1200)
      return workspace;
    const base = authArgs();
    const [nextWorkspace, piState] = await Promise.all([
      rawRpc("rr_market_partner_workspace_v67", base),
      rawRpc("rr_market_partner_customer_pi_state_v67", base).catch(() => []),
    ]);
    const piByOrder = new Map(
      (Array.isArray(piState) ? piState : []).map((item) => [String(item.order_id), item]),
    );
    workspace = nextWorkspace || {};
    workspace.orders = (workspace.orders || []).map((order) => {
      const pi = piByOrder.get(String(order.id));
      if (!pi) return order;
      const lines = new Map((pi.lines || []).map((line) => [String(line.id), line]));
      return {
        ...order,
        ...pi,
        lines: (order.lines || []).map((line) => ({
          ...line,
          ...(lines.get(String(line.id)) || {}),
        })),
      };
    });
    workspaceAt = Date.now();
    const owner = String(workspace?.owner_name || "Distributor").trim();
    profile.full_name = owner;
    profile.id = workspace?.owner_customer_id || profile.id;
    return workspace;
  }

  function selectedCustomer(data = workspace) {
    return (data?.customers || []).find(
      (item) => String(item.id) === String(customerId),
    );
  }

  function syntheticChatId() {
    return mode === "CUSTOMER"
      ? `t67-customer-${customerId}`
      : `t67-redzed-${workspace?.owner_customer_id || "owner"}`;
  }

  function lane(channel) {
    if (mode === "REDZED") return "REDZED";
    return channel === "SUPERADMIN_PRIVATE"
      ? "CUSTOMER_DIRECT"
      : "CUSTOMER_GROUP";
  }

  function relationTitle(data = workspace) {
    const owner = String(data?.owner_name || "Distributor")
      .replace(/\s+DISTRIBUTOR$/i, "")
      .trim()
      .toUpperCase();
    if (mode === "REDZED") return `REDZED ↔ ${owner} DISTRIBUTOR`;
    const customer = selectedCustomer(data);
    const group = String(
      customer?.group_name || `${customer?.name || "CUSTOMER"} GROUP`,
    )
      .trim()
      .toUpperCase();
    const ownerShort = owner.split(/\s+/)[0] || "DISTRIBUTOR";
    const customerShort = group.replace(/\s+GROUP$/i, "").trim().split(/\s+/)[0] || "CUSTOMER";
    return `${ownerShort} ${customerShort} GROUP`;
  }

  function distributorLabel(name) {
    const clean = String(name || "Distributor")
      .replace(/\s+DISTRIBUTOR$/i, "")
      .trim();
    return `${clean || "Distributor"} DISTRIBUTOR`;
  }

  function rememberReturn() {
    sessionStorage.setItem(
      RETURN_KEY,
      JSON.stringify({ mode, customer: customerId || null, at: Date.now() }),
    );
  }

  function normalizeMessages(rows) {
    const data = workspace || {};
    const owner = String(data.owner_name || "Distributor").trim();
    const customer = selectedCustomer(data);
    return (Array.isArray(rows) ? rows : [])
      .map((message) => {
        const attachment = message.attachment || null;
        if (attachment?.attachment_id)
          attachmentCache.set(String(attachment.attachment_id), attachment);
        const actor = String(message.actor || "").toUpperCase();
        const sender =
          actor === "CUSTOMER"
            ? customer?.name || "Customer"
            : actor === "REDZED"
              ? "REDZED"
              : owner;
        return {
          id: message.id,
          channel:
            lane("SUPERADMIN_PRIVATE") === "CUSTOMER_DIRECT" &&
            actor === "CUSTOMER_DIRECT"
              ? "SUPERADMIN_PRIVATE"
              : undefined,
          sender_name: sender,
          message_type: attachment
            ? String(attachment.type || "").startsWith("audio/")
              ? "VOICE"
              : "ATTACHMENT"
            : "TEXT",
          body: message.message || null,
          payload: attachment
            ? {
                attachment_id: attachment.attachment_id,
                file_name: attachment.name,
                mime_type: attachment.type,
                byte_size: attachment.byte_size,
              }
            : {},
          reply_to_message_id: null,
          created_at: message.created_at,
        };
      })
      .sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  }

  async function partnerRpc(name, args = {}) {
    const data = await state();
    const base = authArgs();
    const customer = selectedCustomer(data);

    if (name === "rr_chat_staff_inbox_v9434") {
      if (mode === "CUSTOMER" && (!customer || customer.status !== "ACTIVE"))
        return [];
      return [
        {
          chat_id: syntheticChatId(),
          customer_id: mode === "CUSTOMER" ? customerId : null,
          customer_name: relationTitle(data),
          mobile: mode === "CUSTOMER" ? customer?.mobile || "" : "",
          last_message:
            mode === "CUSTOMER"
              ? "Private distributor/customer journey"
              : "Private REDZED/distributor journey",
          can_private_chat: mode === "CUSTOMER",
        },
      ];
    }

    if (
      name === "rr_chat_staff_messages_v9434" ||
      name === "rr_chat_staff_messages_v9479"
    ) {
      const rows = await rawRpc("rr_market_partner_chat_messages_v67", {
        ...base,
        p_lane: lane(args.p_channel),
        p_partner_customer_id: mode === "CUSTOMER" ? customerId : null,
      });
      return normalizeMessages(rows);
    }

    if (
      name === "rr_chat_send_staff_v9433" ||
      name === "rr_chat_send_staff_v9479"
    ) {
      return rawRpc("rr_market_partner_chat_send_v67", {
        ...base,
        p_lane: lane(args.p_channel),
        p_partner_customer_id: mode === "CUSTOMER" ? customerId : null,
        p_message: args.p_body || null,
        p_attachment: null,
      });
    }

    if (
      name === "rr_chat_staff_upload_v9434" ||
      name === "rr_chat_staff_upload_v9479"
    ) {
      return rawRpc("rr_market_partner_chat_send_v67", {
        ...base,
        p_lane: lane(args.p_channel),
        p_partner_customer_id: mode === "CUSTOMER" ? customerId : null,
        p_message: args.p_body || null,
        p_attachment: {
          name: args.p_file_name || "attachment",
          type: args.p_mime_type || "application/octet-stream",
          data_url: `data:${args.p_mime_type || "application/octet-stream"};base64,${args.p_base64 || ""}`,
        },
      });
    }

    if (name === "rr_chat_staff_attachment_v9434") {
      const attachmentId = String(args.p_attachment_id || "");
      let attachment = attachmentCache.get(attachmentId);
      // Message lists intentionally return attachment metadata without the
      // (potentially large) data URL. Fetch the bytes only when the user opens
      // the attachment or the PDF preview asks for them.
      if (!attachment?.data_url) {
        const loaded = await rawRpc("rr_market_partner_chat_attachment_v67", {
          ...base,
          p_lane: lane(args.p_channel || "GROUP"),
          p_partner_customer_id: mode === "CUSTOMER" ? customerId : null,
          p_attachment_id: attachmentId,
        });
        if (loaded?.base64) {
          attachment = {
            ...(attachment || {}),
            name: loaded.file_name || attachment?.name || "attachment",
            type:
              loaded.mime_type ||
              attachment?.type ||
              "application/octet-stream",
            data_url: `data:${loaded.mime_type || attachment?.type || "application/octet-stream"};base64,${loaded.base64}`,
          };
          attachmentCache.set(attachmentId, attachment);
        }
      }
      if (!attachment?.data_url) throw Error("Attachment is unavailable.");
      return {
        file_name: attachment.name || "attachment",
        mime_type: attachment.type || "application/octet-stream",
        base64: String(attachment.data_url).split(",")[1] || "",
      };
    }

    if (name === "rr_chat_group_members_v9433") {
      if (mode === "REDZED")
        return [
          {
            profile_id: "redzed",
            member_name: "REDZED",
            can_private_chat: false,
          },
          {
            profile_id: data.owner_customer_id || "distributor",
            member_name: distributorLabel(data.owner_name),
            can_private_chat: false,
          },
        ];
      return [
        {
          profile_id: data.owner_customer_id || "distributor",
          member_name: distributorLabel(data.owner_name),
          can_private_chat: true,
        },
        ...(data.staff || [])
          .filter((member) => member.status === "ACTIVE")
          .map((member) => ({
            profile_id: member.id,
            member_name: member.name,
            can_private_chat: false,
          })),
        {
          profile_id: customer?.id || "customer",
          member_name: customer?.name || "Customer",
          can_private_chat: false,
        },
      ];
    }

    if (name === "rr_chat_staff_start_call_v9434")
      return { mobile: mode === "CUSTOMER" ? customer?.mobile || null : null };

    if (name === "rr_chat_requirement_detail_v9508") {
      const fresh = await state(true);
      const order = (fresh.orders || []).find(
        (item) => String(item.id) === String(args.p_requirement_id),
      );
      if (!order) throw Error("Requirement is unavailable in this relation.");
      return {
        id: order.id,
        requirement_no: order.requirement_display_no || order.order_ref,
        customer_name: selectedCustomer(fresh)?.name || "Customer",
        message: `Linked ${order.collection_display_no || "collection"}`,
        lines: (order.lines || []).map((line) => ({
          id: line.id,
          lot_no: line.lot_no,
          requested_qty: Number(line.requested_qty || 0),
          accepted_qty: Number(line.requested_qty || 0),
          card: {
            category: line.category,
            item_name: line.article_name,
            size_text: line.size_text,
            primary_image_url: line.image_url,
            media: line.image_url ? [{ image_url: line.image_url }] : [],
          },
        })),
      };
    }

    if (
      name === "rr_chat_internal_docs_for_chat_v9497" ||
      name === "rr_chat_staff_directory_v9434"
    )
      return [];

    if (name === "rr_chat_set_member_v9433")
      throw Error("Staff membership distributor directory से manage करें.");

    return rawRpc(name, args);
  }

  RF853.rpc = partnerRpc;

  supabaseClient.auth.getSession = async () => ({
    data: { session: { user: { id: profile.id } } },
    error: null,
  });
  supabaseClient.from = (table) => {
    if (table !== "rr_user_profiles") return rawFrom(table);
    const chain = {
      select() {
        return chain;
      },
      eq() {
        return chain;
      },
      single: async () => ({ data: profile, error: null }),
    };
    return chain;
  };

  function flash(message, bad = false) {
    const node = $("flash");
    if (!node) return;
    node.textContent = message;
    node.style.color = bad ? "#ffb6bc" : "#fff";
    node.style.display = "block";
    clearTimeout(flash.timer);
    flash.timer = setTimeout(() => (node.style.display = "none"), 2600);
  }

  function actionCss() {
    if ($("rrPartnerChatCss82")) return;
    const style = document.createElement("style");
    style.id = "rrPartnerChatCss82";
    style.textContent = `
      .rrPartnerMetrics82{display:grid;grid-template-columns:repeat(4,1fr);gap:6px;padding:7px 8px;border-bottom:1px solid #293343;background:#0c131c}
      .rrPartnerMetric82{min-width:0;padding:7px 4px;border:1px solid #33465c;border-radius:10px;text-align:center;background:#121d2a}
      .rrPartnerMetric82 small,.rrPartnerMetric82 b{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .rrPartnerMetric82 small{font-size:9px;color:#9facbd;font-weight:900}.rrPartnerMetric82 b{font-size:13px;margin-top:3px}
      .rrPartnerDock82{position:fixed;left:320px;right:0;bottom:70px;z-index:10018;display:grid;grid-template-columns:repeat(3,1fr);gap:7px;padding:8px;background:#0b0f15eF;border-top:1px solid #334154}
      .rrPartnerDock82 button{min-height:48px;border:1px solid #43536b;border-radius:11px;background:#182535;color:#fff;font-weight:900}.rrPartnerDock82 button:first-child{background:#197d51}.rrPartnerDock82 button:last-child{background:#167bc0}
      .rrPartnerSheet82{position:fixed;inset:0;z-index:10180;display:none;align-items:flex-end;background:#000c}.rrPartnerSheet82.on{display:flex}
      .rrPartnerCard82{width:min(760px,100%);max-height:88dvh;overflow:auto;background:#10161f;border:1px solid #43536b;border-radius:20px 20px 0 0;color:#fff}
      .rrPartnerHead82{position:sticky;top:0;z-index:2;display:flex;align-items:center;gap:8px;padding:11px;background:#10161f;border-bottom:1px solid #334154}.rrPartnerHead82 b{flex:1}.rrPartnerHead82 button{width:44px;height:44px}
      .rrPartnerBody82{padding:10px}.rrPartnerOrder82{border:1px solid #35475d;border-radius:13px;padding:11px;margin-bottom:9px;background:#131d29}.rrPartnerOrder82 small{display:block;color:#a2afbf;margin:3px 0 8px}
      .rrPartnerLine82{display:grid;grid-template-columns:1fr 84px;gap:7px;align-items:center;padding:7px 0;border-top:1px solid #2b394a}.rrPartnerLine82 input,.rrPartnerLine82 select{width:100%;padding:8px;background:#0c141e;color:#fff;border:1px solid #43536b;border-radius:8px}
      .rrPartnerOrder82>button{width:100%;min-height:44px;margin-top:8px;border:1px solid #49647f;border-radius:10px;background:#176ca8;color:#fff;font-weight:900}
      .rrPartnerOrder82>button.good{background:#197d51}.rrPartnerEmpty82{padding:28px 10px;text-align:center;color:#9ba9ba}
      .rrPartnerDelete82{display:block;margin-top:7px;border:1px solid #76505a;background:#2b171c;color:#ffbec7;border-radius:7px;padding:5px 8px;font-size:10px;font-weight:900}
      .rrPartnerPiMessage82 img,.rrPartnerPiMessage82 .fsattbtn,.rrPartnerPiMessage82 .attimg,.rrPartnerPiMessage82 .rrMediaThumb9664,.rrPartnerPiMessage82 .rrAutoImg9651{display:none!important}
      .rrPartnerLivePiShell82{position:relative;width:100%;aspect-ratio:210/297;margin:0 0 8px;border:1px solid #52657d;border-radius:12px;overflow:hidden;background:#fff;cursor:pointer}
      .rrPartnerLivePiPreview82{display:block;width:100%;height:100%;border:0;background:#fff;pointer-events:none}
      .rrPartnerPiViewer82{position:fixed;inset:0;z-index:2147483500;display:flex;align-items:flex-start;justify-content:center;padding:54px 8px 12px;background:#05080df2;touch-action:none;transition:opacity .18s ease}
      .rrPartnerPiViewer82 iframe{width:min(100%,760px);height:calc(100dvh - 70px);border:0;border-radius:12px;background:#fff;pointer-events:auto;transition:transform .18s ease}
      .rrPartnerPiViewerClose82{position:fixed;right:12px;top:8px;z-index:2147483502;width:42px;height:42px;border:1px solid #64748b;border-radius:50%;background:#111c;color:#fff;font-size:25px}
      .rrPartnerPiSwipe82{position:absolute;inset:0;z-index:2147483501;touch-action:none;cursor:grab}
      .chat.partner82 .msgs{padding-bottom:160px!important}.attach button[data-pick="internal"]{display:none!important}
      @media(max-width:760px){.rrPartnerDock82{left:0}.rrPartnerMetrics82{grid-template-columns:repeat(4,minmax(0,1fr))}.rrPartnerMetric82 small{font-size:8px}.rrPartnerMetric82 b{font-size:12px}}
    `;
    document.head.appendChild(style);
  }

  function sheet() {
    if ($("rrPartnerSheet82")) return;
    document.body.insertAdjacentHTML(
      "beforeend",
      '<div id="rrPartnerSheet82" class="rrPartnerSheet82"><section class="rrPartnerCard82"><div class="rrPartnerHead82"><b id="rrPartnerSheetTitle82">Journey</b><button id="rrPartnerSheetClose82">×</button></div><div id="rrPartnerSheetBody82" class="rrPartnerBody82"></div></section></div>',
    );
    $("rrPartnerSheetClose82").onclick = closeSheet;
    $("rrPartnerSheet82").onclick = (event) => {
      if (event.target === $("rrPartnerSheet82")) closeSheet();
    };
  }

  function openSheet(title, body) {
    sheet();
    $("rrPartnerSheetTitle82").textContent = title;
    $("rrPartnerSheetBody82").innerHTML = body;
    $("rrPartnerSheet82").classList.add("on");
    history.pushState({ rrPartnerSheet82: true }, "", location.href);
  }

  function closeSheet() {
    $("rrPartnerSheet82")?.classList.remove("on");
  }

  function statusText(order) {
    return (
      {
        DRAFT: "REQUIREMENT RECEIVED",
        READY: "ACTION PENDING",
        CONSOLIDATION_QUEUED: "ADDED TO CONSOLIDATED LIST",
        BATCHED: "SENT TO REDZED",
        PI_PROPOSED: "REDZED PI RECEIVED",
        CONFIRMED: "PI CONFIRMED",
        PARTIAL_CONFIRMED: "PI PARTIAL",
        CI_FINAL: "CI READY",
        CLOSED: "CLOSED",
      }[order.status] || order.status || ""
    );
  }

  function numberedLabel(displayNo, fallback) {
    const text = String(displayNo || fallback || "").trim();
    const match = text.match(/^(COLLECTION|REQUIREMENT)\s+(\d+)(?:\s*·\s*UPDATE\s+(\d+))?/i);
    if (!match) return { title: text || fallback, detail: "" };
    return {
      title: `${match[1].toUpperCase()} ${match[2]}${match[3] ? ` · UPDATE ${match[3]}` : ""}`,
      detail: `${match[1].toUpperCase()} NO. ${match[2]} · UPDATE NO. ${match[3] || 0}`,
    };
  }

  function lineRows(order, editable = false, confirm = false) {
    return (order.lines || [])
      .map((line) => {
        const quantity = Number(
          line.distributor_pi_qty ??
            line.proposed_qty ??
            line.requested_qty ??
            0,
        );
        const control = confirm
          ? `<span><select data-confirm-action="${esc(line.id)}"><option value="CONFIRM">Confirm</option><option value="CHANGE">Change</option><option value="CANCEL">Cancel</option></select><input data-confirm-qty="${esc(line.id)}" type="number" min="0" value="${quantity}"></span>`
          : editable
            ? `<input data-pi-qty="${esc(line.id)}" type="number" min="0" value="${quantity}">`
            : `<b>${quantity} PCS</b>`;
        return `<div class="rrPartnerLine82"><span><b>${esc(line.lot_no || "-")}</b><small>${esc(line.category || line.article_name || "-")} · ${esc(line.size_text || "-")}</small></span>${control}</div>`;
      })
      .join("");
  }

  async function makePi(orderId) {
    const url = new URL("real-market-shared-invoice-test67.html", location.href);
    url.searchParams.set("role", "DISTRIBUTOR");
    url.searchParams.set("order", orderId);
    url.searchParams.set("v", "1");
    location.href = url.href;
  }

  async function sendRedzed(orderIds) {
    try {
      const result = await rawRpc("rr_market_partner_batch_submit_v67", {
        ...authArgs(),
        p_order_ids: orderIds,
      });
      if (result?.batch_id) {
        try {
          await rawRpc("rr_market_partner_chat_send_v67", {
            ...authArgs(),
            p_lane: "REDZED",
            p_partner_customer_id: null,
            p_message: `[PBATCH:${result.batch_id}] ${result.batch_ref || "REQUIREMENT BATCH"} · ${result.order_count || orderIds.length} CLOSED REQUIREMENT(S) SENT TO REDZED`,
            p_attachment: null,
          });
        } catch (error) {
          // The batch is already committed. Do not invite a duplicate push if
          // the chat notification is temporarily unavailable.
          console.warn("REDZED batch chat notification failed", error);
        }
      }
      workspaceAt = 0;
      closeSheet();
      flash(`${result.order_count || orderIds.length} requirement REDZED को भेजी ✓`);
    } catch (error) {
      flash(error.message, true);
    }
  }

  async function setConsolidation(orderId, add) {
    try {
      await rawRpc("rr_market_partner_consolidation_queue_v67", {
        ...authArgs(),
        p_order_id: orderId,
        p_add: Boolean(add),
      });
      workspaceAt = 0;
      closeSheet();
      flash(add ? "Requirement consolidated list में add हुई ✓" : "Requirement consolidated list से हटाई ✓");
    } catch (error) {
      flash(error.message, true);
    }
  }

  async function pushPi(orderIds) {
    try {
      await rawRpc("rr_market_partner_pi_push_v67", {
        ...authArgs(),
        p_order_ids: orderIds,
      });
      workspaceAt = 0;
      closeSheet();
      flash("REDZED PI customer को भेजी ✓");
    } catch (error) {
      flash(error.message, true);
    }
  }

  async function pushCi(orderIds) {
    try {
      await rawRpc("rr_market_partner_ci_push_v67", {
        ...authArgs(),
        p_order_ids: orderIds,
      });
      workspaceAt = 0;
      closeSheet();
      flash("CI customer को भेजी ✓");
    } catch (error) {
      flash(error.message, true);
    }
  }

  async function confirmOrder(orderId) {
    try {
      const data = await state(true);
      const order = (data.orders || []).find((item) => item.id === orderId);
      const decisions = (order?.lines || []).map((line) => ({
        line_id: line.id,
        action:
          document.querySelector(
            `[data-confirm-action="${CSS.escape(line.id)}"]`,
          )?.value || "CONFIRM",
        confirmed_qty: Number(
          document.querySelector(
            `[data-confirm-qty="${CSS.escape(line.id)}"]`,
          )?.value ?? line.proposed_qty ?? line.requested_qty ?? 0,
        ),
      }));
      await rawRpc("rr_market_partner_confirm_order_v67", {
        ...authArgs(),
        p_order_id: orderId,
        p_decisions: decisions,
        p_note: null,
      });
      workspaceAt = 0;
      closeSheet();
      flash("Optional PI confirmation REDZED को भेजी ✓");
    } catch (error) {
      flash(error.message, true);
    }
  }

  async function openRequirements() {
    try {
      const data = await state(true);
      const rows = (data.orders || []).filter(
        (order) =>
          (mode === "REDZED" || order.customer_id === customerId) &&
          order.status !== "SUPERSEDED",
      );
      if (mode === "REDZED") {
        const ready = rows.filter(
          (order) => order.status === "CONSOLIDATION_QUEUED" && !order.redzed_pushed_at,
        );
        openSheet(
          "CONSOLIDATE REQUIREMENT",
          ready.length
            ? ready
                .map(
                  (order) =>
                    `<article class="rrPartnerOrder82"><label><input type="checkbox" data-consolidate-order value="${esc(order.id)}"> <b>${esc(order.requirement_display_no || order.order_ref)}</b></label><small>Customer identity private · ${esc(statusText(order))}</small>${lineRows(order)}<button type="button" data-remove-consolidated="${esc(order.id)}">REMOVE FROM LIST</button></article>`,
                )
                .join("") +
              '<button id="rrSendConsolidated82" type="button">SEND SELECTED TO REDZED</button>'
            : '<div class="rrPartnerEmpty82">No customer-closed requirement waiting for REDZED.</div>',
        );
      } else {
        openSheet(
          "CUSTOMER REQUIREMENT",
          rows.length
            ? rows
                .map((order) => {
                  const canPi = ["DRAFT", "READY"].includes(order.status);
                  const canSend =
                    order.status === "READY" && !order.redzed_pushed_at;
                  const queued =
                    order.status === "CONSOLIDATION_QUEUED" && !order.redzed_pushed_at;
                  return `<article class="rrPartnerOrder82"><b>${esc(order.requirement_display_no || order.order_ref)}</b><small>${esc(statusText(order))} · linked ${esc(order.collection_display_no || "collection")}</small>${lineRows(order, canPi)}${canPi ? `<button class="good" data-make-pi="${esc(order.id)}">${order.distributor_pi_ref ? "UPDATE & RESEND PI" : "MAKE PI & SEND TO CUSTOMER"}</button>` : ""}${canSend ? `<button data-send-redzed="${esc(order.id)}">SEND TO REDZED NOW</button><button type="button" data-add-consolidated="${esc(order.id)}">ADD TO CONSOLIDATED LIST</button>` : ""}${queued ? `<button type="button" data-remove-consolidated="${esc(order.id)}">REMOVE FROM CONSOLIDATED LIST</button>` : ""}</article>`;
                })
                .join("")
            : '<div class="rrPartnerEmpty82">Customer requirement not received yet.</div>',
        );
      }
      document.querySelectorAll("[data-make-pi]").forEach(
        (button) => (button.onclick = () => makePi(button.dataset.makePi)),
      );
      document.querySelectorAll("[data-send-redzed]").forEach(
        (button) =>
          (button.onclick = () => sendRedzed([button.dataset.sendRedzed])),
      );
      document.querySelectorAll("[data-add-consolidated]").forEach(
        (button) => (button.onclick = () => setConsolidation(button.dataset.addConsolidated, true)),
      );
      document.querySelectorAll("[data-remove-consolidated]").forEach(
        (button) => (button.onclick = () => setConsolidation(button.dataset.removeConsolidated, false)),
      );
      const consolidate = document.getElementById("rrSendConsolidated82");
      if (consolidate)
        consolidate.onclick = () => {
          const ids = [...document.querySelectorAll("[data-consolidate-order]:checked")]
            .map((input) => input.value)
            .filter(Boolean);
          if (!ids.length) return flash("कम से कम एक requirement select करें.", true);
          sendRedzed(ids);
        };
    } catch (error) {
      flash(error.message, true);
    }
  }

  async function openDocuments() {
    try {
      const data = await state(true);
      const rows = (data.orders || []).filter(
        (order) =>
          (mode === "REDZED" || order.customer_id === customerId) &&
          (order.distributor_pi_ref || order.pi_ref || order.ci_ref),
      );
      openSheet(
        "PI / CI",
        rows.length
          ? rows
              .map((order) => {
                const confirm =
                  mode === "REDZED" && order.status === "PI_PROPOSED";
                const canPushPi =
                  mode === "CUSTOMER" &&
                  order.pi_ref &&
                  !order.customer_pi_visible;
                const canPushCi =
                  order.status === "CI_FINAL" &&
                  order.ci_ref &&
                  !order.customer_ci_visible;
                const req = numberedLabel(order.requirement_display_no || order.order_ref, "REQUIREMENT");
                const col = numberedLabel(order.collection_display_no, "COLLECTION");
                const stage = order.distributor_pi_ref
                  ? `PI SENT TO CUSTOMER · ${order.distributor_pi_status || "WAITING"}`
                  : statusText(order);
                return `<article class="rrPartnerOrder82"><b>${esc(order.customer_ci_ref || order.distributor_pi_ref || order.pi_ref || order.ci_ref)}</b><small>${esc(stage)} · ${esc(req.title)} · ${esc(col.title)}${order.ci_ref ? ` · Upstream CI ${esc(order.ci_ref)}` : ""}</small>${lineRows(order, false, confirm)}${order.distributor_pi_ref ? `<button class="good" data-live-customer-doc="${esc(order.id)}">OPEN CURRENT CUSTOMER PI / CI</button>` : ""}${confirm ? `<button data-confirm-order="${esc(order.id)}">CONFIRM REDZED PI (OPTIONAL)</button>` : ""}${canPushPi ? `<button data-push-pi="${esc(order.id)}">PUSH REDZED PI TO CUSTOMER</button>` : ""}${canPushCi ? `<button class="good" data-push-ci="${esc(order.id)}">PUSH CI TO CUSTOMER</button>` : ""}</article>`;
              })
              .join("")
          : '<div class="rrPartnerEmpty82">No PI / CI in this private relation yet.</div>',
      );
      document.querySelectorAll("[data-confirm-order]").forEach(
        (button) =>
          (button.onclick = () => confirmOrder(button.dataset.confirmOrder)),
      );
      document.querySelectorAll("[data-push-pi]").forEach(
        (button) => (button.onclick = () => pushPi([button.dataset.pushPi])),
      );
      document.querySelectorAll("[data-push-ci]").forEach(
        (button) => (button.onclick = () => pushCi([button.dataset.pushCi])),
      );
      document.querySelectorAll("[data-live-customer-doc]").forEach((button) => {
        button.onclick = () => {
          rememberReturn();
          const url = new URL("real-market-shared-invoice-test67.html", location.href);
          url.searchParams.set("role", "DISTRIBUTOR");
          url.searchParams.set("order", button.dataset.liveCustomerDoc);
          url.searchParams.set("v", "23");
          location.href = url.href;
        };
      });
    } catch (error) {
      flash(error.message, true);
    }
  }

  async function openSentRedzedRequirements() {
    try {
      const rows = await rawRpc("rr_market_partner_batches_v67", authArgs());
      openSheet(
        "REQUIREMENTS SENT TO REDZED",
        rows.length
          ? rows.map((batch) => {
              const status = batch.status === "SUBMITTED" ? "WAITING FOR REDZED ACTION" : batch.status === "WAITING_CONFIRMATION" ? "PI SENT · CONFIRMATION OPTIONAL" : batch.status === "CI_FINAL" ? "CI FINAL · CYCLE CLOSED" : String(batch.status || "").replaceAll("_", " ");
              const sources = (batch.requirements || []).map((item) => `<section class="rrPartnerOrder82" style="margin-top:10px"><b>${esc(item.requirement_display_no || "Source requirement")}</b><small>${esc(String(item.status || "").replaceAll("_", " "))}</small>${(item.lines || []).map((line) => `<div class="rrPartnerLine82"><span><b>${esc(line.lot_no || "-")}</b><small>${esc(line.category || "-")} · ${esc(line.size_text || "-")}</small></span><span style="text-align:right"><b>${Number(line.requested_qty || 0)} PCS</b><small>${line.proposed_qty == null ? "Requested Qty" : `REDZED working qty ${Number(line.proposed_qty || 0)}`}</small></span></div>`).join("")}</section>`).join("");
              return `<article class="rrPartnerOrder82"><b>${esc(batch.requirement_display_no || batch.batch_ref)}</b><small>${batch.batch_kind === "CONSOLIDATED" ? "CONSOLIDATED" : "SINGLE"} · ${Number(batch.order_count || 0)} source requirement(s) · ${esc(status)}</small><div class="rrPartnerLine82"><b>Distributor view</b><small>Sent requirement is locked here. REDZED Staff can adjust allocation/PI quantity against available or frozen stock.</small></div>${sources}${batch.pi_ref ? `<div class="rrPartnerLine82"><b>${esc(batch.pi_ref)}</b><small>REDZED PI</small></div>` : ""}${batch.ci_ref ? `<div class="rrPartnerLine82"><b>${esc(batch.ci_ref)}</b><small>REDZED CI</small></div>` : ""}</article>`;
            }).join("")
          : '<div class="rrPartnerEmpty82">No requirement has been sent to REDZED yet.</div>',
      );
    } catch (error) {
      flash(error.message, true);
    }
  }

  function openCollection(addMoreRequirementId = "") {
    if (mode !== "CUSTOMER") return openRequirements();
    rememberReturn();
    const url = new URL("real-web-window-v9329.html", location.href);
    url.searchParams.set("v", "partner82");
    url.searchParams.set("from_chat", "1");
    url.searchParams.set("chat_id", syntheticChatId());
    url.searchParams.set("customer_id", customerId);
    url.searchParams.set(
      "customer_name",
      selectedCustomer()?.name || "Customer",
    );
    url.searchParams.set("rr_partner_mode", "CUSTOMER");
    url.searchParams.set("customer", customerId);
    if (addMoreRequirementId)
      url.searchParams.set("append_requirement_id", addMoreRequirementId);
    location.href = url.href;
  }

  async function paintMetrics() {
    if (mode !== "CUSTOMER") return;
    try {
      const metrics = await rawRpc("rr_market_partner_customer_metrics_v67", {
        ...authArgs(),
        p_partner_customer_id: customerId,
      });
      const values = {
        rrReqAvg82: metrics?.req_visible ? metrics.req_average : null,
        rrAllAvg82: metrics?.all_average,
        rrReqQty82: metrics?.req_visible ? metrics.req_qty : null,
        rrReqAmt82: metrics?.req_visible ? metrics.req_amount : null,
      };
      Object.entries(values).forEach(([id, value]) => {
        const node = $(id);
        if (node) node.textContent = value == null ? "—" : `₹${value}`;
      });
      if ($("rrReqQty82") && values.rrReqQty82 != null)
        $("rrReqQty82").textContent = String(values.rrReqQty82);
    } catch (_) {}
  }

  function injectActions() {
    const chat = document.querySelector(".chat");
    if (!chat) return false;
    actionCss();
    // The distributor relation must use the same chat chrome and controls as
    // the established RedZed/customer flow. Remove the former custom metrics
    // and three-button dock; only the actor mapping remains in this adapter.
    chat.classList.remove("partner82");
    $("rrPartnerMetrics82")?.remove();
    $("rrPartnerDock82")?.remove();
    const marketWindow = $("marketWindowDitto");
    if (marketWindow && marketWindow.dataset.rrPartnerMapped !== "1") {
      marketWindow.dataset.rrPartnerMapped = "1";
      marketWindow.addEventListener(
        "click",
        (event) => {
          event.preventDefault();
          event.stopImmediatePropagation();
          openCollection();
        },
        true,
      );
    }
    const internal = document.querySelector('[data-pick="internal"]');
    if (internal) internal.style.display = "none";
    return true;
  }

  function activeRequirementFrom(node) {
    const match = (node?.closest(".msg")?.textContent || node?.textContent || "").match(
      /\[REQ:([0-9a-f-]{36})\]/i,
    );
    return match?.[1] || "";
  }

  async function deleteMessage(messageId) {
    if (!confirm("Delete this message from the private chat?")) return;
    try {
      await rawRpc("rr_market_partner_chat_delete_v67", {
        ...authArgs(),
        p_lane: lane(
          $("privateTab")?.classList.contains("on")
            ? "SUPERADMIN_PRIVATE"
            : "GROUP",
        ),
        p_partner_customer_id: mode === "CUSTOMER" ? customerId : null,
        p_message_id: messageId,
      });
      $("groupTab")?.click();
      flash("Message deleted ✓");
    } catch (error) {
      flash(error.message, true);
    }
  }

  async function hydrateCollectionCard(card, url) {
    if (!card || card.dataset.rrPartnerPreview === "1") return;
    card.dataset.rrPartnerPreview = "1";
    try {
      const parsed = new URL(url, location.href);
      const token = parsed.searchParams.get("t") || parsed.searchParams.get("c");
      if (!token) return;
      if (!collectionPreviewCache.has(token)) {
        collectionPreviewCache.set(
          token,
          rawRpc("rr_market_share_view_v9420", { p_token: token }),
        );
      }
      const share = await collectionPreviewCache.get(token);
      const label = numberedLabel(share?.collection_display_no, "COLLECTION");
      const title = card.querySelector(".rrMkText9505 b");
      const detail = card.querySelector(".rrMkText9505 small");
      setText(title, label.title);
      setText(detail, label.detail || "Tap to view designs, photos and requirement");
      const row = Array.isArray(share?.rows) ? share.rows[0] : null;
      const media = Array.isArray(row?.media) ? row.media : [];
      const imageUrl =
        row?.primary_image_url ||
        media.map((item) => item?.image_url || item?.storage_path).find(Boolean);
      if (!imageUrl || !card.isConnected) return;
      const icon = card.querySelector(".rrMkIcon9505");
      if (!icon) return;
      const image = document.createElement("img");
      image.src = imageUrl;
      image.alt = row?.lot_no || "Collection";
      image.loading = "eager";
      image.decoding = "async";
      image.style.cssText =
        "display:block;width:52px;height:64px;object-fit:cover;border-radius:8px;background:#090d12";
      icon.textContent = "";
      icon.appendChild(image);
    } catch (_) {
      card.dataset.rrPartnerPreview = "";
    }
  }

  function openLivePiViewer(shell, preview) {
    if (!shell || !preview || document.querySelector(".rrPartnerPiViewer82")) return;
    const marker = document.createComment("live-pi-preview");
    shell.insertBefore(marker, preview);
    const viewer = document.createElement("div");
    viewer.className = "rrPartnerPiViewer82";
    viewer.innerHTML = '<button type="button" class="rrPartnerPiViewerClose82" aria-label="Close">×</button><div class="rrPartnerPiSwipe82" aria-label="Drag down to close"></div>';
    viewer.appendChild(preview);
    document.body.appendChild(viewer);
    try { preview.contentWindow.scrollTo(0,0); } catch (_) {}
    let startY = 0, dragY = 0;
    const close = () => {
      marker.parentNode?.insertBefore(preview, marker);
      preview.style.transform="";
      try { preview.contentWindow.scrollTo(0,0); } catch (_) {}
      marker.remove();
      viewer.remove();
    };
    viewer.querySelector(".rrPartnerPiViewerClose82").onclick = close;
    const swipe = viewer.querySelector(".rrPartnerPiSwipe82");
    swipe.addEventListener("pointerdown", (event) => { startY=event.clientY; dragY=0; swipe.setPointerCapture?.(event.pointerId); });
    swipe.addEventListener("pointermove", (event) => { if(!startY) return; dragY=Math.max(0,event.clientY-startY); });
    swipe.addEventListener("pointerup", () => { if(dragY>70) close(); startY=0; dragY=0; });
    swipe.addEventListener("pointercancel", () => { startY=0; dragY=0; });
  }

  function decorateMessages() {
    document.querySelectorAll("#msgs .msg[data-msg-id]").forEach((message) => {
      const messageText = message.textContent || "";
      const requirementMatch = messageText.match(/\[REQ:([0-9a-f-]{36})\]/i);
      const piMatch = messageText.match(/\[DPI:([0-9a-f-]{36})\]\s*([^·\n]+)?/i);
      const batchMatch = messageText.match(/\[PBATCH:([0-9a-f-]{36})\]/i);
      if (requirementMatch) {
        const order = (workspace?.orders || []).find((item) => String(item.id) === requirementMatch[1]);
        const card = message.querySelector(".rrReqCard9508");
        if (order && card) {
          const req = numberedLabel(order.requirement_display_no || order.order_ref, "REQUIREMENT");
          const col = numberedLabel(order.collection_display_no, "COLLECTION");
          setText(card.querySelector("b"), `📋 ${req.title}`);
          setText(card.querySelector("small"), `${req.detail} · ${col.detail} · Tap to review styles & qty`);
          setText(card.querySelector(".rrReqOpen9508"), `OPEN ${req.title} ›`);
        }
      }
      if (piMatch && !message.querySelector(".rrPartnerPiCard82")) {
        message.classList.add("rrPartnerPiMessage82");
        message.querySelectorAll(".att,.attimg,.attachment,.media,.rrMediaThumb9664,.rrAutoImg9651").forEach((node) => { node.style.display = "none"; });
        [...message.children].forEach((child) => {
          if (child.tagName === "DIV" && /\[DPI:/i.test(child.textContent || "")) child.style.display = "none";
        });
        const card = document.createElement("button");
        card.type = "button";
        card.className = "rrMarketLinkCard9505 rrPartnerPiCard82";
        card.innerHTML = `<span class="rrMkIcon9505">📄</span><span class="rrMkText9505"><b>${esc(String(piMatch[2] || "PI").trim())}</b><small>Editable distributor PI · customer sees the same live document</small></span><span class="rrMkGo9505">EDIT PI ›</span>`;
        card.onclick = (event) => {
          event.preventDefault();
          event.stopPropagation();
          const url = new URL("real-market-shared-invoice-test67.html", location.href);
          url.searchParams.set("role", "DISTRIBUTOR");
          url.searchParams.set("order", piMatch[1]);
          url.searchParams.set("v", "1");
          location.href = url.href;
        };
        const previewShell = document.createElement("div");
        previewShell.className = "rrPartnerLivePiShell82";
        previewShell.setAttribute("role", "button");
        previewShell.tabIndex = 0;
        const preview = document.createElement("iframe");
        preview.className = "rrPartnerLivePiPreview82";
        preview.title = `${String(piMatch[2] || "PI").trim()} latest complete JPG`;
        preview.loading = "eager";
        const previewUrl = new URL("real-market-shared-invoice-test67.html", location.href);
        previewUrl.searchParams.set("role", "DISTRIBUTOR");
        previewUrl.searchParams.set("order", piMatch[1]);
        previewUrl.searchParams.set("mode", "jpeg");
        previewUrl.searchParams.set("embed", "1");
        previewUrl.searchParams.set("v", "20");
        preview.src = previewUrl.href;
        previewShell.appendChild(preview);
        previewShell.onclick = () => openLivePiViewer(previewShell, preview);
        previewShell.onkeydown = (event) => { if(event.key === "Enter" || event.key === " "){ event.preventDefault(); openLivePiViewer(previewShell, preview); } };
        message.insertBefore(previewShell, message.querySelector("time"));
        message.insertBefore(card, message.querySelector("time"));
      }
      if (batchMatch && !message.querySelector(".rrPartnerBatchCard82")) {
        [...message.children].forEach((child) => {
          if (child.tagName === "DIV" && /\[PBATCH:/i.test(child.textContent || "")) child.style.display = "none";
        });
        const card = document.createElement("button");
        card.type = "button";
        card.className = "rrMarketLinkCard9505 rrPartnerBatchCard82";
        card.innerHTML = '<span class="rrMkIcon9505">📋</span><span class="rrMkText9505"><b>REQUIREMENT SENT TO REDZED</b><small>Tap to open requirement number, update number and quantities</small></span><span class="rrMkGo9505">OPEN ›</span>';
        card.onclick = (event) => { event.preventDefault(); event.stopPropagation(); openSentRedzedRequirements(); };
        message.insertBefore(card, message.querySelector("time"));
      }
      if (!message.querySelector(".rrMarketLinkCard9505")) {
        const text = message.textContent || "";
        const absolute = text.match(/https:\/\/[^\s<]+\/s\.html\?[^\s<]+/i);
        const sharePath = text.match(/\/s\.html\?[^\s<]+/i);
        if (absolute || sharePath) {
          const rawUrl = (absolute?.[0] || sharePath?.[0] || "").replace(
            /[),.;]+$/,
            "",
          );
          const url = absolute ? rawUrl : new URL(rawUrl, location.href).href;
          const card = document.createElement("button");
          card.type = "button";
          card.className = "rrMarketLinkCard9505";
          card.innerHTML =
            '<span class="rrMkIcon9505">🛍️</span><span class="rrMkText9505"><b>COLLECTION</b><small>Loading collection number…</small></span><span class="rrMkGo9505">OPEN ›</span>';
          card.onclick = (event) => {
            event.preventDefault();
            event.stopPropagation();
            const collectionUrl = new URL(url, location.href);
            collectionUrl.searchParams.set("open", "collection");
            location.href = collectionUrl.href;
          };
          const body = [...message.children].find(
            (node) => node.tagName === "DIV" && /\/s\.html\?/i.test(node.textContent || ""),
          );
          if (body) body.style.display = "none";
          message.insertBefore(card, message.querySelector("time"));
          hydrateCollectionCard(card, url);
        }
      }
      if (!message.querySelector(".rrPartnerDelete82")) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "rrPartnerDelete82";
        button.textContent = "DELETE";
        button.onclick = (event) => {
          event.preventDefault();
          event.stopPropagation();
          deleteMessage(message.dataset.msgId);
        };
        message.appendChild(button);
      }
    });
  }

  function applyLabels() {
    setText($("chatTitle"), relationTitle());
    const brand = document.querySelector(".chatBrand");
    setText(brand, "💬 Real Chat");
    setText($("privateTab"), mode === "CUSTOMER" ? "🔒 DISTRIBUTOR" : "");
    setText($("groupTab"), mode === "CUSTOMER" ? "GROUP" : "REDZED");
    if (mode === "REDZED") {
      if ($("privateTab")) $("privateTab").style.display = "none";
      setText($("groupInfo"), "RELATION INFO");
      if ($("callBtn")) $("callBtn").style.display = "none";
    }
  }

  function autoOpen() {
    if (didAutoOpen) return false;
    const row = document.querySelector("#inboxRows .chatrow[data-chat]");
    if (!row || row.dataset.rrPartnerOpened82 === "1") return false;
    didAutoOpen = true;
    row.dataset.rrPartnerOpened82 = "1";
    localStorage.setItem("rr_real_chat_last_group_v9507", row.dataset.chat);
    row.click();
    setTimeout(() => {
      applyLabels();
      injectActions();
      decorateMessages();
    }, 100);
    return true;
  }

  document.addEventListener(
    "click",
    (event) => {
      const card = event.target.closest?.(".rrReqCard9508");
      if (card) {
        activeRequirementId = activeRequirementFrom(card);
        history.pushState({ rrPartnerRequirement82: true }, "", location.href);
      }

      if (event.target.closest?.("#rrReqPi9508")) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (!activeRequirementId)
          return flash("Requirement card दोबारा open करें.", true);
        makePi(activeRequirementId);
      }

      if (event.target.closest?.("#rrReqAdd9508")) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (!activeRequirementId)
          return flash("Requirement card दोबारा open करें.", true);
        openCollection(activeRequirementId);
      }

      if (event.target.closest?.("#backInbox")) {
        event.preventDefault();
        event.stopImmediatePropagation();
        location.href = "real-market-distributor-test67.html";
      }
    },
    true,
  );

  addEventListener("popstate", () => {
    if ($("rrPartnerSheet82")?.classList.contains("on")) {
      closeSheet();
      return;
    }
    if ($("rrReqBack9508")?.classList.contains("on")) {
      $("rrReqBack9508").classList.remove("on");
      return;
    }
    if ($("inbox")?.classList.contains("hide")) {
      location.href = "real-market-distributor-test67.html";
    }
  });

  const observer = new MutationObserver(() => {
    autoOpen();
    injectActions();
    applyLabels();
    decorateMessages();
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });

  window.RR_PARTNER_STAFF_CHAT_V82 = {
    mode,
    customerId,
    state,
    authArgs,
    openCollection,
    openRequirements,
    openDocuments,
  };
})();
