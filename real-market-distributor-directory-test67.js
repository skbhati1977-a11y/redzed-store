(() => {
  "use strict";
  const $ = (s) => document.querySelector(s),
    $$ = (s) => [...document.querySelectorAll(s)],
    esc = (v) =>
      String(v ?? "").replace(
        /[&<>"']/g,
        (c) =>
          ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c],
      );
  let state = { customers: [], groups: [], staff: [] },
    viewKind = "CUSTOMER";
  const rpc = (n, a = {}) => RF853.rpc(n, a),
    auth = () => {
      try {
        return {
          p_session_token:
            JSON.parse(localStorage.getItem("rr_customer_secure_session_v9592") || "{}")
              .session_token || "",
          p_device_id: RR_CUSTOMER_SECURE_SESSION_V9592.device(),
        };
      } catch (_) {
        return {
          p_session_token: "",
          p_device_id: RR_CUSTOMER_SECURE_SESSION_V9592.device(),
        };
      }
    };
  function note(text, bad = false) {
    const n = $("#notice");
    n.textContent = text;
    n.style.borderColor = bad ? "#e66b72" : "#5484a9";
    n.style.display = "block";
    clearTimeout(note.t);
    note.t = setTimeout(() => (n.style.display = "none"), 4200);
  }
  function open(id) {
    $("#" + id)?.classList.add("on");
  }
  function close(id) {
    $("#" + id)?.classList.remove("on");
  }
  function owner() {
    const n = String(state.owner_name || "DISTRIBUTOR").trim().toUpperCase();
    return n.includes("DISTRIBUTOR") ? n : `${n} DISTRIBUTOR`;
  }
  async function load() {
    try {
      state = await rpc("rr_market_partner_workspace_v67", auth());
      $("#brandTitle").textContent = owner();
      paint();
    } catch (e) {
      note(e.message, true);
    }
  }
  function filtered(list) {
    const q = $("#customerSearch").value.trim().toLowerCase();
    return list.filter(
      (x) =>
        !q ||
        `${x.name || ""} ${x.mobile || ""} ${x.role || ""}`
          .toLowerCase()
          .includes(q),
    );
  }
  function statusButton(kind, item) {
    return `<button type="button" class="statusBtn ${item.status === "ACTIVE" ? "" : "off"}" data-status-kind="${kind}" data-status-id="${item.id}" data-active="${item.status === "ACTIVE"}">${item.status === "ACTIVE" ? "ACTIVE" : "INACTIVE"}</button>`;
  }
  function paintCustomers() {
    const rows = filtered(state.customers || []);
    $("#customers").innerHTML = rows.length
      ? rows
          .map(
            (c) =>
              `<article class="customer" data-chat="${c.id}"><div class="avatar">${esc((c.name || "?")[0])}</div><div class="grow"><span class="kindBadge">CUSTOMER · ${esc(c.group_name || `${c.name} GROUP`)}</span><b>${esc(c.name)}</b><small>${esc(c.mobile || "No mobile")}</small></div>${statusButton("CUSTOMER", c)}</article>`,
          )
          .join("")
      : '<div class="empty">No customer found.</div>';
    $$("[data-chat]").forEach((row) => {
      row.onclick = (e) => {
        if (e.target.closest("button")) return;
        location.href = `real-sales-live-chat-v9434.html?rr_partner_mode=CUSTOMER&customer=${encodeURIComponent(row.dataset.chat)}&from=distributor`;
      };
    });
  }
  function paintStaff() {
    const rows = filtered(state.staff || []);
    $("#customers").innerHTML = rows.length
      ? rows
          .map(
            (s) =>
              `<article class="customer"><div class="avatar">${esc((s.name || "?")[0])}</div><div class="grow"><span class="kindBadge">STAFF · ${esc(s.role || "STAFF")}</span><b>${esc(s.name)}</b><small>${esc(s.mobile || "No mobile")} · ${s.status === "ACTIVE" ? "All active customer groups" : "Removed from all groups"}</small></div>${statusButton("STAFF", s)}</article>`,
          )
          .join("")
      : '<div class="empty">No staff found. Add staff with the ＋ button.</div>';
  }
  function paintGroups() {
    const activeStaff = (state.staff || []).filter((s) => s.status === "ACTIVE");
    const rows = (state.customers || []).map((c) => ({
      ...c,
      members: c.status === "ACTIVE" ? activeStaff : [],
    }));
    $("#groups").innerHTML = rows.length
      ? rows
          .map(
            (g) =>
              `<div class="listItem"><b>${esc(g.group_name || `${g.name} GROUP`)}</b><br><span class="muted">Customer: ${esc(g.name)} · Distributor: Admin<br>${g.status === "ACTIVE" ? `${g.members.length} active staff auto-enrolled${g.members.length ? ` · ${g.members.map((s) => esc(s.name)).join(", ")}` : ""}` : "Inactive · history preserved"}</span></div>`,
          )
          .join("")
      : '<div class="empty">Customer save करते ही उसका group यहाँ बनेगा.</div>';
  }
  function paint() {
    $("#customersTab").classList.toggle("on", viewKind === "CUSTOMER");
    $("#staffTab").classList.toggle("on", viewKind === "STAFF");
    viewKind === "CUSTOMER" ? paintCustomers() : paintStaff();
    paintGroups();
    $$("[data-status-kind]").forEach((button) => {
      button.onclick = (e) => {
        e.stopPropagation();
        setStatus(
          button.dataset.statusKind,
          button.dataset.statusId,
          button.dataset.active !== "true",
        );
      };
    });
  }
  function cleanMobile(value) {
    return String(value || "").replace(/[^0-9+]/g, "");
  }
  function decode(value) {
    return String(value || "")
      .replace(/\\n/gi, " ")
      .replace(/\\,/g, ",")
      .replace(/\\;/g, ";")
      .trim();
  }
  function parseVcf(raw) {
    return String(raw || "")
      .replace(/\r?\n[ \t]/g, "")
      .split(/END:VCARD/i)
      .map((card) => {
        const full = card.match(/(?:^|\n)FN(?:;[^:]*)?:(.*)/i),
          parts = card.match(/(?:^|\n)N(?:;[^:]*)?:(.*)/i),
          name = decode(
            full?.[1] ||
              (parts
                ? decode(parts[1]).split(";").filter(Boolean).reverse().join(" ")
                : ""),
          ),
          numbers = [...card.matchAll(/(?:^|\n)TEL(?:;[^:]*)?:(.*)/gi)]
            .map((x) => cleanMobile(decode(x[1])))
            .filter(Boolean);
        return { name, mobile: numbers[0] || "" };
      })
      .filter((x) => x.name && x.mobile);
  }
  async function importVcf(file) {
    if (!file) return;
    try {
      $("#vcfStatus").textContent = "VCF reading…";
      const contacts = parseVcf(await file.text()),
        kind = $("#vcfKind").value;
      if (!contacts.length) throw Error("VCF में contacts नहीं मिले.");
      const result = await rpc("rr_market_partner_contact_bulk_v67", {
        ...auth(),
        p_contact_kind: kind,
        p_contacts: contacts,
        p_active: true,
      });
      $("#vcfStatus").textContent =
        `${result.saved} saved · ${result.skipped} skipped`;
      viewKind = kind;
      note(`${result.saved} ${kind.toLowerCase()} contacts saved ✓`);
      await load();
    } catch (e) {
      note(e.message, true);
    } finally {
      $("#vcfFile").value = "";
    }
  }
  function contactKindChanged() {
    const staff = $("#contactKind").value === "STAFF";
    $("#contactRole").classList.toggle("hidden", !staff);
    $("#contactSheetTitle").textContent = staff
      ? "Add / Update Staff"
      : "Add / Update Customer";
  }
  async function saveContact() {
    const kind = $("#contactKind").value,
      name = $("#contactName").value.trim(),
      mobile = cleanMobile($("#contactMobile").value);
    if (!name || !mobile) return note("Name और mobile required.", true);
    try {
      const result = await rpc("rr_market_partner_contact_save_v67", {
        ...auth(),
        p_contact_kind: kind,
        p_name: name,
        p_mobile: mobile,
        p_role: kind === "STAFF" ? $("#contactRole").value : null,
        p_active: $("#contactActive").checked,
      });
      $("#contactName").value = $("#contactMobile").value = "";
      close("addBack");
      viewKind = kind;
      note(
        `${kind === "STAFF" ? "Staff" : "Customer"} ${result.created ? "added" : "updated"} ✓`,
      );
      await load();
    } catch (e) {
      note(e.message, true);
    }
  }
  async function setStatus(kind, id, active) {
    try {
      await rpc(
        kind === "STAFF"
          ? "rr_market_partner_staff_status_set_v67"
          : "rr_market_partner_customer_status_set_v67",
        {
          ...auth(),
          ...(kind === "STAFF"
            ? { p_staff_id: id }
            : { p_partner_customer_id: id }),
          p_active: active,
        },
      );
      note(
        kind === "STAFF"
          ? active
            ? "Staff active · all customer groups joined ✓"
            : "Staff inactive · all groups removed ✓"
          : active
            ? "Customer active · permanent group restored ✓"
            : "Customer inactive · group history preserved ✓",
      );
      await load();
    } catch (e) {
      note(e.message, true);
      await load();
    }
  }
  function switchView(kind) {
    viewKind = kind;
    paint();
  }
  function wire() {
    $("#menuBtn").onclick = () => open("drawerBack");
    $("#addBtn").onclick = () => {
      $("#contactKind").value = viewKind;
      $("#contactActive").checked = true;
      contactKindChanged();
      open("addBack");
    };
    $("#customersTab").onclick = () => switchView("CUSTOMER");
    $("#staffTab").onclick = () => switchView("STAFF");
    $("#groupsBtn").onclick = () => {
      close("drawerBack");
      paintGroups();
      open("groupsBack");
    };
    $("#staffBtn").onclick = () => {
      close("drawerBack");
      switchView("STAFF");
    };
    $("#redzedChatBtn").onclick = () =>
      (location.href =
        "real-sales-live-chat-v9434.html?rr_partner_mode=REDZED&from=distributor");
    $$("[data-close]").forEach(
      (button) => (button.onclick = () => close(button.dataset.close)),
    );
    $$(".modalBack,.drawerBack").forEach((backdrop) => {
      backdrop.onclick = (e) => {
        if (e.target === backdrop) close(backdrop.id);
      };
    });
    $("#customerSearch").oninput = paint;
    $("#vcfFile").onchange = (e) => importVcf(e.target.files?.[0]);
    $("#contactKind").onchange = contactKindChanged;
    $("#saveContact").onclick = saveContact;
    contactKindChanged();
  }
  async function boot() {
    try {
      const session = await RR_CUSTOMER_SECURE_SESSION_V9592.ensure();
      if (!session) return note("Valid distributor login से खोलें.", true);
      wire();
      await load();
    } catch (e) {
      note(e.message, true);
    }
  }
  document.addEventListener("rr:customer-secure-session-ready", boot, {
    once: true,
  });
  if (document.readyState !== "loading") setTimeout(boot, 100);
})();
