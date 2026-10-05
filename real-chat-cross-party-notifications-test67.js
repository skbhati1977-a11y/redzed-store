(() => {
  "use strict";
  if (window.__RR_CROSS_PARTY_NOTIFICATIONS_TEST67__) return;
  window.__RR_CROSS_PARTY_NOTIFICATIONS_TEST67__ = true;

  const MUTE_KEY = "rr_chat_mute";
  let audio = null;
  const muted = () => localStorage.getItem(MUTE_KEY) === "1";
  function tone() {
    if (muted()) return;
    try {
      audio ||= new (window.AudioContext || window.webkitAudioContext)();
      if (audio.state === "suspended") audio.resume();
      const now = audio.currentTime;
      [[740, 0], [988, 0.13]].forEach(([frequency, delay]) => {
        const oscillator = audio.createOscillator();
        const gain = audio.createGain();
        oscillator.frequency.value = frequency;
        gain.gain.setValueAtTime(0.0001, now + delay);
        gain.gain.exponentialRampToValueAtTime(0.12, now + delay + 0.01);
        gain.gain.exponentialRampToValueAtTime(0.0001, now + delay + 0.18);
        oscillator.connect(gain);
        gain.connect(audio.destination);
        oscillator.start(now + delay);
        oscillator.stop(now + delay + 0.2);
      });
    } catch (_) {}
  }

  function banner(title, body) {
    let box = document.getElementById("rrCrossPartyNotice67");
    if (!box) {
      box = document.createElement("button");
      box.id = "rrCrossPartyNotice67";
      box.type = "button";
      box.setAttribute("aria-label", "Dismiss chat notification");
      box.onclick = () => { clearTimeout(banner.timer); box.hidden = true; };
      box.style.cssText = "position:fixed;z-index:2147483646;top:12px;left:50%;transform:translateX(-50%);width:min(92vw,440px);padding:13px 15px;border:1px solid #6caef2;border-radius:14px;background:#122236;color:#fff;box-shadow:0 12px 34px #000a;text-align:left;font:inherit";
      document.body.appendChild(box);
    }
    box.innerHTML = `<b style="display:block;margin-bottom:3px">${escapeHtml(title)}</b><span>${escapeHtml(body)}</span>`;
    box.hidden = false;
    clearTimeout(banner.timer);
    banner.timer = setTimeout(() => (box.hidden = true), 5500);
  }

  const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[char]);

  async function systemNotice(title, body, key) {
    if (muted() || !("Notification" in window) || Notification.permission !== "granted") return;
    const options = {
      body,
      tag: `rr-cross-${key}`,
      renotify: false,
      vibrate: [160, 80, 160],
      data: { url: location.href },
      icon: "./redzed-icon-test67.svg",
      badge: "./redzed-icon-test67.svg",
    };
    try {
      const registration = await navigator.serviceWorker?.ready;
      if (registration) return registration.showNotification(title, options);
      new Notification(title, options);
    } catch (_) {}
  }

  // The first server batch in each chat is history, however late it arrives.
  // DOM decorations, restored nodes and timers are never new-message sources.
  const streams = new Map();
  const openedAt = Date.now();
  let actor = null;
  function revision(message) {
    const p=message.payload || {};
    return [message.id, p.requirement_update_no ?? "", p.collection_update_no ?? ""].join("|");
  }
  function receive(name, args, rows) {
    if (!Array.isArray(rows) || !/rr_chat_customer_messages/.test(name)) return;
    const stream=[args.p_chat_id || args.p_token || args.p_session_token || location.pathname, args.p_channel || "GROUP"].join("|");
    let entry=streams.get(stream);
    if (!entry) { streams.set(stream,{keys:new Set(rows.map(revision)),watermark:Math.max(openedAt,...rows.map(m=>Date.parse(m.created_at)||0))}); return; }
    const {keys}=entry;
    rows.slice().reverse().forEach(message => {
      const key=revision(message);
      if (keys.has(key)) return;
      keys.add(key);
      if ((Date.parse(message.created_at)||0)<=entry.watermark) return;
      const own=actor?.id && String(message.sender_kind || "STAFF").toUpperCase()==="STAFF" && (message.sender_profile_id===actor.id || message.sender_name===actor.full_name);
      if (own || muted() || String(message.sender_kind || "").toUpperCase() !== "STAFF") return;
      const title=document.getElementById("chatTitle")?.textContent?.trim() || "REDZED Chat";
      const body=`${message.sender_name || "New update"}: ${message.body || "New activity"}`.slice(0,180);
      banner(title,body);tone();navigator.vibrate?.([160,80,160]);
      // The open chat already shows this update. System alerts belong to background receipt.
      if(document.hidden) systemNotice(title,body,key);
    });
    entry.watermark=Math.max(entry.watermark,...rows.map(m=>Date.parse(m.created_at)||0));
  }
  function hook() {
    if(document.getElementById("inboxRows")) return true;
    if(!window.RF853?.rpc || RF853.rpc.__rrNotice71) return false;
    const base=RF853.rpc.bind(RF853);
    const wrapped=async(name,args={})=>{const result=await base(name,args);receive(name,args,result);return result;};
    wrapped.__rrNotice71=true;RF853.rpc=wrapped;
    base("rr_chat_actor_profile_v9433",{}).then(value=>{actor=value;}).catch(()=>{});
    return true;
  }
  if(!hook()) {let tries=0;const timer=setInterval(()=>{if(hook()||++tries>60)clearInterval(timer);},100);}

  if(!document.getElementById("inboxRows")) navigator.serviceWorker?.register("./redzed-sw-test67.js?v=68").catch(() => {});
  else navigator.serviceWorker?.getRegistration?.().then(async reg=>{const notices=await reg?.getNotifications?.();(notices||[]).filter(n=>/^rr-(cross-)?/.test(n.tag||"")).forEach(n=>n.close());}).catch(()=>{});
  addEventListener("pointerdown", () => {
    try {
      audio ||= new (window.AudioContext || window.webkitAudioContext)();
      audio.resume();
    } catch (_) {}
  }, { once: true, passive: true });

})();

