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
  const rememberedKey = "rr_customer_device_login_test71";
  const sessionsKey = "rr_customer_share_sessions_test71";
  let pending = null, validatedAt = 0;

  function parse(key) {
    try { return JSON.parse(localStorage.getItem(key) || "null"); } catch (_) { return null; }
  }
  function ident() {
    const legacy = parse(legacyIdentityKey);
    const value = parse(identityKey) || parse(rememberedKey) || (legacy?.share_token ? legacy : null);
    return value?.name && value?.mobile
      ? { name: String(value.name).trim(), mobile: String(value.mobile).trim() }
      : null;
  }
  function remember(name, mobile) {
    const value = { name: String(name).trim(), mobile: String(mobile).trim(), share_token: token };
    localStorage.setItem(identityKey, JSON.stringify(value));
    localStorage.setItem(rememberedKey, JSON.stringify({...value, verified:true}));
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
    return value?.share_token === token ? value : parse(sessionsKey)?.[token] || null;
  }
  function save(value) {
    const bound = {...value, share_token:token};
    const sessions = parse(sessionsKey) || {};const previous=parse(sessionKey);if(previous?.share_token&&previous.session_token)sessions[previous.share_token]=previous;delete sessions[token];sessions[token]=bound;
    const entries=Object.entries(sessions).slice(-12);
    localStorage.setItem(sessionsKey,JSON.stringify(Object.fromEntries(entries)));
    localStorage.setItem(sessionKey, JSON.stringify(bound));
  }
  function clear() {
    const value = parse(sessionKey);
    if (!value || value.share_token === token) localStorage.removeItem(sessionKey);
    const sessions=parse(sessionsKey)||{};delete sessions[token];localStorage.setItem(sessionsKey,JSON.stringify(sessions));
    validatedAt=0;
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
      document.getElementById("rrSecureReentry9592")?.remove();
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
    
    const validated = await rpc("rr_customer_session_validate_v9590", { p_session_token: result.session_token, p_device_id: trustedDevice });
    save({ session_token: result.session_token, issued_at: new Date().toISOString() });
    remember(result.customer_name || identity.name, identity.mobile);
    window.RR_CUSTOMER_TRUSTED_SESSION = validated;validatedAt=Date.now();
    return validated;
  }

  const invalidSession = error => /session invalid|session.*expired|trusted device.*(?:required|match)/i.test(String(error?.message||error));
  const wrongIdentity = error => /mobile.*(?:match|required)|different customer|customer.*(?:inactive|unavailable)/i.test(String(error?.message||error));
  async function restore() {
    const trustedDevice=device(),current=saved();
    if(current?.session_token){
      try{
        const validated=await rpc('rr_customer_session_validate_v9590',{p_session_token:current.session_token,p_device_id:trustedDevice});
        save(current);const boundIdentity=parse(identityKey);if(boundIdentity?.name&&boundIdentity?.mobile)remember(boundIdentity.name,boundIdentity.mobile);window.RR_CUSTOMER_TRUSTED_SESSION=validated;validatedAt=Date.now();return validated;
      }catch(error){if(!invalidSession(error))throw error;clear();}
    }
    if(!token)return null;
    const identity=ident();
    if(identity){try{return await issue(identity,trustedDevice)}catch(error){if(!wrongIdentity(error))throw error;}}
    let input=await askIdentity(await expectedCustomer());
    for(;;){
      try{const validated=await issue(input,trustedDevice);input.modal.remove();return validated}
      catch(error){
        input.error.textContent=error.message;
        const modal=input.modal,err=input.error;
        input=await new Promise(resolve=>{modal.querySelector('button').onclick=()=>{
          const name=modal.querySelector('[name=rrName]').value.trim(),mobile=modal.querySelector('[name=rrMobile]').value.trim();
          if(!name||!mobile){err.textContent='Customer name and mobile are required.';return;}
          resolve({name,mobile,modal,error:err});
        }});
      }
    }
  }
  function ensure(){
    if(window.RR_CUSTOMER_TRUSTED_SESSION&&saved()?.session_token&&Date.now()-validatedAt<15000)return Promise.resolve(window.RR_CUSTOMER_TRUSTED_SESSION);
    if(pending)return pending;
    pending=restore().finally(()=>{pending=null});return pending;
  }
  function logout(){clear();localStorage.removeItem(rememberedKey);localStorage.removeItem(identityKey);localStorage.removeItem(legacyIdentityKey);localStorage.removeItem(sessionsKey);window.RR_CUSTOMER_TRUSTED_SESSION=null;}
  window.RR_CUSTOMER_SECURE_SESSION_V9592 = { ensure, clear, device, logout };
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
