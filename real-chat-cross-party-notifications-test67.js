(() => {
  "use strict";
  if (window.__RR_CROSS_PARTY_NOTIFICATIONS_TEST67__) return;
  window.__RR_CROSS_PARTY_NOTIFICATIONS_TEST67__ = true;

  const MUTE_KEY = "rr_chat_mute";
  const seen = new Set();
  let seeded = false;
  let audio = null;

  const muted = () => localStorage.getItem(MUTE_KEY) === "1";
  const messageKey = (node) =>
    String(node.dataset.msgId || node.getAttribute("data-message-id") || node.textContent || "").replace(/\s+/g, " ").trim();

  function label(node) {
    const sender = node.querySelector("small")?.textContent?.trim() || "New update";
    const raw = node.textContent.replace(/\s+/g, " ").trim();
    return {
      title: document.getElementById("chatTitle")?.textContent?.trim() || "REDZED Chat",
      body: `${sender}: ${raw.replace(sender, "").trim() || "New activity"}`.slice(0, 180),
    };
  }

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
      renotify: true,
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

  function alertIncoming(node, key) {
    const { title, body } = label(node);
    banner(title, body);
    if (document.getElementById("rrChatBar")) {
      if (!muted()) navigator.vibrate?.([160, 80, 160]);
      return;
    }
    tone();
    if (!muted()) navigator.vibrate?.([160, 80, 160]);
    systemNotice(title, body, key);
  }

  function scan() {
    const nodes = [...document.querySelectorAll("#msgs .msg, #rrMsgs .msg, #rrMsgs .rr-msg")];
    if (!seeded) {
      if (!nodes.length) return;
      nodes.forEach((node) => {
        const key = messageKey(node);
        if (key) seen.add(key);
      });
      seeded = true;
      return;
    }
    nodes.forEach((node) => {
      const key = messageKey(node);
      if (!key || seen.has(key)) return;
      seen.add(key);
      if (!node.classList.contains("me")) alertIncoming(node, key);
    });
    if (seen.size > 600) [...seen].slice(0, 300).forEach((key) => seen.delete(key));
  }

  navigator.serviceWorker?.register("./rz-sw-v61.js?v=61push9", { updateViaCache: "none" }).catch(() => {});
  addEventListener("pointerdown", () => {
    try {
      audio ||= new (window.AudioContext || window.webkitAudioContext)();
      audio.resume();
    } catch (_) {}
  }, { once: true, passive: true });
  new MutationObserver(scan).observe(document.documentElement, { subtree: true, childList: true });
  setTimeout(() => {
    scan();
  }, 350);
  setTimeout(() => (seeded = true), 2500);
})();
