(() => {
  const V="9276";
  const JOURNEY_SCRIPT=`real-upm-journey-track-v9254.js?v=${V}`;
  const TRAVELLER_SCRIPT=`real-upm-alter-traveller-grid-v9268.js?v=${V}`;
  const tabs = [
    {key:"CUTTING", label:"Cutting", url:`real-cutting-master.html?v=${V}`},
    {key:"PRINTING", label:"Printing", url:`real-universal-production-v770.html?dept=PRINTING&label=Printing&v=${V}`},
    {key:"STICKER", label:"Sticker", url:`real-universal-production-v770.html?dept=STICKER&label=Sticker&v=${V}`},
    {key:"METAL_ID", label:"Metal ID", url:`real-universal-production-v770.html?dept=METAL_ID&label=Metal+ID&v=${V}`},
    {key:"STITCHING", label:"KR / Stitching", url:`real-universal-production-v770.html?dept=STITCHING&label=KR+Stitching&v=${V}`},
    {key:"OVERLOCK", label:"OV / Overlock", url:`real-universal-production-v770.html?dept=OVERLOCK&label=Overlock&v=${V}`},
    {key:"FOLDING", label:"FLD / Folding", url:`real-universal-production-v770.html?dept=FOLDING&label=Folding&v=${V}`},
    {key:"KAAJ", label:"Kaaj", url:`real-universal-production-v770.html?dept=KAAJ&label=Kaaj&v=${V}`},
    {key:"BUTTON", label:"Button", url:`real-universal-production-v770.html?dept=BUTTON&label=Button&v=${V}`},
    {key:"TEAK_TANKI", label:"Teak / Tanki", url:`real-universal-production-v770.html?dept=TEAK_TANKI&label=Teak+Tanki&v=${V}`},
    {key:"THREAD_CUT", label:"Thread Cutting", url:`real-universal-production-v770.html?dept=THREAD_CUT&label=Thread+Cutting&v=${V}`},
    {key:"QC", label:"QC", url:`real-universal-production-v770.html?dept=QC&label=QC&v=${V}`},
    {key:"PRESS", label:"Press", url:`real-universal-production-v770.html?dept=PRESS&label=Press&v=${V}`},
    {key:"PACKING", label:"Packing", kind:"finish", url:`real-finished-goods-v787.html?view=packing&v=${V}`},
    {key:"DESPATCH", label:"Despatch", kind:"finish", url:`real-finished-goods-v787.html?view=despatch&v=${V}`},
    {key:"SUBMITTED", label:"Submitted Work", kind:"finish", url:`real-upm-submitted-work-v772.html?v=${V}`},
    {key:"CONTROL", label:"All / Open Random Queue", kind:"finish", url:`real-universal-production-v770.html?v=${V}`}
  ];

  const $ = id => document.getElementById(id);
  const frame = $("upmFrame");
  const holder = $("upmTabs");
  const loading = $("loadingBadge");
  const current = $("currentView");
  const direct = $("openDirect");
  let activeTab = null;

  function injectScript(tab, src, attr) {
    try {
      const d = frame.contentDocument;
      if (!d?.head) return;
      frame.dataset.upmDept = tab?.key || "";
      d.documentElement.dataset.upmDepartment = tab?.key || "";
      d.body && (d.body.dataset.department = tab?.key || "");
      if (d.querySelector(`script[data-${attr}]`)) return;
      const s = d.createElement('script');
      s.src = src;
      s.async = true;
      s.setAttribute(`data-${attr}`, '1');
      d.head.appendChild(s);
    } catch (e) {
      console.warn('UPM child helper injection skipped:', e?.message || e);
    }
  }

  function injectHelpers(tab) {
    injectScript(tab, JOURNEY_SCRIPT, 'upm-journey-9276');
    injectScript(tab, TRAVELLER_SCRIPT, 'upm-traveller-9276');
  }

  function selectTab(tab, push=true) {
    activeTab = tab;
    frame.dataset.upmDept = tab.key;
    document.querySelectorAll(".upm-tab").forEach(b => b.classList.toggle("active", b.dataset.key === tab.key));
    loading.hidden = false;
    current.textContent = tab.label;
    direct.href = tab.url;
    frame.src = tab.url;
    if (push) {
      const u = new URL(location.href);
      u.searchParams.set("tab", tab.key);
      history.replaceState(null, "", u);
    }
  }

  tabs.forEach(tab => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "upm-tab";
    if (tab.kind) b.dataset.kind = tab.kind;
    b.dataset.key = tab.key;
    b.textContent = tab.label;
    b.addEventListener("click", () => selectTab(tab));
    holder.appendChild(b);
  });

  frame.addEventListener("load", () => {
    loading.hidden = true;
    if (activeTab) {
      frame.dataset.upmDept = activeTab.key;
      setTimeout(() => injectHelpers(activeTab), 60);
      setTimeout(() => injectHelpers(activeTab), 500);
    }
  });
  $("reloadTab").addEventListener("click", () => {
    loading.hidden = false;
    try { frame.contentWindow.location.reload(); }
    catch { frame.src = frame.src; }
  });

  const requested = new URL(location.href).searchParams.get("tab");
  selectTab(tabs.find(t => t.key === requested) || tabs.find(t => t.key === "CONTROL") || tabs[0], false);
})();
