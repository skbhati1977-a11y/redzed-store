(() => {
  "use strict";
  const MODE =
      window.RR_DISTRIBUTOR_CHAT_MODE === "REDZED" ? "REDZED" : "CUSTOMER",
    Q = new URLSearchParams(location.search),
    customerId = Q.get("customer") || "";
  const $ = (s) => document.querySelector(s),
    $$ = (s) => [...document.querySelectorAll(s)],
    esc = (v) =>
      String(v ?? "").replace(
        /[&<>"']/g,
        (c) =>
          ({
            "&": "&amp;",
            "<": "&lt;",
            ">": "&gt;",
            '"': "&quot;",
            "'": "&#39;",
          })[c],
      ),
    money = (v) =>
      Number(v || 0).toLocaleString("en-IN", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });
  let state = {
      customers: [],
      orders: [],
      collections: [],
      batches: [],
      collectionCoreViews: [],
    },
    customer = null,
    metrics = null,
    messages = [],
    market = [],
    selected = new Set(),
    pendingAttachment = null,
    recorder = null,
    recordStream = null,
    recordParts = [],
    recordStart = 0,
    expandedCollectionNo,
    activeLane = MODE === "CUSTOMER" ? "CUSTOMER_GROUP" : "REDZED";
  const rpc = (n, a = {}) => RF853.rpc(n, a),
    auth = () => {
      try {
        return {
          p_session_token:
            JSON.parse(
              localStorage.getItem("rr_customer_secure_session_v9592") || "{}",
            ).session_token || "",
          p_device_id: RR_CUSTOMER_SECURE_SESSION_V9592.device(),
        };
      } catch (_) {
        return {
          p_session_token: "",
          p_device_id: RR_CUSTOMER_SECURE_SESSION_V9592.device(),
        };
      }
    };
  function note(t, bad = false) {
    const n = $("#notice");
    if (!n) return;
    n.textContent = t;
    n.style.borderColor = bad ? "#e66b72" : "#5484a9";
    n.style.display = "block";
    clearTimeout(note.t);
    note.t = setTimeout(() => (n.style.display = "none"), 4200);
  }
  function statusLabel(o) {
    return (
      {
        DRAFT: "CUSTOMER REQUIREMENT OPEN",
        READY: "REQUIREMENT CLOSED",
        BATCHED: "SENT TO REDZED",
        PI_PROPOSED: "REDZED PI RECEIVED",
        CONFIRMED: "PI CONFIRMED",
        PARTIAL_CONFIRMED: "PI PARTIAL",
        CI_FINAL: "CI READY",
        SUPERSEDED: "PREVIOUS REQUIREMENT UPDATE",
        CANCELLED: "CANCELLED",
        CLOSED: "CLOSED",
      }[o.status] ||
      o.status ||
      ""
    );
  }
  function eventAttachment(a) {
    if (!a?.data_url) return "";
    const t = String(a.type || "");
    if (t.startsWith("image/"))
      return `<img src="${esc(a.data_url)}" alt="${esc(a.name || "attachment")}" style="display:block;max-width:220px;max-height:260px;border-radius:9px;margin-top:7px">`;
    if (t.startsWith("audio/"))
      return `<audio controls src="${esc(a.data_url)}" style="display:block;max-width:100%;margin-top:7px"></audio>`;
    return `<a href="${esc(a.data_url)}" download="${esc(a.name || "attachment")}" style="color:#72c7ff">📎 ${esc(a.name || "Attachment")}</a>`;
  }
  async function load() {
    try {
      const a = auth(),
        calls = [
          rpc("rr_market_partner_workspace_v67", a),
          rpc("rr_market_partner_customer_pi_state_v67", a),
          rpc("rr_market_partner_chat_messages_v67", {
            ...a,
            p_lane: activeLane,
            p_partner_customer_id: MODE === "CUSTOMER" ? customerId : null,
          }),
        ];
      if (MODE === "CUSTOMER")
        calls.push(
          rpc("rr_market_partner_customer_metrics_v67", {
            ...a,
            p_partner_customer_id: customerId,
          }),
          rpc("rr_market_partner_sender_core_views_v81", {
            ...a,
            p_partner_customer_id: customerId,
          }),
        );
      const out = await Promise.all(calls),
        byOrder = new Map((out[1] || []).map((x) => [x.order_id, x]));
      state = out[0] || state;
      state.orders = (state.orders || []).map((o) => {
        const p = byOrder.get(o.id),
          byLine = new Map((p?.lines || []).map((l) => [l.id, l]));
        return p
          ? {
              ...o,
              ...p,
              lines: (o.lines || []).map((l) => ({
                ...l,
                ...(byLine.get(l.id) || {}),
              })),
            }
          : o;
      });
      messages = out[2] || [];
      metrics = MODE === "CUSTOMER" ? out[3] : upstreamMetrics();
      if (MODE === "CUSTOMER") {
        state.collectionCoreViews = Array.isArray(out[4]?.views)
          ? out[4].views
          : [];
        customer = (state.customers || []).find((c) => c.id === customerId);
        if (!customer)
          throw Error("Selected distributor customer is unavailable.");
        $("#collectionBtn").disabled = customer.status !== "ACTIVE";
        $("#collectionBtn").title =
          customer.status === "ACTIVE"
            ? "Send or update collection"
            : "Activate customer before sending a new collection";
      }
      paintHeader();
      paintMetrics();
      paintTimeline();
      paintPanels();
    } catch (e) {
      note(e.message || String(e), true);
      $("#timeline").innerHTML =
        `<div class="empty">${esc(e.message || e)}</div>`;
    }
  }
  function ownerName() {
    let n = String(state.owner_name || "DISTRIBUTOR")
      .trim()
      .toUpperCase();
    return n.includes("DISTRIBUTOR") ? n : `${n} DISTRIBUTOR`;
  }
  function paintHeader() {
    const owner = ownerName();
    if (MODE === "CUSTOMER") {
      const other = String(customer.group_name || customer.name || "CUSTOMER")
        .trim()
        .toUpperCase();
      $("#relationTitle").textContent = `${owner} ↔ ${other}`;
      $("#relationName").textContent = `${owner} ↔ ${other}`;
      $("#relationSub").textContent =
        `${customer.status} · customer group chat`;
      $("#directLane").textContent = owner.replace(/ DISTRIBUTOR$/, "");
      $("#groupLane").textContent = customer.group_name ? "GROUP" : "CUSTOMER";
    } else {
      $("#relationTitle").textContent = `REDZED ↔ ${owner}`;
      $("#relationName").textContent = `REDZED ↔ ${owner}`;
      $("#relationSub").textContent =
        "Private upstream relation · customer identities hidden";
      $("#groupLane").textContent = "DISTRIBUTOR";
      $("#directLane").textContent = "REDZED";
    }
  }
  function upstreamMetrics() {
    const valid = (state.orders || []).filter(
        (o) => o.status !== "SUPERSEDED" && o.status !== "CANCELLED",
      ),
      ready = valid.filter((o) => o.status === "READY" && !o.redzed_pushed_at),
      hist = valid.filter((o) => o.status === "CI_FINAL" && o.ci_ref);
    let rq = 0,
      ra = 0,
      unresolved = false;
    ready.forEach((o) =>
      (o.lines || []).forEach((l) => {
        const q = Math.max(0, Number(l.requested_qty || 0));
        rq += q;
        if (l.base_rate == null) unresolved = true;
        else ra += q * Number(l.base_rate);
      }),
    );
    let hq = 0,
      ha = 0,
      hbad = false;
    hist.forEach((o) =>
      (o.lines || []).forEach((l) => {
        const q = Math.max(
          0,
          Number(l.confirmed_qty ?? l.proposed_qty ?? l.requested_qty ?? 0),
        );
        hq += q;
        if (l.base_rate == null) hbad = true;
        else ha += q * Number(l.base_rate);
      }),
    );
    return {
      req_visible: ready.length > 0,
      req_qty: rq || null,
      req_amount: rq && !unresolved ? ra : null,
      req_average: rq && !unresolved ? ra / rq : null,
      all_average: hq && !hbad ? ha / hq : null,
    };
  }
  function setMetric(id, v, suffix = "") {
    const b = $(`#${id} b`);
    if (!b) return;
    if (v == null) {
      b.textContent = "—";
      return;
    }
    b.textContent =
      id === "reqQtyBox"
        ? `${Math.max(0, Math.floor(Number(v)))} PCS`
        : `${suffix}${money(v)}`;
  }
  function paintMetrics() {
    const m = metrics || {};
    setMetric("reqQtyBox", m.req_qty);
    setMetric("reqAmtBox", m.req_amount, "₹");
    setMetric("reqAvgBox", m.req_average, "₹");
    setMetric("allAvgBox", m.all_average, "₹");
    ["#reqQtyBox", "#reqAmtBox", "#reqAvgBox"].forEach((id) => {
      const e = $(id);
      if (e) e.style.display = m.req_visible === false ? "none" : "flex";
    });
  }
  function customerEvents() {
    const out = [],
      linkedOrderIds = new Set();
    (state.collectionCoreViews || []).forEach((item) => {
      const core = item.view || {},
        collection = (core.collections || [])[0] || {},
        requirement = (core.requirements || [])[0] || null,
        requirementId = core.requirement?.id || requirement?.id,
        latestRequirement =
          (state.orders || []).find((order) => order.id === requirementId) ||
          null,
        collectionNo = String(item.collection_no || ""),
        update = Number(item.latest_update_no || 0),
        requiredQty = new Map(
          (requirement?.lines || []).map((line) => [
            String(line.lot_no || "").trim().toLowerCase(),
            Math.max(0, Math.floor(Number(line.qty || 0))),
          ]),
        ),
        coreRows = new Map(
          (core.rows || []).map((line) => [
            String(line.lot_no || "").trim().toLowerCase(),
            line,
          ]),
        ),
        lines = (collection.lines || []).map((line) => {
          const lot = String(line.lot_no || "").trim().toLowerCase(),
            base = coreRows.get(lot) || {};
          return {
            ...base,
            ...line,
            image_url: line.image_url || base.primary_image_url || "",
            requested_qty: requiredQty.get(lot) || 0,
          };
        });
      // The direct core intentionally exposes only the latest Requirement
      // snapshot for a Collection root. Mark every older/superseded snapshot
      // in that root as linked too, so it cannot render as a second chat row.
      (state.orders || [])
        .filter((order) => order.customer_id === customerId)
        .forEach((order) => {
          const no = String(order.collection_display_no || "").match(/\d+/)?.[0];
          if (String(Number(no || 0)) === String(Number(collectionNo || 0)))
            linkedOrderIds.add(order.id);
        });
      out.push({
        at: item.created_at || collection.created_at || core.created_at,
        side: "mine",
        kind: "collection-chain",
        title: `COLLECTION ${collectionNo}`.trim(),
        text: `${lines.length} unique samples · ${update ? `latest UPDATE ${update}` : "original collection"}${latestRequirement ? ` · ${latestRequirement.requirement_display_no || `REQUIREMENT ${latestRequirement.requirement_no || ""}`}` : " · waiting requirement"}`,
        collection: item.root_collection_id || collection.id,
        collectionNo,
        latestUpdate: update,
        latestRequirement,
        lines,
        ask: `COLLECTION ${collectionNo}`.trim(),
      });
    });
    (state.orders || [])
      .filter(
        (o) => o.customer_id === customerId && !linkedOrderIds.has(o.id),
      )
      .forEach((o) => {
        out.push({
          at: o.created_at,
          side: "theirs",
          title:
            o.requirement_display_no ||
            `REQUIREMENT ${o.requirement_no || ""}`.trim(),
          text: `${Number(o.requirement_update_no || 0) ? `UPDATE ${o.requirement_update_no} · ` : ""}${statusLabel(o)} · linked COLLECTION ${(o.collection_display_no || "").match(/\d+/)?.[0] || ""}`,
        });
        if (o.distributor_pi_ref)
          out.push({
            at: o.distributor_pi_pushed_at || o.created_at,
            side: "mine",
            title: `PI ${o.distributor_pi_ref}`,
            text: `Sent to customer · ${o.distributor_pi_status}`,
          });
        if (o.customer_ci_visible && o.ci_ref)
          out.push({
            at: o.customer_ci_pushed_at || o.created_at,
            side: "mine",
            title: `CI ${o.ci_ref}`,
            text: "Final CI sent to customer",
          });
      });
    if (expandedCollectionNo === undefined && out.length) {
      const newest = out
        .filter((event) => event.kind === "collection-chain")
        .sort((a, b) => new Date(b.at) - new Date(a.at))[0];
      if (newest) expandedCollectionNo = newest.collectionNo;
    }
    return out;
  }
  function eventTime(value) {
    if (!value) return "";
    try {
      return new Date(value).toLocaleString("en-IN", {
        day: "2-digit",
        month: "2-digit",
        year: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
      });
    } catch (_) {
      return "";
    }
  }
  function chainLines(lines) {
    const rows = Array.isArray(lines) ? lines : [];
    if (!rows.length) return '<div class="chainEmpty">No samples</div>';
    return `<div class="chainLines">${rows
      .map(
        (line) => {
          const qty = Math.max(
            0,
            Math.floor(Number(line.requested_qty || 0)),
          );
          return `<div class="chainLine ${qty ? "isRequired" : ""}">${line.image_url ? `<button type="button" class="chainPhoto" data-chain-photo="${esc(line.lot_no)}" aria-label="Open ${esc(line.lot_no)} photos"><img src="${esc(line.image_url)}" loading="lazy" alt="${esc(line.lot_no || "sample")}"></button>` : '<span class="chainNoImage">👕</span>'}<div><b>${esc(line.lot_no || "-")}</b><small>${esc(line.category || line.article_name || "-")} · 📐 ${esc(line.size_text || "-")}</small>${qty ? `<span class="chainMeta"><em class="requiredQty">REQUIRED ${qty} PCS</em></span>` : ""}</div></div>`;
        },
      )
      .join("")}</div>`;
  }
  function renderCollectionChain(event) {
    const open = String(expandedCollectionNo) === String(event.collectionNo),
      latestRequirement = event.latestRequirement,
      requirementTitle = latestRequirement
        ? latestRequirement.requirement_display_no ||
          `REQUIREMENT ${latestRequirement.requirement_no || event.collectionNo}`
        : "REQUIREMENT WAITING",
      pi = latestRequirement?.distributor_pi_ref,
      ci = latestRequirement?.customer_ci_visible && latestRequirement?.ci_ref;
    return `<article class="bubble mine collectionChain ${open ? "open" : ""}"><button type="button" class="chainToggle" data-chain-toggle="${esc(event.collectionNo)}" aria-expanded="${open}"><span><b>${esc(event.title)}</b><small>${esc(event.text)}</small></span><strong>${open ? "CLOSE ▲" : "OPEN ▼"}</strong></button>${open ? `<div class="chainJourney"><div class="chainProgress"><span>COLLECTION ${esc(event.collectionNo)}${Number(event.latestUpdate || 0) ? ` · UPDATE ${Number(event.latestUpdate)}` : ""}</span><span>${esc(requirementTitle)}${latestRequirement ? ` · ${esc(statusLabel(latestRequirement))}` : ""}</span>${pi ? `<span>PI ${esc(pi)} · ${esc(latestRequirement.distributor_pi_status || "SENT")}</span>` : ""}${ci ? `<span>CI ${esc(latestRequirement.ci_ref)} · SENT</span>` : ""}</div><div class="chainSectionTitle">NEWEST SAMPLES FIRST · REQUIRED QTY FIXED</div>${chainLines(event.lines)}</div>` : ""}<button type="button" data-ask-context="${esc(event.ask)}">HOLD / ASK</button></article>`;
  }
  function redzedEvents() {
    const out = [];
    (state.orders || [])
      .filter((o) => o.redzed_pushed_at)
      .forEach((o) =>
        out.push({
          at: o.redzed_pushed_at,
          side: "mine",
          title: o.requirement_display_no || "REQUIREMENT",
          text: "Sent to REDZED",
          ask: o.requirement_display_no || "REQUIREMENT",
        }),
      );
    (state.batches || []).forEach((b) => {
      if (b.pi_ref)
        out.push({
          at: b.submitted_at,
          side: "theirs",
          title: `PI ${b.pi_ref}`,
          text: `REDZED · ${b.status}`,
        });
      if (b.ci_ref)
        out.push({
          at: b.submitted_at,
          side: "theirs",
          title: `CI ${b.ci_ref}`,
          text: "Final CI from REDZED",
        });
    });
    return out;
  }
  function paintTimeline() {
    const atBottom = innerHeight + scrollY >= document.body.scrollHeight - 100,
      out =
        MODE === "CUSTOMER"
          ? activeLane === "CUSTOMER_GROUP"
            ? customerEvents()
            : []
          : redzedEvents();
    messages.forEach((m) =>
      out.push({
        at: m.created_at,
        side: m.actor === "DISTRIBUTOR" ? "mine" : "theirs",
        title: m.actor === "DISTRIBUTOR" ? "DISTRIBUTOR" : m.actor,
        text: m.message || "",
        attachment: m.attachment,
        messageId: m.id,
      }),
    );
    out.sort((a, b) => new Date(a.at) - new Date(b.at));
    $("#timeline").innerHTML = out.length
      ? out
          .map(
            (e) =>
              e.kind === "collection-chain"
                ? renderCollectionChain(e)
                : `<article class="bubble ${e.side}"><b>${esc(e.title)}</b>${e.text ? `<small>${esc(e.text)}</small>` : ""}${eventAttachment(e.attachment)}${e.ask ? `<button type="button" data-ask-context="${esc(e.ask)}">HOLD / ASK</button>` : ""}${e.messageId ? `<button type="button" data-delete-chat="${esc(e.messageId)}">DELETE MESSAGE</button>` : ""}</article>`,
          )
          .join("")
      : `<div class="empty">${MODE === "CUSTOMER" ? (activeLane === "CUSTOMER_GROUP" ? "Send the first collection to start this customer journey." : "Start a private direct chat with this customer.") : "No private REDZED activity yet."}</div>`;
    $$("[data-ask-context]").forEach(
      (b) =>
        (b.onclick = () => {
          const input = $("#messageInput");
          input.value = `HOLD / ASK — ${b.dataset.askContext}: `;
          input.focus();
        }),
    );
    $$("[data-chain-toggle]").forEach(
      (button) =>
        (button.onclick = () => {
          const no = button.dataset.chainToggle;
          expandedCollectionNo =
            String(expandedCollectionNo) === String(no) ? null : no;
          paintTimeline();
        }),
    );
    $$("[data-chain-photo]").forEach(
      (button) =>
        (button.onclick = () => openChainViewer(button.dataset.chainPhoto)),
    );
    $$("[data-delete-chat]").forEach(
      (button) =>
        (button.onclick = () => deleteChatMessage(button.dataset.deleteChat)),
    );
    if (atBottom)
      setTimeout(
        () => scrollTo({ top: document.body.scrollHeight, behavior: "smooth" }),
        0,
      );
  }
  function paintPanels() {
    if (MODE === "CUSTOMER") {
      paintRequirements();
      paintDocuments();
    } else {
      paintUpstreamRequirements();
      paintUpstreamPi();
      paintUpstreamCi();
    }
  }
  function openPanel(id) {
    $(`#${id}`)?.classList.add("on");
  }
  function closePanel(id) {
    $(`#${id}`)?.classList.remove("on");
  }
  function media(r) {
    const a = (Array.isArray(r.media) ? r.media : [])
      .map((x) => x.image_url || x.storage_path)
      .filter(Boolean);
    if (r.primary_image_url && !a.includes(r.primary_image_url))
      a.unshift(r.primary_image_url);
    return a.slice(0, 4);
  }
  function calc(r) {
    const margin = Math.max(0, Number($("#marginInput").value || 0)),
      discount = Math.max(0, Number($("#discountInput").value || 0));
    return {
      margin,
      discount,
      sale: Number(r.sale_rate || 0) + margin,
      final: Math.max(0, Number(r.sale_rate || 0) + margin - discount),
    };
  }
  function activeCollectionNo() {
    const latest = (state.collectionCoreViews || [])[0];
    return latest && !latest.view?.requirement_locked
      ? String(latest.collection_no || "")
      : "";
  }
  function sentLots() {
    const sent = new Set();
    // Use the direct core output itself. Once present in any collection root,
    // the lot cannot re-enter this customer's collection picker.
    (state.collectionCoreViews || []).forEach((item) =>
      (item.view?.rows || []).forEach((line) => {
          const lot = String(line.lot_no || "").trim().toLowerCase();
          if (lot) sent.add(lot);
        }),
    );
    return sent;
  }
  function paintLots() {
    const already = sentLots(),
      q = String($("#lotSearch").value || "")
        .trim()
        .toLowerCase(),
      rows = market
        .filter((r) => !already.has(String(r.lot_no).trim().toLowerCase()))
        .filter(
          (r) =>
            !q ||
            `${r.lot_no} ${r.category || ""} ${r.full_item_name || ""}`
              .toLowerCase()
              .includes(q),
        );
    [...selected].forEach((lot) => {
      if (already.has(String(lot || "").trim().toLowerCase()))
        selected.delete(lot);
    });
    $("#lotStatus").textContent =
      `${rows.length} fresh samples · ${already.size} already-sent hidden · ${selected.size} selected`;
    $("#lots").innerHTML =
      rows
        .map((r, i) => {
          const p = calc(r);
          return `<article class="product ${selected.has(r.lot_no) ? "sel" : ""}"><input class="pick" data-pick="${esc(r.lot_no)}" type="checkbox" ${selected.has(r.lot_no) ? "checked" : ""}><button class="photo" data-photo="${i}">${r.primary_image_url ? `<img src="${esc(r.primary_image_url)}" loading="lazy">` : "👕"}</button><div class="facts"><span>🏷 <b>${esc(r.lot_no)}</b></span><span>▦ ${esc(r.category || r.full_item_name || "-")}</span><span>📐 ${esc(r.size_text || "-")}</span><span class="stock">${esc(r.stock_label || "STOCK-IN")}</span></div><div class="rates">Purchase ₹${money(r.sale_rate)}<br>Sale ₹${money(p.sale)} − Less ₹${money(p.discount)} = <strong>₹${money(p.final)}</strong></div></article>`;
        })
        .join("") || '<div class="empty">No fresh samples available.</div>';
    $$("[data-pick]").forEach(
      (x) =>
        (x.onchange = () => {
          x.checked
            ? selected.add(x.dataset.pick)
            : selected.delete(x.dataset.pick);
          paintLots();
        }),
    );
    $$("[data-photo]").forEach(
      (b, i) => (b.onclick = () => openViewer(rows[i])),
    );
  }
  async function loadLots() {
    try {
      $("#lotStatus").textContent = "Loading TEST67 lots…";
      const no = activeCollectionNo(),
        active = (state.collectionCoreViews || []).find(
          (item) => String(item.collection_no || "") === no,
        ),
        nextUpdate = Number(active?.latest_update_no || 0) + 1;
      $("#collectionPanelTitle").textContent = no
        ? `ADD FRESH SAMPLES · COLLECTION ${no} · UPDATE ${nextUpdate}`
        : "SEND NEW COLLECTION";
      market =
        (await rpc("rr_market_partner_cards_v67", {
          ...auth(),
          p_search: null,
        })) || [];
      selected.clear();
      paintLots();
    } catch (e) {
      note(e.message, true);
    }
  }
  function openViewer(r) {
    const a = media(r);
    if (!a.length) return note("Photos unavailable.", true);
    $("#viewerTitle").textContent =
      `${r.lot_no} · ${r.category || r.full_item_name || ""}`;
    $("#viewerImage").src = a[0];
    $("#viewerThumbs").innerHTML = a
      .map(
        (u, i) =>
          `<button class="${i ? "" : "on"}" data-vimg="${esc(u)}"><img src="${esc(u)}"></button>`,
      )
      .join("");
    $$("[data-vimg]").forEach(
      (b) =>
        (b.onclick = () => {
          $("#viewerImage").src = b.dataset.vimg;
          $$("[data-vimg]").forEach((x) => x.classList.toggle("on", x === b));
        }),
    );
    $("#viewerBack").classList.add("on");
  }
  async function openChainViewer(lot) {
    try {
      let row = market.find(
        (item) =>
          String(item.lot_no || "").trim().toLowerCase() ===
          String(lot || "").trim().toLowerCase(),
      );
      if (!row) {
        const rows =
          (await rpc("rr_market_partner_cards_v67", {
            ...auth(),
            p_search: lot,
          })) || [];
        row = rows.find(
          (item) =>
            String(item.lot_no || "").trim().toLowerCase() ===
            String(lot || "").trim().toLowerCase(),
        );
      }
      if (!row) throw Error("Sample photos unavailable.");
      openViewer(row);
    } catch (e) {
      note(e.message || String(e), true);
    }
  }
  async function sendCollection() {
    const already = sentLots(),
      lines = market
      .filter(
        (r) =>
          selected.has(r.lot_no) &&
          !already.has(String(r.lot_no).trim().toLowerCase()),
      )
      .map((r) => {
        const p = calc(r);
        return {
          lot_no: r.lot_no,
          margin_amount: p.margin,
          discount_amount: p.discount,
        };
      });
    if (!lines.length)
      return note("कम से कम एक fresh sample select करें.", true);
    try {
      const d = await rpc("rr_market_partner_collection_priced_create_v67", {
        ...auth(),
        p_partner_customer_id: customerId,
        p_lines: lines,
      });
      note(`${d.collection_display_no} customer chat में भेजी ✓`);
      closePanel("collectionPanel");
      await load();
    } catch (e) {
      note(e.message, true);
    }
  }
  function customerOrders() {
    return (state.orders || []).filter(
      (o) => o.customer_id === customerId && o.status !== "SUPERSEDED",
    );
  }
  function orderCard(o, docs = false) {
    const canPi = ["DRAFT", "READY"].includes(o.status),
      ready = o.status === "READY" && !o.redzed_pushed_at;
    return `<article class="card"><div class="row"><b>${esc(o.requirement_display_no || o.order_ref)}</b><span>${esc(statusLabel(o))}</span></div><div class="muted">Linked ${esc(o.collection_display_no || "collection")}</div>${(o.lines || []).map((l) => `<div class="line">${l.image_url ? `<img src="${esc(l.image_url)}">` : ""}<b>${esc(l.lot_no)}</b> · ${esc(l.category || "-")} · ${esc(l.size_text || "-")}<br>Required <b>${Number(l.requested_qty || 0)}</b>${canPi && !docs ? `<input data-dpi="${l.id}" type="number" min="0" value="${Number(l.distributor_pi_qty ?? l.requested_qty ?? 0)}">` : ""}</div>`).join("")}${canPi && !docs ? `<button class="good" data-make-pi="${o.id}">${o.distributor_pi_ref ? "UPDATE & RESEND PI" : "MAKE PI & SEND TO CUSTOMER"}</button>` : ""}${ready && !docs ? `<button class="primary" data-send-redzed="${o.id}">SEND CLOSED REQUIREMENT TO REDZED</button>` : ""}${o.redzed_pushed_at ? '<div class="muted">Sent to REDZED ✓</div>' : ""}${o.status === "CI_FINAL" && !o.customer_ci_visible ? `<button class="good" data-push-ci="${o.id}">PUSH CI TO CUSTOMER</button>` : ""}</article>`;
  }
  function paintRequirements() {
    const rows = customerOrders();
    $("#requirements").innerHTML = rows.length
      ? rows.map((o) => orderCard(o)).join("")
      : '<div class="empty">Customer requirement not received yet.</div>';
    $$("[data-make-pi]").forEach(
      (b) => (b.onclick = () => makePi(b.dataset.makePi)),
    );
    $$("[data-send-redzed]").forEach(
      (b) => (b.onclick = () => sendRedzed([b.dataset.sendRedzed])),
    );
    $$("[data-push-ci]").forEach(
      (b) => (b.onclick = () => pushCi(b.dataset.pushCi)),
    );
  }
  function paintDocuments() {
    const rows = customerOrders().filter(
      (o) => o.distributor_pi_ref || o.ci_ref,
    );
    $("#documents").innerHTML = rows.length
      ? rows.map((o) => orderCard(o, true)).join("")
      : '<div class="empty">No PI / CI yet.</div>';
  }
  async function makePi(id) {
    try {
      const o = state.orders.find((x) => x.id === id),
        lines = (o.lines || []).map((l) => ({
          line_id: l.id,
          qty: Math.max(
            0,
            Math.floor(
              Number($(`[data-dpi="${l.id}"]`)?.value ?? l.requested_qty) || 0,
            ),
          ),
        })),
        d = await rpc("rr_market_partner_make_customer_pi_v67", {
          ...auth(),
          p_order_id: id,
          p_lines: lines,
          p_note: null,
        });
      note(`${d.distributor_pi_ref} customer को भेजी · requirement closed ✓`);
      await load();
    } catch (e) {
      note(e.message, true);
    }
  }
  async function sendRedzed(ids) {
    try {
      const d = await rpc("rr_market_partner_batch_submit_v67", {
        ...auth(),
        p_order_ids: ids,
      });
      note(`${d.order_count} requirement REDZED को भेजी ✓`);
      await load();
    } catch (e) {
      note(e.message, true);
    }
  }
  async function pushCi(ids) {
    const orderIds = Array.isArray(ids) ? ids : [ids];
    try {
      await rpc("rr_market_partner_ci_push_v67", {
        ...auth(),
        p_order_ids: orderIds,
      });
      note(
        `${orderIds.length} customer${orderIds.length === 1 ? "" : "s"} को CI भेजी ✓`,
      );
      await load();
    } catch (e) {
      note(e.message, true);
    }
  }
  function paintUpstreamRequirements() {
    const rows = (state.orders || []).filter(
      (o) => o.status === "READY" && !o.redzed_pushed_at,
    );
    $("#upstreamRequirements").innerHTML = rows.length
      ? rows
          .map(
            (o) =>
              `<article class="card"><label><input data-upstream-order type="checkbox" value="${o.id}"> <b>${esc(o.requirement_display_no || o.order_ref)}</b></label><div class="muted">Private customer identity withheld upstream · ${(o.lines || []).length} lots</div>${(o.lines || []).map((l) => `<div class="line"><b>${esc(l.lot_no)}</b> · Qty ${Number(l.requested_qty || 0)}</div>`).join("")}</article>`,
          )
          .join("") +
        '<button id="sendBatchBtn" class="formButton blue">SEND SELECTED TO REDZED</button>'
      : '<div class="empty">No closed requirement waiting for REDZED.</div>';
    if ($("#sendBatchBtn"))
      $("#sendBatchBtn").onclick = () => {
        const ids = $$("[data-upstream-order]:checked").map((x) => x.value);
        if (!ids.length) return note("Requirement select करें.", true);
        sendRedzed(ids);
      };
  }
  function paintUpstreamPi() {
    const rows = (state.orders || []).filter((o) => o.status === "PI_PROPOSED");
    $("#requirements").innerHTML = rows.length
      ? rows
          .map(
            (o) =>
              `<article class="card"><b>${esc(o.pi_ref || "REDZED PI")}</b><div class="muted">Optional confirmation</div>${(o.lines || []).map((l) => `<div class="line"><b>${esc(l.lot_no)}</b> · Proposed ${Number(l.proposed_qty ?? l.requested_qty ?? 0)}<select data-action="${l.id}"><option value="CONFIRM">Confirm</option><option value="CHANGE">Request change</option><option value="CANCEL">Cancel</option></select><input data-confirm="${l.id}" type="number" min="0" value="${Number(l.confirmed_qty ?? l.proposed_qty ?? l.requested_qty ?? 0)}"></div>`).join("")}<button class="primary" data-confirm-order="${o.id}">CONFIRM REDZED PI (OPTIONAL)</button></article>`,
          )
          .join("")
      : '<div class="empty">No REDZED PI waiting.</div>';
    $$("[data-confirm-order]").forEach(
      (b) => (b.onclick = () => confirmOrder(b.dataset.confirmOrder)),
    );
  }
  async function confirmOrder(id) {
    try {
      const o = state.orders.find((x) => x.id === id),
        decisions = (o.lines || []).map((l) => ({
          line_id: l.id,
          action: $(`[data-action="${l.id}"]`).value,
          confirmed_qty: Number($(`[data-confirm="${l.id}"]`).value),
        }));
      await rpc("rr_market_partner_confirm_order_v67", {
        ...auth(),
        p_order_id: id,
        p_decisions: decisions,
        p_note: null,
      });
      note("Optional PI confirmation REDZED को भेजी ✓");
      await load();
    } catch (e) {
      note(e.message, true);
    }
  }
  function paintUpstreamCi() {
    const rows = (state.batches || []).filter(
        (b) => b.ci_ref || b.status === "CI_FINAL",
      ),
      pendingCustomerCi = (state.orders || []).filter(
        (o) => o.status === "CI_FINAL" && o.ci_ref && !o.customer_ci_visible,
      );
    $("#documents").innerHTML = rows.length
      ? rows
          .map(
            (b) =>
              `<article class="card"><b>CI ${esc(b.ci_ref || "—")}</b><div class="muted">${esc(b.batch_ref || "")} · ${esc(b.status || "")}</div></article>`,
          )
          .join("") +
        (pendingCustomerCi.length
          ? `<button id="pushAllCiBtn" class="formButton blue">PUSH CI TO ALL ${pendingCustomerCi.length} CUSTOMERS</button>`
          : '<div class="muted">All customer-wise CI copies are sent.</div>')
      : '<div class="empty">No REDZED CI yet. PI confirmation is optional.</div>';
    if ($("#pushAllCiBtn"))
      $("#pushAllCiBtn").onclick = () =>
        pushCi(pendingCustomerCi.map((o) => o.id));
  }
  function fileData(file) {
    return new Promise((ok, fail) => {
      if (file.size > 6291456)
        return fail(Error("Attachment 6 MB से कम रखें."));
      const r = new FileReader();
      r.onload = () =>
        ok({
          name: file.name,
          type: file.type || "application/octet-stream",
          data_url: String(r.result || ""),
        });
      r.onerror = fail;
      r.readAsDataURL(file);
    });
  }
  async function sendMessage(e) {
    e?.preventDefault();
    const msg = $("#messageInput").value.trim();
    if (!msg && !pendingAttachment) return;
    try {
      $("#sendMessageBtn").disabled = true;
      await rpc("rr_market_partner_chat_send_v67", {
        ...auth(),
        p_lane: activeLane,
        p_partner_customer_id: MODE === "CUSTOMER" ? customerId : null,
        p_message: msg || null,
        p_attachment: pendingAttachment,
      });
      $("#messageInput").value = "";
      pendingAttachment = null;
      note("Message sent ✓");
      await load();
    } catch (x) {
      note(x.message, true);
    } finally {
      $("#sendMessageBtn").disabled = false;
    }
  }
  async function deleteChatMessage(messageId) {
    if (!messageId || !confirm("Delete this message from the chat?")) return;
    try {
      await rpc("rr_market_partner_chat_delete_v67", {
        ...auth(),
        p_lane: activeLane,
        p_partner_customer_id: MODE === "CUSTOMER" ? customerId : null,
        p_message_id: messageId,
      });
      note("Message deleted ✓");
      await load();
    } catch (error) {
      note(error.message, true);
    }
  }
  async function toggleRecord() {
    if (recorder?.state === "recording") {
      recorder.stop();
      return;
    }
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder)
      return note("Voice recording इस browser में supported नहीं है.", true);
    try {
      recordStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      recordParts = [];
      recordStart = Date.now();
      recorder = new MediaRecorder(recordStream);
      recorder.ondataavailable = (e) => {
        if (e.data.size) recordParts.push(e.data);
      };
      recorder.onstop = async () => {
        try {
          const blob = new Blob(recordParts, {
              type: recorder.mimeType || "audio/webm",
            }),
            file = new File([blob], `voice-${Date.now()}.webm`, {
              type: blob.type,
            });
          pendingAttachment = await fileData(file);
          pendingAttachment.duration = Math.max(
            1,
            Math.round((Date.now() - recordStart) / 1000),
          );
          note("Voice ready · Send arrow दबाएँ");
        } catch (e) {
          note(e.message, true);
        } finally {
          recordStream?.getTracks().forEach((t) => t.stop());
          recorder = null;
          $("#micBtn").textContent = "🎙";
        }
      };
      recorder.start();
      $("#micBtn").textContent = "■";
      note("Recording… stop के लिए फिर दबाएँ");
    } catch (e) {
      note(
        e.name === "NotAllowedError" ? "Mic permission Allow करें." : e.message,
        true,
      );
    }
  }
  function wire() {
    $("#backBtn").onclick = () => {
      if (!window.RRMobileBackStepTest67?.back?.())
        location.href = "real-market-distributor-test67.html";
    };
    $("#refreshBtn").onclick = load;
    $$("[data-close-panel]").forEach(
      (b) => (b.onclick = () => closePanel(b.dataset.closePanel)),
    );
    $$(".panelBack").forEach(
      (p) =>
        (p.onclick = (e) => {
          if (e.target === p) closePanel(p.id);
        }),
    );
    $("#collectionBtn").onclick = () => {
      openPanel("collectionPanel");
      if (MODE === "CUSTOMER") loadLots();
    };
    $("#requirementBtn").onclick = () => openPanel("requirementPanel");
    $("#documentsBtn").onclick = () => openPanel("documentsPanel");
    $("#composer").onsubmit = sendMessage;
    $("#attachInput").onchange = async (e) => {
      try {
        pendingAttachment = await fileData(e.target.files?.[0]);
        note(`${pendingAttachment.name} ready · Send arrow दबाएँ`);
      } catch (x) {
        note(x.message, true);
      } finally {
        e.target.value = "";
      }
    };
    $("#micBtn").onclick = toggleRecord;
    if (MODE === "CUSTOMER") {
      $("#groupLane").onclick = () => {
        activeLane = "CUSTOMER_GROUP";
        $("#groupLane").classList.add("on");
        $("#directLane").classList.remove("on");
        $("#messageInput").placeholder = "Message to customer group";
        load();
      };
      $("#directLane").onclick = () => {
        activeLane = "CUSTOMER_DIRECT";
        $("#directLane").classList.add("on");
        $("#groupLane").classList.remove("on");
        $("#messageInput").placeholder = "Private message to customer";
        load();
      };
      $("#loadLotsBtn").onclick = loadLots;
      $("#lotSearch").oninput = paintLots;
      $("#marginInput").oninput = paintLots;
      $("#discountInput").oninput = paintLots;
      $("#sendCollectionBtn").onclick = sendCollection;
      $("#closeViewer").onclick = () => $("#viewerBack").classList.remove("on");
      $("#viewerBack").onclick = (e) => {
        if (e.target === $("#viewerBack"))
          $("#viewerBack").classList.remove("on");
      };
    }
  }
  async function boot() {
    try {
      const s = await RR_CUSTOMER_SECURE_SESSION_V9592.ensure();
      if (!s) return note("Valid distributor login से खोलें.", true);
      if (MODE === "CUSTOMER" && !customerId)
        throw Error("Customer reference missing.");
      wire();
      await load();
    } catch (e) {
      note(e.message, true);
      $("#timeline").innerHTML = `<div class="empty">${esc(e.message)}</div>`;
    }
  }
  document.addEventListener("rr:customer-secure-session-ready", boot, {
    once: true,
  });
  if (document.readyState !== "loading") setTimeout(boot, 100);
})();
