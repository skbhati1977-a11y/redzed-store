(() => {
  "use strict";
  if (window.__RR_CUSTOMER_SECURE_SESSION_V9680__) return;
  window.__RR_CUSTOMER_SECURE_SESSION_V9680__ = true;

  const query = new URLSearchParams(location.search);
  const token = query.get("t") || query.get("c") || "";
  const legacyIdentityKey = "rr_market_customer_identity_v9423";
  const identityKey = `${legacyIdentityKey}:${token || "unassigned"}`;
  const sessionKey = "rr_customer_secure_session_v9592";
  const deviceKey = "rr_customer_device_v9592";

  function parse(key) {
    try { return JSON.parse(localStorage.getItem(key) || "null"); } catch (_) { return null; }
  }
  function ident() {
    const value = parse(identityKey);
    return value?.name && value?.mobile
      ? { name: String(value.name).trim(), mobile: String(value.mobile).trim() }
      : null;
  }
  function remember(name, mobile) {
    const value = { name: String(name).trim(), mobile: String(mobile).trim(), share_token: token };
    localStorage.setItem(identityKey, JSON.stringify(value));
    // Existing customer-chat renderers read this key. It is updated only after
    // the token-bound backend has accepted the identity.
    localStorage.setItem(legacyIdentityKey, JSON.stringify(value));
  }
  function device() {
    let value = localStorage.getItem(deviceKey);
    if (!value) {
      const bytes = new Uint8Array(24);
      crypto.getRandomValues(bytes);
      value = [...bytes].map((item) => item.toString(16).padStart(2, "0")).join("");
      localStorage.setItem(deviceKey, value);
    }
    return value;
  }
  function saved() {
    const value = parse(sessionKey);
    return value?.share_token === token ? value : null;
  }
  function save(value) { localStorage.setItem(sessionKey, JSON.stringify({ ...value, share_token: token })); }
  function clear() {
    const value = parse(sessionKey);
    if (!value || value.share_token === token) localStorage.removeItem(sessionKey);
  }
  async function rpc(name, args) { return RF853.rpc(name, args); }

  async function expectedCustomer() {
    if (!token) return null;
    try {
      const share = await rpc("rr_market_share_view_v9420", { p_token: token });
      const name = String(share?.customer_name || "").trim();
      return name ? { name } : null;
    } catch (_) {
      return null;
    }
  }

  function askIdentity(expected) {
    return new Promise((resolve) => {
      if (document.getElementById("rrSecureReentry9592")) return;
      const modal = document.createElement("div");
      modal.id = "rrSecureReentry9592";
      modal.style.cssText = "position:fixed;inset:0;z-index:2147483646;background:rgba(5,10,16,.94);display:flex;align-items:center;justify-content:center;padding:18px;font-family:Arial,sans-serif";
      modal.innerHTML = `<div style="width:min(420px,100%);background:#121c29;border:1px solid #4b617c;border-radius:16px;padding:18px;color:#fff"><b style="display:block;font-size:20px;margin-bottom:6px">OPEN SECURE CHAT</b><small style="display:block;color:#aeb9c7;margin-bottom:14px">${expected?.name ? "यह collection इसी customer के लिए है। Registered mobile verify करें।" : "Enter the customer name and mobile used for this collection."}</small><input name="rrName" placeholder="Customer name" autocomplete="name" style="box-sizing:border-box;width:100%;padding:12px;margin:0 0 9px;border:1px solid #50647e;border-radius:9px;background:#0d1219;color:#fff;font-size:16px"><input name="rrMobile" placeholder="Mobile number" inputmode="tel" autocomplete="tel" style="box-sizing:border-box;width:100%;padding:12px;margin:0 0 12px;border:1px solid #50647e;border-radius:9px;background:#0d1219;color:#fff;font-size:16px"><div data-err style="min-height:18px;color:#ffb7b7;font-size:12px;margin-bottom:8px"></div><button type="button" style="width:100%;padding:12px;border:0;border-radius:9px;background:#fff;color:#111;font-weight:900;font-size:15px">CONTINUE TO CHAT</button></div>`;
      document.body.appendChild(modal);
      const nameInput = modal.querySelector("[name=rrName]");
      const mobileInput = modal.querySelector("[name=rrMobile]");
      const error = modal.querySelector("[data-err]");
      if (expected?.name) {
        nameInput.value = expected.name;
        nameInput.readOnly = true;
        nameInput.setAttribute("aria-readonly", "true");
      }
      modal.querySelector("button").onclick = () => {
        const name = nameInput.value.trim();
        const mobile = mobileInput.value.trim();
        if (!name || !mobile) { error.textContent = "Customer name and mobile are required."; return; }
        resolve({ name, mobile, modal, error });
      };
    });
  }

  async function issue(identity, trustedDevice) {
    const result = await rpc("rr_customer_session_issue_bound_v9680", {
      p_token: token,
      p_customer_name: identity.name,
      p_mobile: identity.mobile,
      p_device_id: trustedDevice,
    });
    save({ session_token: result.session_token, issued_at: new Date().toISOString() });
    remember(result.customer_name || identity.name, identity.mobile);
    const validated = await rpc("rr_customer_session_validate_v9590", { p_session_token: result.session_token, p_device_id: trustedDevice });
    window.RR_CUSTOMER_TRUSTED_SESSION = validated;
    return validated;
  }

  async function ensure() {
    const trustedDevice = device();
    const current = saved();
    if (current?.session_token) {
      try {
        const validated = await rpc("rr_customer_session_validate_v9590", { p_session_token: current.session_token, p_device_id: trustedDevice });
        window.RR_CUSTOMER_TRUSTED_SESSION = validated;
        return validated;
      } catch (_) { clear(); }
    }
    if (!token) return null;
    let identity = ident();
    let promptState = null;
    if (!identity) promptState = await askIdentity(await expectedCustomer());
    identity ||= promptState;
    try {
      const validated = await issue(identity, trustedDevice);
      promptState?.modal?.remove();
      return validated;
    } catch (error) {
      clear();
      localStorage.removeItem(identityKey);
      if (promptState?.error) promptState.error.textContent = error.message;
      throw error;
    }
  }

  window.RR_CUSTOMER_SECURE_SESSION_V9592 = { ensure, clear, device };
  async function boot() {
    try {
      await ensure();
      document.dispatchEvent(new CustomEvent("rr:customer-secure-session-ready", { detail: window.RR_CUSTOMER_TRUSTED_SESSION }));
    } catch (error) {
      console.warn("secure customer session", error.message);
      document.dispatchEvent(new CustomEvent("rr:customer-secure-session-error", { detail: { message: error.message } }));
    }
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, { once: true });
  else boot();
})();
