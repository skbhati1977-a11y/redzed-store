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
  let pending = null, validatedAt = 0, transportToken = '';

  function bindTransport(sessionToken) {
    if (transportToken === sessionToken) return;
    const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: {persistSession:false, autoRefreshToken:false, detectSessionInUrl:false},
      global: {headers:{'x-rr-customer-session':sessionToken, 'x-rr-customer-device':device()}},
    });
    window.supabaseClient = window.supabaseDb = window.redzedSupabase = window.sb = client;
    transportToken = sessionToken;
  }

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
      const share = await rpc("rr_customer_login_hint_test71", { p_token: token });
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
      modal.innerHTML = `<div style="width:min(420px,100%);background:#121c29;border:1px solid #4b617c;border-radius:16px;padding:18px;color:#fff"><b style="display:block;font-size:20px;margin-bottom:6px">OPEN SECURE CHAT</b><small style="display:block;color:#aeb9c7;margin-bottom:14px">${expected?.name ? "यह collection इसी customer के लिए है। Registered mobile verify करें।" : "Enter the customer name and mobile used for this collection."}</small><input name="rrName" placeholder="Customer name" autocomplete="name" style="box-sizing:border-box;width:100%;padding:12px;margin:0 0 9px;border:1px solid #50647e;border-radius:9px;background:#0d1219;color:#fff;font-size:16px"><input name="rrMobile" placeholder="Mobile number" inputmode="tel" autocomplete="tel" style="box-sizing:border-box;width:100%;padding:12px;margin:0 0 12px;border:1px solid #50647e;border-radius:9px;background:#0d1219;color:#fff;font-size:16px"><div data-err style="min-height:18px;color:#ffb7b7;font-size:12px;margin-bottom:8px"></div><button type="button" style="width:100%;padding:12px;border:0;border-radius:9px;background:#fff;color:#111;font-weight:900;font-size:15px">VERIFY MOBILE & CONTINUE</button></div>`;
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

  async function verifyPhoneOtp(identity, trustedDevice) {
    const otpCall=async body=>{const response=await fetch(SUPABASE_URL+'/functions/v1/rr-customer-phone-otp-test71',{method:'POST',headers:{'Content-Type':'application/json',apikey:SUPABASE_ANON_KEY},body:JSON.stringify(body)});const data=await response.json();if(!response.ok)throw Error(data.error||'SMS verification अभी उपलब्ध नहीं है।');return data;};
    let challenge=null,lastSent=0;
    const send=async()=>{
      challenge=await otpCall({action:'send',token,customer_name:identity.name,mobile:identity.mobile,device_id:trustedDevice});
      lastSent=Date.now();
    };
    await send();
    document.getElementById('rrCustomerPhoneOtp71')?.remove();
    const modal=document.createElement('div');modal.id='rrCustomerPhoneOtp71';modal.style.cssText='position:fixed;inset:0;z-index:2147483647;background:#050a10;display:grid;place-items:center;padding:18px;color:#fff;font-family:system-ui';
    modal.innerHTML='<section style="width:min(420px,100%);padding:22px;border:1px solid #4b617c;border-radius:16px;background:#121c29;box-sizing:border-box"><h2>VERIFY REGISTERED MOBILE</h2><p data-otp-info></p><input data-otp-code aria-label="SMS OTP" placeholder="6 digit SMS OTP" autocomplete="one-time-code" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" style="width:100%;box-sizing:border-box;padding:14px;font-size:22px;border-radius:9px"><p data-otp-error role="status" aria-live="polite"></p><button data-otp-verify>VERIFY OTP</button> <button data-otp-resend>RESEND OTP</button> <button data-otp-cancel>CANCEL</button></section>';
    document.body.appendChild(modal);
    const code=modal.querySelector('[data-otp-code]'),notice=modal.querySelector('[data-otp-error]'),verify=modal.querySelector('[data-otp-verify]'),resend=modal.querySelector('[data-otp-resend]');
    modal.querySelector('[data-otp-info]').textContent=`${challenge.customer_name} · ${challenge.phone}\nइस registered नंबर पर मिला SMS OTP भरें। OTP verify होने के बाद ही Super Admin को request जाएगी। OTP किसी अन्य व्यक्ति को न दें।`;
    code.focus?.();
    try{return await new Promise((resolve,reject)=>{
      let busy=false;
      modal.querySelector('[data-otp-cancel]').onclick=()=>{if(!busy)reject(Error('OTP verification cancelled. Chat locked है।'));};
      resend.onclick=async()=>{if(busy)return;const left=Math.ceil((60000-(Date.now()-lastSent))/1000);if(left>0){notice.textContent=`Resend के लिए ${left} seconds इंतज़ार करें।`;return;}busy=true;resend.disabled=true;try{await send();notice.textContent='नया OTP भेजा गया।';code.value='';}catch(error){notice.textContent=error.message;}finally{busy=false;resend.disabled=false;}};
      verify.onclick=async()=>{if(busy)return;const value=String(code.value||'').trim();if(!/^\d{6}$/.test(value)){notice.textContent='SMS में मिला 6 digit OTP भरें।';return;}busy=true;verify.disabled=true;try{
        const data=await otpCall({action:'verify',challenge_id:challenge.challenge_id,device_id:trustedDevice,otp:value});
        if(data?.otp_verified!==true)throw Error('SMS OTP verification required.');resolve(data);
      }catch(error){notice.textContent=error.message;}finally{busy=false;verify.disabled=false;}};
      code.addEventListener?.('keydown',event=>{if(event.key==='Enter')verify.click();});
    });}finally{code.value='';modal.remove();}
  }

  async function chooseVerification(identity,trustedDevice,args) {
    const modal=document.createElement('div');modal.id='rrCustomerVerificationChoice71';
    modal.setAttribute('role','dialog');modal.setAttribute('aria-modal','true');
    modal.style.cssText='position:fixed;inset:0;z-index:2147483647;background:#050a10;display:grid;place-items:center;padding:18px;color:#fff;font-family:system-ui';
    modal.innerHTML='<section style="width:min(420px,100%);padding:22px;background:#121c29;border-radius:16px"><b>VERIFY REGISTERED NUMBER</b><p>WhatsApp पर request code भेजें। Admin sender नंबर जाँचकर device approve करेगा। यह manual verification है।</p><button data-verification-wa>VERIFY VIA WHATSAPP</button><p>SMS OTP के लिए SMS service configured होना जरूरी है।</p><button data-verification-sms>USE SMS OTP</button><button data-verification-cancel>CANCEL</button><p data-verification-error role="status"></p></section>';
    document.body.appendChild(modal);
    try{return await new Promise((resolve,reject)=>{
      let busy=false;
      modal.querySelector('[data-verification-cancel]').onclick=()=>{if(!busy)reject(Error('Verification cancelled. Chat locked है।'));};
      for(const [selector,run] of [['[data-verification-wa]',()=>rpc('rr_customer_whatsapp_request_test71',args)],['[data-verification-sms]',()=>verifyPhoneOtp(identity,trustedDevice)]]){
        modal.querySelector(selector).onclick=async()=>{if(busy)return;busy=true;modal.querySelectorAll('button').forEach(b=>b.disabled=true);try{resolve(await run());}catch(error){modal.querySelector('[data-verification-error]').textContent=error.message;}finally{busy=false;modal.querySelectorAll('button').forEach(b=>b.disabled=false);}};
      }
    });}finally{modal.remove();}
  }

  async function waitForApproval(request, identity, trustedDevice) {
    let modal=identity.modal, owned=false;
    if(!modal){
      document.getElementById('rrSecureApprovalWaiting71')?.remove();
      modal=document.createElement('div');modal.id='rrSecureApprovalWaiting71';owned=true;
      modal.style.cssText='position:fixed;inset:0;z-index:2147483646;background:#050a10;display:grid;place-items:center;padding:18px;color:#fff;font-family:system-ui';
      modal.innerHTML='<section style="width:min(420px,100%);box-sizing:border-box;padding:22px;border:1px solid #4b617c;border-radius:16px;background:#121c29"><b style="font-size:22px">WAITING FOR APPROVAL</b><p data-wait role="status" aria-live="polite"></p></section>';
      document.body.appendChild(modal);
    }
    const message=modal.querySelector('[data-wait]')||identity.error;
    const submit=modal.querySelector('button'),oldText=submit?.textContent;
    if(submit)submit.textContent='WAITING FOR APPROVAL';
    if(message){message.setAttribute?.('role','status');message.setAttribute?.('aria-live','polite');message.style.whiteSpace='pre-line';}
    modal.querySelectorAll('input,button').forEach(el=>el.disabled=true);
    let whatsappBox=null;
    if(request.whatsapp_code){
      whatsappBox=document.createElement('div');whatsappBox.dataset.whatsappVerification='true';
      const details=document.createElement('p');details.style.whiteSpace='pre-line';
      details.textContent=`WhatsApp manual verification\nCode: ${request.whatsapp_code}\nअपने registered WhatsApp नंबर ${identity.mobile} से भेजें। Admin वास्तविक sender नंबर जाँचकर इसी device को approve करेगा।\nCode expiry: ${new Date(request.whatsapp_expires_at).toLocaleString()}`;
      const link=document.createElement('a');link.textContent='OPEN WHATSAPP & SEND REQUEST';link.target='_blank';link.rel='noopener noreferrer';link.style.color='#9ed5ff';
      const text=`Redzed TEST71 device login verification\nCustomer: ${request.customer_name||identity.name}\nRegistered number: ${identity.mobile}\nRequest: ${request.request_id}\nCode: ${request.whatsapp_code}\nPlease check my actual WhatsApp sender number and approve this device manually.`;
      link.href=`https://wa.me/${request.whatsapp_destination}?text=${encodeURIComponent(text)}`;
      whatsappBox.append(details,link);message?.parentElement?.appendChild(whatsappBox);
    }
    let failures=0;
    const remind=()=>{if(document.hidden||request.approval_status!=='PENDING')return;rpc('rr_customer_login_remind_test71',{p_request_id:request.request_id,p_device_id:trustedDevice}).catch(()=>{});};
    document.addEventListener('visibilitychange',remind);
    window.addEventListener?.('pageshow',remind);
    try{
      for(;;){
        if(message)message.textContent=`${request.customer_name||identity.name} · ${identity.mobile}\n${request.approval_status==='PAUSED'?'Super Admin ने access PAUSE किया है। Resume होने तक chat locked है।':'Super Admin approval का इंतज़ार है। Chat अभी locked है।'}`;
        if(request.approval_status==='APPROVED')return;
        if(request.approval_status==='OTP_REQUIRED')throw Error('Verification expired or unavailable. Reload to create a new WhatsApp request or verify SMS OTP.');
        if(['REJECTED','REVOKED'].includes(request.approval_status))throw Error('Login approval rejected or revoked. Contact Super Admin.');
        await new Promise(resolve=>setTimeout(resolve,5000));
        try{
          request={...request,...await rpc('rr_customer_login_status_test71',{p_request_id:request.request_id,p_device_id:trustedDevice})};failures=0;
        }catch(error){
          failures++;
          if(message)message.textContent='Approval status अभी load नहीं हुआ। Internet आने पर अपने-आप check होगा।';
          if(failures>=12)throw Error('Approval status unavailable. Check your connection and try again.');
        }
      }
    }finally{
      whatsappBox?.remove();
      document.removeEventListener?.('visibilitychange',remind);
      window.removeEventListener?.('pageshow',remind);
      if(owned)modal.remove();else {modal.querySelectorAll('input,button').forEach(el=>el.disabled=false);if(submit)submit.textContent=oldText;}
    }
  }

  async function issue(identity, trustedDevice) {
    const args={
      p_token: token,
      p_customer_name: identity.name,
      p_mobile: identity.mobile,
      p_device_id: trustedDevice,
    };
    let result = await rpc("rr_customer_session_issue_bound_v9680", args);
    if(result?.approval_status==='OTP_REQUIRED')result=await chooseVerification(identity,trustedDevice,args);
    else if(result?.whatsapp_pending)result=await rpc('rr_customer_whatsapp_request_test71',args);
    if(result?.approval_status && !result.session_token){
      await waitForApproval(result,identity,trustedDevice);
      result=await rpc('rr_customer_session_issue_bound_v9680',args);
    }
    if(!result?.session_token)throw Error('Super Admin approval required for this device.');
    
    const validated = await rpc("rr_customer_session_validate_v9590", { p_session_token: result.session_token, p_device_id: trustedDevice });
    save({ session_token: result.session_token, issued_at: new Date().toISOString() });
    remember(result.customer_name || identity.name, identity.mobile);
    bindTransport(result.session_token);
    window.RR_CUSTOMER_TRUSTED_SESSION = validated;validatedAt=Date.now();
    return validated;
  }

  const invalidSession = error => /session invalid|session.*expired|trusted device.*(?:required|match)|approval required|access paused/i.test(String(error?.message||error));
  const wrongIdentity = error => /mobile.*(?:match|required)|different customer|customer.*(?:inactive|unavailable)|approval rejected/i.test(String(error?.message||error));
  async function restore() {
    const trustedDevice=device(),current=saved();
    if(current?.session_token){
      try{
        const validated=await rpc('rr_customer_session_validate_v9590',{p_session_token:current.session_token,p_device_id:trustedDevice});
        save(current);bindTransport(current.session_token);const boundIdentity=parse(identityKey);if(boundIdentity?.name&&boundIdentity?.mobile)remember(boundIdentity.name,boundIdentity.mobile);window.RR_CUSTOMER_TRUSTED_SESSION=validated;validatedAt=Date.now();return validated;
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
